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

enum NicknameDescription: ResourceObjectDescription {
    public static var jsonType: String { return "nicknames" }

    public struct Attributes: JSONAPI.Attributes {
        public let lastQuit: Attribute<String?>
        public let lastRealHost: Attribute<String?>?
        public let lastRealName: Attribute<String?>
        public let lastSeen: Attribute<Date?>
        public let lastUserMask: Attribute<String?>
        public let display: Attribute<String>
        public let nick: Attribute<String>
        public let createdAt: Attribute<Date>
        public let updatedAt: Attribute<Date>
        public let vhost: Attribute<String?>
        public let email: Attribute<String?>
        public let score: Attribute<Int>?
    }

    public struct Relationships: JSONAPI.Relationships {
        public let user: ToOneRelationship<User?>?
    }
}
typealias Nickname = JSONEntity<NicknameDescription>

typealias NicknameSearchDocument = Document<
    ManyResourceBody<Nickname>,
    Include7<User, Rat, Group, Client, Epic, Ship, Decal>
>

extension NicknameSearchDocument {
    static func from (data documentData: Data) throws -> NicknameSearchDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(DateFormatter.iso8601Full)

        return try decoder.decode(NicknameSearchDocument.self, from: documentData)
    }

    var user: User? {
        let userId = self.body.primaryResource?.values[0].relationships.user?.id

        return self.body.includes![User.self].first(where: {
            userId != nil && $0.id == userId
        })
    }

    func ratsBelongingTo (user: User) -> [Rat] {
        return user.relationships.rats?.ids.compactMap({ ratId in
            return self.body.includes![Rat.self].first(where: {
                $0.id.rawValue == ratId.rawValue
            })
        }) ?? []
    }

    var permissions: [AccountPermission] {
        let groupIds = self.user?.relationships.groups?.ids ?? []

        return self.body.includes![Group.self].filter({
            groupIds.contains($0.id)
        }).flatMap({
            $0.attributes.permissions.value
        })
    }
}
typealias NicknameGetDocument = Document<
    SingleResourceBody<Nickname>,
    Include7<User, Rat, Group, Client, Epic, Ship, Decal>
>

extension NicknameGetDocument {
    static func from (data documentData: Data) throws -> NicknameGetDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(DateFormatter.iso8601Full)

        return try decoder.decode(NicknameGetDocument.self, from: documentData)
    }
}
