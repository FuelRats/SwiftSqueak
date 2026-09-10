import XCTest

@testable import mechasqueak

final class BoardToolsTests: XCTestCase {
    func testBoardToolsRegistered() {
        XCTAssertEqual(
            BoardTools.all().map(\.name),
            ["active_cases", "case_detail", "rat_lookup", "find_command"])
    }

    func testCommandMatchesMapsFieldsAndDropsEmptyAliases() {
        let commands = [
            Command(
                id: 1, name: "sctime", aliases: "sccalc traveltime",
                description: "Calculate supercruise travel time.", tags: "time"),
            Command(id: 2, name: "gametime", aliases: "", description: "Game time.", tags: "time")
        ]
        let matches = BoardTools.commandMatches(commands)
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches[0].name, "sctime")
        XCTAssertEqual(matches[0].aliases, "sccalc traveltime")
        XCTAssertEqual(matches[0].description, "Calculate supercruise travel time.")
        XCTAssertNil(matches[1].aliases)
    }

    func testCommandMatchesRespectsResultLimit() {
        let commands = (0..<10).map {
            Command(id: $0, name: "cmd\($0)", aliases: "", description: "d", tags: "t")
        }
        XCTAssertEqual(BoardTools.commandMatches(commands).count, DataTools.searchResultLimit)
    }
}
