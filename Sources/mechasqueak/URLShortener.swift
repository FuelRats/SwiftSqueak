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

import Foundation
import AsyncHTTPClient

class URLShortener {
    static func shorten (
        url: URL, keyword: String?,
        complete: @escaping (ShortURLResponse) -> Void,
        error: @escaping (Error?) -> Void
    ) {
        var requestUrl = URLComponents(string: configuration.shortener.url)!
        requestUrl.queryItems = [
            URLQueryItem(name: "action", value: "shorturl"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "url", value: url.absoluteString),
            URLQueryItem(name: "signature", value: configuration.shortener.signature)
        ]

        if let keyword = keyword {
            requestUrl.queryItems?.append(URLQueryItem(name: "keyword", value: keyword))
        }

        var request = try! HTTPClient.Request(url: requestUrl.url!, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)

        httpClient.execute(request: request).whenCompleteExpecting(status: 200) { result in
            switch result {
                case .success(let response):
                    let decoder = JSONDecoder()

                    guard let shortenResult = try? decoder.decode(ShortURLResponse.self, from: Data(buffer: response.body!)) else {
                        error(nil)
                        return
                    }
                    complete(shortenResult)
                case .failure(let restError):
                    error(restError)
            }
        }
    }

    static func attemptShorten (url: URL, complete: @escaping (URL) -> Void) {
        URLShortener.shorten(url: url, keyword: nil, complete: { response in
            complete(response.shorturl)
        }, error: { _ in
            complete(url)
        })
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
