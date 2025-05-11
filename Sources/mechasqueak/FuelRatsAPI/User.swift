import AsyncHTTPClient
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

enum UserDescription: ResourceObjectDescription {
    public static var jsonType: String { return "users" }

    public struct Attributes: JSONAPI.SparsableAttributes {
        public enum CodingKeys: String, JSONAPI.SparsableCodingKey {
            case data
            case email
            case status
            case suspended
            case stripeId
            case createdAt
            case updatedAt
        }

        public var data: Attribute<UserDataObject>
        public let email: Attribute<String>?
        public let status: Attribute<UserStatus>
        public var suspended: Attribute<Date>?
        public let stripeId: Attribute<String>?
        public let createdAt: Attribute<Date>
        public let updatedAt: Attribute<Date>
    }

    public struct Relationships: JSONAPI.Relationships {
        public let rats: ToManyRelationship<Rat>?
        public let displayRat: ToOneRelationship<Rat?>?
        public let groups: ToManyRelationship<Group>?
        public let clients: ToManyRelationship<Client>?
        public let epics: ToManyRelationship<Epic>?
        public let decals: ToManyRelationship<Decal>?
        public let nicknames: ToManyRelationship<Nickname>?
        public let avatar: ToOneRelationship<AvatarImage?>?
    }
}
typealias User = JSONEntity<UserDescription>
typealias UserGetDocument = Document<
    SingleResourceBody<User>, Include8<Rat, Ship, Epic, Nickname, Client, Decal, Group, AvatarImage>
>

extension User {
    static func get(id: UUID) async throws -> UserGetDocument {
        let request = try! HTTPClient.Request(apiPath: "/users/\(id.uuidString)", method: .GET)

        return try await httpClient.execute(request: request, forDecodable: UserGetDocument.self)
    }

    @discardableResult
    static func update(user: User) async throws -> UserGetDocument {
        let patchRequestDocument = SingleDocument(
            apiDescription: .none, body: .init(resourceObject: user), includes: .none, meta: .none,
            links: .none)
        var request = try HTTPClient.Request(
            apiPath: "/users/\(user.id.rawValue.uuidString)", method: .PATCH)
        request.headers.add(name: "Content-Type", value: "application/json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try! encoder.encode(patchRequestDocument)
        debug(String(data: body, encoding: .utf8)!)

        request.body = .data(body)

        return try await httpClient.execute(request: request, forDecodable: UserGetDocument.self)
    }

    @discardableResult
    func suspend(date: Date) async throws -> UserGetDocument {
        let updatedUser = self.tappingAttributes({
            $0.suspended = .init(value: date)
        }).sparse(with: [UserDescription.Attributes.CodingKeys.suspended]).resourceObject
            .replacingRelationships({ _ in
                return UserDescription.Relationships(
                    rats: nil,
                    displayRat: nil,
                    groups: nil,
                    clients: nil,
                    epics: nil,
                    decals: nil,
                    nicknames: nil,
                    avatar: nil
                )
            })
        return try await User.update(user: updatedUser)
    }

    @discardableResult
    func changeEmail(to email: String) async throws -> UserGetDocument {
        let body: [String: Any] = [
            "data": [
                "type": "email-changes",
                "id": self.id.rawValue.uuidString,
                "attributes": [
                    "email": email
                ],
            ]
        ]
        var request = try HTTPClient.Request(
            apiPath: "/users/\(self.id.rawValue.uuidString)/email", method: .PATCH)
        request.headers.add(name: "Content-Type", value: "application/json")
        request.body = .data(try! JSONSerialization.data(withJSONObject: body, options: []))

        return try await httpClient.execute(request: request, forDecodable: UserGetDocument.self)
    }

    @discardableResult
    func updateUserData(dataObject: UserDataObject) async throws -> UserGetDocument {
        let updatedUser = self.tappingAttributes {
            $0.data = .init(value: dataObject)
        }.sparse(with: [UserDescription.Attributes.CodingKeys.data]).resourceObject
            .replacingRelationships({ _ in
                return UserDescription.Relationships(
                    rats: nil,
                    displayRat: nil,
                    groups: nil,
                    clients: nil,
                    epics: nil,
                    decals: nil,
                    nicknames: nil,
                    avatar: nil
                )
            })
        return try await User.update(user: updatedUser)
    }
}

enum UserStatus: String, Codable {
    case active
    case inactive
    case legacy
    case deactivated
}

struct UserDataObject: Codable, Equatable {
    var preferredPrivateMethod: MessagingMethod? = .Privmsg
    var clientTranslateSubscription: ClientTranslateSubscription? = nil
}

enum MessagingMethod: String, Codable {
    case Privmsg
    case Notice
}
