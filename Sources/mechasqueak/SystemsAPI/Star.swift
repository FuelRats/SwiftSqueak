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
import CryptoSwift
import NIO

enum StarDescription: ResourceObjectDescription {
    public static var jsonType: String { return "stars" }

    public struct Attributes: JSONAPI.Attributes {
        public let bodyId: Attribute<Int64>
        public var name: Attribute<String>
        public var type: Attribute<String>
        public var subType: Attribute<String>
        public var parents: Attribute<[[String: Int64]]?>
        public var distanceToArrival: Attribute<Int64?>
        public var isMainStar: Attribute<Bool?>
        public var isScoopable: Attribute<Bool>
        public var age: Attribute<Int64>
        public var luminosity: Attribute<SystemsAPI.Star.YerkesLuminosity>
        public var absoluteMagnitude: Attribute<Double?>
        public var solarMasses: Attribute<Double>
        public var solarRadius: Attribute<Double?>
        public var surfaceTemperature: Attribute<Double>
        public var orbitalPeriod: Attribute<Double?>
        public var semiMajorAxis: Attribute<Double?>
        public var orbitalEccentricity: Attribute<Double?>
        public var oribtalInclination: Attribute<Double>?
        public var argOfPeriapsis: Attribute<Double?>
        public var rotationalPeriod: Attribute<Double?>
        public var rotationalPeriodTidallyLocked: Attribute<Bool?>
        public var axialTilt: Attribute<Double?>
        public var belts: Attribute<[SystemsAPI.Belt]?>
        public var systemName: Attribute<String>
    }

    public struct Relationships: JSONAPI.Relationships {
    }
}

extension SystemsAPI {
    typealias Star = SystemsAPIJSONEntity<StarDescription>
}

extension SystemsAPI.Star {
    var spectralClass: SystemsAPI.Star.SpectralClass? {
        if self.type == "Star" {
            return SpectralClass.from(subType: self.subType)
        }
        return SpectralClass.from(subType: self.type)
    }
    
    var description: String {
        switch (self.spectralClass, self.luminosity) {
        case (let spectral, let lum) where spectral?.within([.O, .B, .A]) == true && lum.within([.Ia]) == true:
            return "Blue hypergiant"
            
        case (let spectral, let lum) where spectral?.within([.F, .G, .K]) == true && lum.within([.Ia]) == true:
            return "Yellow hypergiant"
            
        case (let spectral, let lum) where spectral?.within([.M]) == true && lum.within([.Ia]) == true:
            return "Red hypergiant"
            
        case (let spectral, let lum) where spectral?.within([.O, .B, .A]) == true && lum.within([.Iab, .Ib, .I]) == true:
            return "Blue supergiant"
            
        case (let spectral, let lum) where spectral?.within([.F, .G]) == true && lum.within([.Iab, .Ib, .I]) == true:
            return "Yellow supergiant"
            
        case (let spectral, let lum) where spectral?.within([.K, .M]) == true && lum.within([.Iab, .Ib, .I]) == true:
            return "Red supergiant"
            
        case (let spectral, let lum) where spectral?.within([.O, .B, .A]) == true && lum.within([.II, .III]) == true:
            return "Blue giant"
            
        case (let spectral, let lum) where spectral?.within([.F, .G]) == true && lum.within([.II, .III]) == true:
            return "Yellow giant"
        
        case (let spectral, let lum) where spectral?.within([.K, .M]) == true && lum.within([.II, .III]) == true:
            return "Red giant"
            
        case (let spectral, let lum) where spectral?.within([.O, .B, .A]) == true && lum.within([.IV]) == true:
            return "Blue sub-giant"
            
        case (let spectral, let lum) where spectral?.within([.F, .G]) == true && lum.within([.IV]) == true:
            return "Yellow sub-giant"
            
        case (let spectral, let lum) where spectral?.within([.K, .M]) == true && lum.within([.IV]) == true:
            return "Red sub-giant"
            
        case (.O, _):
            return "Blue-white star"
            
        case (.B, _):
            return "Blue star"
            
        case (.A, _):
            return "White star"
            
        case (.F, _):
            return "Yellow-white star"
            
        case (.G, _):
            return "Yellow dwarf"
            
        case (.K, _):
            return "Orange dwarf"
            
        case (.M, _):
            return "Red dwarf"
            
        case (let spectral, _) where spectral?.within([.L, .T, .Y]) == true:
            return "Brown dwarf"
            
        case (.TTS, _):
            return "T Tauri star"
            
        case (.W, _):
            return "Wolf-Rayet star"
            
        case (.C, _):
            return "Carbon star"
            
        case (.S, _):
            return "Cool giant"
            
        case (.MS, _):
            return "Barium star"
            
        case (.DA, _):
            return "White dwarf"
            
        case (.HAeBe, _):
            return "Herbig Ae/Be star"
            
        default:
            return self.subType
        }
    }
    
    enum YerkesLuminosity: String, Codable {
        case Ia
        case Iab
        case Ib
        case I
        case II
        case III
        case IV
        case V
        case Va
        case Vab
        case Vb
        case Vz
        case VI
        case VII
        
        func within (_ classes: [YerkesLuminosity]) -> Bool {
            return classes.contains(self)
        }
    }
    
    enum SpectralClass: String {
        case O
        case B
        case A
        case F
        case G
        case K
        case M
        case L
        case T
        case Y
        case TTS
        case W
        case C
        case S
        case MS
        case DA
        case HAeBe
        
        func within (_ classes: [SpectralClass]) -> Bool {
            return classes.contains(self)
        }
        
        private static let subTypeMap: [String: SpectralClass] = [
            "T Tauri Star": .TTS,
            "Wolf-Rayet Star": .W,
            "C Star": .C,
            "S-type Star": .S,
            "MS-type Star": .MS,
            "White Dwarf (DA) Star": .DA,
            "Herbig Ae/Be Star": .HAeBe
        ]
        
        static func from (subType: String) -> SpectralClass? {
            if let starClass = subType.components(separatedBy: " ").first, let spectralClass = SpectralClass(rawValue: starClass) {
                return spectralClass
            }
            return subTypeMap[subType]
        }
    }
}
