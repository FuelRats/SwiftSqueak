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
import AsyncHTTPClient

struct StarSystem: CustomStringConvertible, Codable, Equatable {
    static func == (lhs: StarSystem, rhs: StarSystem) -> Bool {
        return lhs.name == rhs.name
    }
    
    var name: String {
        didSet {
            name = name.prefix(64).uppercased()
        }
    }
    var manuallyCorrected: Bool = false
    var automaticallyCorrected: Bool = false
    var searchResult: SystemsAPI.SearchDocument.SearchResult? = nil
    var permit: Permit? = nil
    var availableCorrections: [SystemsAPI.SearchDocument.SearchResult]? = nil
    var landmarks: [SystemsAPI.LandmarkDocument.LandmarkResult] = []
    var clientProvidedBody: String?
    var proceduralCheck: SystemsAPI.ProceduralCheckDocument?
    var data: SystemGetDocument?
    var position: Vector3?
    var lookupAttempted: Bool = false
    var jumpCallWarned: Bool = false

    init (
        name: String,
        manuallyCorrected: Bool = false,
        searchResult: SystemsAPI.SearchDocument.SearchResult? = nil,
        availableCorrections: [SystemsAPI.SearchDocument.SearchResult]? = nil,
        landmark: SystemsAPI.LandmarkDocument.LandmarkResult? = nil,
        landmarks: [SystemsAPI.LandmarkDocument.LandmarkResult] = [],
        clientProvidedBody: String? = nil,
        proceduralCheck: SystemsAPI.ProceduralCheckDocument? = nil,
        lookupAttempted: Bool = false
    ) {
        self.name = name.prefix(64).uppercased()
        if self.name.hasSuffix(" SYSTEM") {
            self.name.removeLast(7)
        }
        self.manuallyCorrected = manuallyCorrected
        self.searchResult = searchResult
        if let searchResult = searchResult {
            self.permit = StarSystem.Permit(fromSearchResult: searchResult)
        }
        self.availableCorrections = availableCorrections
        self.landmarks = landmarks
        self.clientProvidedBody = clientProvidedBody
        self.proceduralCheck = proceduralCheck
        self.lookupAttempted = lookupAttempted
    }

    mutating func merge (_ starSystem: StarSystem) {
        self.name = starSystem.name
        self.searchResult = starSystem.searchResult
        self.permit = starSystem.permit
        self.availableCorrections = starSystem.availableCorrections
        self.landmarks = starSystem.landmarks
        self.proceduralCheck = starSystem.proceduralCheck
        self.data = starSystem.data
        self.lookupAttempted = starSystem.lookupAttempted
    }
    
    func getBody (byName bodyName: String) -> SystemsAPI.Body? {
        return self.data?.body.includes?[SystemsAPI.Body.self].first(where: { $0.name == "\($0.systemName) \(bodyName)" || $0.name == bodyName })
    }
    
    func getStar (byName starName: String) -> SystemsAPI.Star? {
        return self.data?.body.includes?[SystemsAPI.Star.self].first(where: { $0.name == "\($0.systemName) \(starName)" || $0.name == starName })
    }
    
