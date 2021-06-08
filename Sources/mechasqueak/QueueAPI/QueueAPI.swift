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
import IRCKit

class QueueAPI {
    static var pendingQueueJoins: [String: EventLoopPromise<Void>] = [:]
    
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
    
    @available(*, deprecated, message: "Use getConfig() async instead")
    static func getConfig () -> EventLoopFuture<QueueAPIConfiguration> {
        let requestUrl = configuration.queue!.url.appendingPathComponent("/config/")
        var request = try! HTTPClient.Request(url: requestUrl, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.queue!.token)")

        return httpClient.execute(request: request, forDecodable: QueueAPIConfiguration.self, withDecoder: decoder)
    }
    
    static func getConfig () async throws -> QueueAPIConfiguration {
        let requestUrl = configuration.queue!.url.appendingPathComponent("/config/")
        var request = try! HTTPClient.Request(url: requestUrl, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.queue!.token)")

        return try await httpClient.execute(request: request, forDecodable: QueueAPIConfiguration.self, withDecoder: decoder)
    }
    
    @available(*, deprecated, message: "Use fetchStatistics(fromDate date) async instead")
    static func fetchStatistics (fromDate date: Date) -> EventLoopFuture<QueueAPIStatistics> {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "YYYY-MM-dd"
        
        let formattedDate = dateFormatter.string(from: date)
        var requestUrl = URLComponents(url: configuration.queue!.url, resolvingAgainstBaseURL: true)!
        requestUrl.path.append("/queue/statistics/")
        requestUrl.queryItems = [URLQueryItem(name: "daterequested", value: formattedDate), URLQueryItem(name: "detailed", value: "false")]
        
        var request = try! HTTPClient.Request(url: requestUrl.url!, method: .POST)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.queue!.token)")

