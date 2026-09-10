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

import Foundation

/// Tier-1 tools built directly on MechaSqueak's existing reusable API functions
/// (`SystemsAPI`, `Fact`). Read-only; each returns compact JSON.
enum DataTools {
    static let searchResultLimit = 5
    static let nearestSystemLimit = 3

    static func all() -> [AITool] {
        [searchSystem, systemInfo, nearestStation, factLookup]
    }

    // MARK: - search_system

    static let searchSystem = AITool(
        name: "search_system",
        description: """
        Search the Fuel Rats systems database for star systems matching a name (handles typos and \
        partial names). Use to resolve or disambiguate a system name before looking it up.
        """,
        inputSchema: .objectSchema(
            properties: [("query", .stringSchema("The system name to search for"))],
            required: ["query"])
    ) { input, _ in
        guard let query = input["query"]?.stringValue, query.isEmpty == false else {
            return ToolOutput.error("missing 'query'")
        }
        do {
            let document = try await SystemsAPI.performSearch(forSystem: query)
            let results = (document.data ?? []).prefix(searchResultLimit).map { result in
                SystemMatch(
                    name: result.name,
                    permitRequired: result.permitRequired,
                    permitName: result.permitName,
                    similarity: result.similarity)
            }
            if results.isEmpty {
                return ToolOutput.error("no systems found for '\(query)'")
            }
            return ToolOutput.json(SearchSummary(query: query, matches: Array(results)))
        } catch {
            aiLogger.error("[tool:search_system] \(error)")
            return ToolOutput.error("system search failed")
        }
    }

    // MARK: - system_info

    static let systemInfo = AITool(
        name: "system_info",
        description: """
        Look up a single star system by (corrected) name: whether it exists, whether it requires a \
        permit, and its nearest known landmark and distance. Use for questions about a specific system.
        """,
        inputSchema: .objectSchema(
            properties: [("system", .stringSchema("The star system name"))],
            required: ["system"])
    ) { input, _ in
        guard let name = input["system"]?.stringValue, name.isEmpty == false else {
            return ToolOutput.error("missing 'system'")
        }
        do {
            let system = try await SystemsAPI.performSystemCheck(forSystem: name)
            return ToolOutput.json(summarize(system))
        } catch {
            aiLogger.error("[tool:system_info] \(error)")
            return ToolOutput.error("system lookup failed")
        }
    }

    static func summarize(_ system: StarSystem) -> SystemInfoSummary {
        SystemInfoSummary(
            name: system.name,
            exists: system.searchResult != nil,
            permitRequired: system.permit != nil,
            permitName: system.permit?.name,
            nearestLandmark: system.landmark.map {
                Landmark(name: $0.name, distanceLy: $0.distance)
            })
    }

    // MARK: - nearest_station

    static let nearestStation = AITool(
        name: "nearest_station",
        description: """
        Find the nearest populated systems with stations to a given star system, including station \
        names and distances. Use for "nearest station/refuel/repair" style questions.
        """,
        inputSchema: .objectSchema(
            properties: [("system", .stringSchema("The star system to search near"))],
            required: ["system"])
    ) { input, _ in
        guard let name = input["system"]?.stringValue, name.isEmpty == false else {
            return ToolOutput.error("missing 'system'")
        }
        do {
            guard let document = try await SystemsAPI.getNearestStations(
                forSystem: name, limit: nearestSystemLimit) else {
                return ToolOutput.error("no populated systems found near '\(name)'")
            }
            let systems = document.data.prefix(nearestSystemLimit).map { populated in
                NearestSystemSummary(
                    system: populated.name,
                    distanceLy: populated.distance,
                    station: populated.stations.first.map { station in
                        StationSummary(
                            name: station.name,
                            type: station.type.map { "\($0)" },
                            distanceLs: station.distance)
                    })
            }
            return ToolOutput.json(NearestSummary(near: name, systems: Array(systems)))
        } catch {
            aiLogger.error("[tool:nearest_station] \(error)")
            return ToolOutput.error("nearest-station lookup failed")
        }
    }

    // MARK: - fact_lookup

    static let factLookup = AITool(
        name: "fact_lookup",
        description: """
        Search MechaSqueak's fact database — canned answers dispatchers use for common questions \
        (platform help, procedures, references). Returns matching facts and their text.
        """,
        inputSchema: .objectSchema(
            properties: [("name", .stringSchema("The fact name or keywords to search for"))],
            required: ["name"])
    ) { input, context in
        guard let query = input["name"]?.stringValue, query.isEmpty == false else {
            return ToolOutput.error("missing 'name'")
        }
        do {
            let grouped = try await Fact.search(query, locale: context.locale)
            let facts = grouped.prefix(searchResultLimit).compactMap { fact -> FactSummary? in
                let message = fact.messages[context.locale.short]?.message
                    ?? fact.messages.values.first?.message
                guard let message else { return nil }
                return FactSummary(name: fact.canonicalName, message: ToolOutput.truncate(message))
            }
            if facts.isEmpty {
                return ToolOutput.error("no facts found for '\(query)'")
            }
            return ToolOutput.json(FactSummaryList(query: query, facts: Array(facts)))
        } catch {
            aiLogger.error("[tool:fact_lookup] \(error)")
            return ToolOutput.error("fact lookup failed")
        }
    }

    // MARK: - Result summaries

    struct SearchSummary: Encodable {
        let query: String
        let matches: [SystemMatch]
    }

    struct SystemMatch: Encodable {
        let name: String
        let permitRequired: Bool
        let permitName: String?
        let similarity: Double?
    }

    struct SystemInfoSummary: Encodable {
        let name: String
        let exists: Bool
        let permitRequired: Bool
        let permitName: String?
        let nearestLandmark: Landmark?
    }

    struct Landmark: Encodable {
        let name: String
        let distanceLy: Double
    }

    struct NearestSummary: Encodable {
        let near: String
        let systems: [NearestSystemSummary]
    }

    struct NearestSystemSummary: Encodable {
        let system: String
        let distanceLy: Double
        let station: StationSummary?
    }

    struct StationSummary: Encodable {
        let name: String
        let type: String?
        let distanceLs: Double?
    }

    struct FactSummaryList: Encodable {
        let query: String
        let facts: [FactSummary]
    }

    struct FactSummary: Encodable {
        let name: String
        let message: String
    }
}