    func systemBodyDescription (forBody body: String) -> String {
        if let systemStar = self.getStar(byName: body) {
            if let starClass = systemStar.spectralClass {
                return "\(body) (\(starClass) \(systemStar.description))"
            }
            return systemStar.description
        } else if let systemBody = self.getBody(byName: body) {
            return "\(body) \(systemBody.description)"
        }
        return body
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
    
    var landmarkDescription: String? {
        return self.description
    }

    var description: String {
        return (try? stencil.renderLine(name: "starsystem.stencil", context: [
            "system": self,
            "landmark": self.landmark as Any,
            "invalid": self.isInvalid
        ])) ?? ""
    }
    
    var info: String {
        get async {
            var plotUrl: URL?
            if self.landmark?.distance ?? 0 > 2500 {
                plotUrl = try? await generateSpanshRoute(from: "Sol", to: self.name)
            } else if let procedural = self.proceduralCheck, procedural.estimatedSolDistance.2 > 2500 {
                if let nearestTarget = try? await SystemsAPI.getNearestSystem(forCoordinates: procedural.sectordata.coords)?.data {
                    plotUrl = try? await generateSpanshRoute(from: "Sol", to: nearestTarget.name)
                }
            }
            
            let stars = self.data?.body.includes?[SystemsAPI.Star.self] ?? []
            let bodies = self.data?.body.includes?[SystemsAPI.Body.self] ?? []
            let stations = self.data?.body.includes?[SystemsAPI.Station.self] ?? []
            
            let allegiance = (self.data?.body.data?.primary.value.systemAllegiance ?? stations.first(where: {
                $0.allegiance != nil
            })?.allegiance)?.rawValue
            
            let government = stations.reduce([:], { (acc: [SystemsAPI.Government: Int], current) in
                var acc = acc
                guard let currentGov = current.government else {
                    return acc
                }
                if let value = acc[currentGov] {
                    acc[currentGov] = value + 1
                } else {
                    acc[currentGov] = 1
                }
                return acc
            }).enumerated().sorted(by: { $0.element.value > $1.element.value }).first?.element.key.ircFormatted
            
            let economy = stations.reduce([:], { (acc: [SystemsAPI.Economy: Int], current) in
                var acc = acc
                guard let currentEcon = current.economy else {
                    return acc
                }
                if let value = acc[currentEcon] {
                    acc[currentEcon] = value + 1
                } else {
                    acc[currentEcon] = 1
                }
                return acc
            }).enumerated().sorted(by: { $0.element.value > $1.element.value }).first?.element.key.rawValue
            
            let largeStations = stations.filter({ $0.type?.hasLargePad ?? false && $0.type?.isPlanetary == false })
            let outposts = stations.filter({ $0.type == .Outpost })
            let planetary = stations.filter({ $0.type?.isPlanetary ?? false })
            
            return (try? stencil.renderLine(name: "systeminfo.stencil", context: [
                "system": self,
                "landmark": self.landmark as Any,
                "region": self.galacticRegion as Any,
                "invalid": self.isInvalid,
                "plotUrl": plotUrl?.absoluteString as Any,
                "stations": stations,
                "largeStations": largeStations,
                "planetary": planetary,
                "outposts": outposts,
                "stars": stars,
                "bodies": bodies,
                "allegiance": allegiance as Any,
                "government": government as Any,
                "economy": economy as Any,
                "underAttack": isUnderAttack as Any
            ])) ?? ""
        }
    }
    
    var isUnderAttack: Bool {
        if self.data?.body.data?.primary.value.attributes.systemAllegiance.value == .Thargoid {
            return true
        }
        let stations = self.data?.body.includes?[SystemsAPI.Station.self] ?? []
        return stations.contains(where: {
            $0.stationState != nil
        })
    }
    
    var hasSecondaryFuelStar: Bool {
        let stars = self.data?.body.includes?[SystemsAPI.Star.self] ?? []
        return stars.contains(where: {
            $0.isScoopable && $0.isMainStar != true
        })
    }

    var isIncomplete: Bool {
        if self.landmark != nil || (self.proceduralCheck != nil && self.isInvalid == false) {
            return false
        }

        if self.name.hasSuffix("SECTOR") && self.name.components(separatedBy: " ").count < 4 {
            return true
        }
        
        if ProceduralSystem.proceduralEndPattern.matches(self.name.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()) {
            return true
        }

        return mecha.sectors.contains(where: { $0.name == self.name })
    }
    
    var isInvalid: Bool {
        if ProceduralSystem.proceduralSystemExpression.matches(self.name), let procedural = ProceduralSystem(string: self.name) {
            return (self.proceduralCheck?.isPgSystem == false || (self.proceduralCheck?.isPgSector == false && self.proceduralCheck?.sectordata.handauthored == false)) || !procedural.isValid
        }
        return self.lookupAttempted && self.landmark == nil
    }

    var isConfirmed: Bool {
        return self.landmark != nil || (self.proceduralCheck?.isPgSystem == true && (self.proceduralCheck?.isPgSector == true || self.proceduralCheck?.sectordata.handauthored == true))
    }
    
    
    var landmark: SystemsAPI.LandmarkDocument.LandmarkResult? {
        let systemName = self.name.uppercased()
        return self.landmarks.first(where: { $0.name.uppercased() != systemName }) ?? self.landmarks.first
    }

    var twitterDescription: String? {
        var description = ""
        if let galacticRegion = self.galacticRegion, galacticRegion.name != "The Inner Orion Spur" {
            description = "In \(galacticRegion.name) "
        }
        guard let landmark = self.landmark else {
            if let procedural = self.proceduralCheck, procedural.isPgSystem == true && (procedural.isPgSector || procedural.sectordata.handauthored) {
                let (landmark, distance, _) = procedural.estimatedLandmarkDistance
                description += "~\(distance) LY from \(landmark.name)"
                return description
            }
            return nil
        }
        if landmark.distance < 50 {
            description += "near \(landmark.name)"
        } else if landmark.distance < 500 {
            description += "~\(ceil(landmark.distance / 10) * 10)LY from \(landmark.name)"
        } else if landmark.distance < 2000 {
            description += "~\(ceil(landmark.distance / 100) * 100)LY from \(landmark.name)"
        } else {
            description += "~\(ceil(landmark.distance / 1000))kLY from \(landmark.name)"
        }
        
        if let permit = self.permit {
            if let permitName = permit.name {
                description += " (REQUIRES \(permitName.uppercased()) PERMIT)"
            } else {
                description += " (REQUIRES PERMIT)"
            }
        }
        return description
    }
    
    var coordinates: Vector3? {
        return self.searchResult?.coords ?? self.proceduralCheck?.sectordata.coords
    }
    
    var galacticRegion: GalacticRegion? {
        guard let coordinates = self.coordinates else {
            return nil
        }
        let point = CGPoint(x: coordinates.x, y: coordinates.z)
        return regions.first(where: {
            point.intersects(polygon: $0.coordinates)
        })
    }
 }

func generateSpanshRoute (from: String, to: String, range: Int = 65) async throws -> URL {
    var request = try HTTPClient.Request(url: URL(string: "https://spansh.co.uk/api/route")!, method: .POST)
    
    let requestBody: [String: String?] = [
        "efficiency": "60",
        "range": String(range),
        "from": from,
        "to": to
    ]
    request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
    request.headers.add(name: "Content-Type", value: "application/x-www-form-urlencoded; charset=utf-8")
    request.body = try .formUrlEncoded(requestBody)
    let response = try await httpClient.execute(request: request, forDecodable: SpanshResponse.self)
    var url = URLComponents(string: "https://www.spansh.co.uk/plotter/results/\(response.job)")!
    url.queryItems = requestBody.queryItems
    
    
    return await URLShortener.attemptShorten(url: url.url!)
}

fileprivate struct SpanshResponse: Codable {
    let job: String
    let status: String
}

extension Optional where Wrapped == StarSystem {
    var description: String {
        if let system = self {
            return system.description
        }
        return "unknown system"
    }

