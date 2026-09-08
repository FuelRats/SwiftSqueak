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
import Logging

/// AI-subsystem logger. Declared outside `main.swift` so it is lazily initialized on first use,
/// which keeps it valid in the test host (where `main.swift`'s eager globals never run) while
/// still picking up the Gelf backend in production (created after `LoggingSystem.bootstrap`).
let aiLogger = Logger(label: "com.fuelrats.mechasqueak.ai")

/// A provider-neutral chat-completion interface. The concrete `Anthropic` client conforms;
/// the rest of the AI feature depends only on this so the backend stays swappable.
protocol LLMProvider: Sendable {
    func complete(_ request: LLMRequest) async throws -> LLMResponse
}

// MARK: - Request

struct LLMRequest: Sendable {
    let model: String
    let maxTokens: Int
    let system: String?
    var messages: [LLMMessage]
    var tools: [LLMTool]

    init(
        model: String,
        maxTokens: Int,
        system: String? = nil,
        messages: [LLMMessage],
        tools: [LLMTool] = []
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.system = system
        self.messages = messages
        self.tools = tools
    }
}

struct LLMMessage: Sendable {
    enum Role: String, Sendable {
        case user
        case assistant
    }

    let role: Role
    var content: [LLMContentBlock]

    /// Convenience for a plain-text user/assistant turn.
    static func text(_ role: Role, _ text: String) -> LLMMessage {
        LLMMessage(role: role, content: [.text(text, citations: [])])
    }
}

/// A single content block in a message. Documents and tool results carry untrusted
/// content and are never interpreted as instructions (prompt-injection boundary).
enum LLMContentBlock: Sendable {
    /// Assistant/user text. On responses, `citations` may be populated by the provider.
    case text(String, citations: [LLMCitation])
    /// A source document for retrieval-grounded answers (citations + prompt caching).
    case document(LLMDocument)
    /// A tool invocation requested by the model.
    case toolUse(id: String, name: String, input: JSONValue)
    /// The result of executing a tool, fed back to the model.
    case toolResult(toolUseId: String, content: String, isError: Bool)
}

/// A retrievable source document. `enableCitations` turns on grounded citations;
/// `cacheControl` marks the block ephemeral so tool-loop re-sends bill at the cache rate.
struct LLMDocument: Sendable {
    let title: String
    let text: String
    let context: String?
    var enableCitations: Bool
    var cacheControl: Bool

    init(
        title: String,
        text: String,
        context: String? = nil,
        enableCitations: Bool = true,
        cacheControl: Bool = true
    ) {
        self.title = title
        self.text = text
        self.context = context
        self.enableCitations = enableCitations
        self.cacheControl = cacheControl
    }
}

struct LLMTool: Sendable {
    let name: String
    let description: String
    /// A JSON Schema object describing the tool input (`additionalProperties: false`).
    let inputSchema: JSONValue
}

// MARK: - Response

struct LLMResponse: Sendable {
    let content: [LLMContentBlock]
    let stopReason: LLMStopReason
    let usage: LLMUsage

    /// All text blocks concatenated (ignores documents/tool blocks).
    var text: String {
        content.compactMap { block in
            if case let .text(value, _) = block { return value }
            return nil
        }.joined()
    }

    /// Citations attached to any text block, in order.
    var citations: [LLMCitation] {
        content.flatMap { block -> [LLMCitation] in
            if case let .text(_, citations) = block { return citations }
            return []
        }
    }

    /// Tool-use blocks the model wants executed this round.
    var toolCalls: [(id: String, name: String, input: JSONValue)] {
        content.compactMap { block in
            if case let .toolUse(id, name, input) = block { return (id, name, input) }
            return nil
        }
    }
}

enum LLMStopReason: String, Sendable {
    case endTurn = "end_turn"
    case toolUse = "tool_use"
    case maxTokens = "max_tokens"
    case stopSequence = "stop_sequence"
    case pauseTurn = "pause_turn"
    case refusal
    case unknown

    init(apiValue: String?) {
        self = apiValue.flatMap(LLMStopReason.init(rawValue:)) ?? .unknown
    }
}

struct LLMCitation: Sendable, Equatable {
    let citedText: String
    let documentIndex: Int
    let documentTitle: String?
    let startCharIndex: Int?
    let endCharIndex: Int?
}

struct LLMUsage: Sendable, Equatable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadInputTokens: Int
    let cacheCreationInputTokens: Int

    init(
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadInputTokens: Int = 0,
        cacheCreationInputTokens: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
    }

    /// Accumulates usage across the rounds of a tool loop.
    static func + (lhs: LLMUsage, rhs: LLMUsage) -> LLMUsage {
        LLMUsage(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            cacheReadInputTokens: lhs.cacheReadInputTokens + rhs.cacheReadInputTokens,
            cacheCreationInputTokens: lhs.cacheCreationInputTokens + rhs.cacheCreationInputTokens)
    }
}

// MARK: - Errors

enum LLMError: Error, Sendable {
    /// The API returned a non-retryable client error (e.g. 400); do not retry.
    case badRequest(status: UInt, body: String)
    /// The model declined to answer (`stop_reason == "refusal"`).
    case refused
    /// Retries were exhausted after transient failures.
    case retriesExhausted(underlying: String)
}
