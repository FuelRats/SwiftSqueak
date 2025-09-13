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
import IRCKit
import NIO
import NIOHTTP1

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

    static func getConfig() async throws -> QueueAPIConfiguration {
        let request = try HTTPClient.Request(queuePath: "/config/", method: .GET)

        return try await httpClient.execute(
            request: request, forDecodable: QueueAPIConfiguration.self, withDecoder: decoder)
    }

    static func fetchStatistics(fromDate date: Date) async throws -> QueueAPIStatistics {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "YYYY-MM-dd"
        let formattedDate = dateFormatter.string(from: date)

        let request = try HTTPClient.Request(
            queuePath: "/queue/statistics/", method: .POST,
            query: ["daterequested": formattedDate, "detailed": "false"])

        return try await httpClient.execute(
            request: request, forDecodable: QueueAPIStatistics.self, withDecoder: decoder)
    }

    static func fetchQueue() async throws -> [QueueParticipant] {
        let request = try HTTPClient.Request(queuePath: "/queue/", method: .GET)

        return try await httpClient.execute(
            request: request, forDecodable: [QueueParticipant].self, withDecoder: decoder)
    }

    @discardableResult
    static func dequeue() async throws -> QueueParticipant {
        let request = try HTTPClient.Request(queuePath: "/queue/dequeue", method: .POST)

        let participant = try await httpClient.execute(
            request: request, forDecodable: QueueParticipant.self, withDecoder: decoder)

        do {
            try await anticipateQueueJoin(participant: participant)
            return participant
        } catch {
            return try await dequeue()
        }
    }

    @discardableResult
    static func setMaxActiveClients(_ maxActiveClients: Int) async throws -> QueueAPIConfiguration {
        let request = try HTTPClient.Request(
            queuePath: "/config/max_active_clients", method: .PUT,
            query: ["max_active_clients": String(maxActiveClients)])

        return try await httpClient.execute(
            request: request, forDecodable: QueueAPIConfiguration.self,
            withDecoder: QueueAPI.decoder)
    }

    static func awaitQueueJoin(participant: QueueParticipant) -> EventLoopFuture<Void> {
        let future = loop.next().makePromise(of: Void.self)

        // Immedately resolve if client is already being rescued
        Task {
            if await board.first(where: {
                $0.value.client?.lowercased() == participant.client.name.lowercased()
            }) != nil {
                future.succeed(())
            }

            // Add a reference of pending client joins
            QueueAPI.pendingQueueJoins[participant.client.name.lowercased()] = future

            // Make a 15 second timeout where mecha will give up on the client joining
            loop.next().scheduleTask(
                in: .seconds(15),
                {
                    Task {
                        if let promise = QueueAPI.pendingQueueJoins[
                            participant.client.name.lowercased()] {
                            promise.fail(ClientJoinError.joinFailed)
                            await board.removePendingJoin(key: participant.client.name.lowercased())
                        }
                    }
                })
        }

        return future.futureResult
    }

    static func anticipateQueueJoin(participant: QueueParticipant) async throws {
        // Immedately resolve if client is already being rescued
        if await board.first(where: {
            $0.value.client?.lowercased() == participant.client.name.lowercased()
        }) != nil {
            return
        }

        return try await withCheckedThrowingContinuation({ continuation in
            awaitQueueJoin(participant: participant).whenComplete({ result in
                switch result {
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    case .success:
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
            return Double(time).timeSpan(maximumUnits: 2)
        }
        return 0.0.timeSpan(maximumUnits: 2)
    }

    var averageRescuetimeSpan: String {
        if let time = self.averageRescuetime {
            return Double(time).timeSpan(maximumUnits: 2)
        }
        return 0.0.timeSpan(maximumUnits: 2)
    }

    var longestQueuetimeSpan: String {
        if let time = self.longestQueuetime {
            return Double(time).timeSpan(maximumUnits: 2)
        }
        return 0.0.timeSpan(maximumUnits: 2)
    }
}

extension HTTPClient.Request {
    init(queuePath: String, method: HTTPMethod, query: [String: String?] = [:]) throws {
        var url = URLComponents(url: configuration.queue!.url, resolvingAgainstBaseURL: false)!

        url.queryItems = query.queryItems
        try self.init(url: url.url!.appendingPathComponent(queuePath), method: method)

        self.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        self.headers.add(name: "Authorization", value: "Bearer \(configuration.queue!.token)")
        self.headers.add(name: "Content-Type", value: "application/vnd.api+json")
    }
}
