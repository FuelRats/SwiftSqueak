/*
 Copyright 2022 The Fuel Rats Mischief
 
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


struct PlaystationNetwork {
    static func performLookup (name: String) async -> (ProfileLookup, PresenceResponse?) {
        let profile = await performRetryingProfileLookup(name: name)
        if case let .found(account) = profile {
            let presence = try? await getUserPresence(accountId: account.accountId)
            return (profile, presence)
        }
        return (profile, nil)
    }
    
    static func refreshAuthenticationToken () async throws {
        guard let psnConfig = configuration.psn else {
            return
        }
        
        let url = URLComponents(string: "https://ca.account.sony.com/api/authz/v3/oauth/token")!
        
        var request = URLRequest(url: url.url!)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.addValue("Basic YWM4ZDE2MWEtZDk2Ni00NzI4LWIwZWEtZmZlYzIyZjY5ZWRjOkRFaXhFcVhYQ2RYZHdqMHY=", forHTTPHeaderField: "Authorization")
        request.httpBody = [
            "refresh_token": psnConfig.refreshToken,
            "grant_type": "refresh_token",
            "token_format": "jwt",
            "scope": "psn:mobile.v1 psn:clientapp"
        ].formUrlEncoded
        
        let (result, _) = try await URLSession.shared.data(for: request, delegate: nil)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        let response = try decoder.decode(RefreshTokenResponse.self, from: result)
        configuration.psn?.token = response.accessToken
        configuration.psn?.refreshToken = response.refreshToken
        try configuration.save()
    }
    
    static func performRetryingProfileLookup (name: String, retried: Bool = false) async -> ProfileLookup {
        guard let psnConfig = configuration.psn else {
            return .failure
        }
        
        var url = URLComponents(string: "https://us-prof.np.community.playstation.net/userProfile/v1/users/\(name)/profile2")!
        url.queryItems = []
        url.queryItems?.append(URLQueryItem(name: "fields", value: "npId,onlineId,accountId,avatarUrls,plus,aboutMe,languagesUsed,trophySummary(@default,level,progress,earnedTrophies),isOfficiallyVerified,personalDetail(@default,profilePictureUrls),personalDetailSharing,personalDetailSharingRequestMessageFlag,primaryOnlineStatus,presences(@default,@titleInfo,platform,lastOnlineDate,hasBroadcastData),requestMessageFlag,blocking,friendRelation,following,consoleAvailability"))
        do {
            var request = try HTTPClient.Request(url: url.url!, method: .GET)
            
            request.headers.add(name: "Authorization", value: "Bearer \(psnConfig.token)")
            
            let response = try await httpClient.execute(request: request, forDecodable: ProfileResponse.self)
            return .found(response.profile)
        } catch let error as HTTPClient.Response {
            if error.status == .notFound {
                return .notFound
            } else if error.status == .unauthorized && retried == false {
                do {
                    try await refreshAuthenticationToken()
                    return await performRetryingProfileLookup(name: name, retried: true)
                } catch {
                    mecha.connections.first?.sendMessage(toTarget: "#rattech", contents: String(describing: error))
                    return .failure
                }
            }
            return .failure
        } catch {
            return .failure
        }
    }
    
    static func getProfile (name: String) async throws -> Profile? {
        guard let psnConfig = configuration.psn else {
            throw URLError(.cannotConnectToHost)
        }
        let url = URLComponents(string: "https://us-prof.np.community.playstation.net/userProfile/v1/users/\(name)/profile2")!
        
        var request = try HTTPClient.Request(url: url.url!, method: .GET)
        
        request.headers.add(name: "Authorization", value: "Bearer \(psnConfig.token)")
        
        let resp = try await httpClient.execute(request: request, forDecodable: ProfileResponse.self)
        return resp.profile
    }
    
    static func getUserPresence (accountId: String) async throws -> PresenceResponse? {
        guard let psnConfig = configuration.psn else {
            return nil
        }
        var url = URLComponents(string: "https://m.np.playstation.net/api/userProfile/v1/internal/users/\(accountId)/basicPresences")!
        url.queryItems = [
            "type": "primary"
        ].queryItems
        
        var request = try HTTPClient.Request(url: url.url!, method: .GET)
        
        request.headers.add(name: "Authorization", value: "Bearer \(psnConfig.token)")
        
        return try await httpClient.execute(request: request, forDecodable: PresenceResponse.self)
    }
    
    struct ProfileResponse: Codable {
        let profile: Profile
    }
    
    struct Profile: Codable {
        let onlineId: String
        let accountId: String
        let npId: String
        let plus: Int
        let aboutMe: String
        let languagesUsed: [String]
        let isOfficiallyVerified: Bool
        let personalDetailSharing: String
        let personalDetailSharingRequestMessageFlag: Bool
        let requestMessageFlag: Bool
    }
    
    struct PresenceResponse: Codable {
        let basicPresence: BasicPresence
        
        struct BasicPresence: Codable {
            let availability: String
            let primaryPlatformInfo: PrimaryPlatformInfo?
            let gameTitleInfoList: [Title]?
        }
        
        struct PrimaryPlatformInfo: Codable {
            let onlineStatus: OnlineStatus
            let platform: Platform
            let lastOnlineDate: Date
        }
        
        enum OnlineStatus: String, Codable {
            case online
            case offline
        }
        
        var elitePresence: Title? {
            return self.basicPresence.gameTitleInfoList?.first(where: { $0.npTitleId == "CUSA06362_00" })
        }
        
        var currentActivity: String? {
            return self.basicPresence.gameTitleInfoList?.first?.titleName
        }
    }
    
    struct Title: Codable {
        let npTitleId: String
        let titleName: String
        let format: Platform
        let launchPlatform: Platform
    }
    
    enum Platform: String, Codable {
        case ps3
        case ps4
        case ps5
    }
    
    struct RefreshTokenResponse: Codable {
        var accessToken: String
        var tokenType: String
        var expiresIn: Int
        var scope: String
        var idToken: String
        var refreshToken: String
        var refreshTokenExpiresIn: Int
    }
    
    enum ProfileLookup: Codable {
            case found(Profile)
            case notFound
            case failure
    }
}

typealias PSN = PlaystationNetwork
