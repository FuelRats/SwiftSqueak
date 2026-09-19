import XCTest

@testable import mechasqueak

final class AIToolTests: XCTestCase {
    private func schemaJSON(_ tool: AITool) throws -> String {
        let data = try Anthropic.encodeRequestBody(
            LLMRequest(model: "m", maxTokens: 8, messages: [.text(.user, "x")], tools: [tool.llmTool]))
        return String(data: data, encoding: .utf8) ?? ""
    }

    func testIsErrorPayloadDistinguishesErrorsFromResults() {
        XCTAssertTrue(ToolOutput.isErrorPayload(ToolOutput.error("not found")))
        XCTAssertFalse(ToolOutput.isErrorPayload(ToolOutput.json(["scoopable": true])))
        XCTAssertFalse(ToolOutput.isErrorPayload("No documents matched. Try different keywords."))
    }

    func testTierOneToolsAreRegistered() {
        let names = DataTools.all().map(\.name).sorted()
        XCTAssertEqual(
            names, ["fact_lookup", "list_facts", "nearest_station", "search_system", "system_info"])
    }

    func testToolLookupByName() {
        let tools = DataTools.all()
        XCTAssertEqual(tools.tool(named: "system_info")?.name, "system_info")
        XCTAssertNil(tools.tool(named: "does_not_exist"))
    }

    func testEverySchemaIsAStrictObject() throws {
        for tool in DataTools.all() {
            guard case let .object(pairs) = tool.inputSchema else {
                return XCTFail("\(tool.name) schema must be an object")
            }
            let keyed = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
            XCTAssertEqual(keyed["type"]?.stringValue, "object", "\(tool.name)")
            XCTAssertEqual(keyed["additionalProperties"]?.boolValue, false, "\(tool.name) must be strict")
            XCTAssertNotNil(keyed["properties"], "\(tool.name) must declare properties")
            XCTAssertNotNil(keyed["required"]?.arrayValue, "\(tool.name) must declare required")
        }
    }

    func testSchemaSerializesForAnthropic() throws {
        let json = try schemaJSON(DataTools.searchSystem)
        XCTAssertTrue(json.contains("\"name\":\"search_system\""))
        XCTAssertTrue(json.contains("\"input_schema\""))
        XCTAssertTrue(json.contains("\"additionalProperties\":false"))
        XCTAssertTrue(json.contains("\"query\""))
    }

    // MARK: - Output helpers

    func testTruncateAppendsEllipsisOnlyWhenNeeded() {
        XCTAssertEqual(ToolOutput.truncate("short", limit: 10), "short")
        let truncated = ToolOutput.truncate(String(repeating: "a", count: 20), limit: 10)
        XCTAssertEqual(truncated.count, 11) // 10 chars + ellipsis
        XCTAssertTrue(truncated.hasSuffix("…"))
    }

    func testErrorOutputIsJSON() {
        XCTAssertEqual(ToolOutput.error("not found"), #"{"error":"not found"}"#)
    }

    func testSystemInfoJSONEncoding() {
        let summary = DataTools.SystemInfoSummary(
            name: "Fuelum",
            exists: true,
            permitRequired: false,
            permitName: nil,
            nearestLandmark: DataTools.Landmark(name: "Fuelum", distanceLy: 0))
        let json = ToolOutput.json(summary)
        XCTAssertTrue(json.contains("\"name\":\"Fuelum\""))
        XCTAssertTrue(json.contains("\"exists\":true"))
        XCTAssertTrue(json.contains("\"permitRequired\":false"))
    }
}
