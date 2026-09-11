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

import AsyncHTTPClient
import Foundation
import Logging
import NIO
import NIOHTTP1

/// Claude backend for `LLMProvider`, talking to the Anthropic Messages API over raw HTTP.
///
/// Every wire field uses explicit `CodingKeys`; the encoder/decoder run with default key
/// strategies (no snake_case conversion) so keys like `input_schema`, `cache_control`,
/// `tool_use_id`, `additionalProperties`, and `cited_text` serialize exactly as the API expects.
struct Anthropic: LLMProvider {
    /// The status + relevant headers + body of one HTTP attempt, decoupled from AsyncHTTPClient
    /// so the retry logic can be exercised in unit tests without a live server.
    struct HTTPParts: Sendable {
        let status: UInt
        let retryAfter: Double?
        let body: Data
    }

    /// Performs one request attempt with the given encoded body.
    typealias Transport = @Sendable (_ body: Data) async throws -> HTTPParts
    /// Sleeps for the given number of seconds (injectable so tests don't actually wait).
    typealias Sleeper = @Sendable (_ seconds: Double) async -> Void

    let maxRetries: Int
    private let transport: Transport
    private let sleeper: Sleeper

    static let messagesURL = "https://api.anthropic.com/v1/messages"
    static let apiVersion = "2023-06-01"

    /// Hard ceiling on any inter-attempt sleep, including a server-supplied `Retry-After`. Prevents a
    /// hostile or misconfigured header from pinning one of the scarce in-flight slots for minutes.
    static let maxRetryDelay: Double = 30

    // Default model identifiers (callers pass the model via the request).
    static let answerModel = "claude-opus-4-8"
    static let gateModel = "claude-haiku-4-5"
    static let translateModel = "claude-haiku-4-5"
    static let timezoneModel = "claude-haiku-4-5"
    static let caseModel = "claude-haiku-4-5"

    /// A decoder that keeps wire keys verbatim (the wire structs carry explicit `CodingKeys`).
    static let decoder = JSONDecoder()
    /// An encoder that keeps wire keys verbatim.
    static let encoder = JSONEncoder()

    /// Production initializer: talks to the Anthropic API via the shared `httpClient`.
    init(token: String, maxRetries: Int = 3, urlString: String = Anthropic.messagesURL) {
        self.maxRetries = maxRetries
        self.sleeper = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
        self.transport = { body in
            var httpRequest = try HTTPClient.Request(url: URL(string: urlString)!, method: .POST)
            httpRequest.headers.add(name: "x-api-key", value: token)
            httpRequest.headers.add(name: "anthropic-version", value: Anthropic.apiVersion)
            httpRequest.headers.add(name: "content-type", value: "application/json")
            httpRequest.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
            httpRequest.body = .data(body)
            let response = try await httpClient.execute(
                request: httpRequest, deadline: .now() + .seconds(180)).get()
            return HTTPParts(
                status: response.status.code,
                retryAfter: response.headers.first(name: "retry-after").flatMap(Double.init),
                body: response.body.map { Data(buffer: $0) } ?? Data())
        }
    }

