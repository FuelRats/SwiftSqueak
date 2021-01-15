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
    let pending: Bool
    let client: QueueClient

    struct QueueClient: Codable, Hashable {
        private enum CodingKeys: String, CodingKey {
            case id
            case name = "client_name"
            case system = "client_system"
            case platform
            case locale
            case o2Status = "o2_status"
        }
        let id: Int
        let name: String
        let system: String
        let platform: GamePlatform
        let locale: Locale
        let o2Status: Bool
    }

    func dequeue () -> EventLoopFuture<QueueParticipant> {
        var requestUrl = configuration.queue.url.appendingPathComponent("/queue")
        requestUrl.appendPathComponent(self.uuid.uuidString)
        requestUrl.appendPathComponent("/dequeue")

        var request = try! HTTPClient.Request(url: requestUrl, method: .POST)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)

        return httpClient.execute(request: request, forDecodable: QueueParticipant.self)
    }
}