    var name: String {
        if let system = self {
            return system.name
        }
        return "unknown system"
    }
}

func loadRegions () -> [GalacticRegion] {
    let regionPath = URL(
        fileURLWithPath: configuration.sourcePath.path
    ).appendingPathComponent("regions.json")

    guard let regionData = try? Data(contentsOf: regionPath) else {
        fatalError("Could not locate region file in \(regionPath.absoluteString)")
    }

    let regionDecoder = JSONDecoder()
    return try! regionDecoder.decode([GalacticRegion].self, from: regionData)
}

let regions = loadRegions()

func loadNamedBodies () -> [String: String] {
    let namedBodyPath = URL(
        fileURLWithPath: configuration.sourcePath.path
    ).appendingPathComponent("namedbodies.json")

    guard let bodyData = try? Data(contentsOf: namedBodyPath) else {
        fatalError("Could not locate named bodies file in \(namedBodyPath.absoluteString)")
    }

    let bodyDecoder = JSONDecoder()
    return try! bodyDecoder.decode([String: String].self, from: bodyData)
}

let namedBodies = loadNamedBodies()

struct GalacticRegion: Decodable {
    let id: Int
    let name: String
    let coordinates: [CGPoint]
    
    enum CodingKeys: String, CodingKey {
        case id, name, coordinates
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.coordinates = try container.decode([[Double]].self, forKey: .coordinates).map({ CGPoint(x: $0[0], y: $0[2]) })
    }
}
