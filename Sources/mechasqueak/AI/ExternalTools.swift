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

/// External Elite Dangerous data tools (EDSM + Spansh). Keyless; sends a descriptive User-Agent
/// and caches responses briefly. Fills gaps the Fuel Rats systems API doesn't cover — notably
/// authoritative primary-star scoopability and permit status, full-system body listings, and
/// neutron-highway route plotting.
enum ExternalTools {
    static let cache = ResponseCache()
    static let edsmBase = "https://www.edsm.net"
    static let spanshBase = "https://spansh.co.uk"
    static let nearestRadius = 50
    static let nearestSystemLimit = 5
    static let routeWaypointLimit = 10
    static let routeDefaultEfficiency = 60
    static let routePollAttempts = 6
    static let routePollInterval: UInt64 = 2_000_000_000

    static func all() -> [AITool] {
        [edsmSystem, edsmNearest, scoopableStar, routePlot]
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

    // MARK: - scoopable_star

    static let scoopableStar = AITool(
        name: "scoopable_star",
        description: """
        List the stars in a system from EDSM and whether each is fuel-scoopable (KGB FOAM), with \
        the nearest scoopable star's arrival distance. Use for "is there a fuel star in <system>" \
        or "where can a stranded commander refuel in <system>" questions.
        """,
        inputSchema: .objectSchema(
            properties: [("system", .stringSchema("The star system name"))],
            required: ["system"])
    ) { input, _ in
        guard let name = input["system"]?.stringValue, name.isEmpty == false else {
            return ToolOutput.error("missing 'system'")
        }
        let url = edsmURL(path: "/api-system-v1/bodies", query: ["systemName": name])
        do {
            let data = try await fetch(url)
            guard let summary = parseBodies(data) else {
                return ToolOutput.error("no body data for '\(name)' in EDSM")
            }
            return ToolOutput.json(summary)
        } catch {
            aiLogger.error("[tool:scoopable_star] \(error)")
            return ToolOutput.error("EDSM body lookup failed")
        }
    }

    /// Parses an EDSM `/bodies` response down to its stars and their scoopability. EDSM returns
    /// `{"bodies": []}` (or `[]`) for an unknown/unmapped system, which maps to "no data" (nil).
    static func parseBodies(_ data: Data) -> ScoopableSummary? {
        guard let document = try? edsmDecoder.decode(EDSMBodiesDocument.self, from: data),
              let name = document.name else {
            return nil
        }
        let stars = document.bodies.filter { $0.type == "Star" }.map {
            StarSummary(
                name: $0.name,
                subType: $0.subType,
                scoopable: $0.isScoopable ?? false,
                mainStar: $0.isMainStar ?? false,
                distanceLs: $0.distanceToArrival)
        }
        if stars.isEmpty {
            return nil
        }
        let nearestScoopable = stars
            .filter { $0.scoopable }
            .min { ($0.distanceLs ?? .greatestFiniteMagnitude) < ($1.distanceLs ?? .greatestFiniteMagnitude) }
        return ScoopableSummary(
            system: name,
            hasScoopableStar: stars.contains { $0.scoopable },
            nearestScoopableLs: nearestScoopable?.distanceLs,
            stars: stars)
    }

    // MARK: - route_plot

    static let routePlot = AITool(
        name: "route_plot",
        description: """
        Plot a neutron-highway jump route between two star systems via Spansh, given a ship's \
        jump range. Returns the total number of jumps, straight-line distance, and the neutron \
        boost waypoints. Use for "how many jumps from A to B" or long-distance travel questions. \
        `efficiency` (0-100, default \(routeDefaultEfficiency)) trades a longer path for more \
        neutron boosts.
        """,
        inputSchema: .objectSchema(
            properties: [
                ("from", .stringSchema("The origin star system")),
                ("to", .stringSchema("The destination star system")),
                ("jump_range", .numberSchema("The ship's laden jump range in light years")),
                ("efficiency", .integerSchema(
                    "Optional 0-100; higher favours more neutron boosts over a shorter path"))
            ],
            required: ["from", "to", "jump_range"])
    ) { input, _ in
        guard let from = input["from"]?.stringValue, from.isEmpty == false else {
            return ToolOutput.error("missing 'from'")
        }
        guard let to = input["to"]?.stringValue, to.isEmpty == false else {
            return ToolOutput.error("missing 'to'")
        }
        guard let range = input["jump_range"]?.doubleValue, range > 0 else {
            return ToolOutput.error("missing or invalid 'jump_range'")
        }
        let efficiency = input["efficiency"]?.intValue ?? routeDefaultEfficiency
        do {
            guard let summary = try await spanshRoute(
                from: from, to: to, range: range, efficiency: efficiency) else {
                return ToolOutput.error("could not plot a route from '\(from)' to '\(to)'")
            }
            return ToolOutput.json(summary)
        } catch {
            aiLogger.error("[tool:route_plot] \(error)")
            return ToolOutput.error("route plotting failed")
        }
    }

    /// Submits a Spansh neutron-route job, then polls for the result. Spansh is asynchronous:
    /// `POST /api/route` returns a job id, and `GET /api/results/<id>` returns `{"status":"queued"}`
    /// until the route is ready, at which point it carries a `result` object.
    static func spanshRoute(
        from: String, to: String, range: Double, efficiency: Int
    ) async throws -> RouteSummary? {
        let body = formEncode([
            "efficiency": String(max(0, min(100, efficiency))),
            "range": String(range),
            "from": from,
            "to": to
        ])
        var request = try HTTPClient.Request(url: spanshBase + "/api/route", method: .POST)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Content-Type", value: "application/x-www-form-urlencoded")
        request.headers.add(name: "Accept", value: "application/json")
        request.body = .string(body)

        let submit = try await httpClient.execute(
            request: request, deadline: .now() + .seconds(15)).get()
        guard (200...202).contains(submit.status.code),
              let submitData = submit.body.map({ Data(buffer: $0) }),
              let job = try? edsmDecoder.decode(SpanshJob.self, from: submitData), let id = job.job else {
            return nil
        }

        let resultURL = spanshBase + "/api/results/" + id
        for attempt in 0..<routePollAttempts {
            if attempt > 0 {
                try await Task.sleep(nanoseconds: routePollInterval)
            }
            let poll = try await httpClient.execute(
                request: HTTPClient.Request(url: resultURL, method: .GET), deadline: .now() + .seconds(15)
            ).get()
            guard let data = poll.body.map({ Data(buffer: $0) }) else { continue }
            if let summary = parseRoute(data) {
                return summary
            }
        }
        return nil
    }

    /// Parses a Spansh `/results` payload. Returns nil while the job is still queued (no `result`).
    static func parseRoute(_ data: Data) -> RouteSummary? {
        guard let document = try? edsmDecoder.decode(SpanshResult.self, from: data),
              let result = document.result else {
            return nil
        }
        let boosts = result.systemJumps.filter { $0.neutronStar == true }.map { $0.system }
        return RouteSummary(
            from: result.sourceSystem,
            to: result.destinationSystem,
            totalJumps: result.totalJumps,
            distanceLy: result.distance,
            neutronBoosts: boosts.count,
            waypoints: Array(boosts.prefix(routeWaypointLimit)))
    }

    /// Percent-encodes key/value pairs for an `application/x-www-form-urlencoded` body.
    static func formEncode(_ pairs: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return pairs.map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(encoded)"
        }.joined(separator: "&")
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

    struct EDSMBodiesDocument: Decodable {
        let name: String?
        let bodies: [Body]

        struct Body: Decodable {
            let name: String
            let type: String?
            let subType: String?
            let isMainStar: Bool?
            let isScoopable: Bool?
            let distanceToArrival: Double?
        }
    }

    // MARK: - Spansh wire types

    struct SpanshJob: Decodable {
        let job: String?
    }

    struct SpanshResult: Decodable {
        let result: Route?

        struct Route: Decodable {
            let sourceSystem: String
            let destinationSystem: String
            let distance: Double
            let totalJumps: Int
            let systemJumps: [Jump]

            enum CodingKeys: String, CodingKey {
                case sourceSystem = "source_system"
                case destinationSystem = "destination_system"
                case distance
                case totalJumps = "total_jumps"
                case systemJumps = "system_jumps"
            }

            struct Jump: Decodable {
                let system: String
                let neutronStar: Bool?

                enum CodingKeys: String, CodingKey {
                    case system
                    case neutronStar = "neutron_star"
                }
            }
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

    struct ScoopableSummary: Encodable {
        let system: String
        let hasScoopableStar: Bool
        let nearestScoopableLs: Double?
        let stars: [StarSummary]
    }

    struct StarSummary: Encodable {
        let name: String
        let subType: String?
        let scoopable: Bool
        let mainStar: Bool
        let distanceLs: Double?
    }

    struct RouteSummary: Encodable {
        let from: String
        let to: String
        let totalJumps: Int
        let distanceLy: Double
        let neutronBoosts: Int
        let waypoints: [String]
    }
}
