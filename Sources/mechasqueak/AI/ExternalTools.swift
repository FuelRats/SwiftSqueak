/*
 Copyright 2026 The Fuel Rats Mischief

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
import NIO

/// A tiny TTL cache for keyless external API responses, keyed by request URL.
actor ResponseCache {
    private var store: [String: (expires: Date, value: Data)] = [:]
    private let ttl: TimeInterval

    init(ttl: TimeInterval = 300) {
        self.ttl = ttl
    }

    func value(for key: String) -> Data? {
        guard let entry = store[key] else { return nil }
        if entry.expires < Date() {
            store[key] = nil
            return nil
        }
        return entry.value
    }

    func store(_ value: Data, for key: String) {
        store[key] = (Date().addingTimeInterval(ttl), value)
    }
}

/// External Elite Dangerous data tools (EDSM). Keyless; sends a descriptive User-Agent and
/// caches responses briefly. Fills gaps the Fuel Rats systems API doesn't cover — notably
/// authoritative primary-star scoopability and permit status.
///
/// Spansh route/search tools are intentionally not implemented yet: the Spansh route and
/// search endpoint details were flagged unverified during planning and need a live spike
/// before shipping (tracked as an open item), rather than guessing the wire contract here.
enum ExternalTools {
    static let cache = ResponseCache()
    static let edsmBase = "https://www.edsm.net"
    static let nearestRadius = 50
    static let nearestSystemLimit = 5

    static func all() -> [AITool] {
        [edsmSystem, edsmNearest]
    }

    // MARK: - HTTP

    /// GETs a URL as JSON with a descriptive User-Agent, using the short-lived cache.
    static func fetch(_ url: String) async throws -> Data {
        if let cached = await cache.value(for: url) {
            return cached
        }
        var request = try HTTPClient.Request(url: URL(string: url)!, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Accept", value: "application/json")
        let response = try await httpClient.execute(
            request: request, deadline: .now() + .seconds(15)).get()
        guard (200...202).contains(response.status.code) else {
            throw LLMError.badRequest(status: response.status.code, body: "")
        }
        let data = response.body.map { Data(buffer: $0) } ?? Data()
        await cache.store(data, for: url)
        return data
    }

    static func edsmURL(path: String, query: [String: String]) -> String {
        var components = URLComponents(string: edsmBase + path)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!.absoluteString
    }

    // MARK: - edsm_system

    static let edsmSystem = AITool(
        name: "edsm_system",
        description: """
        Look up authoritative Elite Dangerous data for a star system from EDSM: whether it needs a \
        permit, and its primary star's type and whether it is fuel-scoopable (KGB FOAM). Use for \
        questions about a specific system's star or permit status.
        """,
        inputSchema: .objectSchema(
            properties: [("system", .stringSchema("The star system name"))],
            required: ["system"])
    ) { input, _ in
        guard let name = input["system"]?.stringValue, name.isEmpty == false else {
            return ToolOutput.error("missing 'system'")
        }
        let url = edsmURL(
            path: "/en/api-v1/system",
            query: [
                "systemName": name,
                "showPrimaryStar": "1",
                "showPermit": "1",
                "showCoordinates": "1"
            ])
        do {
            let data = try await fetch(url)
            guard let summary = parseSystem(data) else {
                return ToolOutput.error("system '\(name)' not found in EDSM")
            }
            return ToolOutput.json(summary)
        } catch {
            aiLogger.error("[tool:edsm_system] \(error)")
            return ToolOutput.error("EDSM lookup failed")
        }
    }

    /// Parses an EDSM `/system` response. EDSM returns `[]` for an unknown system, so a
    /// non-object / empty payload maps to "not found" (nil).
    static func parseSystem(_ data: Data) -> EDSMSystemSummary? {
        guard let system = try? edsmDecoder.decode(EDSMSystem.self, from: data),
              system.name?.isEmpty == false, let name = system.name else {
            return nil
        }
        return EDSMSystemSummary(
            name: name,
            permitRequired: system.requirePermit ?? false,
            permitName: system.permitName,
            primaryStar: system.primaryStar.flatMap { star in
                star.type == nil && star.isScoopable == nil
                    ? nil
                    : EDSMStarSummary(type: star.type, scoopable: star.isScoopable)
            })
    }

    // MARK: - edsm_nearest

    static let edsmNearest = AITool(
        name: "edsm_nearest",
        description: """
        Find the nearest known star systems to a given system via EDSM (within \(nearestRadius) ly), \
        and list stations in the closest one. Use as a fallback for "nearest system/station" questions \
        when the Fuel Rats data is insufficient.
        """,
        inputSchema: .objectSchema(
            properties: [("system", .stringSchema("The star system to search near"))],
            required: ["system"])
    ) { input, _ in
        guard let name = input["system"]?.stringValue, name.isEmpty == false else {
            return ToolOutput.error("missing 'system'")
        }
        let sphereURL = edsmURL(
            path: "/api-v1/sphere-systems",
            query: [
                "systemName": name,
                "radius": String(nearestRadius),
                "minRadius": "1"
            ])
        do {
            let sphereData = try await fetch(sphereURL)
            let nearest = parseSphereSystems(sphereData, limit: nearestSystemLimit)
            if nearest.isEmpty {
                return ToolOutput.error("no systems found near '\(name)'")
            }
            // List stations for the single closest neighbour.
            var stations: [EDSMStationSummary] = []
            if let closest = nearest.first {
                let stationURL = edsmURL(
                    path: "/api-system-v1/stations", query: ["systemName": closest.name])
                if let stationData = try? await fetch(stationURL) {
                    stations = parseStations(stationData)
                }
            }
            return ToolOutput.json(EDSMNearestSummary(near: name, systems: nearest, stations: stations))
        } catch {
            aiLogger.error("[tool:edsm_nearest] \(error)")
            return ToolOutput.error("EDSM nearest-system lookup failed")
        }
    }

    static func parseSphereSystems(_ data: Data, limit: Int) -> [EDSMNeighbour] {
        guard let systems = try? edsmDecoder.decode([EDSMSphereSystem].self, from: data) else {
            return []
        }
        return systems
            .sorted { ($0.distance ?? .greatestFiniteMagnitude) < ($1.distance ?? .greatestFiniteMagnitude) }
            .prefix(limit)
            .map { EDSMNeighbour(name: $0.name, distanceLy: $0.distance ?? 0) }
    }

    static func parseStations(_ data: Data) -> [EDSMStationSummary] {
        guard let document = try? edsmDecoder.decode(EDSMStationsDocument.self, from: data) else {
            return []
        }
        return document.stations.prefix(nearestSystemLimit).map {
            EDSMStationSummary(name: $0.name, type: $0.type, distanceLs: $0.distanceToArrival)
        }
    }

    static let edsmDecoder = JSONDecoder()

    // MARK: - EDSM wire types

    struct EDSMSystem: Decodable {
        let name: String?
        let requirePermit: Bool?
        let permitName: String?
        let primaryStar: PrimaryStar?

        struct PrimaryStar: Decodable {
            let type: String?
            let name: String?
            let isScoopable: Bool?
        }
    }

    struct EDSMSphereSystem: Decodable {
        let name: String
        let distance: Double?
    }

    struct EDSMStationsDocument: Decodable {
        let name: String?
        let stations: [Station]

        struct Station: Decodable {
            let name: String
            let type: String?
            let distanceToArrival: Double?
        }
    }

    // MARK: - Result summaries

    struct EDSMSystemSummary: Encodable {
        let name: String
        let permitRequired: Bool
        let permitName: String?
        let primaryStar: EDSMStarSummary?
    }

    struct EDSMStarSummary: Encodable {
        let type: String?
        let scoopable: Bool?
    }

    struct EDSMNearestSummary: Encodable {
        let near: String
        let systems: [EDSMNeighbour]
        let stations: [EDSMStationSummary]
    }

    struct EDSMNeighbour: Encodable {
        let name: String
        let distanceLy: Double
    }

    struct EDSMStationSummary: Encodable {
        let name: String
        let type: String?
        let distanceLs: Double?
    }
}
