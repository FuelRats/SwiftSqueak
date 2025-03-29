/*
 Copyright 2025 The Fuel Rats Mischief

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
import IRCKit
import AsyncHTTPClient

struct OpenAI {
    static func request (params: OpenAIRequest) async throws -> OpenAIResponse {
        var request = try HTTPClient.Request(url: URL(string: "https://api.openai.com/v1/chat/completions")!, method: .POST)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.openAIToken ?? "")")
        request.headers.add(name: "Content-Type", value: "application/json")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(params)
        request.body = .data(data)

        return try await httpClient.execute(request: request, forDecodable: OpenAIResponse.self)
    }
}

struct OpenAIMessage: Codable {
    let role: OpenAIRole
    let content: String
    
    enum OpenAIRole: String, Codable {
        case system
        case assistant
        case user
    }
}

struct OpenAIRequest: Codable {
    let model: String
    let temperature: Double
    let maxTokens: Int?
    let messages: [OpenAIMessage]
    
    init (messages: [OpenAIMessage], model: String = "gpt-4o", temperature: Double = 1.0, maxTokens: Int? = nil) {
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.messages = messages
    }
}

struct OpenAIResponse: Codable {
    let id: String
    let object: String
    let usage: OpenAIUsage
    let choices: [OpenAIChoice]
    
    struct OpenAIUsage: Codable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int
    }
    
    struct OpenAIChoice: Codable {
        let message: OpenAIMessage
        let finishReason: String?
        let index: Int
    }
}
