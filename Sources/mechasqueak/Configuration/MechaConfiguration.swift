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
@preconcurrency import IRCKit

func requireEnv(_ name: String) -> String {
    guard let value = ProcessInfo.processInfo.environment[name] else {
        fatalError("Required environment variable '\(name)' not set")
    }
    return value
}

func env(_ name: String) -> String? {
    ProcessInfo.processInfo.environment[name]
}

struct XboxTokens: Codable {
    var xuid: String
    var uhs: String
    var token: String
    var refreshToken: String
}

struct MechaConfiguration: Sendable {
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

    static func fromEnvironment() -> MechaConfiguration {
        let general = GeneralConfiguration(
            signal: requireEnv("GENERAL_SIGNAL"),
            rescueChannel: requireEnv("GENERAL_RESCUE_CHANNEL"),
            reportingChannel: requireEnv("GENERAL_REPORTING_CHANNEL"),
            drillMode: env("GENERAL_DRILL_MODE") == "true",
            drillChannels: (env("GENERAL_DRILL_CHANNELS") ?? "").split(separator: ",").map(String.init),
            ratDenylist: (env("GENERAL_RAT_DENYLIST") ?? "").split(separator: ",").map(String.init),
            dispatchDenylist: (env("GENERAL_DISPATCH_DENYLIST") ?? "").split(separator: ",").map(String.init),
            cooldownExceptionChannels: (env("GENERAL_COOLDOWN_EXCEPTION_CHANNELS") ?? "")
                .split(separator: ",").map(String.init),
            operLogin: env("GENERAL_OPER_LOGIN")?.split(separator: ",").map(String.init),
            debug: env("GENERAL_DEBUG") == "true"
        )

        var ircConfig = IRCClientConfiguration(
            serverName: requireEnv("IRC_SERVER_NAME"),
            serverAddress: requireEnv("IRC_SERVER_HOST"),
            serverPort: Int(env("IRC_SERVER_PORT") ?? "6697") ?? 6697,
            nickname: requireEnv("IRC_NICKNAME"),
            username: env("IRC_USERNAME") ?? requireEnv("IRC_NICKNAME"),
            realName: env("IRC_REALNAME") ?? requireEnv("IRC_NICKNAME")
        )
        ircConfig.serverPassword = env("IRC_SERVER_PASSWORD")
        ircConfig.authenticationUsername = env("IRC_AUTH_USERNAME")
        ircConfig.authenticationPassword = env("IRC_AUTH_PASSWORD")
        ircConfig.channels = requireEnv("IRC_CHANNELS").split(separator: ",").map(String.init)
        ircConfig.autoConnect = env("IRC_AUTO_CONNECT") != "false"
        ircConfig.autoReconnect = env("IRC_AUTO_RECONNECT") != "false"
        ircConfig.floodControlMaximumMessages = Int(env("IRC_FLOOD_CONTROL_MAX_MESSAGES") ?? "20") ?? 20
        ircConfig.floodControlDelayTimerInterval = Int(env("IRC_FLOOD_CONTROL_DELAY") ?? "3") ?? 3
        ircConfig.prefersInsecureConnection = env("IRC_PREFERS_INSECURE") == "true"
        ircConfig.allowsServerSelfSignedCertificate = env("IRC_ALLOW_SELF_SIGNED_CERT") == "true"
        let channels = ircConfig.channels.map { $0.lowercased() }
        if !channels.contains(general.rescueChannel.lowercased()) {
            fatalError("GENERAL_RESCUE_CHANNEL '\(general.rescueChannel)' is not in IRC_CHANNELS")
        }
        if !channels.contains(general.reportingChannel.lowercased()) {
            fatalError("GENERAL_REPORTING_CHANNEL '\(general.reportingChannel)' is not in IRC_CHANNELS")
        }
        let connections = [ircConfig]

        let api = FuelRatsAPIConfiguration(
            url: URL(string: requireEnv("API_URL"))!,
            websocket: env("API_WEBSOCKET").flatMap(URL.init(string:)),
            userId: UUID(uuidString: requireEnv("API_USER_ID"))!,
            token: requireEnv("API_TOKEN")
        )

        let queue: QueueConfiguration? = env("QUEUE_URL").map {
            QueueConfiguration(url: URL(string: $0)!, token: requireEnv("QUEUE_TOKEN"))
        }

        let database = DatabaseConfiguration(
            host: requireEnv("DB_HOST"),
            port: Int32(env("DB_PORT") ?? "5432") ?? 5432,
            database: requireEnv("DB_NAME"),
            username: requireEnv("DB_USERNAME"),
            password: env("DB_PASSWORD")
        )

        let shortener = URLShortenerConfiguration(
            url: URL(string: requireEnv("SHORTENER_URL"))!,
            signature: requireEnv("SHORTENER_SIGNATURE")
        )

        let sourcePath = URL(fileURLWithPath: env("SOURCE_PATH") ?? FileManager.default.currentDirectoryPath)

        // Xbox: client ID/secret from env, tokens from volume file
        var xbox: XboxLiveConfiguration?
        if let clientId = env("XBOX_CLIENT_ID"),
           let clientSecret = env("XBOX_CLIENT_SECRET") {
            let tokenFile = "/data/xbox_tokens.json"
            if let tokenData = try? Data(contentsOf: URL(fileURLWithPath: tokenFile)),
               let tokens = try? JSONDecoder().decode(XboxTokens.self, from: tokenData) {
                xbox = XboxLiveConfiguration(
                    xuid: tokens.xuid, uhs: tokens.uhs,
                    token: tokens.token, refreshToken: tokens.refreshToken,
                    clientId: clientId, clientSecret: clientSecret
                )
            }
        }

        // PSN: tokens from volume file
        var psn: PlayStationNetworkConfiguration?
        let psnTokenFile = "/data/psn_tokens.json"
        if let tokenData = try? Data(contentsOf: URL(fileURLWithPath: psnTokenFile)),
           let tokens = try? JSONDecoder().decode(PlayStationNetworkConfiguration.self, from: tokenData) {
            psn = tokens
        }

        let chrono: ChronoConfiguration? = {
            guard let nodePath = env("CHRONO_NODE_PATH"),
                  let file = env("CHRONO_FILE") else { return nil }
            return ChronoConfiguration(nodePath: nodePath, file: file)
        }()

        let mastodon = env("MASTODON_TOKEN").map { MastodonConfiguration(token: $0) }

        let bluesky: BlueSkyConfiguration? = {
            guard let handle = env("BLUESKY_HANDLE"),
                  let appPassword = env("BLUESKY_APP_PASSWORD") else { return nil }
            return BlueSkyConfiguration(handle: handle, appPassword: appPassword)
        }()

        let openAIToken = env("OPENAI_TOKEN")

        let webServer: WebServerConfiguration? = {
            guard let host = env("WEB_HOST"), let portStr = env("WEB_PORT"),
                  let port = Int(portStr) else { return nil }
            return WebServerConfiguration(host: host, port: port)
        }()

        return MechaConfiguration(
            general: general, connections: connections, api: api, queue: queue,
            database: database, shortener: shortener, sourcePath: sourcePath,
            xbox: xbox, psn: psn, chrono: chrono, mastodon: mastodon,
            bluesky: bluesky, openAIToken: openAIToken, webServer: webServer
        )
    }
}