    /// Testing initializer: inject a fake transport and sleeper.
    init(maxRetries: Int, transport: @escaping Transport, sleeper: @escaping Sleeper) {
        self.maxRetries = maxRetries
        self.transport = transport
        self.sleeper = sleeper
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        let body = try Anthropic.encodeRequestBody(request)

        var lastError: Error = LLMError.retriesExhausted(underlying: "no attempts made")
        for attempt in 1...max(1, maxRetries) {
            // Unwind promptly if a surrounding deadline cancelled us (see AIService.withTimeout).
            try Task.checkCancellation()
            let parts: HTTPParts
            do {
                parts = try await transport(body)
            } catch {
                // Transport-level failure (connection/timeout) — retry with backoff.
                lastError = error
                aiLogger.error("[Anthropic] transport error (attempt \(attempt)/\(maxRetries)): \(error)")
                if attempt < maxRetries {
                    await sleeper(Double(attempt) * 2.0)
                    continue
                }
                throw error
            }

            switch parts.status {
                case 200...202:
                return try Anthropic.parseSuccess(parts.body)

                case 429:
                lastError = LLMError.retriesExhausted(underlying: "429 rate limited")
                let retryAfterText = parts.retryAfter.map { "\($0)" } ?? "n/a"
                aiLogger.warning("[Anthropic] 429 rate limited (attempt \(attempt)/\(maxRetries)), retry-after=\(retryAfterText)")
                if attempt < maxRetries {
                    await sleeper(min(parts.retryAfter ?? Double(attempt) * 2.0, Anthropic.maxRetryDelay))
                    continue
                }
                throw lastError

                case 500...599:
                lastError = LLMError.retriesExhausted(underlying: "server error \(parts.status)")
                aiLogger.error("[Anthropic] server error \(parts.status) (attempt \(attempt)/\(maxRetries))")
                if attempt < maxRetries {
                    await sleeper(Double(attempt) * 2.0)
                    continue
                }
                throw lastError

                default:
                // 4xx (bad request, auth, etc.) — surface immediately, never retry.
                let bodyText = String(data: parts.body, encoding: .utf8) ?? ""
                aiLogger.error("[Anthropic] request failed \(parts.status): \(bodyText)")
                throw LLMError.badRequest(status: parts.status, body: bodyText)
            }
        }
        throw lastError
    }

    /// Encodes a provider-neutral request into the Anthropic wire body.
    static func encodeRequestBody(_ request: LLMRequest) throws -> Data {
        try encoder.encode(AnthropicRequest(from: request))
    }

    /// Decodes a successful (2xx) Anthropic response body, mapping a refusal to `LLMError.refused`.
    static func parseSuccess(_ data: Data) throws -> LLMResponse {
        let decoded = try decoder.decode(AnthropicResponse.self, from: data)
        if decoded.stopReason == LLMStopReason.refusal.rawValue {
            throw LLMError.refused
        }
        return decoded.toLLMResponse()
    }
}

// MARK: - Request wire types

private struct AnthropicRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [AnthropicMessage]
    let tools: [AnthropicTool]?
    let toolChoice: AnthropicToolChoice?
    let temperature: Double?

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case tools
        case toolChoice = "tool_choice"
        case temperature
    }

    init(from request: LLMRequest) {
        self.model = request.model
        self.maxTokens = request.maxTokens
        self.system = request.system
        self.messages = request.messages.map { message in
            AnthropicMessage(
                role: message.role.rawValue,
                content: message.content.map(AnthropicBlock.init(from:)))
        }
        self.tools = request.tools.isEmpty
            ? nil
            : request.tools.map {
                AnthropicTool(name: $0.name, description: $0.description, inputSchema: $0.inputSchema)
            }
        self.toolChoice = request.toolChoice.map(AnthropicToolChoice.init)
        self.temperature = request.temperature
    }
}

private struct AnthropicToolChoice: Encodable {
    let type: String
    let name: String?

    init(_ choice: LLMToolChoice) {
        switch choice {
            case .auto:
            self.type = "auto"
            self.name = nil
            case let .tool(name):
            self.type = "tool"
            self.name = name
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case name
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(name, forKey: .name)
    }
}

private struct AnthropicTool: Encodable {
    let name: String
    let description: String
    let inputSchema: JSONValue

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }
}

private struct AnthropicMessage: Codable {
    let role: String
    let content: [AnthropicBlock]
}

// MARK: - Content blocks

private enum AnthropicBlock: Codable {
    case text(TextBlock)
    case document(DocumentBlock)
    case toolUse(ToolUseBlock)
    case toolResult(ToolResultBlock)