        return httpClient.execute(request: request, forDecodable: QueueAPIStatistics.self, withDecoder: decoder)
    }
    
    static func fetchStatistics (fromDate date: Date) async throws -> QueueAPIStatistics {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "YYYY-MM-dd"
        
        let formattedDate = dateFormatter.string(from: date)
        var requestUrl = URLComponents(url: configuration.queue!.url, resolvingAgainstBaseURL: true)!
        requestUrl.path.append("/queue/statistics/")
        requestUrl.queryItems = [URLQueryItem(name: "daterequested", value: formattedDate), URLQueryItem(name: "detailed", value: "false")]
        
        var request = try! HTTPClient.Request(url: requestUrl.url!, method: .POST)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.queue!.token)")

        return try await httpClient.execute(request: request, forDecodable: QueueAPIStatistics.self, withDecoder: decoder)
    }

    @available(*, deprecated, message: "Use fetchQueue() async instead")
    static func fetchQueue () -> EventLoopFuture<[QueueParticipant]> {
        let requestUrl = configuration.queue!.url.appendingPathComponent("/queue/")
        var request = try! HTTPClient.Request(url: requestUrl, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.queue!.token)")

        return httpClient.execute(request: request, forDecodable: [QueueParticipant].self, withDecoder: decoder)
    }
    
    static func fetchQueue () async throws -> [QueueParticipant] {
        let requestUrl = configuration.queue!.url.appendingPathComponent("/queue/")
        var request = try! HTTPClient.Request(url: requestUrl, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.queue!.token)")

        return try await httpClient.execute(request: request, forDecodable: [QueueParticipant].self, withDecoder: decoder)
    }
    
    @available(*, deprecated, message: "Use dequeue() async instead")
    @discardableResult
    static func dequeue (existingPromise: EventLoopPromise<QueueParticipant>? = nil) -> EventLoopFuture<QueueParticipant> {
        let promise = existingPromise ?? loop.next().makePromise(of: QueueParticipant.self)
        var requestUrl = configuration.queue!.url.appendingPathComponent("/queue")
        requestUrl.appendPathComponent("/dequeue")

        var request = try! HTTPClient.Request(url: requestUrl, method: .POST)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.queue!.token)")

        httpClient.execute(request: request, forDecodable: QueueParticipant.self, withDecoder: decoder).whenComplete({ result in
            switch result {
            case .failure(let error):
                promise.fail(error)
                
            case .success(let participant):
                awaitQueueJoin(participant: participant).whenComplete({ result in
                    switch result {
                    case .failure(_):
                        dequeue(existingPromise: promise)
                    case .success(_):
                        promise.succeed(participant)
                    }
                })
            }
        })
        return promise.futureResult
    }
    
    @discardableResult
    static func dequeue () async throws -> QueueParticipant {
        var requestUrl = configuration.queue!.url.appendingPathComponent("/queue")
        requestUrl.appendPathComponent("/dequeue")

        var request = try! HTTPClient.Request(url: requestUrl, method: .POST)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.queue!.token)")
        
        let participant = try await httpClient.execute(request: request, forDecodable: QueueParticipant.self, withDecoder: decoder)
        
        do {
            try await anticipateQueueJoin(participant: participant)
            return participant
        } catch {
            return try await dequeue()
        }
    }
    
    @available(*, deprecated, message: "Use setMaxActiveClients(_ maxActiveClients) async instead")
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
    
    @discardableResult
    static func setMaxActiveClients (_ maxActiveClients: Int) async throws -> QueueAPIConfiguration {
        var requestUrl = URLComponents(url: configuration.queue!.url, resolvingAgainstBaseURL: true)!
        requestUrl.path.append("/config/max_active_clients")
        requestUrl.queryItems = [URLQueryItem(name: "max_active_clients", value: String(maxActiveClients))]

        var request = try! HTTPClient.Request(url: requestUrl.url!, method: .PUT)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.queue!.token)")

        return try await httpClient.execute(request: request, forDecodable: QueueAPIConfiguration.self, withDecoder: QueueAPI.decoder)
    }
    
    
    static func awaitQueueJoin (participant: QueueParticipant) -> EventLoopFuture<Void> {
        let future = loop.next().makePromise(of: Void.self)
        
        // Immedately resolve if client is already being rescued
        if mecha.rescueBoard.rescues.first(where: { $0.client?.lowercased() == participant.client.name.lowercased() }) != nil {
            future.succeed(())
        }
        
        // Add a reference of pending client joins
        QueueAPI.pendingQueueJoins[participant.client.name.lowercased()] = future
        
        // Make a 15 second timeout where mecha will give up on the client joining
        loop.next().scheduleTask(in: .seconds(15), {
            if let promise = QueueAPI.pendingQueueJoins[participant.client.name.lowercased()] {
                promise.fail(ClientJoinError.joinFailed)
                RescueBoard.pendingClientJoins.removeValue(forKey: participant.client.name.lowercased())
            }
        })
        
        return future.futureResult
    }
    
    static func anticipateQueueJoin (participant: QueueParticipant) async throws -> Void {
        // Immedately resolve if client is already being rescued
        if mecha.rescueBoard.rescues.first(where: { $0.client?.lowercased() == participant.client.name.lowercased() }) != nil {
            return
        }
        
        return try await withCheckedThrowingContinuation({ continuation in
            awaitQueueJoin(participant: participant).whenComplete({ result in
                switch result {
                case .failure(let error):
                    continuation.resume(throwing: error)
                case .success(_):
                    continuation.resume(returning: ())
                }
                
            })
        })
    }
}

struct QueueAPIConfiguration: Codable {
    let maxActiveClients: Int
    let clearOnRestart: Bool
    let prioritizeCr: Bool
    let prioritizeNonCr: Bool
}

struct QueueAPIStatistics: Codable {
    let totalClients: Int?
    let instantJoin: Int?
    let queuedJoin: Int?
    let averageQueuetime: Int?
    let averageRescuetime: Int?
    let longestQueuetime: Int?
    let lostQueues: Int?
    let successfulQueues: Int?
    
    var averageQueuetimeSpan: String {
        if let time = self.averageQueuetime {
            return Double(time).timeSpan
        }
        return 0.0.timeSpan
    }
    
    var averageRescuetimeSpan: String {
        if let time = self.averageRescuetime {
            return Double(time).timeSpan
        }
        return 0.0.timeSpan
    }
    
    var longestQueuetimeSpan: String {
        if let time = self.longestQueuetime {
            return Double(time).timeSpan
        }
        return 0.0.timeSpan
    }
}
