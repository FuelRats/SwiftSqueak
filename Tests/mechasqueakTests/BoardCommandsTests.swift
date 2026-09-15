import Foundation
import IRCKit
import XCTest

@testable import mechasqueak

/// Covers the pure decision logic behind `!addcase`/`!inject` free-text case creation — the routing
/// gate, the `-o/-h/-l` expansion override, and the field resolution (platform/expansion/client) that
/// `buildRescue` applies. `buildRescue` itself needs a live `IRCBotCommand`, so the Rescue construction
/// and SignalScanner fallback wiring stay covered by the end-to-end harness (`tools/scenarios/addcase.json`).
final class BoardCommandsTests: XCTestCase {
    private func fields(
        cmdr: String? = nil, platform: GamePlatform? = nil, system: String? = nil,
        codeRed: Bool = false, expansion: GameMode? = nil, language: Locale? = nil
    ) -> CaseParser.CaseFields {
        CaseParser.CaseFields(
            cmdrName: cmdr, platform: platform, system: system, codeRed: codeRed,
            expansion: expansion, language: language)
    }

    // MARK: routing gate

    func testFreeTextCreateWhenNoArgumentsAndNoteFollowsNick() {
        XCTAssertTrue(BoardCommands.isFreeTextCreate(
            arguments: [:], options: OrderedSet<Character>(), parameterCount: 2))
    }

    func testFreeTextCreateAllowsForceAndExpansionModifierOptions() {
        XCTAssertTrue(BoardCommands.isFreeTextCreate(
            arguments: [:], options: OrderedSet<Character>("fo"), parameterCount: 2))
    }

    func testStructuredPathWhenNamedArgumentPresent() {
        XCTAssertFalse(BoardCommands.isFreeTextCreate(
            arguments: ["sys": "Sol"], options: OrderedSet<Character>(), parameterCount: 2))
    }

    func testStructuredPathWhenNoNote() {
        XCTAssertFalse(BoardCommands.isFreeTextCreate(
            arguments: [:], options: OrderedSet<Character>(), parameterCount: 1))
    }

    func testStructuredPathWhenUnrelatedOptionPresent() {
        XCTAssertFalse(BoardCommands.isFreeTextCreate(
            arguments: [:], options: OrderedSet<Character>("x"), parameterCount: 2))
    }

    // MARK: expansion option

    func testExpansionOptionMapsFlags() {
        XCTAssertEqual(BoardCommands.expansionOption(from: OrderedSet<Character>("o")), .odyssey)
        XCTAssertEqual(BoardCommands.expansionOption(from: OrderedSet<Character>("h")), .horizons)
        XCTAssertEqual(BoardCommands.expansionOption(from: OrderedSet<Character>("l")), .legacy)
        XCTAssertNil(BoardCommands.expansionOption(from: OrderedSet<Character>("f")))
        XCTAssertNil(BoardCommands.expansionOption(from: OrderedSet<Character>()))
    }

    func testExpansionOptionFirstMatchWins() {
        XCTAssertEqual(BoardCommands.expansionOption(from: OrderedSet<Character>("oh")), .odyssey)
    }

    // MARK: field resolution

    func testNonLegacyExpansionForcesPCWhenPlatformUnset() {
        let resolved = BoardCommands.resolvedCase(
            fields(platform: nil, system: "Fuelum", expansion: .odyssey),
            nick: "Rat", text: "pc ody fuelum", expansionOverride: nil)
        XCTAssertEqual(resolved.platform, .PC)
    }

    func testNonLegacyExpansionForcesPCOverConsolePlatform() {
        // Xbox/PS are legacy-only, so a horizons/odyssey case must be PC.
        let resolved = BoardCommands.resolvedCase(
            fields(platform: .Xbox, system: "Sol", expansion: .horizons),
            nick: "Rat", text: "xbox hor sol", expansionOverride: nil)
        XCTAssertEqual(resolved.platform, .PC)
    }

    func testLegacyExpansionKeepsConsolePlatform() {
        let resolved = BoardCommands.resolvedCase(
            fields(platform: .Xbox, system: "Sol", expansion: .legacy),
            nick: "Rat", text: "xbox sol", expansionOverride: nil)
        XCTAssertEqual(resolved.platform, .Xbox)
        XCTAssertEqual(resolved.expansion, .legacy)
    }

    func testExpansionOverrideWinsAndForcesPC() {
        let resolved = BoardCommands.resolvedCase(
            fields(platform: .Xbox, system: "Sol", expansion: .legacy),
            nick: "Rat", text: "sol", expansionOverride: .odyssey)
        XCTAssertEqual(resolved.expansion, .odyssey)
        XCTAssertEqual(resolved.platform, .PC)
    }

    func testClientStaysNickWhenModelSlipsCmdrWithoutLabel() {
        // The deterministic gate: a bare system token the model mislabelled as a CMDR must not
        // become the client — the client stays the dispatcher-supplied nick.
        let resolved = BoardCommands.resolvedCase(
            fields(cmdr: "Lauma", platform: .PC),
            nick: "Wrench7", text: "Lauma PC", expansionOverride: nil)
        XCTAssertEqual(resolved.client, "Wrench7")
    }

    func testClientUsesCmdrWhenNoteHasExplicitLabel() {
        let resolved = BoardCommands.resolvedCase(
            fields(cmdr: "Space Dawg", platform: .PC, system: "Colonia"),
            nick: "SamW", text: "cmdr is Space Dawg, pc, Colonia", expansionOverride: nil)
        XCTAssertEqual(resolved.client, "Space Dawg")
    }

    func testClientIsNickWhenNoCmdrExtracted() {
        let resolved = BoardCommands.resolvedCase(
            fields(platform: .PC, system: "Sol"),
            nick: "Pilot", text: "pc sol", expansionOverride: nil)
        XCTAssertEqual(resolved.client, "Pilot")
    }
}