struct GeneralConfiguration: Codable, Sendable {
    let signal: String
    let rescueChannel: String
    let reportingChannel: String
    var drillMode: Bool = false
    let drillChannels: [String]
    let ratDenylist: [String]
    let dispatchDenylist: [String]
    let cooldownExceptionChannels: [String]

    let operLogin: [String]?
    var debug: Bool = false
}

struct QueueConfiguration: Codable, Sendable {
    let url: URL
    let token: String
}

struct FuelRatsAPIConfiguration: Codable, Sendable {
    let url: URL
    let websocket: URL?
    let userId: UUID
    let token: String
}

struct DatabaseConfiguration: Codable, Sendable {
    let host: String
    let port: Int32
    let database: String

    let username: String
    let password: String?
}

struct URLShortenerConfiguration: Codable, Sendable {
    let url: URL
    let signature: String
}

struct XboxLiveConfiguration: Codable, Sendable {
    var xuid: String
    var uhs: String
    var token: String
    var refreshToken: String
    let clientId: String
    let clientSecret: String
}

struct PlayStationNetworkConfiguration: Codable, Sendable {
    var token: String
    var refreshToken: String
    var basicAuth: String
}

struct ChronoConfiguration: Codable, Sendable {
    let nodePath: String
    let file: String
}

struct MastodonConfiguration: Codable, Sendable {
    let token: String
}

struct BlueSkyConfiguration: Codable, Sendable {
    let handle: String
    let appPassword: String
}

struct WebServerConfiguration: Codable, Sendable {
    let host: String
    let port: Int
}
