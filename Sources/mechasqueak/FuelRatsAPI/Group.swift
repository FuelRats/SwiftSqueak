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

import AsyncHTTPClient
import Foundation
import IRCKit
import JSONAPI
import NIO

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

enum AccountPermission: String, Codable, Sendable {
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
    init(from decoder: Decoder) throws {
        self =
            try AccountPermission(rawValue: decoder.singleValueContainer().decode(RawValue.self))
            ?? AccountPermission.UnknownPermission
    }
}

typealias Group = JSONEntity<GroupDescription>
typealias GroupSearchDocument = Document<ManyResourceBody<Group>, NoIncludes>
typealias GroupDocument = Document<SingleResourceBody<Group>, NoIncludes>

/// Plain-JSON payload of `GET /anope/channels` (not a JSON:API document).
struct RegisteredChannelsResponse: Codable {
    let channels: [String]
}

/// Valid Anope channel-access FLAGS letters. Mirror of the authoritative set in the
/// API at `src/helpers/groupFlagLetters.mjs` — keep in sync. Lowercase `g` is invalid.
let validGroupFlagLetters = Set<Character>("ABFGHIKNOQUVabcfhikmoqstuv")

/// JSON:API request body carrying a `groups` resource's attributes for a write.
private struct GroupWriteBody<A: Encodable>: Encodable {
    struct DataObject: Encodable {
        let type = "groups"
        let attributes: A
    }
    let data: DataObject

    init(_ attributes: A) {
        self.data = DataObject(attributes: attributes)
    }
}

/// Partial `groups` attributes for a `PUT /groups/:id` — only the set fields are
/// encoded (JSON:API PATCH semantics). `vhost` is a double optional: the outer
/// optional marks whether the field is being changed, the inner value encodes as
/// JSON `null` to clear the vhost.
private struct GroupPatchAttributes: Encodable {
    var vhost: String??
    var priority: Int?
    var withoutPrefix: Bool?

