/*
 Copyright 2021 The Fuel Rats Mischief

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
import NIO
import NIOHTTP1

extension HTTPClient {
    static var defaultJsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(.iso8601Full)
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
    
    func execute <T: AnyRange> (
        request: Request,
        deadline: NIODeadline? = .now() + .seconds(5),
        expecting statusCode: T
    ) async throws -> HTTPClient.Response where T.Bound == Int {
        try await withCheckedThrowingContinuation({ continuation in
            self.execute(request: request, deadline: deadline).whenComplete { result in
                switch result {
                    case .success(let response):
                        if statusCode.contains(Int(response.status.code)) {
                            continuation.resume(returning: response)
                        } else {
                            continuation.resume(throwing: response)
                        }

                    case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        })
    }
    
    func execute<D> (
        request: Request,
        forDecodable decodable: D.Type,
        deadline: NIODeadline? = .now() + .seconds(5),
        withDecoder decoder: JSONDecoder = defaultJsonDecoder
    ) async throws -> D where D: Decodable {
        let response = try await self.execute(request: request, deadline: deadline, expecting: 200...202)
        do {
            guard let body = response.body else {
                debug(request.url.absoluteString)
                debug(String(describing: response))
                if let body = response.body {
                    debug(String(data: Data(buffer: body), encoding: .utf8) ?? "")
                }
                throw response
            }
            return try decoder.decode(D.self, from: Data(buffer: body))
        } catch {
            if let body = response.body {
                debug(String(data: Data(buffer: body), encoding: .utf8) ?? "")
            }
            debug(String(describing: error))
            throw error
        }
    }
}

extension HTTPClient.Request {
    init (apiPath: String, method: HTTPMethod, command: IRCBotCommand? = nil, query: [String: String?] = [:]) throws {
        var url = URLComponents(string: "\(configuration.api.url)")!
        url.path = apiPath
        
        url.queryItems = query.queryItems
        try self.init(url: url.url!, method: method)
        
        self.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        self.headers.add(name: "Authorization", value: "Bearer \(configuration.api.token)")
        self.headers.add(name: "Content-Type", value: "application/vnd.api+json")
        if let command = command, let user = command.message.user.associatedAPIData?.user {
            self.headers.add(name: "x-representing", value: user.id.rawValue.uuidString)
        }
    }
}

extension HTTPClient.Response: @retroactive Error {}

private let sAllowedCharacters: CharacterSet = {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.insert(" ")
    allowed.remove("+")
    allowed.remove("/")
    allowed.remove("?")
    allowed.remove("*")
    allowed.remove("!")
    allowed.remove("$")
    return allowed
}()

private func urlEscape (_ str: String) -> String {
    return str.replacingOccurrences(of: "\n", with: "\r\n")
        .addingPercentEncoding(withAllowedCharacters: sAllowedCharacters)!
        .replacingOccurrences(of: " ", with: "+")
}

extension HTTPClient.Body {
    static func encodable<T: Encodable> (_ object: T) throws -> HTTPClient.Body {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(DateFormatter.iso8601Full)
        return .data(try encoder.encode(object))
    }
    
    static func formUrlEncoded(_ query: [String: String?]) throws -> HTTPClient.Body {
        let str = query.map({ (key, value) -> String in
            if let value = value {
                return "\(urlEscape(key))=\(urlEscape(value))"
            }
            return urlEscape(key)
        }).joined(separator: "&")
        return .string(str)
    }
}

extension Dictionary where Key == String, Value == String? {
    var queryItems: [URLQueryItem] {
        return self.reduce([], { (items, current) in
            var items = items
            items.append(URLQueryItem(name: current.key, value: current.value))
            return items
        })
    }
    
    var formUrlEncoded: Data? {
        let str = self.map({ (key, value) -> String in
            if let value = value {
                return "\(urlEscape(key))=\(urlEscape(value))"
            }
            return urlEscape(key)
        }).joined(separator: "&")
        return str.data(using: .utf8)
    }
}
