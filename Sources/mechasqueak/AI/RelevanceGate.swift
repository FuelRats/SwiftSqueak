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

    /// Pure lexical prefilter. Permissive by design — its only job is to cheaply reject obvious
    /// non-questions before the paid stage; the Haiku call is the precise filter.
    static func prefilterPasses(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        let collapsed = lower.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)

        // Pure greeting / thanks / reaction — silent.
        if reactionWords.contains(collapsed) {
            return false
        }
        // A question mark is a strong, sufficient signal.
        if text.contains("?") {
            return true
        }
        // Too short to be a real request (and no question mark).
        if text.count < minLength {
            return false
        }

        let words = lower.split { $0 == " " || $0 == "," || $0 == "!" || $0 == "." }.map(String.init)
        guard let firstWord = words.first else { return false }

        // A yes/no or imperative lead ("is …", "does …", "tell …", "explain …").
        if leadWords.contains(firstWord) {
            return true
        }
        // An interrogative anywhere ("… how does … work").
        if words.contains(where: { interrogatives.contains($0) }) {
            return true
        }
        // Multi-word request phrases.
        if signalPhrases.contains(where: { lower.hasPrefix($0) || lower.contains(" \($0)") }) {
            return true
        }
        return false
    }

    /// Full gate: prefilter, then a Haiku binary classification. Fails closed (silent) on error.
    func isRelevant(_ question: String) async -> Bool {
        guard RelevanceGate.prefilterPasses(question) else {
            return false
        }
        let system = """
        You are a relevance filter for the Fuel Rats' Elite Dangerous assistant bot. The user already \
        addressed the bot by name. Answer 'y' if their message is a genuine question or request — \
        about Fuel Rats procedure, Elite Dangerous, a star system/station/route, the bot's data, or a \
        direct question aimed at the bot itself (what it is or can do) — even if basic, silly, or \
        sloppily phrased. Answer 'n' for greetings, thanks, reactions, statements, and idle chatter \
        with no question or request. Answer with exactly one character: y or n.
        """
        let request = LLMRequest(
            model: model, maxTokens: 1, system: system, messages: [.text(.user, question)])
        do {
            let response = try await provider.complete(request)
            return response.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("y")
        } catch {
            // Fail closed: stay silent in-channel, but surface a log so a dead gate is detectable.
            // Log rate-limiting / ops-channel mirroring is a planned hardening step.
            aiLogger.error("[gate] classification failed, defaulting to silent: \(error)")
            return false
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

    static let leadWords: Set<String> = [
        "how", "what", "whats", "what's", "why", "when", "where", "who", "which", "whose", "whom",
        "is", "are", "am", "was", "were", "do", "does", "did", "can", "could", "should", "would",
        "will", "has", "have", "had", "may", "might", "tell", "explain", "help", "list", "find",
        "show", "give", "describe", "define", "whats"
    ]

    static let interrogatives: Set<String> = [
        "how", "what", "whats", "what's", "why", "when", "where", "who", "which", "whose", "whom"
    ]

    static let signalPhrases: [String] = [
        "tell me", "how do", "how to", "how does", "what is", "what are", "help me",
        "can you", "do you", "is there", "are there", "i need", "i want to know", "explain"
    ]
}