    private enum TypeKey: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let type = try decoder.container(keyedBy: TypeKey.self).decode(String.self, forKey: .type)
        switch type {
            case "text":
            self = .text(try TextBlock(from: decoder))
            case "document":
            self = .document(try DocumentBlock(from: decoder))
            case "tool_use":
            self = .toolUse(try ToolUseBlock(from: decoder))
            case "tool_result":
            self = .toolResult(try ToolResultBlock(from: decoder))
            default:
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unknown content block type '\(type)'"))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
            case let .text(block): try block.encode(to: encoder)
            case let .document(block): try block.encode(to: encoder)
            case let .toolUse(block): try block.encode(to: encoder)
            case let .toolResult(block): try block.encode(to: encoder)
        }
    }

    init(from block: LLMContentBlock) {
        switch block {
            case let .text(text, _):
            self = .text(TextBlock(text: text, citations: nil))
            case let .document(document):
            self = .document(DocumentBlock(
                source: .init(data: document.text),
                title: document.title,
                context: document.context,
                citations: document.enableCitations ? .init(enabled: true) : nil,
                cacheControl: document.cacheControl ? .init() : nil))
            case let .toolUse(id, name, input):
            self = .toolUse(ToolUseBlock(id: id, name: name, input: input))
            case let .toolResult(toolUseId, content, isError):
            self = .toolResult(ToolResultBlock(
                toolUseId: toolUseId, content: content, isError: isError ? true : nil))
        }
    }

    func toLLMBlock() -> LLMContentBlock {
        switch self {
            case let .text(block):
            let citations = (block.citations ?? []).map {
                LLMCitation(
                    citedText: $0.citedText,
                    documentIndex: $0.documentIndex,
                    documentTitle: $0.documentTitle,
                    startCharIndex: $0.startCharIndex,
                    endCharIndex: $0.endCharIndex)
            }
            return .text(block.text, citations: citations)
            case let .document(block):
            return .document(LLMDocument(
                title: block.title ?? "",
                text: block.source.data,
                context: block.context,
                enableCitations: block.citations?.enabled ?? false,
                cacheControl: block.cacheControl != nil))
            case let .toolUse(block):
            return .toolUse(id: block.id, name: block.name, input: block.input)
            case let .toolResult(block):
            return .toolResult(
                toolUseId: block.toolUseId, content: block.content, isError: block.isError ?? false)
        }
    }
}

private struct TextBlock: Codable {
    var type = "text"
    let text: String
    var citations: [AnthropicCitation]?
}

private struct DocumentBlock: Codable {
    var type = "document"
    let source: Source
    let title: String?
    let context: String?
    let citations: CitationsConfig?
    let cacheControl: CacheControl?

    enum CodingKeys: String, CodingKey {
        case type
        case source
        case title
        case context
        case citations
        case cacheControl = "cache_control"
    }

    struct Source: Codable {
        var type = "text"
        var mediaType = "text/plain"
        let data: String

        enum CodingKeys: String, CodingKey {
            case type
            case mediaType = "media_type"
            case data
        }
    }

    struct CitationsConfig: Codable {
        let enabled: Bool
    }

    struct CacheControl: Codable {
        var type = "ephemeral"
    }
}

private struct ToolUseBlock: Codable {
    var type = "tool_use"
    let id: String
    let name: String
    let input: JSONValue
}

private struct ToolResultBlock: Codable {
    var type = "tool_result"
    let toolUseId: String
    let content: String
    let isError: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case toolUseId = "tool_use_id"
        case content
        case isError = "is_error"
    }
}

private struct AnthropicCitation: Codable {
    var type: String?
    let citedText: String
    let documentIndex: Int
    let documentTitle: String?
    let startCharIndex: Int?
    let endCharIndex: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case citedText = "cited_text"
        case documentIndex = "document_index"
        case documentTitle = "document_title"
        case startCharIndex = "start_char_index"
        case endCharIndex = "end_char_index"
    }
}

// MARK: - Response wire types

private struct AnthropicResponse: Decodable {
    let id: String?
    let type: String?
    let role: String?
    let model: String?
    let content: [AnthropicBlock]
    let stopReason: String?
    let usage: Usage?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case role
        case model
        case content
        case stopReason = "stop_reason"
        case usage
    }

    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheReadInputTokens: Int?
        let cacheCreationInputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
        }
    }

    func toLLMResponse() -> LLMResponse {
        LLMResponse(
            content: content.map { $0.toLLMBlock() },
            stopReason: LLMStopReason(apiValue: stopReason),
            usage: LLMUsage(
                inputTokens: usage?.inputTokens ?? 0,
                outputTokens: usage?.outputTokens ?? 0,
                cacheReadInputTokens: usage?.cacheReadInputTokens ?? 0,
                cacheCreationInputTokens: usage?.cacheCreationInputTokens ?? 0))
    }
}
