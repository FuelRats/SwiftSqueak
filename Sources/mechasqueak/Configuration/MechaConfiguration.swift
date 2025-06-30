import Foundation
import IRCKit
import AsyncHTTPClient
import NIO

struct MechaConfiguration {
    let vault: VaultClient
    
    let general: GeneralConfiguration
    let connections: [IRCClientConfiguration]
    let api: FuelRatsAPIConfiguration
    let queue: QueueConfiguration?
    let database: DatabaseConfiguration
    let shortener: URLShortenerConfiguration
    var xbox: XboxLiveConfiguration?
    var psn: PlayStationNetworkConfiguration?
    let mastodon: MastodonConfiguration?
    let bluesky: BlueSkyConfiguration?
    let openAIToken: String?
    let webServer: WebServerConfiguration?

    init?(env: [String: String] = ProcessInfo.processInfo.environment) {
        vault = VaultClient(env: env)
        let vaultSecrets = try vault.fetchSecretBlocking(at: "swiftsqueak")

        self.general = try GeneralConfiguration(env: env)
        self.connections = [] // You will need to manually configure IRCClientConfiguration instances
        
        self.api = try FuelRatsAPIConfiguration(env: env, secret: vaultSecrets)
        self.queue = QueueConfiguration(env: env, secret: vaultSecrets)
        self.database = try DatabaseConfiguration(env: env, secret: vaultSecrets)
        self.shortener = try URLShortenerConfiguration(env: env, secret: vaultSecrets)
        self.xbox = XboxLiveConfiguration(secret: vaultSecrets)
        self.psn = PlayStationNetworkConfiguration(secret: vaultSecrets)
        self.mastodon = MastodonConfiguration(secret: vaultSecrets)
        self.bluesky = BlueSkyConfiguration(secret: vaultSecrets)
        self.openAIToken = vaultSecrets["OPENAI_TOKEN"]
        self.webServer = WebServerConfiguration(env: env)
    }
}

extension IRCClientConfiguration {
    init(env: [String: String], secret: [String: String]) throws {
        self.init(
            serverName: try env.get("IRC_SERVER_NAME"),
            serverAddress: try env.get("IRC_SERVER_ADDRESS"),
            serverPort: Int(env["IRC_SERVER_PORT"] ?? "") ?? 6697,
            nickname: try env.get("IRC_NICKNAME"),
            username: try env.get("IRC_USERNAME"),
            realName: try env.get("IRC_REAL_NAME")
        )
        
        self.autoConnect = (try? env.get("IRC_AUTO_CONNECT")) == "true"
        self.autoReconnect = (try? env.get("IRC_AUTO_RECONNECT")) == "true"
        self.serverPassword = secret["IRC_SERVER_PASSWORD"]
        self.authenticationUsername = secret["IRC_AUTHENTICATION_USERNAME"]
        self.authenticationPassword = secret["IRC_AUTHENTICATION_PASSWORD"]
        
        self.prefersInsecureConnection = (try? env.get("IRC_PREFER_INSECURE_CONNECTION")) == "true"
        self.clientCertificatePath = try? env.get("IRC_CLIENT_CERTIFICATE_PATH")
        self.allowsServerSelfSignedCertificate = (try? env.get("IRC_ALLOWS_SERVER_SELF_SIGNED_CERTIFICATE")) == "true"
        
        self.channels = try env.get("IRC_CHANNELS").split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }
}

struct GeneralConfiguration {
    let signal: String
    let rescueChannel: String
    let reportingChannel: String
    let drillMode: Bool
    let drillChannels: [String]
    let ratDenylist: [String]
    let dispatchDenylist: [String]
    let cooldownExceptionChannels: [String]
    let operLogin: [String]?

    init(env: [String: String]) throws {
        signal = try env.get("GENERAL_SIGNAL")
        rescueChannel = try env.get("GENERAL_RESCUE_CHANNEL")
        reportingChannel = try env.get("GENERAL_REPORTING_CHANNEL")
        drillMode = env["GENERAL_DRILL_MODE"] == "true"
        drillChannels = env["GENERAL_DRILL_CHANNELS"]?.components(separatedBy: ",") ?? []
        ratDenylist = env["GENERAL_RAT_DENYLIST"]?.components(separatedBy: ",") ?? []
        dispatchDenylist = env["GENERAL_DISPATCH_DENYLIST"]?.components(separatedBy: ",") ?? []
        cooldownExceptionChannels = env["GENERAL_COOLDOWN_EXCEPTION_CHANNELS"]?.components(separatedBy: ",") ?? []
        operLogin = env["GENERAL_OPER_LOGIN"]?.components(separatedBy: ",")
    }
}

struct FuelRatsAPIConfiguration {
    let url: URL
    let websocket: URL?
    let userId: UUID
    let token: String

    init(env: [String: String], secret: [String: String]) throws {
        url = try URL(string: env.get("API_URL"))!
        websocket = URL(string: env["API_WEBSOCKET"] ?? "")
        userId = try UUID(uuidString: secret.get("API_USER_ID"))!
        token = try secret.get("API_TOKEN")
    }
}

struct QueueConfiguration {
    let url: URL
    let token: String

    init?(env: [String: String], secret: [String: String]) {
        guard let urlStr = env["QUEUE_URL"],
              let url = URL(string: urlStr),
              let token = secret["QUEUE_TOKEN"] else { return nil }
        self.url = url
        self.token = token
    }
}

struct DatabaseConfiguration {
    let host: String
    let port: Int32
    let database: String
    let username: String
    let password: String?

