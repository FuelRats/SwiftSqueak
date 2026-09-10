import Foundation
import XCTest

@testable import mechasqueak

final class TimeToolsTests: XCTestCase {
    private struct ToolStub: LLMProvider {
        let input: JSONValue
        func complete(_ request: LLMRequest) async throws -> LLMResponse {
            LLMResponse(
                content: [.toolUse(id: "t", name: "timezone_convert", input: input)],
                stopReason: .toolUse, usage: LLMUsage())
        }
    }

    private struct TextOnlyStub: LLMProvider {
        func complete(_ request: LLMRequest) async throws -> LLMResponse {
            LLMResponse(content: [.text("no tool", citations: [])], stopReason: .endTurn, usage: LLMUsage())
        }
    }

    // MARK: - Registration

    func testToolRegistered() {
        XCTAssertEqual(TimeTools.all().map(\.name), ["timezone_convert"])
    }

    // MARK: - Deterministic conversion (DST-correct)

    func testConvertSummerAppliesBritishSummerTime() throws {
        let result = try XCTUnwrap(TimeTools.convert(
            time: "15:00", date: "2024-07-15", fromZone: "Europe/London", toZones: ["UTC"]))
        XCTAssertEqual(result.source.time, "15:00")
        XCTAssertEqual(result.source.utcOffset, "+01:00", "London is on BST (UTC+1) in July")
        XCTAssertEqual(result.targets.first?.time, "14:00")
        XCTAssertEqual(result.targets.first?.utcOffset, "+00:00")
    }

    func testConvertWinterHasNoDaylightOffset() throws {
        let result = try XCTUnwrap(TimeTools.convert(
            time: "15:00", date: "2024-01-15", fromZone: "Europe/London", toZones: ["UTC"]))
        XCTAssertEqual(result.source.utcOffset, "+00:00", "London is on GMT in January")
        XCTAssertEqual(result.targets.first?.time, "15:00")
    }

    func testConvertAcrossZonesUsesInstantOffsets() throws {
        let result = try XCTUnwrap(TimeTools.convert(
            time: "15:00", date: "2024-07-15", fromZone: "Europe/London",
            toZones: ["America/New_York"]))
        // 15:00 BST == 14:00 UTC == 10:00 EDT.
        XCTAssertEqual(result.targets.first?.name, "New York")
        XCTAssertEqual(result.targets.first?.time, "10:00")
        XCTAssertEqual(result.targets.first?.utcOffset, "-04:00")
    }

    func testConvertHandlesMultipleTargets() throws {
        let result = try XCTUnwrap(TimeTools.convert(
            time: "12:00", date: "2024-07-15", fromZone: "UTC",
            toZones: ["America/Los_Angeles", "Asia/Tokyo"]))
        XCTAssertEqual(result.targets.map(\.name), ["Los Angeles", "Tokyo"])
        XCTAssertEqual(result.targets.map(\.time), ["05:00", "21:00"])
    }

    func testConvertRejectsBadTimeAndZone() {
        XCTAssertNil(TimeTools.convert(time: "nonsense", date: nil, fromZone: "UTC", toZones: ["UTC"]))
        XCTAssertNil(TimeTools.convert(time: "15:00", date: nil, fromZone: "Not/AZone", toZones: ["UTC"]))
    }

    // MARK: - Parsing helpers

    func testParseTimeVariants() {
        XCTAssertEqual(TimeTools.parseTime("3pm").map { [$0.hour, $0.minute] }, [15, 0])
        XCTAssertEqual(TimeTools.parseTime("9am").map { [$0.hour, $0.minute] }, [9, 0])
        XCTAssertEqual(TimeTools.parseTime("3:30 pm").map { [$0.hour, $0.minute] }, [15, 30])
        XCTAssertEqual(TimeTools.parseTime("15:00").map { [$0.hour, $0.minute] }, [15, 0])
        XCTAssertEqual(TimeTools.parseTime("12am").map { [$0.hour, $0.minute] }, [0, 0])
        XCTAssertEqual(TimeTools.parseTime("12pm").map { [$0.hour, $0.minute] }, [12, 0])
        XCTAssertNil(TimeTools.parseTime("25:00"))
        XCTAssertNil(TimeTools.parseTime("abc"))
    }

    func testResolveZoneFromIdentifierAndAbbreviation() {
        XCTAssertEqual(TimeTools.resolveZone("Europe/London")?.identifier, "Europe/London")
        XCTAssertNotNil(TimeTools.resolveZone("JST"), "a standard abbreviation resolves")
        XCTAssertNil(TimeTools.resolveZone("Not/AZone"))
    }

    // MARK: - Model-driven interpretation

    func testInterpretConvertsUsingModelArgs() async throws {
        let stub = ToolStub(input: .object([
            ("time", .string("15:00")),
            ("date", .string("2024-07-15")),
            ("from_zone", .string("Europe/London")),
            ("to_zones", .array([.string("UTC")]))
        ]))
        let out = try await TimeTools.interpret("3pm in London", provider: stub)
        let line = try XCTUnwrap(out)
        XCTAssertTrue(line.contains("London"))
        XCTAssertTrue(line.contains("15:00"))
        XCTAssertTrue(line.contains("14:00"), "15:00 BST is 14:00 UTC")
    }

    func testInterpretReturnsNilWhenModelDoesNotCallTool() async throws {
        // Contains a time so it passes the plausibility guard and reaches the provider, which here
        // returns text instead of a tool call.
        let out = try await TimeTools.interpret("convert 3pm somewhere", provider: TextOnlyStub())
        XCTAssertNil(out)
    }

    func testInterpretSkipsModelWhenNoTimePresent() async throws {
        // "banana" has no time, so interpret must short-circuit before ever calling the provider.
        let out = try await TimeTools.interpret("banana", provider: ToolStub(input: .object([])))
        XCTAssertNil(out)
    }

    func testContainsPlausibleTime() {
        XCTAssertTrue(TimeTools.containsPlausibleTime("3pm in London"))
        XCTAssertTrue(TimeTools.containsPlausibleTime("noon UTC in Tokyo"))
        XCTAssertTrue(TimeTools.containsPlausibleTime("midnight in Sydney"))
        XCTAssertFalse(TimeTools.containsPlausibleTime("banana"))
        XCTAssertFalse(TimeTools.containsPlausibleTime("what time is it in London"))
    }
}
