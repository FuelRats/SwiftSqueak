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
import NIO
import AsyncHTTPClient
import IRCKit

enum GroupDescription: ResourceObjectDescription {
    public static var jsonType: String { return "groups" }

    public struct Attributes: JSONAPI.Attributes {
        public let name: Attribute<String>
        public let vhost: Attribute<String?>
        public let withoutPrefix: Attribute<Bool>
        public let priority: Attribute<Int>
        public let permissions: Attribute<[AccountPermission]>
        public let channels: Attribute<[String: String]>
        public let createdAt: Attribute<Date>
        public let updatedAt: Attribute<Date>
    }

    public typealias Relationships = NoRelationships
}

enum AccountPermission: String, Codable {
    case RescueRead = "rescues.read"
    case RescueReadOwn = "rescues.read.me"
    case RescueWrite = "rescues.write"
    case RescueWriteOwn = "rescues.write.me"

    case RatRead = "rats.read"
    case RatReadOwn = "rats.read.me"
    case RatWrite = "rats.write"
    case RatWriteOwn = "rats.write.me"

    case UserRead = "users.read"
    case UserReadOwn = "users.read.me"
    case UserWrite = "users.write"
    case UserWriteOwn = "users.write.me"
    case UserVerified = "users.verified"

    case ClientRead = "clients.read"
    case ClientReadOwn = "clients.read.me"
    case ClientWrite = "clients.write"
    case ClientWriteOwn = "clients.write.me"

    case ShipRead = "ships.read"
    case ShipReadOwn = "ships.read.me"
    case ShipWrite = "ships.write"
    case ShipWriteOwn = "ships.write.me"

    case DecalRead = "decals.read"
    case DecalReadOwn = "decals.read.me"
    case DecalWrite = "decals.write"
    case DecalWriteOwn = "decals.write.me"

    case GroupRead = "groups.read"
    case GroupReadOwn = "groups.read.me"
    case GroupWrite = "groups.write"
    case GroupWriteOwn = "groups.write.me"

    case NicknameRead = "nicknames.read"
    case NicknameReadOwn = "nicknames.read.me"
    case NicknameWrite = "nicknames.write"
    case NicknameWriteOwn = "nicknames.write.me"

    case EpicRead = "epics.read"
    case EpicReadOwn = "epic.read.me"
    case EpicWrite = "epics.write"
    case EpicWriteOwn = "epics.write.me"

    case RescueRevisionRead = "rescue-revisions.read"
    case RescueRevisionWrite = "rescue-revisions.write"

    case TwitterWrite = "twitter.write"
    
    case DispatchRead = "dispatch.read"
    case DispatchWrite = "dispatch.write"

    case AnnouncementWrite = "announcements.write"

    case UnknownPermission = ""
    
    var groups: [Group] {
        return mecha.groups.filter({ $0.permissions.contains(self) && $0.name != "owner" })
    }
}

extension AccountPermission {
    init (from decoder: Decoder) throws {
        self = try AccountPermission(rawValue: decoder.singleValueContainer().decode(RawValue.self))
            ?? AccountPermission.UnknownPermission
    }
}

typealias Group = JSONEntity<GroupDescription>
typealias GroupSearchDocument = Document<ManyResourceBody<Group>, NoIncludes>

extension Group {
    var groupNameMap: [String: String] {
        return [
            "verified": "Verified",
            "developer": "Developer",
            "rat": "Drilled Rat",
            "dispatch": "Drilled Dispatch",
            "trainer": "Trainer",
            "traineradmin": "Training Manager",
            "merch": "Quartermaster",
            "overseer": "Overseer",
            "techrat": "Tech rat",
            "moderator": "Moderator",
            "operations": "Operations team",
            "netadmin": "Network administrator",
            "admin": "Network moderator",
            "owner": "Special snowflake",
        ]
    }
    
    var groupColor: [String: IRCColor] {
        return [
            "verified": .Grey,
            "developer": .LightBlue,
            "rat": .LightGreen,
            "dispatch": .Green,
            "trainer": .Yellow,
            "traineradmin": .Purple,
            "merch": .Grey,
            "overseer": .Orange,
            "techrat": .LightBlue,
            "moderator": .LightRed,
            "operations": .Purple,
            "netadmin": .LightBlue,
            "admin": .Purple,
            "owner": .Purple
        ]
    }
    
    var groupDescription: String {
        return groupNameMap[self.name] ?? self.name
    }
    
    var ircRepresentation: String {
        if let color = groupColor[self.name] {
            return IRCFormat.color(color, groupDescription)
        }
        return groupDescription
    }
    
    static func getList () async throws -> GroupSearchDocument {
        let request = try HTTPClient.Request(apiPath: "/groups", method: .GET)

        return try await httpClient.execute(request: request, forDecodable: GroupSearchDocument.self)
    }

    func addUser (id: UUID) async throws {
        let relationship = ManyRelationshipBody(data: [ManyRelationshipBody.ManyRelationshipBodyDataItem(
            type: "groups",
            id: self.id.rawValue
        )])

        var request = try HTTPClient.Request(apiPath: "/users/\(id.uuidString)/relationships/groups", method: .POST)
        request.headers.add(name: "Content-Type", value: "application/json")
        request.body = try .encodable(relationship)
        
        _ = try await httpClient.execute(request: request, deadline: FuelRatsAPI.deadline, expecting: 204)
    }
    
    func removeUser (id: UUID) async throws {
        let relationship = ManyRelationshipBody(data: [ManyRelationshipBody.ManyRelationshipBodyDataItem(
            type: "groups",
            id: self.id.rawValue
        )])

        var request = try HTTPClient.Request(apiPath: "/users/\(id.uuidString)/relationships/groups", method: .DELETE)
        request.headers.add(name: "Content-Type", value: "application/json")
        request.body = try .encodable(relationship)

        _ = try await httpClient.execute(request: request, deadline: FuelRatsAPI.deadline, expecting: 204)
    }
}