    init(env: [String: String], secret: [String: String]) throws {
        host = try env.get("DB_HOST")
        port = Int32(env["DB_PORT"] ?? "5432") ?? 5432
        database = try env.get("DB_NAME")
        username = secret["DB_USER"] ?? "fuelrats"
        password = secret["DB_PASSWORD"]
    }
}

struct URLShortenerConfiguration {
    let url: URL
    let signature: String

    init(env: [String: String], secret: [String: String]) throws {
        url = try URL(string: env.get("SHORTENER_URL"))!
        signature = try secret.get("SHORTENER_SIGNATURE")
    }
}

struct XboxLiveConfiguration {
    var xuid: String
    var uhs: String
    var token: String
    var refreshToken: String
    let clientId: String
    let clientSecret: String

    init?(secret: [String: String]) {
        guard let xuid = secret["XBOX_XUID"] else { return nil }
        guard let uhs = secret["XBOX_UHS"] else { return nil }
        guard let token = secret["XBOX_TOKEN"] else { return nil }
        guard let refreshToken = secret["XBOX_REFRESH_TOKEN"] else { return nil }
        guard let clientId = secret["XBOX_CLIENT_ID"] else { return nil }
        guard let clientSecret = secret["XBOX_CLIENT_SECRET"] else { return nil }

        self.xuid = xuid
        self.uhs = uhs
        self.token = token
        self.refreshToken = refreshToken
        self.clientId = clientId
        self.clientSecret = clientSecret
    }
}

struct PlayStationNetworkConfiguration {
    var token: String
    var refreshToken: String
    var basicAuth: String

    init?(secret: [String: String]) {
        guard let token = secret["PSN_TOKEN"] else { return nil }
        guard let refreshToken = secret["PSN_REFRESH_TOKEN"] else { return nil }
        guard let basicAuth = secret["PSN_BASIC_AUTH"] else { return nil }

        self.token = token
        self.refreshToken = refreshToken
        self.basicAuth = basicAuth
    }
}

struct MastodonConfiguration {
    let token: String

    init?(secret: [String: String]) {
        guard let token = secret["MASTODON_TOKEN"] else { return nil }
        self.token = token
    }
}

struct BlueSkyConfiguration {
    let handle: String
    let appPassword: String

    init?(secret: [String: String]) {
        guard let handle = secret["BLUESKY_HANDLE"] else { return nil }
        guard let appPassword = secret["BLUESKY_APP_PASSWORD"] else { return nil }

        self.handle = handle
        self.appPassword = appPassword
    }
}

struct WebServerConfiguration {
    let host: String
    let port: Int

    init?(env: [String: String]) {
        guard let host = env["WEB_HOST"],
              let portStr = env["WEB_PORT"],
              let port = Int(portStr) else { return nil }
        self.host = host
        self.port = port
    }
}

private extension Dictionary where Key == String, Value == String {
    func get(_ key: String) throws -> String {
        guard let value = self[key], !value.isEmpty else {
            throw NSError(domain: "Missing environment variable: \(key)", code: 1, userInfo: nil)
        }
        return value
    }
}

struct VaultResponse: Codable {
    struct Wrapper: Codable {
        let data: [String: String]
    }
    let data: Wrapper
}

struct VaultClient {
    let vaultAddr: String
    let tokenPath: String

    init(env: [String: String] = ProcessInfo.processInfo.environment) {
        self.vaultAddr = env["VAULT_ADDR"] ?? "http://localhost:8200"
        self.tokenPath = env["VAULT_TOKEN_FILE"] ?? "/vault/token"
    }

    func loadToken() throws -> String {
        try String(contentsOfFile: tokenPath).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    
    // TODO get rid of url session
    func fetchSecret(at path: String) async throws -> [String: String] {
        let token = try loadToken()
        let url = URL(string: "\(vaultAddr)/v1/secret/data/\(path)")!
        var request = try HTTPClient.Request(url: url, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "X-Vault-Token", value: token)
        
        let response = try await httpClient.execute(
            request: request,
            deadline: .now() + .seconds(10),
            expecting: 200
        )
        
        guard let body = response.body else {
            return [:]
        }
        
        let decoded = try JSONDecoder().decode(VaultResponse.self, from: body)
        return decoded.data.data
    }
    
    func fetchSecretBlocking(at path: String) throws -> [String: String] {
        let token = try loadToken()
        let url = URL(string: "\(vaultAddr)/v1/secret/data/\(path)")!
        var request = try HTTPClient.Request(url: url, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "X-Vault-Token", value: token)
        
        let response = try httpClient.execute(
            request: request,
            deadline: .now() + .seconds(10)
        ).wait()
        
        if response.status.code != 200 {
            throw NSError(domain: "VaultClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Vault request failed"])
        }
        
        guard let body = response.body else {
            return [:]
        }
        
        let decoded = try JSONDecoder().decode(VaultResponse.self, from: body)
        return decoded.data.data
    }

    func updateSecret(at path: String, modifying updates: [String: String]) async throws {
        var existing = try await fetchSecret(at: path)
        for (key, value) in updates {
            existing[key] = value
        }
        let token = try loadToken()
        let writeURL = URL(string: "\(vaultAddr)/v1/secret/data/\(path)")!
        var request = try HTTPClient.Request(url: writeURL, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "X-Vault-Token", value: token)
        request.headers.add(name: "Content-Type", value: "application/json")
        request.body = .data(try JSONEncoder().encode(["data": existing]))
        
        _ = try await httpClient.execute(
            request: request,
            deadline: .now() + .seconds(10),
            expecting: 200
        )
    }
}
