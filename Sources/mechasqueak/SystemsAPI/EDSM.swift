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
import NIO
import AsyncHTTPClient
import IRCKit

class EDSM {
    static let mainSequence: [Character: String] = [
        "O": "Blue-white star",
        "B": "Blue star",
        "A": "White star",
        "F": "Yellow-white star",
        "G": "Yellow dwarf",
        "K": "Orange dwarf",
        "M": "Red dwarf"
    ]
    
    static func getBodies (forSystem systemName: String) -> EventLoopFuture<BodiesResult> {
        var url = URLComponents(string: "https://www.edsm.net/api-system-v1/bodies")!
        url.queryItems = [URLQueryItem(name: "systemName", value: systemName)]

        var request = try! HTTPClient.Request(url: url.url!, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(edsmDateFormatter)

        return httpClient.execute(request: request, forDecodable: BodiesResult.self, withDecoder: decoder)
    }
    
    static func getStations (forSystem systemName: String) -> EventLoopFuture<StationsResult> {
        var url = URLComponents(string: "https://www.edsm.net/api-system-v1/stations")!
        url.queryItems = [URLQueryItem(name: "systemName", value: systemName)]

        var request = try! HTTPClient.Request(url: url.url!, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(edsmDateFormatter)

        return httpClient.execute(request: request, forDecodable: StationsResult.self, withDecoder: decoder)
    }
    
    static let edsmDateFormatter: DateFormatter = {
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
      formatter.calendar = Calendar(identifier: .iso8601)
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.locale = Locale(identifier: "en_US_POSIX")
      return formatter
    }()
    
    struct BodiesResult: Codable {
        let id: Int
        let id64: Int64
        let name: String
        let url: URL
        let bodyCount: Int
        let bodies: [Body]
    }
    
    struct StationsResult: Codable {
        let id: Int
        let id64: Int64
        let name: String
        let url: URL
        let stations: [Station]
    }
    
    struct Body: Codable {
        let id: Int
        let id64: Int64
        let bodyId: Int
        let name: String
        let discovery: Discovery?
        let type: CelestialBodyType
        let subType: String
        let distanceToArrival: Int64
        let isMainStar: Bool?
        let isScoopable: Bool?
        let age: Int?
        let spectralClass: String?
        let luminosity: String?
        let absoluteMagnitude: Double?
        let solarMasses: Double?
        let solarRadius: Double?
        let isLandable: Bool?
        let gravity: Double?
        let earthMasses: Double?
        let radius: Double?
        let surfaceTemperature: Int
        let surfacePressure: Double?
        let volcanismType: String?
        let atmosphereType: String?
        let atmosphereComposition: [String: Double]?
        let solidComposition: [String: Double]?
        let terraformingState: String?
        let orbitalPeriod: Double?
        let semiMajorAxis: Double?
        let orbitalEccentricity: Double?
        let orbitalInclination: Double?
        let argOfPeriapsis: Double?
        let rotationalPeriod: Double?
        let rotationalPeriodTidallyLocked: Bool
        let axialTilt: Double?
        let materials: [String: Double]?
        let updateTime: Date
        
        struct Discovery: Codable {
            let commander: String
            let date: Date
        }
        
        enum CelestialBodyType: String, Codable {
            case Planet
            case Star
        }
        
        var isMainSequence: Bool {
            guard let spectralClass = self.spectralClass else {
                return false
            }
            return EDSM.mainSequence.keys.contains(where: { spectralClass.hasPrefix(String($0)) })
        }
        
        var starDescription: String? {
            return self.isMainStar ?? false ? bodyType : nil
        }
        
        var bodyDescription: String? {
            if self.isMainStar == true {
                return bodyType
            }
            let distance = Double(self.distanceToArrival).eliteDistance
            var description = "\(bodyType) ~\(distance) from main star"
            if self.orbitalEccentricity ?? 1 < 0.6 || self.orbitalEccentricity ?? 1 > 1.5 {
                description += " (Eccentric orbit)"
            }
            return description
        }
        
        var bodyType: String {
            guard self.type == .Star, let spectralClass = self.spectralClass else {
                return subType
            }
            if self.isMainSequence {
                let name = EDSM.mainSequence[spectralClass.first!]!
                return "\(spectralClass) \(name)"
            }
            let subType = self.subType
            if let firstIndex = subType.firstIndex(of: "("), let end = subType.firstIndex(of: ")") {
                let start = subType.index(after: firstIndex)
                return "\(spectralClass) \(subType[start..<end])"
            }
            return "\(spectralClass) \(subType)"
        }
    }
    
    struct Station: Codable {
        let id: Int
        let marketId: Int
        let type: String
        let name: String
        let distanceToArrival: Double
        let allegience: String?
        let government: String?
        let economy: String?
        let secondEconomy: String?
        let haveMarket: Bool
        let haveShipyard: Bool
        let haveOutfitting: Bool
        let otherServices: [String]
        let updateTime: StationUpdateTimes
        
        struct StationUpdateTimes: Codable {
            let information: Date?
            let market: Date?
            let shipyard: Date?
            let outfitting: Date?
        }
        
        var services: [String] {
            var services: [String] = []
            if self.otherServices.contains("Refuel") {
                services.append("Refuel")
            }
            
            if self.otherServices.contains("Repair") {
                services.append("Repair")
            }
            
            if self.otherServices.contains("Restock") {
                services.append("Restock")
            }
            
            if self.haveShipyard {
                services.append("Shipyard")
            }
            
            if self.haveOutfitting {
                services.append("Outfitting")
            }
            
            if self.haveMarket {
                services.append("Market")
            }
            return services
        }
    }
}
