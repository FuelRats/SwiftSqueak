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
import IRCKit

struct StarSystem: CustomStringConvertible, Codable {
    var name: String {
        didSet {
            name = name.prefix(64).uppercased()
        }
    }
    var manuallyCorrected: Bool = false
    var permit: Permit? = nil
    var availableCorrections: [SystemsAPI.SearchDocument.SearchResult]? = nil
    var landmark: SystemsAPI.LandmarkDocument.LandmarkResult? = nil
    var clientProvidedBody: String?
    var proceduralCheck: SystemsAPI.ProceduralCheckDocument?
    var bodies: [EDSM.Body]? = nil
    var stations: [EDSM.Station]? = nil

    init (
        name: String,
        manuallyCorrected: Bool = false,
        permit: Permit? = nil,
        availableCorrections: [SystemsAPI.SearchDocument.SearchResult]? = nil,
        landmark: SystemsAPI.LandmarkDocument.LandmarkResult? = nil,
        clientProvidedBody: String? = nil,
        proceduralCheck: SystemsAPI.ProceduralCheckDocument? = nil
    ) {
        self.name = name.prefix(64).uppercased()
        self.manuallyCorrected = manuallyCorrected
        self.permit = permit
        self.availableCorrections = availableCorrections
        self.landmark = landmark
        self.clientProvidedBody = clientProvidedBody
        self.proceduralCheck = proceduralCheck
    }

    mutating func merge (_ starSystem: StarSystem) {
        self.name = starSystem.name
        self.permit = starSystem.permit
        self.availableCorrections = starSystem.availableCorrections
        self.landmark = starSystem.landmark
        self.proceduralCheck = starSystem.proceduralCheck
        self.bodies = starSystem.bodies
        self.stations = starSystem.stations
    }

    struct Permit: CustomStringConvertible, Codable {
        let name: String?

        var description: String {
            if let name = self.name {
                return "(\(name) Permit Required)"
            }
            return "(Permit Required)"
        }

        init? (fromSearchResult result: SystemsAPI.SearchDocument.SearchResult?) {
            guard let result = result, result.permitRequired else {
                return nil
            }
            self.name = result.permitName
        }
    }
    
    func body (byName name: String) -> EDSM.Body? {
        guard let bodies = self.bodies, bodies.count > 0 else {
            return nil
        }
        
        let composedName = "\(self.name.uppercased()) \(name.uppercased())"
        return bodies.first(where: { $0.name.uppercased() == composedName })
    }

    var description: String {
        var systemInfo = "\"\(self.name)\""
        if let landmark = self.landmark {
            systemInfo += " ("
            if let bodyInfo = self.bodies, let mainStar = bodyInfo.first(where: { $0.isMainStar == true }), let description = mainStar.bodyDescription {
                systemInfo += description + " "
            }
            if landmark.description.count > 0 {
                systemInfo += "\(landmark.description))"
            } else {
                systemInfo += ")"
            }
        } else if let procedural = self.proceduralCheck, procedural.isPgSystem == true && (procedural.isPgSector || procedural.sectordata.handauthored) {
            let (landmark, distance) = procedural.estimatedLandmarkDistance
            systemInfo += " (Estimated ~\(distance) LY from \(landmark.name))"
        } else if isInvalid || isIncomplete {
            systemInfo += IRCFormat.color(.Grey, " (Invalid system name)")
        } else {
            systemInfo += " (Not found in galaxy database)"
        }
        if let permit = self.permit {
            systemInfo += " " + IRCFormat.color(.Orange, permit.description)
        }
        return systemInfo
    }
    
    var shortDescription: String {
        var systemInfo = "\"\(self.name)\""
        if let landmark = self.landmark {
            systemInfo += landmark.description
        } else if self.proceduralCheck?.isPgSystem == true && self.proceduralCheck?.isPgSector == true {
            systemInfo += " (Valid procedural)"
        } else {
            systemInfo += " (Not found)"
        }
        if self.permit != nil {
            systemInfo += IRCFormat.bold(IRCFormat.color(.Orange, "*"))
        }
        return systemInfo
    }
    
    var info: String {
        var description = self.description + "."
        if let bodies = self.bodies, bodies.count > 1 {
            description += " \(bodies.count) stellar bodies"
        }
        let allStations = self.refuelingStations
        if allStations.count > 0 {
            let stations = allStations.filter({ $0.type != .FleetCarrier })
            let carriers = allStations.filter({ $0.type == .FleetCarrier })
            if stations.count > 0 {
                description += ", \(stations.count) \(stations.count > 1 ? "stations" : "station")"
            }
            if carriers.count > 0 {
                description += ", \(carriers.count) fleet \(carriers.count > 1 ? "carriers" : "carrier")"
            }
            
            let station = allStations.first!
            if station.type == .FleetCarrier {
                return description
            }
            if let economy = station.economy {
                description += ", Economy: \(economy)"
            }
            
            if let government = station.government {
                description += ", Government: \(government)"
            }
        }
        return description
    }

    var isIncomplete: Bool {
        if self.landmark != nil || (self.proceduralCheck != nil && self.isInvalid == false) {
            return false
        }

        if self.name.hasSuffix("SECTOR") && self.name.components(separatedBy: " ").count < 4 {
            return true
        }

        return sectors.contains(where: { $0.name == self.name })
    }
    
    var isInvalid: Bool {
        if let procedural = ProceduralSystem(string: self.name) {
            return (self.proceduralCheck?.isPgSystem == true && (self.proceduralCheck?.isPgSector == true || self.proceduralCheck?.sectordata.handauthored == true)) || !procedural.isValid
        }
        return false
    }

    var isConfirmed: Bool {
        return self.landmark != nil || (self.proceduralCheck?.isPgSystem == true && (self.proceduralCheck?.isPgSector == true || self.proceduralCheck?.sectordata.handauthored == true))
    }

    var twitterDescription: String? {
        guard let landmark = self.landmark else {
            if let procedural = self.proceduralCheck, procedural.isPgSystem == true && (procedural.isPgSector || procedural.sectordata.handauthored) {
                let (landmark, distance) = procedural.estimatedLandmarkDistance
                return "~\(distance) LY from \(landmark.name)"
            }
            return nil
        }
        if landmark.distance < 50 {
            return "near \(landmark.name)"
        }

        if landmark.distance < 500 {
            return "~\(ceil(landmark.distance / 10) * 10)LY from \(landmark.name)"
        }

        if landmark.distance < 2000 {
            return "~\(ceil(landmark.distance / 100) * 100)LY from \(landmark.name)"
        }

        return "~\(ceil(landmark.distance / 1000))kLY from \(landmark.name)"
    }
    
    var refuelingStations: [EDSM.Station] {
        var stations = self.stations?.filter({
            $0.otherServices.contains("Refuel")
        }) ?? []
        stations.sort(by: {
            $0.type.rating < $1.type.rating
        })
        return stations
    }
 }

extension Optional where Wrapped == StarSystem {
    var description: String {
        if let system = self {
            return system.description
        }
        return "u\u{200B}nknown system"
    }

    var name: String {
        if let system = self {
            return system.name
        }
        return "u\u{200B}nknown system"
    }
}
