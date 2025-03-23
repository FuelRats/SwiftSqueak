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

import AsyncHTTPClient
import Foundation
import IRCKit
import JSONAPI
import NIO
import NIOHTTP1

let maxUsefulDistance = 300000.0
let minPreferredDistance = 15000.0
let limitedPenalty = 50.0

class SystemsAPI {
    private static var shortNamesCapitalisation = [
        "IX": "Ix",
        "H": "h",
        "AO": "Ao",
        "EL": "El",
        "KI": "Ki",
    ]

    static func performSearch(forSystem systemName: String, quickSearch: Bool = false) async throws
        -> SearchDocument
    {
        var queryItems = [
            "name": systemName
        ]
        if quickSearch {
            queryItems["fast"] = "true"
        }

        let request = try HTTPClient.Request(
            systemApiPath: "/mecha", method: .GET, query: queryItems)

        let deadline: NIODeadline? = .now() + (quickSearch ? .seconds(5) : .seconds(180))
        return try await httpClient.execute(
            request: request, forDecodable: SearchDocument.self, deadline: deadline)
    }

    static func performLandmarkCheck(forSystem systemName: String) async throws -> LandmarkDocument
    {
        let request = try HTTPClient.Request(
            systemApiPath: "/landmark", method: .GET,
            query: [
                "name": systemName
            ])
        return try await httpClient.execute(request: request, forDecodable: LandmarkDocument.self)
    }

