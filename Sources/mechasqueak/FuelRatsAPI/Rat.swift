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
import JSONAPI
import IRCKit

enum RatDescription: ResourceObjectDescription {
    public static var jsonType: String { return "rats" }

    public struct Attributes: JSONAPI.Attributes {
        public let name: Attribute<String>
        public let data: Attribute<RatDataObject>
        public let platform: Attribute<GamePlatform>
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
}

struct RatDataObject: Codable, Equatable {

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

    var signal: String {
        if configuration.general.drillMode {
            return ""
        }
        switch self {
            case .PC:
                return "(PC_SIGNAL)"

            case .Xbox:
                return "(XB_SIGNAL)"

            case .PS:
                return "(PS_SIGNAL)"
        }
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

extension Optional where Wrapped == GamePlatform {
    var ircRepresentable: String {
        return self?.ircRepresentable ?? "u\u{200B}nknown platform"
    }
}
