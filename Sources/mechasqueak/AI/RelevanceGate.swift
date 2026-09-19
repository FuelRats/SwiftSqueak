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

/// Two-stage relevance gate for the always-listening surface. A free, synchronous prefilter drops
/// obvious non-questions (greetings, thanks, reactions, too-short) without spending a token; what
/// survives goes to a cheap Haiku yes/no. The gate decides "is this a genuine question or request
/// directed at the bot" — a dumb or pointless *question* still passes (it gets answered, with
/// personality); only chatter, greetings, and reactions are silenced.
struct RelevanceGate: Sendable {
    let provider: LLMProvider
    let model: String

    init(provider: LLMProvider, model: String = Anthropic.gateModel) {
        self.provider = provider
        self.model = model
    }

    static let minLength = 5

    /// Pure lexical prefilter. Deliberately permissive: the user already addressed the bot by name,
    /// so its only job is to cheaply drop bare greetings/reactions and too-short noise before the
    /// paid stage. Everything else passes to the Haiku gate, which makes the final call.
    static func prefilterPasses(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = text.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)

        // Pure greeting / thanks / reaction with nothing else — stay silent.
        if reactionWords.contains(collapsed) {
            return false
        }
        // A question mark is always enough.
        if text.contains("?") {
            return true
        }
        // Too short to carry a real message (and no question mark).
        if text.count < minLength {
            return false
        }
        // Addressed by name with actual content: engage. The Haiku gate filters borderline chatter.
        return true
    }

    /// The gate's verdict: whether to answer, whether the paid classification *failed* (an outage,
    /// distinct from a confident "no" — so the caller can surface it rather than silently drop), and the
    /// Haiku token usage to charge against the budget.
    struct Decision: Sendable {
        let relevant: Bool
        let failed: Bool
        let usage: LLMUsage
    }

    /// Full gate: prefilter, then a Haiku binary classification. On error returns `failed` (fails closed
    /// on `relevant`, but the caller can tell an outage apart from a real "no").
    func classify(_ question: String) async -> Decision {
        guard RelevanceGate.prefilterPasses(question) else {
            return Decision(relevant: false, failed: false, usage: LLMUsage())
        }
        let system = """
        You are a relevance filter for MechaSqueak, the Fuel Rats' Elite Dangerous bot. The user \
        ADDRESSED the bot by name, so they almost always want a response. Be permissive: answer 'y' \
        for anything with something to respond to, a question, request, statement, banter aimed at \
        the bot, or a recall/follow-up about the channel conversation, even if basic, silly, \
        off-topic, or sloppily phrased. Answer 'n' ONLY when there is genuinely nothing to respond \
        to: a bare greeting, thanks, or reaction and nothing else (hi, thanks, lol, o7, nice, gg). \
        When in doubt, answer 'y'. Answer with exactly one character: y or n.
        """
        let request = LLMRequest(
            model: model, maxTokens: 1, system: system, messages: [.text(.user, question)])
        do {
            let response = try await provider.complete(request)
            let yes = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased().hasPrefix("y")
            return Decision(relevant: yes, failed: false, usage: response.usage)
        } catch {
            // Fail closed on relevance, but report `failed` so the caller can surface an outage (and
            // count it) instead of silently swallowing every question during an upstream failure.
            aiLogger.error("[gate] classification failed: \(error)")
            return Decision(relevant: false, failed: true, usage: LLMUsage())
        }
    }

    // MARK: - Prefilter vocabulary

    static let reactionWords: Set<String> = [
        "hi", "hii", "hello", "helo", "hey", "heya", "yo", "sup", "hiya", "howdy", "greetings",
        "thanks", "thank", "thankyou", "thx", "ty", "tysm", "cheers", "danke", "gracias",
        "lol", "lmao", "lmfao", "rofl", "haha", "hahaha", "heh", "hehe", "lel", "kek",
        "ok", "okay", "kk", "k", "nice", "cool", "neat", "sweet", "gg", "ggs", "o7", "wow",
        "oof", "rip", "yep", "yup", "nope", "nah", "yeah", "yes", "no", "true", "based", "same",
        "bye", "cya", "gn", "gm", "morning", "night", "welcome", "np"
    ]
}
