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
import NIO
import AsyncHTTPClient

class QueueAPI {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(.iso8601Full)
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
    
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(.iso8601Full)
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
    
    static func getConfig () -> EventLoopFuture<QueueAPIConfiguration> {
        let requestUrl = configuration.queue!.url.appendingPathComponent("/config/")
        var request = try! HTTPClient.Request(url: requestUrl, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.queue!.token)")

        return httpClient.execute(request: request, forDecodable: QueueAPIConfiguration.self, withDecoder: decoder)
    }

    static func fetchQueue () -> EventLoopFuture<[QueueParticipant]> {
        let requestUrl = configuration.queue!.url.appendingPathComponent("/queue/")
        var request = try! HTTPClient.Request(url: requestUrl, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.queue!.token)")

        return httpClient.execute(request: request, forDecodable: [QueueParticipant].self, withDecoder: decoder)
    }
    
    @discardableResult
    static func dequeue () -> EventLoopFuture<QueueParticipant> {
        var requestUrl = configuration.queue!.url.appendingPathComponent("/queue")
        requestUrl.appendPathComponent("/dequeue")

        var request = try! HTTPClient.Request(url: requestUrl, method: .POST)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.queue!.token)")

        return httpClient.execute(request: request, forDecodable: QueueParticipant.self, withDecoder: decoder)
    }
    
    @discardableResult
    static func setMaxActiveClients (_ maxActiveClients: Int) -> EventLoopFuture<QueueAPIConfiguration> {
        var requestUrl = URLComponents(url: configuration.queue!.url, resolvingAgainstBaseURL: true)!
        requestUrl.path.append("/config/max_active_clients")
        requestUrl.queryItems = [URLQueryItem(name: "max_active_clients", value: String(maxActiveClients))]

        var request = try! HTTPClient.Request(url: requestUrl.url!, method: .PUT)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.queue!.token)")

        return httpClient.execute(request: request, forDecodable: QueueAPIConfiguration.self, withDecoder: QueueAPI.decoder)
    }
}

struct QueueAPIConfiguration: Codable {
    let maxActiveClients: Int
    let clearOnRestart: Bool
    let prioritizeCr: Bool
    let prioritizeNonCr: Bool
}

