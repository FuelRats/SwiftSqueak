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

    init(pipeline: AskPipeline, gate: RelevanceGate, state: AIState) {
        self.pipeline = pipeline
        self.gate = gate
        self.state = state
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
            state: AIState())
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
        let question = AIService.extractQuestion(from: raw, botNick: message.client.currentNick) ?? raw
        guard question.isEmpty == false else { return }
        await respond(to: message, question: question, isPM: true)
    }

    // MARK: - Core flow

    private func respond(to message: IRCPrivateMessage, question: String, isPM: Bool) async {
        // Cheap prefilter before touching any paid path.
        guard RelevanceGate.prefilterPasses(question) else { return }

        // Atomic cooldown + in-flight + budget reservation.
        switch await state.reserve(key: cooldownKey(message)) {
            case .reserved:
            break
            case .cooldown, .overCapacity:
            return  // silent in-channel and in PM
            case .overBudget:
            if isPM { message.reply(message: AIService.busyMessage) }
            return
        }

        // Paid Haiku relevance gate.
        guard await gate.isRelevant(question) else {
            await state.release()
            return
        }

        do {
            // Pass the invoking message so the run_command tool can dispatch a read-only command
            // as this user, with native permission/cooldown/destination enforcement.
            let reply = try await pipeline.answer(
                question: question, context: ToolContext(message: message))
            send(reply, to: message)
        } catch {
            aiLogger.error("[ai] pipeline error: \(error)")
            if isPM { message.reply(message: AIService.errorMessage) }
        }
        await state.release()
    }

    private func send(_ reply: AIReply, to message: IRCPrivateMessage) {
        guard reply.refused == false, reply.text.isEmpty == false else {
            message.reply(message: reply.refused ? AIService.refusalMessage : AIService.emptyMessage)
            return
        }
        let lines = reply.text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.isEmpty == false }
        message.reply(list: lines.isEmpty ? [reply.text] : lines, separator: " ")

        if reply.citations.isEmpty == false {
            let sources = reply.citations.map { "\($0.title): \($0.url)" }.joined(separator: " · ")
            message.reply(list: ["Sources: \(sources)"], separator: " ")
        }
    }

    // MARK: - Helpers

    /// Cooldown key = (client, channel, identity). Channel names collide across networks, so the
    /// client identity discriminates them; identity prefers the authenticated account over the nick.
    private func cooldownKey(_ message: IRCPrivateMessage) -> String {
        let identity = message.user.account ?? message.user.nickname.lowercased()
        return "\(ObjectIdentifier(message.client))|\(message.destination.name.lowercased())|\(identity)"
    }

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
    static let refusalMessage = "I don't have that. Ask a live dispatcher before you invent policy."
    static let emptyMessage = "Nothing useful to say to that."
    static let busyMessage = "Busy. Try again shortly."
    static let errorMessage = "Something broke on my end. Try again shortly."
}
