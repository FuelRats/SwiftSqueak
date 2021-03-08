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
    static func performSearch (forSystem systemName: String, quickSearch: Bool = false) -> EventLoopFuture<SearchDocument> {
        var url = URLComponents(string: "https://system.api.fuelrats.com/mecha")!
        url.queryItems = [URLQueryItem(name: "name", value: systemName)]
        if quickSearch {
            url.queryItems?.append(URLQueryItem(name: "fast", value: "true"))
        }
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        let deadline: NIODeadline? = .now() + (quickSearch ? .seconds(5) : .seconds(60))

        var request = try! HTTPClient.Request(url: url.url!, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)

        return httpClient.execute(request: request, forDecodable: SearchDocument.self, deadline: deadline)
    }

    static func performLandmarkCheck (forSystem systemName: String) -> EventLoopFuture<LandmarkDocument> {
        var url = URLComponents(string: "https://system.api.fuelrats.com/landmark")!
        url.queryItems = [URLQueryItem(name: "name", value: systemName)]
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")

        var request = try! HTTPClient.Request(url: url.url!, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)

        return httpClient.execute(request: request, forDecodable: LandmarkDocument.self)
    }
    
    static func getSystemInfo (forSystem system: SystemsAPI.SearchDocument.SearchResult) -> EventLoopFuture<StarSystem> {
        let promise = loop.next().makePromise(of: StarSystem.self)
        self.performLandmarkCheck(forSystem: system.name).whenComplete({ result in
            switch result {
            case .failure(let error):
                promise.fail(error)
                
            case .success(let landmarkDocument):
                var starSystem = StarSystem(
                    name: system.name,
                    searchResult: system,
                    availableCorrections: nil,
                    landmark: landmarkDocument.first,
                    landmarks: landmarkDocument.landmarks ?? [],
                    proceduralCheck: nil
                )
                EDSM.getBodies(forSystem: system.name).and(EDSM.getStations(forSystem: system.name)).whenComplete({ result in
                    switch result {
                    case .failure(_):
                        promise.succeed(starSystem)
                    case .success((let bodies, let stations)):
                        starSystem.bodies = bodies.bodies
                        starSystem.stations = stations.stations
                        promise.succeed(starSystem)
                    }
                })
            }
        })
        return promise.futureResult
    }

    static func performProceduralCheck (forSystem systemName: String) -> EventLoopFuture<ProceduralCheckDocument?> {
        let promise = loop.next().makePromise(of: ProceduralCheckDocument?.self)
        var url = URLComponents(string: "https://system.api.fuelrats.com/procname")!
        url.queryItems = [URLQueryItem(name: "name", value: systemName)]
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")

        var request = try! HTTPClient.Request(url: url.url!, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)

        httpClient.execute(request: request, forDecodable: ProceduralCheckDocument.self).whenComplete({ result in
            switch result {
            case .failure(_):
                promise.succeed(nil)
                
            case .success(let document):
                promise.succeed(document)
            }
        })
        return promise.futureResult
    }

    static func performSystemCheck (forSystem systemName: String, includeEdsm: Bool = true) -> EventLoopFuture<StarSystem> {
        let promise = loop.next().makePromise(of: StarSystem.self)

        performSearch(forSystem: systemName, quickSearch: true)
            .and(performProceduralCheck(forSystem: systemName))
            .whenComplete({ result in
                switch result {
                    case .success(let (searchResults, proceduralResult)):
                        let searchResult = searchResults.data?.first(where: {
                            $0.similarity == 1
                        })
                        let properName = searchResult?.name ?? systemName
                        performLandmarkCheck(forSystem: properName).whenSuccess({ landmarkResults in
                            var starSystem = StarSystem(
                                name: searchResult?.name ?? systemName,
                                searchResult: searchResult,
                                availableCorrections: searchResults.data,
                                landmark: landmarkResults.first,
                                landmarks: landmarkResults.landmarks ?? [],
                                proceduralCheck: proceduralResult
                            )
                            
                            if starSystem.landmark != nil && includeEdsm {
                                EDSM.getBodies(forSystem: properName).and(EDSM.getStations(forSystem: properName)).whenComplete({ result in
                                    switch result {
                                    case .failure(let error):
                                        debug(String(describing: error))
                                        promise.succeed(starSystem)
                                    case .success((let bodies, let stations)):
                                        starSystem.bodies = bodies.bodies
                                        starSystem.stations = stations.stations
                                        promise.succeed(starSystem)
                                    }
                                })
                            } else {
                                promise.succeed(starSystem)
                            }
                        })

                    case .failure(let error):
                        promise.fail(error)
                }

            })

        return promise.futureResult
    }


    static func performStatisticsQuery (
        onComplete: @escaping (StatisticsDocument) -> Void,
        onError: @escaping (Error?) -> Void
    ) {
        let url = URLComponents(string: "https://system.api.fuelrats.com/api/stats")!
        var request = try! HTTPClient.Request(url: url.url!, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)

        httpClient.execute(request: request).whenCompleteExpecting(status: 200) { result in
            switch result {
                case .success(let response):
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase

                    do {
                        let result = try decoder.decode(
                            StatisticsDocument.self,
                            from: Data(buffer: response.body!)
                        )
                        onComplete(result)
                    } catch let error {
                        debug(String(describing: error))
                        onError(error)
                    }
                case .failure(let restError):
                    onError(restError)
            }
        }
    }
    
    static func fetchLandmarkList () -> EventLoopFuture<[LandmarkListDocument.LandmarkListEntry]> {
        let promise = loop.next().makePromise(of: [LandmarkListDocument.LandmarkListEntry].self)
        
        let url = URLComponents(string: "https://systems.api.fuelrats.com/landmark?list")!
        var request = try! HTTPClient.Request(url: url.url!, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)

        httpClient.execute(request: request, forDecodable: LandmarkListDocument.self).whenComplete({ result in
            switch result {
                case .failure(_):
                    let fallbackLandmark = LandmarkListDocument.LandmarkListEntry(name: "Sol", coordinates: Vector3(0, 0, 0))
                    promise.succeed([fallbackLandmark])
                    
                case .success(let document):
                    promise.succeed(document.landmarks)
            }
        })
        return promise.futureResult
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


}
