/*
 Copyright 2026 The Fuel Rats Mischief

 Redistribution and use in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice,
 this list of conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following
 disclaimer in the documentation and/or other materials provided with the distribution.

 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote
 products derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
 INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import Foundation
@preconcurrency import IRCKit

/// The live AI service, created at startup when `configuration.ai` is present. Held as a global so
/// the always-listening notification handlers (which capture no instance state, matching the
/// codebase pattern) can reach it.
nonisolated(unsafe) var aiService: AIService?

/// Orchestrates the always-listening AI surface: name-trigger extraction, the atomic
/// reserve → relevance gate → answer pipeline → reply flow, and its safety rails.
final class AIService: Sendable {
    let pipeline: AskPipeline
    let gate: RelevanceGate
    let state: AIState
    let conversations: ConversationManager
    let scrollback: ScrollbackBuffer
    let metrics: AIMetrics

    init(
        pipeline: AskPipeline,
        gate: RelevanceGate,
        state: AIState,
        conversations: ConversationManager,
        scrollback: ScrollbackBuffer,
        metrics: AIMetrics
    ) {
        self.pipeline = pipeline
        self.gate = gate
        self.state = state
        self.conversations = conversations
        self.scrollback = scrollback
        self.metrics = metrics
    }

    /// Builds the service from configuration: one Anthropic client (Opus for answers, Haiku for the
    /// gate) and one Outline retriever scoped to the FRKB + private ED-Knowledge collections.
    static func make(from config: AIConfiguration) -> AIService {
        let anthropic = Anthropic(token: config.anthropicToken)
        let outline = OutlineAPI(
            token: config.outlineToken,
            baseURL: config.outlineBaseURL,
            frkbCollectionId: config.frkbCollectionId,
            edKbCollectionId: config.edKbCollectionId)
        return AIService(
            pipeline: AskPipeline(provider: anthropic, outline: outline),
            gate: RelevanceGate(provider: anthropic),
            state: AIState(),
            conversations: ConversationManager(),
            scrollback: ScrollbackBuffer(),
            metrics: AIMetrics())
    }

    // MARK: - Entry points

    /// A channel message: only acts if it is addressed to the bot by name.
    func handleChannelMessage(_ message: IRCPrivateMessage) async {
        guard let question = AIService.extractQuestion(
            from: message.message, botNick: message.client.currentNick) else {
            return
        }
        await respond(to: message, question: question, isPM: false)
    }

    /// A private message: always addressed to the bot; strip a leading name if present.
    func handlePrivateMessage(_ message: IRCPrivateMessage) async {
        let raw = message.message.trimmingCharacters(in: .whitespacesAndNewlines)
        // A leading "!" is an IRC command handled by the command system; the assistant must not
        // also answer it, or a PM'd command (e.g. "!tz 3pm in London") gets a duplicate reply.
        guard AIService.isCommandInvocation(raw) == false else { return }
        let question = AIService.extractQuestion(from: raw, botNick: message.client.currentNick) ?? raw
        guard question.isEmpty == false else { return }
        await respond(to: message, question: question, isPM: true)
    }

    /// Whether a message is an IRC command invocation (starts with the "!" command prefix), which the
    /// command system owns. The assistant stays out of these.
    static func isCommandInvocation(_ message: String) -> Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("!")
    }

    // MARK: - Core flow

    private func respond(to message: IRCPrivateMessage, question: String, isPM: Bool) async {
        // Cheap prefilter before touching any paid path.
        guard RelevanceGate.prefilterPasses(question) else { return }

        // Atomic cooldown + in-flight + per-user + global budget reservation.
        let user = message.user.account ?? message.user.nickname.lowercased()
        // Public channels get one overall answer per 5 minutes (channel-wide, not per-user), gated the
        // same way command cooldowns are (rescues.write bypasses, i.e. drilled rats and above). PMs and
        // bypassing users keep the light per-user cooldown instead.
        let bypasses = message.user.hasPermission(permission: .RescueWrite)
        let (key, cooldown): (String, TimeInterval?) = (isPM || bypasses)
            ? (cooldownKey(message), nil)
            : (channelCooldownKey(message), AIService.publicChannelCooldown)
        switch await state.reserve(key: key, user: user, cooldown: cooldown) {
            case .reserved:
            break
            case .cooldown, .overCapacity:
            return  // silent in-channel and in PM
            case .overBudget:
            if isPM { message.reply(message: AIService.busyMessage) }
            return
        }

        // Paid Haiku relevance gate.
        let relevant = await gate.isRelevant(question)
        await metrics.recordGate(passed: relevant)
        guard relevant else {
            // No billable answer produced — refund the user's attempt so chatter doesn't lock them out.
            await state.release(refundingUser: user)
            return
        }

        // Multi-turn memory for identified users only (nicks are spoofable).
        let account = message.user.account
        let history = await conversations.history(account: account)

        do {
            // Pass the invoking message so the run_command tool can dispatch a read-only command
            // as this user, with native permission/cooldown/destination enforcement. A deadline
            // bounds how long a stuck upstream call can pin one of the scarce in-flight slots.
            let reply = try await AIService.withTimeout(seconds: AIService.answerDeadline) {
                try await self.pipeline.answer(
                    question: question, history: history, context: ToolContext(message: message))
            }
            send(reply, to: message)
            await metrics.recordAnswer(reply)
            await state.recordUsage(tokens: reply.usage.inputTokens + reply.usage.outputTokens)
            let logLine =
                "[ai] answered refused=\(reply.refused) rounds=\(reply.toolRounds) "
                + "in=\(reply.usage.inputTokens) out=\(reply.usage.outputTokens) "
                + "cacheRead=\(reply.usage.cacheReadInputTokens) citations=\(reply.citations.count)"
            aiLogger.info("\(logLine)")
            if reply.refused == false, reply.text.isEmpty == false {
                await conversations.record(account: account, question: question, answer: reply.text)
            }
            await state.release()
        } catch {
            aiLogger.error("[ai] pipeline error: \(error)")
            if isPM { message.reply(message: AIService.errorMessage) }
            // No answer reached the user — refund the attempt.
            await state.release(refundingUser: user)
        }
    }

    /// Upper bound on a single answer pipeline (all tool rounds + upstream retries). Generous enough
    /// for legitimate multi-round answers, but prevents a hung or rate-limited upstream call from
    /// holding an in-flight slot indefinitely.
    static let answerDeadline: Double = 240

    struct AITimeoutError: Error {}

    /// Runs `operation`, throwing `AITimeoutError` if it doesn't finish within `seconds`. The losing
    /// child is cancelled; `Anthropic.complete` checks for cancellation between retries so it unwinds
    /// promptly (bounded by the in-flight HTTP request's own deadline).
    static func withTimeout<T: Sendable>(
        seconds: Double, operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw AITimeoutError()
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw AITimeoutError() }
            return result
        }
    }

    /// Hard cap on a whole answer. A reply may run to roughly two IRC lines; IRCKit's
    /// `sendMessage(toTarget:)` splits anything over the protocol byte limit on word boundaries, so
    /// we only enforce the overall character budget here (trimmed to a sentence boundary).
    static let maxTotalLength = 800

    private func send(_ reply: AIReply, to message: IRCPrivateMessage) {
        // A run_command dispatch already answered the user in-channel; adding anything here would
        // double-post or contradict it, so stay silent.
        guard reply.deliveredExternally == false else { return }
        guard reply.refused == false, reply.text.isEmpty == false else {
            message.reply(message: reply.refused ? AIService.refusalMessage : AIService.emptyMessage)
            return
        }
        let full = AIService.clamp(AIService.formatForIRC(reply.text), to: AIService.maxTotalLength)
        message.reply(message: full.isEmpty ? AIService.emptyMessage : full)
    }

    /// Collapses an LLM answer into a single IRC-safe line: converts `**bold**` to the IRC bold
    /// control code, strips residual markdown and em/en dashes, and flattens all newlines and runs
    /// of whitespace to single spaces. The model is told to produce IRC-ready prose; this is the
    /// backstop that guarantees one clean line regardless.
    static func formatForIRC(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "\u{2014}", with: "-")  // em dash
            .replacingOccurrences(of: "\u{2013}", with: "-")  // en dash
            .replacingOccurrences(of: "`", with: "")
        if let bold = try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*") {
            let range = NSRange(result.startIndex..., in: result)
            result = bold.stringByReplacingMatches(
                in: result, range: range, withTemplate: "\u{02}$1\u{02}")
        }
        let flattened = result
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
        var collapsed = flattened
        while collapsed.contains("  ") {
            collapsed = collapsed.replacingOccurrences(of: "  ", with: " ")
        }
        return collapsed.trimmingCharacters(in: .whitespaces)
    }

    /// Truncates over-long text without ever stopping mid-sentence: prefer ending at the last
    /// sentence terminator within the limit (clean, no ellipsis); otherwise fall back to the last
    /// word boundary with an ellipsis. The model is told to fit one line, so this rarely fires.
    static func clamp(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let head = String(text.prefix(limit))
        if let terminator = head.lastIndex(where: { ".!?".contains($0) }),
            head.distance(from: head.startIndex, to: terminator) > limit / 2 {
            return String(head[...terminator]).trimmingCharacters(in: .whitespaces)
        }
        if let lastSpace = head.lastIndex(of: " "),
            head.distance(from: head.startIndex, to: lastSpace) > limit / 2 {
            return head[..<lastSpace].trimmingCharacters(in: .whitespaces) + "\u{2026}"
        }
        return head.trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }

    // MARK: - Helpers

    /// Cooldown key = (client, channel, identity). Channel names collide across networks, so the
    /// client identity discriminates them; identity prefers the authenticated account over the nick.
    private func cooldownKey(_ message: IRCPrivateMessage) -> String {
        let identity = message.user.account ?? message.user.nickname.lowercased()
        return "\(ObjectIdentifier(message.client))|\(message.destination.name.lowercased())|\(identity)"
    }

    /// Channel-wide cooldown key (no user identity): one overall answer per channel, used to rate-limit
    /// public-channel questions from unprivileged users.
    private func channelCooldownKey(_ message: IRCPrivateMessage) -> String {
        return "\(ObjectIdentifier(message.client))|\(message.destination.name.lowercased())"
    }

    /// Overall cooldown between AI answers in a public channel for unprivileged users.
    static let publicChannelCooldown: TimeInterval = 5 * 60

    /// Returns the question with the leading bot name stripped, or nil if the message is not
    /// addressed to the bot. The character after the name must be a separator so "MechaSqueakBot"
    /// does not match the nick "MechaSqueak".
    static func extractQuestion(from message: String, botNick: String) -> String? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let nick = botNick.lowercased()
        guard nick.isEmpty == false, trimmed.lowercased().hasPrefix(nick) else { return nil }

        let afterName = trimmed[trimmed.index(trimmed.startIndex, offsetBy: nick.count)...]
        guard let separator = afterName.first else { return nil }
        guard separator == ":" || separator == "," || separator == " " else { return nil }

        let question = afterName
            .drop { $0 == ":" || $0 == "," || $0 == " " }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return question.isEmpty ? nil : question
    }

    // User-facing strings, kept dry and in-character. English-only for now; Lingo-keyed
    // localization is a planned follow-up (m1).
    static let refusalMessage =
        "I don't have that. Take it to Ops, a trainer, or an overseer before you invent policy."
    static let emptyMessage = "Nothing useful to say to that."
    static let busyMessage = "Busy. Try again shortly."
    static let errorMessage = "Something broke on my end. Try again shortly."
}
