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
import SwiftyRequest

enum RescueDescription: ResourceObjectDescription {
    public static var jsonType: String { return "rescues" }

    public struct Attributes: JSONAPI.Attributes {
        public var client: Attribute<String?>
        public var clientNick: Attribute<String?>
        public var clientLanguage: Attribute<String?>
        public var commandIdentifier: Attribute<Int?>
        public var codeRed: Attribute<Bool>
        public var notes: Attribute<String>
        public var platform: Attribute<GamePlatform?>
        public var system: Attribute<String?>
        public var quotes: Attribute<[RescueQuote]>
        public var status: Attribute<RescueStatus>
        public var title: Attribute<String?>
        public var outcome: Attribute<RescueOutcome?>
        public var unidentifiedRats: Attribute<[String]>

        public var createdAt: Attribute<Date>
        public var updatedAt: Attribute<Date>
    }

    public struct Relationships: JSONAPI.Relationships {
        public var rats: ToManyRelationship<Rat>
        public var firstLimpet: ToOneRelationship<Rat?>
    }
}
typealias Rescue = JSONEntity<RescueDescription>

struct RescueDataObject: Codable {
    struct RescueDataStatus: Codable {

    }

    struct MarkForDeletionEntry: Codable {
        var marked: Bool
        var reason: String
        var reporter: String

    }
    var langID: String?
    var status: RescueDataStatus?
    var IRCNick: String?
    var boardIndex: Int?
    var markedForDeletion: MarkForDeletionEntry?
}

struct RescueQuote: Codable, Equatable {
    var author: String
    var message: String
    var createdAt: Date
    var updatedAt: Date
    var lastAuthor: String
}

enum RescueStatus: String, Codable {
    case Open = "open"
    case Inactive = "inactive"
    case Closed = "closed"
}

enum RescueOutcome: String, Codable {
    case Success = "success"
    case Failure = "failure"
    case Invalid = "invalid"
    case Other = "other"
    case Purge = "purge"
}

typealias RescueSearchDocument = Document<ManyResourceBody<Rescue>, Include3<Rat, User, Ship>>
typealias RescueGetDocument = Document<SingleResourceBody<Rescue>, Include3<Rat, User, Ship>>
typealias SingleDocument<Resource: ResourceObjectType> = JSONAPI.Document<
    SingleResourceBody<Resource>,
    NoMetadata,
    NoLinks,
    NoIncludes,
    NoAPIDescription,
    UnknownJSONAPIError
>

extension RescueSearchDocument {
    static func from (data documentData: Data) throws -> RescueSearchDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(DateFormatter.iso8601Full)

        return try decoder.decode(RescueSearchDocument.self, from: documentData)
    }

    func assignedRatsFor (rescue: Rescue) -> [Rat] {
        return rescue.relationships.rats.ids.compactMap({ ratId in
            return self.body.includes![Rat.self].first(where: {
                $0.id.rawValue == ratId.rawValue
            })
        })
    }

    func firstLimpetFor (rescue: Rescue) -> Rat? {
        guard let firstLimpetId = rescue.relationships.firstLimpet.id.rawValue else {
            return nil
        }

        return self.body.includes![Rat.self].first(where: {
            $0.id.rawValue == firstLimpetId
        })
    }

    func convertToLocalRescues (onBoard board: RescueBoard) -> [LocalRescue] {
        guard let rescueList = self.body.data?.primary.values else {
            return []
        }

        return rescueList.map({ (apiRescue) -> LocalRescue in
            let rats = self.assignedRatsFor(rescue: apiRescue)
            let firstLimpet = self.firstLimpetFor(rescue: apiRescue)
            return LocalRescue(fromAPIRescue: apiRescue, withRats: rats, firstLimpet: firstLimpet, onBoard: board)
        })
    }
}

extension Rescue {
    func update (complete: @escaping () -> Void, error: @escaping (Error) -> Void) {
        let patchDocument = SingleDocument(
            apiDescription: .none,
            body: .init(resourceObject: self),
            includes: .none,
            meta: .none,
            links: .none
        )

        let request = RestRequest(
            method: .patch,
            url: "\(configuration.api.url)/rescues/\(self.id.rawValue.uuidString)"
        )
        request.credentials = .bearerAuthentication(token: configuration.api.token)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(DateFormatter.iso8601Full)
        request.messageBody = try! encoder.encode(patchDocument)

        request.responseData(completionHandler: { result in
            switch result {
                case .success:
                    complete()
                case .failure(let restError):
                    error(restError)
            }
        })
    }
}

extension RescueGetDocument {
    static func from (data documentData: Data) throws -> RescueGetDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(DateFormatter.iso8601Full)

        return try decoder.decode(RescueGetDocument.self, from: documentData)
    }

    func assignedRats () -> [Rat] {
        guard let rescue = self.body.data?.primary.value else {
            return []
        }
        return rescue.relationships.rats.ids.compactMap({ ratId in
            return self.body.includes![Rat.self].first(where: {
                $0.id.rawValue == ratId.rawValue
            })
        })
    }

    func firstLimpet () -> Rat? {
        guard let rescue = self.body.data?.primary.value else {
            return nil
        }

        guard let firstLimpetId = rescue.relationships.firstLimpet.id.rawValue else {
            return nil
        }

        return self.body.includes![Rat.self].first(where: {
            $0.id.rawValue == firstLimpetId
        })
    }
}
