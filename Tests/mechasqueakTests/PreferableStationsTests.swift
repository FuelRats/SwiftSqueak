import XCTest

@testable import mechasqueak

final class PreferableStationsTests: XCTestCase {
    private typealias PopulatedSystem = SystemsAPI.NearestPopulatedDocument.PopulatedSystem

    private func station(
        _ name: String, type: String, distance: Double, services: [String], state: String? = nil
    ) -> String {
        """
        {"name": "\(name)", "type": "\(type)", "distance": \(distance),
         "hasMarket": true, "hasShipyard": false, "hasOutfitting": false,
         "services": [\(services.map { "\"\($0)\"" }.joined(separator: ","))],
         "StationState": \(state.map { "\"\($0)\"" } ?? "null")}
        """
    }

    private func system() throws -> PopulatedSystem {
        let stations = [
            station("Obsidian Orbital", type: "Coriolis Starport", distance: 3200, services: ["refuel", "repair"]),
            station("Kwolek Terminal", type: "Outpost", distance: 120, services: ["Refuel"]),
            station("Dalton Port", type: "Planetary Port", distance: 900, services: ["refuel"]),
            station("K7Q-1HT", type: "Fleet Carrier", distance: 50, services: ["refuel"]),
            station("Gernhardt Hub", type: "Ocellus Starport", distance: 400, services: ["refuel"], state: "Abandoned"),
            station("Maury Dock", type: "Orbis Starport", distance: 700, services: ["repair", "rearm"])
        ]
        let json = """
        {"distance": 12.4, "name": "Pleione", "id64": 2789153444971, "allegiance": null,
         "stations": [\(stations.joined(separator: ","))]}
        """
        return try JSONDecoder().decode(PopulatedSystem.self, from: Data(json.utf8))
    }

    private func names(
        _ system: PopulatedSystem, largePad: Bool = false, space: Bool = false, legacy: Bool = false
    ) -> Set<String> {
        Set(system.preferableStations(
            requireLargePad: largePad, requireSpace: space, legacyStations: legacy).map(\.name))
    }

    func testExcludesNonFunctionalAndNonRefuelStationsRegardlessOfFlags() throws {
        // Refuel matching is case-insensitive ("Refuel" and "refuel" both count).
        XCTAssertEqual(
            names(try system()),
            ["Obsidian Orbital", "Kwolek Terminal", "Dalton Port", "K7Q-1HT"])
    }

    func testRequireLargePadDropsOutposts() throws {
        XCTAssertEqual(
            names(try system(), largePad: true), ["Obsidian Orbital", "Dalton Port", "K7Q-1HT"])
    }

    func testRequireSpaceDropsPlanetaryStations() throws {
        XCTAssertEqual(
            names(try system(), space: true), ["Obsidian Orbital", "Kwolek Terminal", "K7Q-1HT"])
    }

    func testLegacyDropsPlayerStations() throws {
        XCTAssertEqual(
            names(try system(), legacy: true), ["Obsidian Orbital", "Kwolek Terminal", "Dalton Port"])
    }
}
