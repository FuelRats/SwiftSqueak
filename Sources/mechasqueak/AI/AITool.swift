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

/// Context passed to every tool invocation. Carries the invoking user's locale (for localized
/// data like facts). Later phases extend this with the invoking command/channel for command
/// dispatch and scrollback.
struct ToolContext: Sendable {
    let locale: Locale

    init(locale: Locale = Locale(identifier: "en")) {
        self.locale = locale
    }
}

/// A model-callable tool. `run` receives the decoded tool input and returns a string (usually
/// compact JSON) that is fed back as an untrusted `tool_result` block — it must never be treated
/// as instructions, and must never trigger a write action.
struct AITool: Sendable {
    let name: String
    let description: String
    let inputSchema: JSONValue
    let run: @Sendable (_ input: JSONValue, _ context: ToolContext) async -> String

    /// The provider-neutral tool descriptor sent to the model.
    var llmTool: LLMTool {
        LLMTool(name: name, description: description, inputSchema: inputSchema)
    }
}

extension Array where Element == AITool {
    /// Looks up a tool by name for the manual tool-use loop.
    func tool(named name: String) -> AITool? {
        first { $0.name == name }
    }

    var llmTools: [LLMTool] {
        map { $0.llmTool }
    }
}

// MARK: - Tool output helpers

enum ToolOutput {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// Encodes a value to a compact JSON string for a tool result, falling back to an error object.
    static func json<T: Encodable>(_ value: T) -> String {
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return #"{"error":"failed to encode result"}"#
        }
        return string
    }

    /// A short error payload the model can react to (e.g. "not found", "lookup failed").
    static func error(_ message: String) -> String {
        json(["error": message])
    }

    /// Truncates a long field so tool results stay within a sane token budget.
    static func truncate(_ text: String, limit: Int = 500) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }
}
