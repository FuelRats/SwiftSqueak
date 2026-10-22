import XCTest

@testable import mechasqueak

final class BoardToolsTests: XCTestCase {
    func testBoardToolsRegistered() {
        XCTAssertEqual(
            BoardTools.all().map(\.name),
            ["active_cases", "case_detail", "rat_lookup", "find_command"])
    }

    func testBoardAndMemberToolsRefuseAnAskerWithoutPermission() async {
        // With no identified asker there is no permission to check, so nothing from the board or the API is shown.
        let context = ToolContext()
        for (tool, input) in [
            (BoardTools.activeCases, JSONValue.object([])),
            (BoardTools.caseDetail, JSONValue.object([("case", .string("1"))])),
            (BoardTools.ratLookup, JSONValue.object([("name", .string("SpaceDawg"))]))
        ] {
            let output = await tool.run(input, context)
            XCTAssertTrue(output.contains("permission"), "\(tool.name) must refuse: \(output)")
        }
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
        let commands = (0..<10).map { (index: Int) in
            Command(id: index, name: "cmd\(index)", aliases: "", description: "d", tags: "t")
        }
        XCTAssertEqual(BoardTools.commandMatches(commands).count, DataTools.searchResultLimit)
    }
}
