/*
 Copyright 2020 The Fuel Rats Mischief

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
import NIO

class URLShortener {
    static func shorten(url: URL, keyword: String? = nil) async throws -> ShortURLResponse {
        var fields = [
            ("action", "shorturl"),
            ("format", "json"),
            ("url", url.absoluteString),
            ("signature", configuration.shortener.signature)
        ]
        if let keyword = keyword {
            fields.append(("keyword", keyword))
        }

        // POSTed as a form so the signature stays out of the query string, and therefore out of access logs.
        var request = try HTTPClient.Request(url: configuration.shortener.url, method: .POST)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Content-Type", value: "application/x-www-form-urlencoded")
        request.body = .string(formEncoded(fields))

        return try await httpClient.execute(request: request, forDecodable: ShortURLResponse.self)
    }

    /// Characters that never need escaping in a form body. Notably excludes "+", which a form decoder reads as space.
    private static let formValueAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

    static func formEncoded(_ fields: [(String, String)]) -> String {
        return fields.map({ name, value in
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: formValueAllowed) ?? ""
            return "\(name)=\(encodedValue)"
        }).joined(separator: "&")
    }

    static func attemptShorten(url: URL) async -> URL {
        do {
            return try await shorten(url: url).shorturl
        } catch {
            return url
        }
    }
}

struct ShortURLResponse: Codable {
    struct URLShortenInfo: Codable {
        let keyword: String
        let url: URL
        let title: String
        let date: String
        let ip: String
    }

    let url: URLShortenInfo
    let status: String
    let message: String
    let title: String
    let shorturl: URL
    let statusCode: Int
}
