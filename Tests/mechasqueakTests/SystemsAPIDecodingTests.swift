import AsyncHTTPClient
import XCTest

@testable import mechasqueak

final class SystemsAPIDecodingTests: XCTestCase {
    // Fixture shaped on the live /api/systems/<id64>?include=stars,planets,stations payload
    // for Nanabozho, whose fleet-carrier stations ($economy_Carrier;) failed decoding and made
    // the whole system lookup report the system as not found.
    private func stationJSON(
        id: String, name: String, type: String?, economy: String,
        allegiance: String?, government: String, state: String?
    ) -> String {
        """
        {"type": "stations", "id": "\(id)", "attributes": {
          "distanceToArrival": 2269.5, "systemName": "Nanabozho",
          "economy": "\(economy)", "type": \(type.map { "\"\($0)\"" } ?? "null"),
          "haveMarket": true, "allegiance": \(allegiance.map { "\"\($0)\"" } ?? "null"),
          "name": "\(name)", "stationState": \(state.map { "\"\($0)\"" } ?? "null"),
          "marketId": null, "haveShipyard": false,
          "government": "\(government)", "haveOutfitting": false,
          "otherServices": ["dock", "refuel", "repair"]},
         "links": {"self": "http://systems.api.fuelrats.com/api/stations/\(id)"},
         "relationships": {}}
        """
    }

    private func document(stations: [String]) -> Data {
        Data("""
        {"data": {"type": "systems", "id": "2832698675930",
          "attributes": {"systemAllegiance": null,
            "coords": {"x": 22.9375, "y": -35.75, "z": 24.15625}, "name": "Nanabozho"},
          "links": {"self": "http://systems.api.fuelrats.com/api/systems/2832698675930"},
          "relationships": {}},
         "included": [\(stations.joined(separator: ","))],
         "meta": {}, "links": {"self": "http://systems.api.fuelrats.com/api/systems/2832698675930"}}
        """.utf8)
    }

    private func decode(_ data: Data) throws -> SystemGetDocument {
        try HTTPClient.defaultJsonDecoder.decode(SystemGetDocument.self, from: data)
    }

    func testCarrierEconomyStationsDecode() throws {
        // The live Nanabozho failure: rescue ships and megaships report $economy_Carrier;.
        let doc = try decode(document(stations: [
            stationJSON(
                id: "128977963", name: "Rescue Ship", type: nil, economy: "$economy_Carrier;",
                allegiance: nil, government: "$government_Corporate;", state: nil),
            stationJSON(
                id: "3858556416", name: "Biobaku Control", type: nil, economy: "$economy_Military;",
                allegiance: "Alliance", government: "$government_Democracy;", state: nil)
        ]))

        let stations = doc.body.includes?[SystemsAPI.Station.self] ?? []
        XCTAssertEqual(stations.count, 2)
        XCTAssertEqual(stations[0].attributes.economy.value, .Carrier)
        XCTAssertEqual(stations[1].attributes.economy.value, .Military)
        XCTAssertEqual(stations[1].attributes.allegiance.value, .Alliance)
    }

    func testUnknownFutureValuesDecodeLeniently() throws {
        // Values Frontier may add later must degrade to unknown/nil, never fail the document.
        let doc = try decode(document(stations: [
            stationJSON(
                id: "9000000001", name: "Futuristic Depot", type: "FloatyMcFloatBase",
                economy: "$economy_SpaceMining;", allegiance: "Yarrr",
                government: "$government_Technocracy;", state: "Exploding")
        ]))

        let stations = doc.body.includes?[SystemsAPI.Station.self] ?? []
        let attributes = try XCTUnwrap(stations.first?.attributes)
        XCTAssertEqual(attributes.economy.value, .unknown)
        XCTAssertEqual(attributes.allegiance.value, .Unknown)
        XCTAssertEqual(attributes.government.value, .unknown)
        // Unknown station type falls back through the nil-type classification chain.
        XCTAssertEqual(attributes.type.value, .Settlement)
        XCTAssertNil(attributes.stationState?.value ?? nil)
    }

    func testPlainEconomyNamesStillDecode() throws {
        // The API also sends unwrapped names (e.g. "High Tech") for some stations.
        let doc = try decode(document(stations: [
            stationJSON(
                id: "529", name: "George Lucas", type: "Coriolis", economy: "High Tech",
                allegiance: "Alliance", government: "Cooperative", state: nil)
        ]))
        let station = try XCTUnwrap(doc.body.includes?[SystemsAPI.Station.self].first)
        XCTAssertEqual(station.attributes.economy.value, .HighTech)
        XCTAssertEqual(station.attributes.type.value, .CoriolisStarport)
    }
}
