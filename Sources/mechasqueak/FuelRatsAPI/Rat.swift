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
import JSONAPI
import IRCKit
import NIO
import AsyncHTTPClient

enum RatDescription: ResourceObjectDescription {
    public static var jsonType: String { return "rats" }

    public struct Attributes: JSONAPI.Attributes {
        public var name: Attribute<String>
        public var data: Attribute<RatDataObject>
        public var platform: Attribute<GamePlatform>
        public var expansion: Attribute<GameExpansion>
        public let frontierId: Attribute<String>?
        public let createdAt: Attribute<Date>
        public let updatedAt: Attribute<Date>
    }

    public struct Relationships: JSONAPI.Relationships {
        public let user: ToOneRelationship<User?>?
        public let ships: ToManyRelationship<Ship>?
    }
}
typealias Rat = JSONEntity<RatDescription>

extension Rat {
    func presence (inIRCChannel channel: IRCChannel) -> [IRCUser] {
        guard let userId = self.relationships.user?.id?.rawValue else {
            return []
        }
        return channel.members.filter({
            return $0.associatedAPIData?.user?.id.rawValue == userId
        })
    }

    func currentNick (inIRCChannel channel: IRCChannel) -> String? {
        var users = self.presence(inIRCChannel: channel)
        if users.count < 1 {
            return nil
        }
        let ratName = self.attributes.name.value.lowercased()

        users.sort(by: { user1, user2 in
            return user1.nickname.lowercased().levenshtein(ratName) < user2.nickname.lowercased().levenshtein(ratName)
        })

        return users[0].nickname
    }
    
    func hasPermitFor(system: StarSystem) -> Bool {
        guard let permit = system.permit else {
            return true
        }
        let permitName = (permit.name ?? system.name).lowercased()
        
        guard let permits = self.attributes.data.value.permits else {
            return false
        }
        return permits.contains(where: { $0.lowercased() == permitName })
    }
    
    func getCurrentRescues () async -> [(key: Int, value: Rescue)] {
        guard let userId = self.relationships.user?.id?.rawValue else {
            return []
        }
        
        return try! await board.filter({ (_, rescue) in
            rescue.rats.contains(where: { $0.relationships.user?.id?.rawValue == userId })
        }).getAllResults()
    }
    
    func getCurrentJumpCalls () async -> [(key: Int, value: Rescue)] {
        guard let userId = self.relationships.user?.id?.rawValue else {
            return []
        }
        
        return try! await board.filter({ (_, rescue) in
            rescue.jumpCalls.contains(where: { $0.0.relationships.user?.id?.rawValue == userId })
        }).getAllResults()
    }
    
    func update() async throws {
        let patchDocument = SingleDocument(
            apiDescription: .none,
            body: .init(resourceObject: self),
            includes: .none,
            meta: .none,
            links: .none
        )
        var request = try! HTTPClient.Request(apiPath: "/rats/\(self.id.rawValue.uuidString)", method: .PATCH)
        request.headers.add(name: "Content-Type", value: "application/vnd.api+json")
        
        request.body = try .encodable(patchDocument)
        
        _ = try await httpClient.execute(request: request, deadline: FuelRatsAPI.deadline, expecting: 200)
    }
    
    func setGameExpansion (_ expansion: GameExpansion) async throws {
        let updatedRat = self.tappingAttributes({ $0.expansion = .init(value: expansion) })
        return try await updatedRat.update()
    }
}

struct RatDataObject: Codable, Equatable {
    var permits: [String]?
}

enum GamePlatform: String, Codable, CaseIterable {
    case PC = "pc"
    case Xbox = "xb"
    case PS = "ps"

    init (from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        if let value = GamePlatform.parsedFromText(text: rawValue) {
            self = value
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid Enum Raw Value"
            ))
        }
    }

    var ircRepresentable: String {
        let platformMap: [GamePlatform: IRCColor] = [
            .PC: .Purple,
            .Xbox: .Green,
            .PS: .LightBlue
        ]

        let englishDescriptions: [GamePlatform: String] = [
            .PC: "PC",
            .Xbox: "Xbox",
            .PS: "Playstation"
        ]

        return IRCFormat.color(platformMap[self]!, englishDescriptions[self]!)
    }

    var factPrefix: String {
        let platformMap: [GamePlatform: String] = [
            .PC: "pc",
            .Xbox: "x",
            .PS: "ps"
        ]
        return platformMap[self]!
    }

    static func parsedFromText (text: String) -> GamePlatform? {
        let text = text.lowercased()
        switch text {
            case "pc":
                return .PC

            case "xbox", "xb", "xb1":
                return .Xbox

            case "ps", "ps4", "playstation", "ps5":
                return .PS

            default:
                return nil
        }
    }
}

enum GameExpansion: String, Codable, CaseIterable {
    case horizons3
    case horizons4
    case odyssey
    
    init (from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        if let value = GameExpansion.parsedFromText(text: rawValue) {
            self = value
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid Enum Raw Value"
            ))
        }
    }
    
    var signal: String {
        if configuration.general.drillMode {
            return ""
        }
        switch self {
            case .horizons3:
                return "(H3_SIGNAL)"
            case .horizons4:
                return "(H4_SIGNAL)"
            case .odyssey:
                return "(ODY_SIGNAL)"
        }
    }
    
    func canSwitchTo (expansion: GameExpansion) -> Bool {
        if self == .horizons4 && expansion == .odyssey {
            return false
        }
        if self == .odyssey && expansion == .horizons4 {
            return false
        }
        return true
    }
    
    static var englishDescriptions: [GameExpansion: String] = [
        .horizons3: "Horizons (3.8)",
        .horizons4: "Horizons (4.0)",
        .odyssey: "Odyssey (4.0)"
    ]
    var englishDescription: String {
        return GameExpansion.englishDescriptions[self]!
    }
    
    static var shortEnglishDescriptions: [GameExpansion: String] = [
        .horizons3: "H3.8",
        .horizons4: "H4.0",
        .odyssey: "ODY"
    ]
    var shortEnglishDescription: String {
        return GameExpansion.shortEnglishDescriptions[self]!
    }
    
    static var colors: [GameExpansion: IRCColor] = [
        .horizons3: .Pink,
        .horizons4: .LightCyan,
        .odyssey: .Orange
    ]
    var color: IRCColor {
        return GameExpansion.colors[self]!
    }
    
    var ircRepresentable: String {
        return IRCFormat.color(self.color, self.englishDescription)
    }
    
    var shortIRCRepresentable: String {
        return IRCFormat.color(self.color, self.shortEnglishDescription)
    }
    
    static func parsedFromText (text: String) -> GameExpansion? {
            let text = text.lowercased()
            switch text {
                case "horizons3", "horizons 3", "horizons 3.8", "horizons (3.8)", "h3", "h3.8", "3horizons", "3h", "3.8h", "3":
                    return .horizons3

                case "horizons4", "horizons 4", "horizons 4.0", "horizons (4.0)", "h4", "h4.0", "4horizons", "4h", "4.0h", "4":
                    return .horizons4

                case "odyssey", "o", "ody", "ody4", "odyssey 4.0", "odyssey (4.0)":
                    return .odyssey

                default:
                    return nil
            }
        }
}

extension Optional where Wrapped == GamePlatform {
    var ircRepresentable: String {
        return self?.ircRepresentable ?? "unknown platform"
    }
}
