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
import CryptoSwift
import AsyncHTTPClient

class Twitter {
    @available(*, deprecated, message: "Use tweet(message) async instead")
    static func tweet (message: String, complete: @escaping () -> Void, error: @escaping (Error?) -> Void) {
        let url = URLComponents(string: "\(configuration.api.url)/webhooks/twitter")!
        var request = try! HTTPClient.Request(url: url.url!, method: .POST)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.api.token)")
        request.headers.add(name: "Content-Type", value: "application/json")

        request.body = .data(try! JSONSerialization.data(withJSONObject: [
            "message": message
        ], options: []))

        httpClient.execute(request: request).whenCompleteExpecting(status: 200) { result in
            switch result {
                case .success:
                    complete()
                case .failure(let restError):
                    error(restError)
            }
        }
    }
    
    static func tweet (message: String) async throws {
        let url = URLComponents(string: "\(configuration.api.url)/webhooks/twitter")!
        var request = try! HTTPClient.Request(url: url.url!, method: .POST)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.api.token)")
        request.headers.add(name: "Content-Type", value: "application/json")

        request.body = .data(try! JSONSerialization.data(withJSONObject: [
            "message": message
        ], options: []))
        
        _ = try await httpClient.execute(request: request, deadline: nil, expecting: 200)
    }
}

fileprivate extension String {
    var twitterUrlEncoded: String? {
        return self.addingPercentEncoding(withAllowedCharacters: CharacterSet(
            charactersIn: "ABCDEFGHIKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        ))
    }
}
