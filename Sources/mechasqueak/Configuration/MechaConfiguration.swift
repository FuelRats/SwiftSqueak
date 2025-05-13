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
import IRCKit
import DefaultCodable

struct MechaConfiguration: Codable {
    let general: GeneralConfiguration
    let connections: [IRCClientConfiguration]
    let api: FuelRatsAPIConfiguration
    let queue: QueueConfiguration?
    let database: DatabaseConfiguration
    let shortener: URLShortenerConfiguration
    let sourcePath: URL
    var xbox: XboxLiveConfiguration?
    var psn: PlayStationNetworkConfiguration?
    let chrono: ChronoConfiguration?
    let mastodon: MastodonConfiguration?
    let bluesky: BlueSkyConfiguration?
    let openAIToken: String?
    let webServer: WebServerConfiguration?
    
    func save () throws {
        let configEncoder = JSONEncoder()
        configEncoder.outputFormatting = .prettyPrinted
        let json = try configEncoder.encode(self)
        try json.write(to: configPath)
    }
}

struct GeneralConfiguration: Codable {
    let signal: String
    let rescueChannel: String
    let reportingChannel: String
    @Default<False>
    var drillMode: Bool
    let drillChannels: [String]
    let ratBlacklist: [String]
    let dispatchBlacklist: [String]
    let cooldownExceptionChannels: [String]

    let operLogin: [String]?
    @Default<False>
    var debug: Bool
}

struct QueueConfiguration: Codable {
    let url: URL
    let token: String
}

struct FuelRatsAPIConfiguration: Codable {
    let url: URL
    let websocket: URL?
    let userId: UUID
    let token: String
}

struct DatabaseConfiguration: Codable {
    let host: String
    let port: Int32
    let database: String

    let username: String
    let password: String?
}

struct URLShortenerConfiguration: Codable {
    let url: URL
    let signature: String
}

struct XboxLiveConfiguration: Codable {
    var xuid: String
    var uhs: String
    var token: String
    var refreshToken: String
    let clientId: String
    let clientSecret: String
}

struct PlayStationNetworkConfiguration: Codable {
    var token: String
    var refreshToken: String
    var basicAuth: String
}

struct ChronoConfiguration: Codable {
    let nodePath: String
    let file: String
}

struct MastodonConfiguration: Codable {
    let token: String
}

struct BlueSkyConfiguration: Codable {
    let handle: String
    let appPassword: String
}

struct WebServerConfiguration: Codable {
    let host: String
    let port: Int
}
