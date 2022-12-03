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

extension Int64: CreatableRawIdType {
    public static func unique() -> Int64 {
        return Int64.random(in: 0...9999999999999)
    }
}

typealias SystemsAPIJSONEntity<Description: ResourceObjectDescription> =
    JSONAPI.ResourceObject<Description, NoMetadata, NoLinks, String>

typealias SystemsAPIDocument<PrimaryResourceBody: JSONAPI.CodableResourceBody, IncludeType: JSONAPI.Include> = JSONAPI.Document<
    PrimaryResourceBody,
    NoMetadata,
    JSONAPILinks,
    IncludeType,
    NoAPIDescription,
    BasicJSONAPIError<String>
>

typealias SystemGetDocument = SystemsAPIDocument<SingleResourceBody<SystemsAPI.System>, Include3<SystemsAPI.Star, SystemsAPI.Body, SystemsAPI.Station>>

enum SystemDescription: ResourceObjectDescription {
    public static var jsonType: String { return "systems" }

    public struct Attributes: JSONAPI.Attributes {
        public var name: Attribute<String>
        public var coords: Attribute<Vector3>
        public var systemAllegiance: Attribute<SystemsAPI.Allegiance?>
    }

    public struct Relationships: JSONAPI.Relationships {
        public let stars: ToManyRelationship<SystemsAPI.Star>?
        public let planets: ToManyRelationship<SystemsAPI.Body>?
        public let stations: ToManyRelationship<SystemsAPI.Station>?
    }
}

extension SystemsAPI {
    typealias System = SystemsAPIJSONEntity<SystemDescription>
    
    enum CelestialBodyType: String, Codable {
        case Planet
        case Star
    }
    
    struct Belt: Codable, Equatable {
        public var mass: Double?
        public var name: String?
        public var type: String?
        public var innerRadius: Double?
        public var outerRadius: Double?
    }
    
    public enum Allegiance: String, Codable {
        case Federation
        case Empire
        case Alliance
        case Independent
        case Thargoid
        case Unknown = ""
    }
}
