/*
 Copyright 2021 The Fuel Rats Mischief
 
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
import AsyncHTTPClient
import NIOSSL
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct XboxLive {
    private static var tlsConfiguration: TLSConfiguration {
        var tlsConfiguration = TLSConfiguration.clientDefault
        tlsConfiguration.certificateVerification = .none
        tlsConfiguration.renegotiationSupport = .none
        return tlsConfiguration
    }
    
    static func performXuidLookup (gamertag: String, retried: Bool = false) async -> XuidLookup {
        guard let xlConfig = configuration.xbox else {
            return .failure
        }
        
        let urlEncodedGamerTag = gamertag.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let url = URLComponents(string: "https://profile.xboxlive.com/users/gt(\(urlEncodedGamerTag))/profile/settings")!
        do {
            var request = try HTTPClient.Request(url: url.url!, method: .GET)
            request.tlsConfiguration = XboxLive.tlsConfiguration
            request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
            request.headers.add(name: "xuid", value: xlConfig.xuid)
            request.headers.add(name: "Authorization", value: "XBL3.0 x=\(xlConfig.uhs);\(xlConfig.token)")
            request.headers.add(name: "x-xbl-contract-version", value: "2")
            
            let response = try await httpClient.execute(request: request, forDecodable: ProfileUserRequest.self)
            if let user = response.profileUsers.first {
                return .found(user)
            }
            return .notFound
        } catch let error as HTTPClient.Response {
            if error.status == .notFound {
                return .notFound
            } else if error.status == .unauthorized && retried == false {
                do {
                    try await refreshAuthenticationToken()
                    return await performXuidLookup(gamertag: gamertag, retried: true)
                } catch {
                    mecha.connections.first?.sendMessage(toTarget: "xlexious", contents: String(describing: error))
                    return .failure
                }
            }
            return .failure
        } catch {
            return .failure
        }
    }
    
    static func refreshAuthenticationToken () async throws {
        let refreshedToken = try await Authentication.refreshToken()!
        configuration.xbox?.refreshToken = refreshedToken.refreshToken
        let liveToken = try await Authentication.exchangeForLiveToken(token: refreshedToken.accessToken)
        let xstsToken = try await Authentication.xstsAuthorize(token: liveToken.Token)
        configuration.xbox?.xuid = xstsToken.DisplayClaims.xui.first!.xid
        configuration.xbox?.uhs = xstsToken.DisplayClaims.xui.first!.uhs
        configuration.xbox?.token = xstsToken.Token
        try configuration.save()
    }
    
    static func getUserPresence (xuid: String) async throws -> UserPresenceRequest? {
        guard let xlConfig = configuration.xbox else {
            return nil
        }
        var url = URLComponents(string: "https://userpresence.xboxlive.com/users/xuid(\(xuid))")!
        url.queryItems = [
            "level": "all"
        ].queryItems
        
        var request = try HTTPClient.Request(url: url.url!, method: .GET)
        
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "xuid", value: xlConfig.xuid)
        request.headers.add(name: "Authorization", value: "XBL3.0 x=\(xlConfig.uhs);\(xlConfig.token)")
        request.headers.add(name: "x-xbl-contract-version", value: "2")
        
        return try await httpClient.execute(request: request, forDecodable: UserPresenceRequest.self)
    }
    
    static func getCommunicationPrivacyState (xuid: String) async throws -> CommunicationPrivacyRequest? {
        guard let xlConfig = configuration.xbox else {
            return nil
        }
        var url = URLComponents(string: "https://privacy.xboxlive.com/users/xuid(\(xlConfig.xuid))/permission/validate")!
        url.queryItems = [
            "setting": "CommunicateUsingText",
            "target": "xuid(\(xuid))"
        ].queryItems
        
        var request = try HTTPClient.Request(url: url.url!, method: .GET)
        
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "xuid", value: xlConfig.xuid)
        request.headers.add(name: "Authorization", value: "XBL3.0 x=\(xlConfig.uhs);\(xlConfig.token)")
        request.headers.add(name: "x-xbl-contract-version", value: "2")
        
        return try await httpClient.execute(request: request, forDecodable: CommunicationPrivacyRequest.self)
    }
    
    static func performLookup (forRescue rescue: Rescue) async -> ProfileLookup {
        guard let clientName = rescue.client else {
            return .notFound
        }
        
        return await performLookup(gamertag: clientName)
    }
    
    static func performLookup (gamertag: String) async -> ProfileLookup {
        let userLookup = await performXuidLookup(gamertag: gamertag)
        guard case let .found(user) = userLookup else {
            if case .notFound = userLookup {
                return .notFound
            }
            return .failure
        }
        
        guard let privacyInfo = try? await getCommunicationPrivacyState(xuid: user.id) else {
            return .failure
        }
        guard let presenceInfo = try? await getUserPresence(xuid: user.id) else {
            return .failure
        }
        return .found(Profile(user: user, presence: presenceInfo, privacy: privacyInfo))
    }
    
    struct Authentication {
        static func refreshToken () async throws -> RefreshTokenResponse? {
            guard let xlConfig = configuration.xbox else {
                return nil
            }
            
            let url = URLComponents(string: "https://login.live.com/oauth20_token.srf")!
            
            var request = URLRequest(url: url.url!)
            request.httpMethod = "POST"
            request.addValue(MechaSqueak.userAgent, forHTTPHeaderField: "User-Agent")
            request.addValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = [
                "refresh_token": xlConfig.refreshToken,
                "client_id": xlConfig.clientId,
                "client_secret": xlConfig.clientSecret,
                "grant_type": "refresh_token",
                "scope": "XboxLive.signin XboxLive.offline_access"
            ].formUrlEncoded
            
            let (result, _) = try await URLSession.shared.data(for: request, delegate: nil)
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            return try! decoder.decode(RefreshTokenResponse.self, from: result)
        }
        
        static func exchangeForLiveToken (token: String) async throws -> LiveTokenResponse {
            let url = URLComponents(string: "https://user.auth.xboxlive.com/user/authenticate")!
            
            var request = URLRequest(url: url.url!)
            request.httpMethod = "POST"
            request.addValue(MechaSqueak.userAgent, forHTTPHeaderField: "User-Agent")
            request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            request.addValue("X-Xbl-Contract-Version", forHTTPHeaderField: "X-Xbl-Contract-Version")
            
            let bodyObject: [String : Any] = [
                "TokenType": "JWT",
                "RelyingParty": "http://auth.xboxlive.com",
                "Properties": [
                    "SiteName": "user.auth.xboxlive.com",
                    "AuthMethod": "RPS",
                    "RpsTicket": "d=\(token)"
                ]
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: bodyObject, options: [])
            let (result, _) = try await URLSession.shared.data(for: request, delegate: nil)
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .formatted(.iso8601Full)
            
            return try! decoder.decode(LiveTokenResponse.self, from: result)
        }
        
        static func xstsAuthorize (token: String) async throws -> XSTSResponse {
            let url = URLComponents(string: "https://xsts.auth.xboxlive.com/xsts/authorize")!
            
            var request = URLRequest(url: url.url!)
            request.httpMethod = "POST"
            request.addValue(MechaSqueak.userAgent, forHTTPHeaderField: "User-Agent")
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            request.addValue("2", forHTTPHeaderField: "x-xbl-contract-version")
            
            let bodyObject: [String : Any] = [
                "TokenType": "JWT",
                "RelyingParty": "http://xboxlive.com",
                "Properties": [
                    "UserTokens": [token],
                    "SandboxId": "RETAIL"
                ]
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: bodyObject, options: [])
            let (result, _) = try await URLSession.shared.data(for: request, delegate: nil)
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .formatted(.iso8601Full)
            
            return try! decoder.decode(XSTSResponse.self, from: result)
        }
        
        struct RefreshTokenResponse: Codable {
            let tokenType: String
            let expiresIn: Int
            let scope: String
            let accessToken: String
            let refreshToken: String
            let userId: String
        }
        
        struct LiveTokenResponse: Codable {
            let IssueInstant: Date
            let NotAfter: Date
            let Token: String
            let DisplayClaims: DisplayClaims
            
            struct DisplayClaims: Codable {
                let xui: [Xui]
                
                struct Xui: Codable {
                    let uhs: String
                }
            }
        }
        
        struct XSTSResponse: Codable {
            let IssueInstant: Date
            let NotAfter: Date
            let Token: String
            let DisplayClaims: DisplayClaims
            
            struct DisplayClaims: Codable {
                let xui: [Xui]
                
                struct Xui: Codable {
                    let gtg: String
                    let xid: String
                    let uhs: String
                    let agg: String
                    let usr: String
                    let utr: String
                    let prv: String
                }
            }
        }
    }
    
    enum XuidLookup: Codable {
        case found(ProfileUserRequest.User)
        case notFound
        case failure
    }
    
    enum ProfileLookup: Codable {
        case found(Profile)
        case notFound
        case failure
        
        var currentActivity: String? {
            guard case let .found(profile) = self else {
                return nil
            }
            
            for device in profile.presence.devices ?? [] {
                guard device.titles.contains(where: { $0.name == "Home" }) else {
                    continue
                }
                for title in device.titles {
                    if let activity = title.activity?.richPresence {
                        return "\(title.name) (\(activity))"
                    }
                    
                    return title.name
                }
            }
            return nil
        }
        
        var elitePresence: String? {
            guard case let .found(profile) = self else {
                return nil
            }
            
            for device in profile.presence.devices ?? [] {
                for title in device.titles {
                    guard title.name.starts(with: "Elite Dangerous"), let richPresence = title.activity?.richPresence else {
                        continue
                    }
                    
                    return richPresence
                }
            }
            return nil
        }
        
        var systemName: String? {
            guard let richPresence = elitePresence, richPresence.starts(with: "Is in ") && richPresence.contains("menu") == false else {
                return nil
            }
            
            return String(richPresence.dropFirst(6))
        }
    }
    
    struct Profile: Codable {
        let user: ProfileUserRequest.User
        let presence: UserPresenceRequest
        let privacy: CommunicationPrivacyRequest
    }
    
    struct ProfileUserRequest: Codable {
        let profileUsers: [User]
        
        struct User: Codable {
            let id: String
            let hostId: String
            let isSponsoredUser: Bool
        }
    }
    
    struct UserPresenceRequest: Codable {
        let xuid: String
        let state: OnlineState
        let lastSeen: LastSeenState?
        let devices: [ActiveDevice]?
        
        enum OnlineState: String, Codable {
            case Online
            case Offline
        }
        
        struct LastSeenState: Codable {
            let deviceType: String
            let titleName: String
            let timestamp: Date
        }
        
        struct ActiveDevice: Codable {
            let type: String
            let titles: [GameTitle]
        }
        
        struct GameTitle: Codable {
            let id: String
            let name: String
            let placement: String
            let activity: Activity?
            let state: TitleState
            let lastModified: Date
            
            struct Activity: Codable {
                let richPresence: String
            }
            
            enum TitleState: String, Codable {
                case Active
                case Inactive
            }
        }
    }
    
    struct CommunicationPrivacyRequest: Codable {
        let isAllowed: Bool
        let reasons: [CommunicationBlockedReason]?
        
        struct CommunicationBlockedReason: Codable {
            let reason: String
        }
    }
}

extension URLSession {
    func data (for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse) {
        return try await withCheckedThrowingContinuation { continuation in
            self.dataTask(with: request, completionHandler: { data, response, error in
                guard let response = response, let data = data else {
                    continuation.resume(throwing: error!)
                    return
                }
                
                continuation.resume(returning: (data, response))
            })
        }
    }
}
