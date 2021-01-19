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
import NIO
import AsyncHTTPClient

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
    static func list () -> EventLoopFuture<GroupSearchDocument> {
        var url = configuration.api.url
        url.appendPathComponent("/groups")
        var request = try! HTTPClient.Request(url: url, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.api.token)")

        return httpClient.execute(request: request, forDecodable: GroupSearchDocument.self)
    }

    func addUser (id: UUID) -> EventLoopFuture<Void> {
        let promise = loop.next().makePromise(of: Void.self)

        var url = configuration.api.url
        url.appendPathComponent("/users")
        url.appendPathComponent(id.uuidString)
        url.appendPathComponent("/relationships/groups")
        print(url.absoluteString)

        let relationship = ManyRelationshipBody(data: [ManyRelationshipBody.ManyRelationshipBodyDataItem(
            type: "groups",
            id: self.id.rawValue
        )])

        var request = try! HTTPClient.Request(url: url, method: .POST)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.api.token)")
        request.headers.add(name: "Content-Type", value: "application/json")
        request.body = try! .encodable(relationship)

        print(String(data: try! JSONEncoder().encode(relationship), encoding: .utf8)!)
        httpClient.execute(request: request).whenCompleteExpecting(status: 204, complete: { result in
            switch result {
                case .success(_):
                    promise.succeed(())

                case .failure(let error):
                    promise.fail(error)
            }
        })
        return promise.futureResult
    }
}
