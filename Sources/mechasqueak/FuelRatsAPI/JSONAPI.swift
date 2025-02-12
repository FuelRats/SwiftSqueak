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

struct JSONAPIMeta: Meta {
    let page: Int?
    let lastPage: Int?
    let nextPage: Int?
    let offset: Int?
    let limit: Int?
    let total: Int?

    let apiVersion: String

    let rateLimitTotal: Int?
    let rateLimitRemaining: Int?
    let rateLimitReset: Date?
}

struct JSONAPILinks: Links {
    let `self`: String
    let first: String?
    let last: String?
    let next: String?
    let previous: String?
}

struct JSONAPIDescriptionMetaData: Meta {
    let apiVersion: String
}

extension UUID: @retroactive CreatableRawIdType {
    public static func unique() -> UUID {
        return UUID()
    }
}

typealias JSONEntity<Description: ResourceObjectDescription> =
    JSONAPI.ResourceObject<Description, NoMetadata, NoLinks, UUID>
typealias UnidentifiedJSONEntity<Description: ResourceObjectDescription> =
    JSONAPI.ResourceObject<Description, NoMetadata, NoLinks, Unidentified>

typealias ToOneRelationship<Entity: JSONAPIIdentifiable> = JSONAPI.ToOneRelationship<Entity, NoIdMetadata, NoMetadata, NoLinks>
typealias ToManyRelationship<Entity: Relatable> = JSONAPI.ToManyRelationship<Entity, NoIdMetadata, NoMetadata, NoLinks>

typealias Document<PrimaryResourceBody: JSONAPI.CodableResourceBody, IncludeType: JSONAPI.Include> = JSONAPI.Document<
    PrimaryResourceBody,
    JSONAPIMeta,
    JSONAPILinks,
    IncludeType,
    APIDescription<JSONAPIDescriptionMetaData>,
    BasicJSONAPIError<String>
>

typealias EventDocument<PrimaryResourceBody: JSONAPI.CodableResourceBody, IncludeType: JSONAPI.Include> = JSONAPI.Document<
    PrimaryResourceBody,
    JSONAPIDescriptionMetaData,
    JSONAPILinks,
    IncludeType,
    APIDescription<JSONAPIDescriptionMetaData>,
    BasicJSONAPIError<String>
>

struct ManyRelationshipBody: Codable {
    let data: [ManyRelationshipBodyDataItem]
    
    struct ManyRelationshipBodyDataItem: Codable {
        let type: String
        let id: UUID
    }
}
