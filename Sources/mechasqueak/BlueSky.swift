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
import AsyncHTTPClient

struct BlueSky {
    static func auth(config: BlueSkyConfiguration) async throws -> BlueSkyAuthResponse {
        let requestUrl = URL(string: "https://bsky.social/xrpc/com.atproto.server.createSession")!

        var request = try HTTPClient.Request(url: requestUrl, method: .POST)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Content-Type", value: "application/json")
        let body = BlueSkyAuthRequest(identifier: config.handle, password: config.appPassword)
        request.body = try .encodable(body)

        return try await httpClient.execute(request: request, forDecodable: BlueSkyAuthResponse.self)
    }

    @discardableResult
    static func post(message: String, link: String? = nil) async throws -> BlueSkyPostResponse {
        guard let config = configuration.bluesky else { throw BlueSkyErrors.missingConfiguration }

        let auth = try await auth(config: config)
        var facets: [BlueSkyPost.Record.Facet] = []
        if let link = link {
            let byteStart = message.bytes.endIndex - link.bytes.count
            let bytesEnd = message.bytes.endIndex
            let facet = BlueSkyPost.Record.Facet(
                index: .init(byteStart: byteStart, byteEnd: bytesEnd),
                features: [.init(type: "app.bsky.richtext.facet#link", uri: link)]
            )
            facets.append(facet)
        }
        let post = BlueSkyPost(
            repo: "alerts.fuelrats.com",
            collection: "app.bsky.feed.post",
            record: .init(
                text: message,
                createdAt: Date(),
                type: "app.bsky.feed.post",
                facets: facets
            )
        )

        let requestUrl = URL(string: "https://bsky.social/xrpc/com.atproto.repo.createRecord")!

        var request = try HTTPClient.Request(url: requestUrl, method: .POST)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Content-Type", value: "application/json")
        request.headers.add(name: "Authorization", value: "Bearer \(auth.accessJwt)")
        request.body = try .encodable(post)

        return try await httpClient.execute(request: request, forDecodable: BlueSkyPostResponse.self)
    }
}

struct BlueSkyAuthRequest: Codable {
    let identifier: String
    let password: String
}

struct BlueSkyAuthResponse: Codable {
    let did: String
    let handle: String
    let email: String
    let accessJwt: String
    let refreshJwt: String
}

struct BlueSkyPost: Codable {
    let repo: String
    let collection: String
    let record: Record
    
    struct Record: Codable {
        enum CodingKeys: String, CodingKey {
            case text
            case createdAt
            case type = "$type"
            case facets
        }
        
        let text: String
        let createdAt: Date
        let type: String
        let facets: [Facet]
        
        struct Facet: Codable {
            let index: Index
            let features: [Feature]
            
            struct Index: Codable {
                let byteStart: Int
                let byteEnd: Int
            }
            
            struct Feature: Codable {
                enum CodingKeys: String, CodingKey {
                    case type = "$type"
                    case uri
                }
                let type: String
                let uri: String
            }
        }
    }
}

struct BlueSkyPostResponse: Codable {
    let uri: String
    let cid: String
    let commit: Commit
    let validationStatus: String
    
    struct Commit: Codable {
        let cid: String
        let rev: String
    }
}

enum BlueSkyErrors: Error {
    case missingConfiguration
}