    enum CodingKeys: String, CodingKey {
        case vhost, priority, withoutPrefix
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let vhost = vhost {
            try container.encode(vhost, forKey: .vhost)
        }
        if let priority = priority {
            try container.encode(priority, forKey: .priority)
        }
        if let withoutPrefix = withoutPrefix {
            try container.encode(withoutPrefix, forKey: .withoutPrefix)
        }
    }
}

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
            "owner": "Special snowflake"
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

    static func getList() async throws -> GroupSearchDocument {
        let request = try HTTPClient.Request(apiPath: "/groups", method: .GET)

        return try await httpClient.execute(
            request: request, forDecodable: GroupSearchDocument.self)
    }

    /// Every channel registered with ChanServ. Used to guard channel-access grants
    /// so a group can only be given access to a channel that actually exists.
    static func getRegisteredChannels() async throws -> [String] {
        let request = try HTTPClient.Request(apiPath: "/anope/channels", method: .GET)

        let response = try await httpClient.execute(
            request: request, forDecodable: RegisteredChannelsResponse.self)
        return response.channels
    }

    func addUser(id: UUID, command: IRCBotCommand? = nil) async throws {
        let relationship = ManyRelationshipBody(data: [
            ManyRelationshipBody.ManyRelationshipBodyDataItem(
                type: "groups",
                id: self.id.rawValue
            )
        ])

        var request = try HTTPClient.Request(
            apiPath: "/users/\(id.uuidString)/relationships/groups", method: .POST,
            command: command)
        request.headers.add(name: "Content-Type", value: "application/json")
        request.body = try .encodable(relationship)

        _ = try await httpClient.execute(
            request: request, deadline: FuelRatsAPI.deadline, expecting: 204)
    }

    func removeUser(id: UUID, command: IRCBotCommand? = nil) async throws {
        let relationship = ManyRelationshipBody(data: [
            ManyRelationshipBody.ManyRelationshipBodyDataItem(
                type: "groups",
                id: self.id.rawValue
            )
        ])

        var request = try HTTPClient.Request(
            apiPath: "/users/\(id.uuidString)/relationships/groups", method: .DELETE,
            command: command)
        request.headers.add(name: "Content-Type", value: "application/json")
        request.body = try .encodable(relationship)

        _ = try await httpClient.execute(
            request: request, deadline: FuelRatsAPI.deadline, expecting: 204)
    }

    /// The bare channel key the group-channel endpoints expect (no leading `#`/`&`).
    static func bareChannel(_ channel: String) -> String {
        if let first = channel.first, first == "#" || first == "&" {
            return String(channel.dropFirst())
        }
        return channel
    }

    /// Add or update a channel's access FLAGS on this group. Acts on behalf of the
    /// caller (`command`) so the API authorises the write against their `groups.write`.
    func setChannel(_ channel: String, flags: String, command: IRCBotCommand) async throws -> Group {
        var request = try HTTPClient.Request(
            apiPath: "/groups/\(self.id.rawValue.uuidString)/channels/\(Group.bareChannel(channel))",
            method: .PUT, command: command)
        request.body = try .encodable(GroupWriteBody(["flags": flags]))

        let document = try await httpClient.execute(request: request, forDecodable: GroupDocument.self)
        return document.body.data!.primary.value
    }

    /// Remove a channel from this group (idempotent). Acts on behalf of `command`'s caller.
    func removeChannel(_ channel: String, command: IRCBotCommand) async throws -> Group {
        let request = try HTTPClient.Request(
            apiPath: "/groups/\(self.id.rawValue.uuidString)/channels/\(Group.bareChannel(channel))",
            method: .DELETE, command: command)

        let document = try await httpClient.execute(request: request, forDecodable: GroupDocument.self)
        return document.body.data!.primary.value
    }

    /// Grant an OAuth permission scope to this group (idempotent). Acts on behalf of `command`'s caller.
    func setPermission(_ scope: String, command: IRCBotCommand) async throws -> Group {
        let request = try HTTPClient.Request(
            apiPath: "/groups/\(self.id.rawValue.uuidString)/permissions/\(scope)",
            method: .PUT, command: command)

        let document = try await httpClient.execute(request: request, forDecodable: GroupDocument.self)
        return document.body.data!.primary.value
    }

    /// Revoke an OAuth permission scope from this group (idempotent). Acts on behalf of `command`'s caller.
    func removePermission(_ scope: String, command: IRCBotCommand) async throws -> Group {
        let request = try HTTPClient.Request(
            apiPath: "/groups/\(self.id.rawValue.uuidString)/permissions/\(scope)",
            method: .DELETE, command: command)

        let document = try await httpClient.execute(request: request, forDecodable: GroupDocument.self)
        return document.body.data!.primary.value
    }

    /// Partial-update this group's scalar attributes (`vhost`/`priority`/`withoutPrefix`)
    /// via `PUT /groups/:id`. Only the fields set on `attributes` are sent.
    private func patch(_ attributes: GroupPatchAttributes, command: IRCBotCommand) async throws -> Group {
        var request = try HTTPClient.Request(
            apiPath: "/groups/\(self.id.rawValue.uuidString)", method: .PUT, command: command)
        request.body = try .encodable(GroupWriteBody(attributes))

        let document = try await httpClient.execute(request: request, forDecodable: GroupDocument.self)
        return document.body.data!.primary.value
    }

    /// Set (or clear, with `nil`) this group's vhost.
    func setVhost(_ vhost: String?, command: IRCBotCommand) async throws -> Group {
        return try await patch(GroupPatchAttributes(vhost: .some(vhost)), command: command)
    }

    /// Set this group's priority.
    func setPriority(_ priority: Int, command: IRCBotCommand) async throws -> Group {
        return try await patch(GroupPatchAttributes(priority: priority), command: command)
    }

    /// Set whether this group's vhost is applied without a rat-name prefix.
    func setWithoutPrefix(_ withoutPrefix: Bool, command: IRCBotCommand) async throws -> Group {
        return try await patch(GroupPatchAttributes(withoutPrefix: withoutPrefix), command: command)
    }

    /// Create a new permission group. Acts on behalf of `command`'s caller.
    static func create(name: String, command: IRCBotCommand) async throws -> Group {
        var request = try HTTPClient.Request(apiPath: "/groups", method: .POST, command: command)
        request.body = try .encodable(GroupWriteBody(["name": name]))

        let document = try await httpClient.execute(request: request, forDecodable: GroupDocument.self)
        return document.body.data!.primary.value
    }

    /// Delete this permission group. Acts on behalf of `command`'s caller.
    func delete(command: IRCBotCommand) async throws {
        let request = try HTTPClient.Request(
            apiPath: "/groups/\(self.id.rawValue.uuidString)", method: .DELETE, command: command)

        _ = try await httpClient.execute(
            request: request, deadline: FuelRatsAPI.deadline, expecting: 204)
    }
}
