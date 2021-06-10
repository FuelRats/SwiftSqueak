/*
 Copyright 202§ The Fuel Rats Mischief

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
import AsyncHTTPClient
import IRCKit
import NIO

class SystemsAPI {
    static func performSearch (forSystem systemName: String, quickSearch: Bool = false) async throws -> SearchDocument {
        var url = URLComponents(string: "https://system.api.fuelrats.com/mecha")!
        url.queryItems = [URLQueryItem(name: "name", value: systemName)]
        if quickSearch {
            url.queryItems?.append(URLQueryItem(name: "fast", value: "true"))
        }
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        let deadline: NIODeadline? = .now() + (quickSearch ? .seconds(5) : .seconds(60))

        var request = try! HTTPClient.Request(url: url.url!, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)

        return try await httpClient.execute(request: request, forDecodable: SearchDocument.self, deadline: deadline)
    }
    
    static func performLandmarkCheck (forSystem systemName: String) async throws -> LandmarkDocument {
        var url = URLComponents(string: "https://system.api.fuelrats.com/landmark")!
        url.queryItems = [URLQueryItem(name: "name", value: systemName)]
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")

        var request = try! HTTPClient.Request(url: url.url!, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)

        return try await httpClient.execute(request: request, forDecodable: LandmarkDocument.self)
    }
    
    static func getSystemInfo (forSystem system: SystemsAPI.SearchDocument.SearchResult) async throws -> StarSystem {
        let (landmarkDocument, systemData) = try await (performLandmarkCheck(forSystem: system.name), getSystemData(forId: system.id64))
        var starSystem = StarSystem(
            name: system.name,
            searchResult: system,
            availableCorrections: nil,
            landmark: landmarkDocument.first,
            landmarks: landmarkDocument.landmarks ?? [],
            proceduralCheck: nil,
            lookupAttempted: true
        )
        starSystem.data = systemData
        return starSystem
    }

    static func performProceduralCheck (forSystem systemName: String) async throws -> ProceduralCheckDocument {
        var url = URLComponents(string: "https://system.api.fuelrats.com/procname")!
        url.queryItems = [URLQueryItem(name: "name", value: systemName)]
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")

        var request = try! HTTPClient.Request(url: url.url!, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)

        return try await httpClient.execute(request: request, forDecodable: ProceduralCheckDocument.self)
    }
    
    
    static func getSystemData (forId id: Int64) async throws -> SystemGetDocument {
        var url = URL(string: "https://systems.api.fuelrats.com/api/systems/")!
        url.appendPathComponent(String(id))

        var request = try! HTTPClient.Request(url: url, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)

        return try await httpClient.execute(request: request, forDecodable: SystemGetDocument.self)
    }
    
    static func getNearestStations (forSystem systemName: String) async throws -> NearestPopulatedDocument {
        var url = URLComponents(string: "https://system.api.fuelrats.com/nearest_populated")!
        url.queryItems = [URLQueryItem(name: "name", value: systemName)]
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")

        var request = try! HTTPClient.Request(url: url.url!, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)

        return try await httpClient.execute(request: request, forDecodable: NearestPopulatedDocument.self)
    }
    
    static func performSystemCheck (forSystem systemName: String) async throws -> StarSystem {
        var systemName = systemName
        if systemName.uppercased() == "SABIYHAN" {
            systemName = "CRUCIS SECTOR ZP-P A5-2"
        }
        
        let (searchResults, proceduralResult) = await (try? performSearch(forSystem: systemName, quickSearch: true), try? performProceduralCheck(forSystem: systemName))
        let searchResult = searchResults?.data?.first(where: {
            $0.similarity == 1
        })
        let properName = searchResult?.name ?? systemName
        
        var starSystem = StarSystem(
            name: properName,
            searchResult: searchResult,
            availableCorrections: searchResults?.data,
            landmark: nil,
            landmarks: [],
            proceduralCheck: proceduralResult,
            lookupAttempted: true
        )
        
        guard let searchResult = searchResult else {
            return starSystem
        }
        
        let (landmarkResults, systemData) = try await (performLandmarkCheck(forSystem: properName), getSystemData(forId: searchResult.id64))
        starSystem.landmark = landmarkResults.first
        starSystem.landmarks = landmarkResults.landmarks ?? []
        starSystem.data = systemData
        return starSystem
    }
    
    static func getStatistics () async throws -> StatisticsDocument {
        let url = URLComponents(string: "https://system.api.fuelrats.com/api/stats")!
        var request = try! HTTPClient.Request(url: url.url!, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)

        let response = try await httpClient.execute(request: request, expecting: 200)
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(
            StatisticsDocument.self,
            from: Data(buffer: response.body!)
        )
    }
    
    static func fetchLandmarkList () async throws -> [LandmarkListDocument.LandmarkListEntry] {
        let url = URLComponents(string: "https://systems.api.fuelrats.com/landmark?list")!
        var request = try! HTTPClient.Request(url: url.url!, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)

        return try await httpClient.execute(request: request, forDecodable: LandmarkListDocument.self).landmarks
    }
    
    static func fetchSectorList () async throws -> [StarSector] {
        let url = URLComponents(string: "https://systems.api.fuelrats.com/get_ha_regions")!
        var request = try! HTTPClient.Request(url: url.url!, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)

        let sectors = try await httpClient.execute(request: request, forDecodable: [String].self)
        return sectors.map({ sector -> StarSector in
            var name = sector.uppercased()
            var hasSector = false
            if name.hasSuffix(" SECTOR") {
                name.removeLast(7)
                hasSector = true
            }
            return StarSector(name: name, hasSector: hasSector)
        })
    }


    struct LandmarkDocument: Codable {
        let meta: Meta
        let landmarks: [LandmarkResult]?

        struct Meta: Codable {
            let name: String?
            let error: String?
        }

        struct LandmarkResult: Codable {
            let name: String
            let distance: Double
        }
        
        var first: LandmarkDocument.LandmarkResult? {
            if self.landmarks?.count ?? 0 < 2 {
                return self.landmarks?.first
            }
            return self.landmarks?.first
        }
    }
    
    struct LandmarkListDocument: Decodable {
        let meta: LandmarkListMeta
        let landmarks: [LandmarkListEntry]
        
        struct LandmarkListEntry: Decodable {
            let name: String
            let coordinates: Vector3
            let soi: Double?
            
            enum CodingKeys: String, CodingKey {
                case name, x, y, z, soi
            }
            
            init (name: String, coordinates: Vector3, soi: Double? = nil) {
                self.name = name
                self.coordinates = coordinates
                self.soi = soi
            }
            
            init (from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                name = try values.decode(String.self, forKey: .name)
                
                let x = try values.decode(Double.self, forKey: .x)
                let y = try values.decode(Double.self, forKey: .y)
                let z = try values.decode(Double.self, forKey: .z)
                self.coordinates = Vector3(x, y, z)
                
                self.soi = try? values.decode(Double.self, forKey: .soi)
            }
        }
        
        struct LandmarkListMeta: Decodable {
            let count: Int
        }
    }

    struct StatisticsDocument: Codable {
        struct SystemsAPIStatistic: Codable {
            struct SystemsAPIStatisticAttributes: Codable {
                let syscount: Int64
                let starcount: Int64
                let bodycount: Int64
            }

            let id: String
            let type: String
            let attributes: SystemsAPIStatisticAttributes
        }

        let data: [SystemsAPIStatistic]
    }

    struct ProceduralCheckDocument: Codable {
        let isPgSystem: Bool
        let isPgSector: Bool
        let sectordata: SectorData
        
        var estimatedLandmarkDistance: (LandmarkListDocument.LandmarkListEntry, String, Double) {
            var landmarkDistances = mecha.landmarks.map({ ($0, self.sectordata.coords.distance(from: $0.coordinates)) })
            landmarkDistances = landmarkDistances.filter({ $0.0.soi == nil || $0.1 < $0.0.soi! })
            landmarkDistances.sort(by: { $0.1 < $1.1 })
            
            let formatter = NumberFormatter.englishFormatter()
            formatter.usesSignificantDigits = true
            formatter.maximumSignificantDigits = self.sectordata.uncertainty.significandWidth
            
            return (landmarkDistances[0].0, formatter.string(from: landmarkDistances[0].1)!, landmarkDistances[0].1)
        }
        
        var estimatedSolDistance: (LandmarkListDocument.LandmarkListEntry, String, Double) {
            let distance = self.sectordata.coords.distance(from: Vector3(0, 0, 0))
            
            let formatter = NumberFormatter.englishFormatter()
            formatter.usesSignificantDigits = true
            formatter.maximumSignificantDigits = self.sectordata.uncertainty.significandWidth
            
            let landmark = LandmarkListDocument.LandmarkListEntry(name: "Sol", coordinates: Vector3(0, 0, 0))
            return (landmark, formatter.string(from: distance)!, distance)
        }
        
        struct SectorData: Codable {
            let handauthored: Bool
            let uncertainty: Double
            let coords: Vector3
        }
        
        var galacticRegion: GalacticRegion? {
            let coordinates = self.sectordata.coords
            let point = CGPoint(x: coordinates.x, y: coordinates.z)
            return regions.first(where: {
                point.intersects(polygon: $0.coordinates)
            })
        }
    }

    struct SearchDocument: Codable {
        let meta: Meta
        let data: [SearchResult]?

        struct Meta: Codable {
            let name: String?
            let error: String?
            let type: String?
        }

        struct SearchResult: Codable {
            let name: String
            let id64: Int64
            let coords: Vector3

            let similarity: Double?
            let distance: Int?
            let permitRequired: Bool
            let permitName: String?

            var searchSimilarityText: String {
                if let distance = self.distance {
                    return String(distance)
                } else if let similarity = self.similarity {
                    return "\(String(Int(similarity * 100)))%"
                } else {
                    return "?"
                }
            }

            var permitText: String? {
                if self.permitRequired {
                    if let permitName = self.permitName {
                        return IRCFormat.color(.Orange, "(\(permitName) Permit Required)")
                    } else {
                        return IRCFormat.color(.Orange, "(Permit Required)")
                    }
                }
                return nil
            }

            var textRepresentation: String {
                if self.permitRequired {
                    if let permitName = self.permitName {
                        let permitReq = IRCFormat.color(.Orange, "(\(permitName) Permit Required)")
                        return "\"\(self.name)\" [\(self.searchSimilarityText)] \(permitReq)"
                    }
                    let permitReq = IRCFormat.color(.Orange, "(Permit Required)")
                    return "\"\(self.name)\" [\(self.searchSimilarityText)] \(permitReq)"
                }
                return "\"\(self.name)\" [\(self.searchSimilarityText)]"
            }


            func correctionRepresentation (index: Int) -> String {
                if self.permitRequired {
                    if let permitName = self.permitName {
                        let permitReq = IRCFormat.color(.Orange, "(\(permitName) Permit Required)")
                        return "(\(IRCFormat.bold(index.description))) \"\(self.name)\" \(permitReq)"
                    }
                    let permitReq = IRCFormat.color(.Orange, "(Permit Required)")
                    return "(\(IRCFormat.bold(index.description))) \"\(self.name)\" \(permitReq)"
                }
                return "(\(IRCFormat.bold(index.description))) \"\(self.name)\""
            }

            func rateCorrectionFor (system: String) -> Int? {
                let system = system.lowercased()
                let correctionName = self.name.lowercased()


                let isWithinReasonableEditDistance = (system.levenshtein(correctionName) < 2 && correctionName.strippingNonLetters == system.strippingNonLetters)
                let originalIsProceduralSystem = ProceduralSystem.proceduralSystemExpression.matches(system)

                if correctionName.strippingNonAlphanumeric == system.strippingNonAlphanumeric {
                    return 0
                }

                if correctionName == system.dropLast(1) && system.last!.isLetter {
                    return 2
                }

                if system.levenshtein(correctionName) < 2 && correctionName.strippingNonLetters == system.strippingNonLetters {
                    return 3
                }

                if isWithinReasonableEditDistance && !originalIsProceduralSystem {
                    return 4
                }
                return nil
            }
        }
    }
    
    struct NearestPopulatedDocument: Codable {
        let meta: Meta
        let data: [PopulatedSystem]
        
        var preferableSystem: PopulatedSystem? {
            return self.data.sorted(by: {
                ($0.preferableStation?.hasLargePad == true && $1.preferableStation?.hasLargePad != true) && $1.distance / $0.distance < 10
            }).first
        }
        
        var largePadSystem: PopulatedSystem? {
            return self.data.filter({ $0.hasStationWithLargePad }).first
        }
        
        struct PopulatedSystem: Codable {
            let distance: Double
            let name: String
            let id64: Int64
            let stations: [Station]
            
            var hasStationWithLargePad: Bool {
                return self.stations.contains(where: { $0.hasLargePad })
            }
            
            var preferableStation: Station? {
                return self.stations.sorted(by: {
                    ($0.type.rating < $1.type.rating && ($0.distance - $1.distance) < 25000) || (($0.hasLargePad && $1.hasLargePad == false) && ($0.distance - $1.distance) < 300000)
                }).first
            }
            
            var largePadStation: Station? {
                return self.stations.filter({ $0.hasLargePad }).first
            }
            
            struct Station: Codable {
                static let notableServices = ["Shipyard", "Outfitting", "Refuel", "Repair", "Restock"]
                let name: String
                let type: StationType
                let distance: Double
                let hasMarket: Bool
                let hasShipyard: Bool
                let hasOutfitting: Bool
                let services: [String]
                
                enum StationType: String, Codable {
                    case CoriolisStarport = "Coriolis Starport"
                    case OcellusStarport = "Ocellus Starport"
                    case OrbisStarport = "Orbis Starport"
                    case Outpost
                    case PlanetaryOutpost = "Planetary Outpost"
                    case PlanetaryPort = "Planetary Port"
                    case AsteroidBase = "Asteroid base"
                    case MegaShip = "Mega ship"
                    case FleetCarrier = "Fleet Carrier"
                    
                    
                    static let ratings: [StationType: UInt] = [
                        .CoriolisStarport: 0,
                        .OcellusStarport: 0,
                        .OrbisStarport: 0,
                        .AsteroidBase: 1,
                        .MegaShip: 1,
                        .PlanetaryPort: 2,
                        .PlanetaryOutpost: 3,
                        .Outpost: 3,
                        .FleetCarrier: 4
                    ]
                    
                    var rating: UInt {
                        return StationType.ratings[self]!
                    }
                }
                
                var hasLargePad: Bool {
                    return self.type != .Outpost && self.type != .PlanetaryOutpost
                }
                
                var notableServices: [String] {
                    return allServices.filter({ Station.notableServices.contains($0) })
                }
                
                var allServices: [String] {
                    var services: [String] = self.services
                    
                    if self.hasShipyard {
                        services.append("Shipyard")
                    }
                    
                    if self.hasOutfitting {
                        services.append("Outfitting")
                    }
                    
                    if self.hasMarket {
                        services.append("Market")
                    }
                    return services
                }
            }
        }
        
        struct Meta: Codable {
            let name: String?
            let type: String?
        }
    }
}

struct StarSector {
    let name: String
    let hasSector: Bool
}
