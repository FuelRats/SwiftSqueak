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

func readSecret(_ name: String) -> String? {
    let path = "/run/secrets/\(name)"
    return try? String(contentsOfFile: path, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func requireSecret(_ name: String) -> String {
    guard let value = readSecret(name) else {
        fatalError("Required Docker secret '\(name)' not found at /run/secrets/\(name)")
    }
    return value
}

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
        ircConfig.serverPassword = readSecret("irc_server_password")
        ircConfig.authenticationUsername = readSecret("irc_auth_username")
        ircConfig.authenticationPassword = readSecret("irc_auth_password")
        ircConfig.channels = requireEnv("IRC_CHANNELS").split(separator: ",").map(String.init)
        let connections = [ircConfig]

        let api = FuelRatsAPIConfiguration(
            url: URL(string: requireEnv("API_URL"))!,
            websocket: env("API_WEBSOCKET").flatMap(URL.init(string:)),
            userId: UUID(uuidString: requireSecret("api_user_id"))!,
            token: requireSecret("api_token")
        )

        let queue: QueueConfiguration? = env("QUEUE_URL").map {
            QueueConfiguration(url: URL(string: $0)!, token: requireSecret("queue_token"))
        }

        let database = DatabaseConfiguration(
            host: requireEnv("DB_HOST"),
            port: Int32(env("DB_PORT") ?? "5432") ?? 5432,
            database: requireEnv("DB_NAME"),
            username: requireSecret("db_username"),
            password: readSecret("db_password")
        )

        let shortener = URLShortenerConfiguration(
            url: URL(string: requireEnv("SHORTENER_URL"))!,
            signature: requireSecret("shortener_signature")
        )

        let sourcePath = URL(fileURLWithPath: env("SOURCE_PATH") ?? FileManager.default.currentDirectoryPath)

        // Xbox: client ID/secret from secrets, tokens from volume file
        var xbox: XboxLiveConfiguration?
        if let clientId = readSecret("xbox_client_id"),
           let clientSecret = readSecret("xbox_client_secret") {
            let tokenFile = "/data/xbox_tokens.json"
            if let tokenData = try? Data(contentsOf: URL(fileURLWithPath: tokenFile)),
               let tokens = try? JSONDecoder().decode(XboxTokens.self, from: tokenData) {
                xbox = XboxLiveConfiguration(
                    xuid: tokens.xuid, uhs: tokens.uhs,
                    token: tokens.token, refreshToken: tokens.refreshToken,
                    clientId: clientId, clientSecret: clientSecret
                )
            } else {
                // No token file yet — Xbox features disabled until seeded
                xbox = nil
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

        let mastodon = readSecret("mastodon_token").map { MastodonConfiguration(token: $0) }

        let bluesky: BlueSkyConfiguration? = {
            guard let handle = readSecret("bluesky_handle"),
                  let appPassword = readSecret("bluesky_app_password") else { return nil }
            return BlueSkyConfiguration(handle: handle, appPassword: appPassword)
        }()

        let openAIToken = readSecret("openai_token")

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
