import XCTest

@testable import mechasqueak

final class ExternalToolsTests: XCTestCase {
    func testExternalToolsRegistered() {
        XCTAssertEqual(ExternalTools.all().map(\.name).sorted(), ["edsm_nearest", "edsm_system"])
    }

    func testEdsmURLIncludesShowFlags() {
        let url = ExternalTools.edsmURL(
            path: "/en/api-v1/system",
            query: ["systemName": "Sol", "showPrimaryStar": "1", "showPermit": "1"])
        XCTAssertTrue(url.hasPrefix("https://www.edsm.net/en/api-v1/system?"))
        XCTAssertTrue(url.contains("showPrimaryStar=1"))
        XCTAssertTrue(url.contains("showPermit=1"))
        XCTAssertTrue(url.contains("systemName=Sol"))
    }

    func testParseSystemWithScoopablePrimaryStar() {
        let fixture = """
        {"name":"Sol","requirePermit":true,"permitName":"Sol",
         "primaryStar":{"type":"G (White-Yellow) Star","name":"Sol","isScoopable":true},
         "coords":{"x":0,"y":0,"z":0}}
        """
        let summary = ExternalTools.parseSystem(Data(fixture.utf8))
        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.name, "Sol")
        XCTAssertEqual(summary?.permitRequired, true)
        XCTAssertEqual(summary?.permitName, "Sol")
        XCTAssertEqual(summary?.primaryStar?.scoopable, true)
        XCTAssertEqual(summary?.primaryStar?.type, "G (White-Yellow) Star")
    }

    func testParseSystemNotFoundReturnsNilForEmptyArray() {
        // EDSM returns [] for an unknown system.
        XCTAssertNil(ExternalTools.parseSystem(Data("[]".utf8)))
        XCTAssertNil(ExternalTools.parseSystem(Data("{}".utf8)))
    }

    func testParseSphereSystemsSortsByDistance() {
        let fixture = """
        [{"name":"Far","distance":40.0},
         {"name":"Near","distance":3.2},
         {"name":"Mid","distance":12.0}]
        """
        let neighbours = ExternalTools.parseSphereSystems(Data(fixture.utf8), limit: 2)
        XCTAssertEqual(neighbours.map(\.name), ["Near", "Mid"])
        XCTAssertEqual(neighbours.first?.distanceLy, 3.2)
    }

    func testParseStations() {
        let fixture = """
        {"name":"Sol","stations":[
          {"name":"Galileo","type":"Ocellus Starport","distanceToArrival":505.0},
          {"name":"Daedalus","type":"Coriolis Starport","distanceToArrival":186.0}]}
        """
        let stations = ExternalTools.parseStations(Data(fixture.utf8))
        XCTAssertEqual(stations.count, 2)
        XCTAssertEqual(stations.first?.name, "Galileo")
        XCTAssertEqual(stations.first?.distanceLs, 505.0)
    }

    func testCacheReturnsStoredValueThenRespectsMiss() async {
        let cache = ResponseCache(ttl: 60)
        let miss = await cache.value(for: "k")
        XCTAssertNil(miss)
        await cache.store(Data("v".utf8), for: "k")
        let hit = await cache.value(for: "k")
        XCTAssertEqual(hit, Data("v".utf8))
        let otherMiss = await cache.value(for: "other")
        XCTAssertNil(otherMiss)
    }
}