    static func getSystemInfo(forSystem system: SystemsAPI.SearchDocument.SearchResult) async throws
        -> StarSystem
    {
        let (landmarkDocument, systemData) = try await (
            performLandmarkCheck(forSystem: system.name), getSystemData(forId: system.id64)
        )
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

    static func performProceduralCheck(forSystem systemName: String) async throws
        -> ProceduralCheckDocument
    {
        let request = try HTTPClient.Request(
            systemApiPath: "/procname", method: .GET,
            query: [
                "name": systemName
            ])

        return try await httpClient.execute(
            request: request, forDecodable: ProceduralCheckDocument.self)
    }

    static func getSystemData(forId id: Int64) async throws -> SystemGetDocument {
        let request = try HTTPClient.Request(
            systemApiPath: "/api/systems/\(id)", method: .GET,
            query: [
                "include": "stars,planets,stations"
            ])

        return try await httpClient.execute(request: request, forDecodable: SystemGetDocument.self)
    }

    static func getNearestStations(forSystem systemName: String, limit: Int = 10) async throws
        -> NearestPopulatedDocument
    {
        let request = try HTTPClient.Request(
            systemApiPath: "/nearest_populated", method: .GET,
            query: [
                "name": systemName,
                "limit": String(limit),
            ])

        return try await httpClient.execute(
            request: request, forDecodable: NearestPopulatedDocument.self)
    }

    static func getNearestPreferableStation(
        forSystem systemName: String,
        limit: Int = 10,
        largePad: Bool,
        requireSpace: Bool
    ) async throws -> (
        SystemsAPI.NearestPopulatedDocument.PopulatedSystem,
        SystemsAPI.NearestPopulatedDocument.PopulatedSystem.Station
    )? {
        let response = try await SystemsAPI.getNearestStations(forSystem: systemName, limit: limit)

        guard
            let system = response.preferableSystems(
                requireLargePad: largePad, requireSpace: requireSpace
            ).first
        else {
            return nil
        }

        guard
            let station = system.preferableStations(
                requireLargePad: largePad, requireSpace: requireSpace
            ).first
        else {
            return nil
        }
        return (system, station)
    }

    static func getNearestSystem(forCoordinates coords: Vector3) async throws
        -> NearestSystemDocument?
    {
        let request = try HTTPClient.Request(
            systemApiPath: "/nearest_coords", method: .GET,
            query: [
                "x": String(coords.x),
                "y": String(coords.y),
                "z": String(coords.z),
            ])

        return try await httpClient.execute(
            request: request, forDecodable: NearestSystemDocument.self)
    }

    static func performSystemCheck(forSystem systemName: String) async throws -> StarSystem {
        var systemName = systemName
        if let shortNameCorrection = shortNamesCapitalisation[systemName.uppercased()] {
            systemName = shortNameCorrection
        }

        let (searchResults, proceduralResult) = await (
            try? performSearch(forSystem: systemName, quickSearch: true),
            try? performProceduralCheck(forSystem: systemName)
        )
        let searchResult = searchResults?.data?.filter({ $0.similarity == 1 }).sorted(by: {
            $0.coords.distance(from: Vector3(0, 0, 0)) < $1.coords.distance(from: Vector3(0, 0, 0))
        }).first
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

        let (landmarkResults, systemData) = try await (
            performLandmarkCheck(forSystem: properName), getSystemData(forId: searchResult.id64)
        )
        starSystem.landmarks = landmarkResults.landmarks ?? []
        starSystem.data = systemData
        return starSystem
    }

    static func getStatistics() async throws -> StatisticsDocument {
        let request = try HTTPClient.Request(systemApiPath: "/api/stats", method: .GET)

        let response = try await httpClient.execute(request: request, expecting: 200)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(
            StatisticsDocument.self,
            from: Data(buffer: response.body!)
        )
    }

    static func fetchLandmarkList() async throws -> [LandmarkListDocument.LandmarkListEntry] {
        let request = try HTTPClient.Request(
            systemApiPath: "/landmark", method: .GET,
            query: [
                "list": "true"
            ])

        return try await httpClient.execute(
            request: request, forDecodable: LandmarkListDocument.self
        ).landmarks
    }

    static func fetchSectorList() async throws -> [StarSector] {
        let request = try HTTPClient.Request(systemApiPath: "/get_ha_regions", method: .GET)

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

            init(name: String, coordinates: Vector3, soi: Double? = nil) {
                self.name = name
                self.coordinates = coordinates
                self.soi = soi
            }

            init(from decoder: Decoder) throws {
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
            var landmarkDistances = mecha.landmarks.map({
                ($0, self.sectordata.coords.distance(from: $0.coordinates))
            })
            landmarkDistances = landmarkDistances.filter({ $0.0.soi == nil || $0.1 < $0.0.soi! })
            landmarkDistances.sort(by: { $0.1 < $1.1 })

            let formatter = NumberFormatter.englishFormatter()
            formatter.usesSignificantDigits = true
            formatter.maximumSignificantDigits = self.sectordata.uncertainty.significandWidth

            return (
                landmarkDistances[0].0, formatter.string(from: landmarkDistances[0].1)!,
                ceil(landmarkDistances[0].1)
            )
        }

        var estimatedSolDistance: (LandmarkListDocument.LandmarkListEntry, String, Double) {
            let distance = self.sectordata.coords.distance(from: Vector3(0, 0, 0))

            let formatter = NumberFormatter.englishFormatter()
            formatter.usesSignificantDigits = true
            formatter.maximumSignificantDigits = self.sectordata.uncertainty.significandWidth

            let landmark = LandmarkListDocument.LandmarkListEntry(
                name: "Sol", coordinates: Vector3(0, 0, 0))
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

            func correctionRepresentation(index: Int) -> String {
                if self.permitRequired {
                    if let permitName = self.permitName {
                        let permitReq = IRCFormat.color(.Orange, "(\(permitName) Permit Required)")
                        return
                            "(\(IRCFormat.bold(index.description))) \"\(self.name)\" \(permitReq)"
                    }
                    let permitReq = IRCFormat.color(.Orange, "(Permit Required)")
                    return "(\(IRCFormat.bold(index.description))) \"\(self.name)\" \(permitReq)"
                }
                return "(\(IRCFormat.bold(index.description))) \"\(self.name)\""
            }

            func rateCorrectionFor(system: String) -> Int? {
                let system = system.lowercased()
                let correctionName = self.name.lowercased()

                let isWithinReasonableEditDistance =
                    (system.levenshtein(correctionName) < 2
                        && correctionName.strippingNonLetters == system.strippingNonLetters)
                let originalIsProceduralSystem = ProceduralSystem.proceduralSystemExpression
                    .matches(system)

                if correctionName.strippingNonAlphanumeric == system.strippingNonAlphanumeric {
                    return 0
                }

                if correctionName == system.dropLast(1) && system.last!.isLetter {
                    return 2
                }

                if system.levenshtein(correctionName) < 2
                    && correctionName.strippingNonLetters == system.strippingNonLetters
                {
                    return 3
                }

                if isWithinReasonableEditDistance && !originalIsProceduralSystem {
                    return 4
                }
                return nil
            }
        }
    }

    struct NearestSystemDocument: Codable {
        let meta: Meta
        let data: NearestSystem?

        struct NearestSystem: Codable {
            let id64: Int64
            let name: String
            let distance: Double
        }

        struct Meta: Codable {
            let name: String?
            let type: String?
        }
    }

    struct NearestPopulatedDocument: Codable {
        let meta: Meta
        let data: [PopulatedSystem]

        func preferableSystems(requireLargePad: Bool = false, requireSpace: Bool = false)
            -> [PopulatedSystem]
        {
            return self.data.filter({ $0.allegiance != .Thargoid }).sorted(by: {
                ($0.preferableStations(requireLargePad: requireLargePad, requireSpace: requireSpace)
                    .first?.hasLargePad == true
                    && $1.preferableStations(
                        requireLargePad: requireLargePad, requireSpace: requireSpace
                    ).first?.hasLargePad != true)
                    && $1.distance / $0.distance < 10
            })
        }

        struct PopulatedSystem: Codable {
            let distance: Double
            let name: String
            let id64: Int64
            let stations: [Station]
            let allegiance: SystemsAPI.Allegiance?

            var hasStationWithLargePad: Bool {
                return self.stations.contains(where: { $0.hasLargePad })
            }

            func preferableStations(requireLargePad: Bool, requireSpace: Bool) -> [Station] {
                let stations = self.stations.filter { (requireLargePad == false || $0.hasLargePad)
                    && (requireSpace == false || $0.type?.isLargeSpaceStation ?? true) && $0.isFunctional }
                let maxDistance = stations.map { $0.distance ?? 0 }.max() ?? maxUsefulDistance
                let weightDistance = maxUsefulDistance / maxDistance
                let weightRanking = minPreferredDistance * weightDistance

                return stations.sorted(by: {
                    $0.score(weightDistance: weightDistance, weightRanking: weightRanking) < $1.score(weightDistance: weightDistance, weightRanking: weightRanking)
                })
            }

            struct Station: Codable {
                static let notableServices = [
                    "Shipyard", "Outfitting", "Refuel", "Repair", "Rearm",
                ]
                let name: String
                let type: StationType?
                let distance: Double?
                let hasMarket: Bool
                let hasShipyard: Bool
                let hasOutfitting: Bool
                let services: [String]
                let stationState: State?

                enum CodingKeys: String, CodingKey {
                    case name
                    case type
                    case distance
                    case hasMarket
                    case hasShipyard
                    case hasOutfitting
                    case services
                    case stationState = "StationState"
                }

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)

                    var name = try container.decode(String.self, forKey: .name)
                    
                    var stationState = try container.decodeIfPresent(
                        State.self, forKey: .stationState)
                    
                    var stationType = try container.decodeIfPresent(StationType.self, forKey: .type)
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
                    self.name = name

                    self.distance = try container.decodeIfPresent(Double.self, forKey: .distance)
                    self.hasMarket = try container.decode(Bool.self, forKey: .hasMarket)
                    self.hasShipyard = try container.decode(Bool.self, forKey: .hasShipyard)
                    self.hasOutfitting = try container.decode(Bool.self, forKey: .hasOutfitting)
                    self.services = try container.decode([String].self, forKey: .services)

                    if stationState == .Construction && stationType == nil {
                        stationType = .SpaceConstructionDepot
                    }
                    if stationType == nil && self.name.hasPrefix("System Colonisation Ship") {
                        stationType = .SystemColonizationShip
                        stationState = .Construction
                    }
                    if stationType == nil {
                        stationType = .Settlement
                    }

                    self.type = stationType
                    self.stationState = stationState
                }

                public enum State: String, Codable {
                    case UnderAttack
                    case Destroyed
                    case Abandoned
                    case Damaged
                    case Construction
                    case UnderRepairs
                }
                
                var isFunctional: Bool {
                    return self.stationState != .Destroyed && self.stationState != .Abandoned && self.stationState != .UnderAttack
                }
                
                var isLimited: Bool {
                    return self.stationState == .Damaged || self.stationState == .UnderRepairs || self.stationState == .Construction
                }
                
                var ranking: UInt {
                    return self.type?.rating ?? 5
                }
                
                func score(weightDistance: Double = 1.0, weightRanking: Double = 0.1) -> Double {
                    let rankingPenalty = Double(self.ranking) + (self.isLimited ? limitedPenalty : 0)
                    return (self.distance ?? 0 * weightDistance) + (rankingPenalty * weightRanking)
                }
                
                enum StationType: String, Codable {
                    case CoriolisStarport = "Coriolis Starport"
                    case OcellusStarport = "Ocellus Starport"
                    case OrbisStarport = "Orbis Starport"
                    case SpaceConstructionDepot = "Space Construction Depot"
                    case SystemColonizationShip = "System Colonization Ship"
                    case Outpost
                    case PlanetaryOutpost = "Planetary Outpost"
                    case PlanetaryPort = "Planetary Port"
                    case AsteroidBase = "Asteroid base"
                    case MegaShip = "Mega ship"
                    case FleetCarrier = "Fleet Carrier"
                    case Settlement = "Odyssey Settlement"
                    case OrbitalConstructionSite = "Orbital Construction Site"
                    case PlanetaryConstructionSite = "Planetary Construction Site"
                    
                    static var brokenDataMapping: [String: String] = [
                        "Coriolis": "Coriolis Starport"
                    ]
                    
                    init (from decoder: Decoder) throws {
                        let container = try decoder.singleValueContainer()
                        var stringValue = try container.decode(String.self)
                        
                        if let remap = StationType.brokenDataMapping[stringValue] {
                            stringValue = remap
                        }
                        
                        if let stationType = StationType(rawValue: stringValue) {
                            self = stationType
                        }
                        throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid station type \(stringValue)"))
                    }

                    static let ratings: [StationType: UInt] = [
                        .CoriolisStarport: 0,
                        .OcellusStarport: 0,
                        .OrbisStarport: 0,
                        .AsteroidBase: 1,
                        .MegaShip: 1,
                        .PlanetaryPort: 2,
                        .PlanetaryOutpost: 3,
                        .Settlement: 3,
                        .SpaceConstructionDepot: 3,
                        .PlanetaryConstructionSite: 4,
                        .OrbitalConstructionSite: 4,
                        .SystemColonizationShip: 5,
                        .FleetCarrier: 5,
                        .Outpost: 6,
                    ]

                    var rating: UInt {
                        return StationType.ratings[self]!
                    }

                    var isLargeSpaceStation: Bool {
                        return [
                            StationType.CoriolisStarport,
                            StationType.OcellusStarport,
                            StationType.OrbisStarport,
                            StationType.AsteroidBase,
                            StationType.MegaShip,
                            StationType.FleetCarrier,
                            StationType.SpaceConstructionDepot,
                            StationType.SystemColonizationShip,
                            StationType.OrbitalConstructionSite,
                        ].contains(self)
                    }

                    var isPlanetary: Bool {
                        return [
                            StationType.PlanetaryPort,
                            StationType.PlanetaryOutpost,
                            StationType.PlanetaryConstructionSite,
                            StationType.Settlement,
                        ].contains(self)
                    }
                }

                var hasLargePad: Bool {
                    return self.type != .Outpost
                }

                var notableServices: [String] {
                    return allServices.filter({ Station.notableServices.contains($0) })
                }

                var allServices: [String] {
                    var services: [String] = self.services.map({ $0.capitalizingFirstLetter() })

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

extension String {
    func capitalizingFirstLetter() -> String {
        guard let first = self.first else { return self }
        return first.uppercased() + self.dropFirst()
    }

    mutating func capitalizeFirstLetter() {
        self = self.capitalizingFirstLetter()
    }
}

struct StarSector {
    let name: String
    let hasSector: Bool
}

extension HTTPClient.Request {
    fileprivate init(systemApiPath: String, method: HTTPMethod, query: [String: String?] = [:])
        throws
    {
        var url = URLComponents(string: "https://systems.api.fuelrats.com")!
        url.path = systemApiPath

        url.queryItems = query.queryItems
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(
            of: "+", with: "%2B")
        try self.init(url: url.url!, method: method)

        self.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
    }
}
