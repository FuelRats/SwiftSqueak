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
        public var type: Attribute<SystemsAPI.NearestPopulatedDocument.PopulatedSystem.Station.StationType>
        public var name: Attribute<String>
        public var distanceToArrival: Attribute<Double>
        public var allegiance: Attribute<String?>
        public var government: Attribute<SystemsAPI.Government?>
        public var economy: Attribute<String?>
        public var haveMarket: Attribute<Bool>
        public var haveShipyard: Attribute<Bool>
        public var haveOutfitting: Attribute<Bool>
        public var otherServices: Attribute<[String]>
        public var systemName: Attribute<String>
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
}
