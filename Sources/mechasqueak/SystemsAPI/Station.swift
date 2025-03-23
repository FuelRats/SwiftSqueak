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

enum StationDescription: ResourceObjectDescription {
    public static var jsonType: String { return "stations" }

    public struct Attributes: JSONAPI.Attributes {
        public var marketId: Attribute<Int64?>
        public var type: Attribute<SystemsAPI.NearestPopulatedDocument.PopulatedSystem.Station.StationType?>
        public var name: Attribute<String>
        public var distanceToArrival: Attribute<Double>
        public var allegiance: Attribute<SystemsAPI.Allegiance?>
        public var government: Attribute<SystemsAPI.Government?>
        public var economy: Attribute<SystemsAPI.Economy?>
        public var haveMarket: Attribute<Bool>
        public var haveShipyard: Attribute<Bool>
        public var haveOutfitting: Attribute<Bool>
        public var otherServices: Attribute<[String]>
        public var systemName: Attribute<String>
        public var stationState: Attribute<SystemsAPI.NearestPopulatedDocument.PopulatedSystem.Station.State?>?
        
        init(from decoder: any Decoder) throws {
            let container: KeyedDecodingContainer<StationDescription.Attributes.CodingKeys> = try decoder.container(keyedBy: StationDescription.Attributes.CodingKeys.self)
            self.marketId = try container.decode(Attribute<Int64?>.self, forKey: StationDescription.Attributes.CodingKeys.marketId)
            var stationType = try container.decode(SystemsAPI.NearestPopulatedDocument.PopulatedSystem.Station.StationType?.self, forKey: StationDescription.Attributes.CodingKeys.type)
            var name = try container.decode(String.self, forKey: StationDescription.Attributes.CodingKeys.name)
            self.distanceToArrival = try container.decode(Attribute<Double>.self, forKey: StationDescription.Attributes.CodingKeys.distanceToArrival)
            self.allegiance = try container.decode(Attribute<SystemsAPI.Allegiance?>.self, forKey: StationDescription.Attributes.CodingKeys.allegiance)
            self.government = try container.decode(Attribute<SystemsAPI.Government?>.self, forKey: StationDescription.Attributes.CodingKeys.government)
            self.economy = try container.decode(Attribute<SystemsAPI.Economy?>.self, forKey: StationDescription.Attributes.CodingKeys.economy)
            self.haveMarket = try container.decode(Attribute<Bool>.self, forKey: StationDescription.Attributes.CodingKeys.haveMarket)
            self.haveShipyard = try container.decode(Attribute<Bool>.self, forKey: StationDescription.Attributes.CodingKeys.haveShipyard)
            self.haveOutfitting = try container.decode(Attribute<Bool>.self, forKey: StationDescription.Attributes.CodingKeys.haveOutfitting)
            self.otherServices = try container.decode(Attribute<[String]>.self, forKey: StationDescription.Attributes.CodingKeys.otherServices)
            self.systemName = try container.decode(Attribute<String>.self, forKey: StationDescription.Attributes.CodingKeys.systemName)
            var stationState = try container.decodeIfPresent(SystemsAPI.NearestPopulatedDocument.PopulatedSystem.Station.State.self, forKey: StationDescription.Attributes.CodingKeys.stationState)
            
            if stationType == nil && name.hasPrefix("Orbital Construction Site: ") {
                name = String(name.dropFirst("Orbital Construction Site: ".count))
                stationType = .OrbitalConstructionSite
                stationState = .Construction
            }
            if stationType == nil && name.hasPrefix("Planetary Construction Site: ") {
                name = String(name.dropFirst("Planetary Construction Site: ".count))
                stationType = .PlanetaryConstructionSite
                stationState = .Construction
            }

            if stationState == .Construction && stationType == nil {
                stationType = .SpaceConstructionDepot
            }
            if stationType == nil && name.hasPrefix("System Colonisation Ship") {
                stationType = .SystemColonizationShip
                stationState = .Construction
            }
            if stationType == nil {
                stationType = .Settlement
            }

            self.name = Attribute(value: name)
            self.type = Attribute(value: stationType)
            self.stationState = Attribute(value: stationState)
        }
    }

    public struct Relationships: JSONAPI.Relationships {
    }
}

extension SystemsAPI {
    typealias Station = SystemsAPIJSONEntity<StationDescription>
    
    enum Government: String, Codable {
        case Anarchy
        case Communism
        case Confederacy
        case Cooperative
        case Corporate
        case Democracy
        case Dictatorship
        case Feudal
        case Patronage
        case PrisonColony = "Prison colony"
        case Theocracy
        case Engineer = "Workshop (Engineer)"
        case Prison
        
        init (from decoder: Decoder) throws {
            var rawValue = try decoder.singleValueContainer().decode(String.self)
            if rawValue.starts(with: "$") {
                rawValue.removeFirst(12)
                rawValue.removeLast()
                if rawValue == "PrisonColony" {
                    rawValue = "Prison colony"
                }
                if rawValue == "Engineer" {
                    rawValue = "Workshop (Engineer)"
                }
            }
            if let value = Government(rawValue: rawValue) {
                self = value
            } else {
                throw DecodingError.dataCorrupted(DecodingError.Context.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid Enum Raw Value"
                ))
            }
        }
        
        var ircFormatted: String {
            switch self {
            case .Anarchy:
                return IRCFormat.color(.LightRed, self.rawValue)
                
            case .Communism, .Dictatorship, .Feudal, .Prison, .Theocracy, .PrisonColony:
                return IRCFormat.color(.Yellow, self.rawValue)
                
            case .Confederacy, .Cooperative, .Democracy, .Patronage:
                return IRCFormat.color(.LightGreen, self.rawValue)
                
            default:
                return IRCFormat.color(.LightGrey, self.rawValue)
            }
        }
    }
    
    enum Economy: String, Codable {
        case Extraction
        case Refinery
        case Industrial
        case HighTech = "High Tech"
        case Agriculture
        case Terraforming
        case Tourism
        case Service
        case Military
        case Colony
        case Rescue
        case Damaged
        case Repair
        case PrivateEnterprise = "Private Enterprise"
        
        init (from decoder: Decoder) throws {
            var rawValue = try decoder.singleValueContainer().decode(String.self)
            if rawValue.starts(with: "$") {
                rawValue.removeFirst(9)
                rawValue.removeLast()
                if rawValue == "HighTech" {
                    rawValue = "High Tech"
                }
                if rawValue == "PrivateEnterprise" {
                    rawValue = "Private Enterprise"
                }
            }
            if let value = Economy(rawValue: rawValue) {
                self = value
            } else {
                throw DecodingError.dataCorrupted(DecodingError.Context.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Invalid Enum Raw Value"
                ))
            }
        }
    }
}
