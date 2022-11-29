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
        public var expansion: Attribute<GameMode>
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
        
        return (try? await board.filter({ (_, rescue) in
            rescue.rats.contains(where: { $0.relationships.user?.id?.rawValue == userId })
        }).getAllResults()) ?? []
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
    
    func setGameExpansion (_ expansion: GameMode) async throws {
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

enum GameMode: String, Codable, CaseIterable {
    case legacy = "horizons3"
    case horizons = "horizons4"
    case odyssey
    
    init (from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        if let value = GameMode.parsedFromText(text: rawValue) {
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
            case .legacy:
                return "(LEG_SIGNAL)"
            case .horizons:
                return "(HOR_SIGNAL)"
            case .odyssey:
                return "(ODY_SIGNAL)"
        }
    }
    
    static var englishDescriptions: [GameMode: String] = [
        .legacy: "Legacy",
        .horizons: "Horizons",
        .odyssey: "Odyssey"
    ]
    var englishDescription: String {
        return GameMode.englishDescriptions[self]!
    }
    
    static var shortEnglishDescriptions: [GameMode: String] = [
        .legacy: "LEG",
        .horizons: "HOR",
        .odyssey: "ODY"
    ]
    var shortEnglishDescription: String {
        return GameMode.shortEnglishDescriptions[self]!
    }
    
    static var colors: [GameMode: IRCColor] = [
        .legacy: .Pink,
        .horizons: .LightCyan,
        .odyssey: .Orange
    ]
    var color: IRCColor {
        return GameMode.colors[self]!
    }
    
    var ircRepresentable: String {
        return IRCFormat.color(self.color, self.englishDescription)
    }
    
    var shortIRCRepresentable: String {
        return IRCFormat.color(self.color, self.shortEnglishDescription)
    }
    
    static func parsedFromText (text: String) -> GameMode? {
        let text = text.lowercased()
        switch text {
            case "legacy", "leg", "l", "horizons3", "horizons 3", "h3", "3h", "horizons 3.8":
                return .legacy

            case "horizons", "hor", "h", "live", "horizons4", "horizons 4", "h4",  "4h", "horizons 4.0":
                return .horizons

            case "odyssey", "o", "ody":
                return .odyssey

            default:
                return nil
        }
    }
    
    func hasSharedUniverse (with mode: GameMode) -> Bool {
        if self != .legacy {
            return mode != .legacy
        }
        return mode == .legacy
    }
}

extension Optional where Wrapped == GamePlatform {
    var ircRepresentable: String {
        return self?.ircRepresentable ?? "unknown platform"
    }
}
