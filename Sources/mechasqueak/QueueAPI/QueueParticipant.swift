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

struct QueueParticipant: Codable, Hashable {
    let uuid: UUID
    let arrivalTime: Date
    var pending: Bool
    var inProgress: Bool
    var client: QueueClient

    struct QueueClient: Codable, Hashable {
        private enum CodingKeys: String, CodingKey {
            case id
            case name = "clientName"
            case system = "clientSystem"
            case platform
            case locale
            case o2Status = "o2Status"
            case expansion
        }
        let id: Int
        var name: String
        var system: String
        var platform: GamePlatform
        var locale: String
        var o2Status: Bool
        var expansion: GameExpansion?
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.uuid = try container.decode(UUID.self, forKey: .uuid)
        if let arrivalTime = try? container.decode(Date.self, forKey: .arrivalTime) {
            self.arrivalTime = arrivalTime
        } else {
            let arrivalTimeString = try container.decode(String.self, forKey: .arrivalTime)
            if let shortArrivalTime = DateFormatter.iso8601Short.date(from: arrivalTimeString) {
                self.arrivalTime = shortArrivalTime
            } else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "No valid date found"))
            }
        }
        self.pending = try container.decode(Bool.self, forKey: .pending)
        self.inProgress = try container.decode(Bool.self, forKey: .inProgress)
        self.client = try container.decode(QueueClient.self, forKey: .client)
    }
    
    @discardableResult
    func setInProgress () async throws -> QueueParticipant {
        var request = try! HTTPClient.Request(queuePath: "/queue/uuid/\(self.uuid.uuidString.lowercased())", method: .PUT)
        
        var queueItem = self
        queueItem.inProgress = true
        request.body = try! .data(QueueAPI.encoder.encode(queueItem))

        return try await httpClient.execute(request: request, forDecodable: QueueParticipant.self, withDecoder: QueueAPI.decoder)
    }
    
    @discardableResult
    func changeName (name: String) async throws -> QueueParticipant {
        var request = try! HTTPClient.Request(queuePath: "/queue/uuid/\(self.uuid.uuidString.lowercased())", method: .PUT)
        
        var queueItem = self
        queueItem.client.name = name
        request.body = try! .data(QueueAPI.encoder.encode(queueItem))

        return try await httpClient.execute(request: request, forDecodable: QueueParticipant.self, withDecoder: QueueAPI.decoder)
    }
    
    @discardableResult
    func delete () async throws -> HTTPClient.Response {
        let request = try! HTTPClient.Request(queuePath: "/queue/uuid/\(self.uuid.uuidString.lowercased())", method: .DELETE)

        return try await httpClient.execute(request: request, deadline: nil, expecting: 204)
    }
}
