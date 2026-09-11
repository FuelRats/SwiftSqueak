import Foundation
import XCTest

@testable import mechasqueak

final class CaseParserTests: XCTestCase {
    private struct ToolStub: LLMProvider {
        let input: JSONValue
        func complete(_ request: LLMRequest) async throws -> LLMResponse {
            LLMResponse(
                content: [.toolUse(id: "c", name: "emit_case", input: input)],
                stopReason: .toolUse, usage: LLMUsage())
        }
    }

    private struct RefusedStub: LLMProvider {
        func complete(_ request: LLMRequest) async throws -> LLMResponse { throw LLMError.refused }
    }

    private struct TextOnlyStub: LLMProvider {
        func complete(_ request: LLMRequest) async throws -> LLMResponse {
            LLMResponse(content: [.text("no tool", citations: [])], stopReason: .endTurn, usage: LLMUsage())
        }
    }

    private func envelope(
        cmdr: String = "", platform: String = "", system: String = "", codeRed: Bool = false,
        expansion: String = "", language: String = "", error: String = ""
    ) -> JSONValue {
        .object([
            ("cmdr_name", .string(cmdr)),
            ("platform", .string(platform)),
            ("system", .string(system)),
            ("code_red", .bool(codeRed)),
            ("expansion", .string(expansion)),
            ("language", .string(language)),
            ("error", .string(error))
        ])
    }

    func testMapsAllStatedFields() async {
        let stub = ToolStub(input: envelope(
            cmdr: "Space Dawg", platform: "xbox", system: "MATET", codeRed: true,
            expansion: "odyssey", language: "ru"))
        let fields = await CaseParser.parse("derek in matet on xbox, out of o2, odyssey", provider: stub)
        XCTAssertEqual(fields?.cmdrName, "Space Dawg")
        XCTAssertEqual(fields?.platform, .Xbox)
        XCTAssertEqual(fields?.system, "MATET")
        XCTAssertEqual(fields?.codeRed, true)
        XCTAssertEqual(fields?.expansion, .odyssey)
        XCTAssertEqual(fields?.language?.identifier, "ru")
    }

    func testEmptyFieldsBecomeNil() async {
        let stub = ToolStub(input: envelope(system: "Fuelum"))
        let fields = await CaseParser.parse("stuck at fuelum", provider: stub)
        XCTAssertNil(fields?.cmdrName)
        XCTAssertNil(fields?.platform)
        XCTAssertEqual(fields?.system, "Fuelum")
        XCTAssertEqual(fields?.codeRed, false)
        XCTAssertNil(fields?.expansion)
        XCTAssertNil(fields?.language)
    }

    func testPlatformSynonymResolves() async {
        let fields = await CaseParser.parse("ps client", provider: ToolStub(input: envelope(platform: "ps")))
        XCTAssertEqual(fields?.platform, .PS)
    }

    func testErrorFieldFallsBackToNil() async {
        let stub = ToolStub(input: envelope(system: "x", error: "not a rescue"))
        let fields = await CaseParser.parse("what is the weather", provider: stub)
        XCTAssertNil(fields, "a flagged non-rescue note must fall back (nil), not fabricate a case")
    }

    func testNoToolCallReturnsNil() async {
        let fields = await CaseParser.parse("hello there", provider: TextOnlyStub())
        XCTAssertNil(fields)
    }

    func testRefusalReturnsNil() async {
        let fields = await CaseParser.parse("anything", provider: RefusedStub())
        XCTAssertNil(fields)
    }

    func testInvalidLanguageCodeBecomesNil() async {
        let stub = ToolStub(input: envelope(system: "Fuelum", language: "russian"))
        let fields = await CaseParser.parse("stuck at fuelum speaks russian", provider: stub)
        XCTAssertNil(fields?.language, "a non-ISO language string must be dropped, not persisted verbatim")
    }

    func testRegionQualifiedLanguageResolves() async {
        let stub = ToolStub(input: envelope(system: "Fuelum", language: "pt-BR"))
        let fields = await CaseParser.parse("cliente fala portugues", provider: stub)
        XCTAssertEqual(fields?.language?.identifier, "pt-BR")
    }

    func testCodeRedKeyAbsentDefaultsFalse() async {
        let input = JSONValue.object([
            ("cmdr_name", .string("")), ("platform", .string("pc")), ("system", .string("Sol")),
            ("expansion", .string("")), ("language", .string("")), ("error", .string(""))
        ])
        let fields = await CaseParser.parse("pc at sol", provider: ToolStub(input: input))
        XCTAssertEqual(fields?.codeRed, false, "a missing code_red key must default to false")
    }

    func testClientNickContextNamesTheNick() {
        let context = CaseParser.clientContext(nick: "Basalt5")
        XCTAssertTrue(context.contains("Basalt5"))
        XCTAssertTrue(context.contains("not a nick"), "must instruct the model not to re-derive a nick")
    }

    func testParseWithClientNickStillMapsFields() async {
        let stub = ToolStub(input: envelope(platform: "xbox", system: "MATET", codeRed: true))
        let fields = await CaseParser.parse("xbox MATET cr", clientNick: "Wrench7", provider: stub)
        XCTAssertEqual(fields?.system, "MATET")
        XCTAssertEqual(fields?.platform, .Xbox)
        XCTAssertEqual(fields?.codeRed, true)
        XCTAssertNil(fields?.cmdrName)
    }

    func testExplicitCmdrLabelDetection() {
        XCTAssertTrue(BoardCommands.hasExplicitCmdrLabel("cmdr Space Dawg, pc, Colonia"))
        XCTAssertTrue(BoardCommands.hasExplicitCmdrLabel("client is Bob on xbox"))
        XCTAssertFalse(BoardCommands.hasExplicitCmdrLabel("Lauma PC"), "a bare system token is not a cmdr label")
        XCTAssertFalse(BoardCommands.hasExplicitCmdrLabel("Koa Entraha PC cr"))
    }
}
