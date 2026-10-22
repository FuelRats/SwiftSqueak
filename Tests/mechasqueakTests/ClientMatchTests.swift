import XCTest

@testable import mechasqueak

final class ClientMatchTests: XCTestCase {
    private func match(existing: (String?, String?), signal: (String?, String?)) -> ClientMatch? {
        clientMatch(
            existingName: existing.0, existingNick: existing.1, clientName: signal.0, clientNick: signal.1)
    }

    func testSameNameOrNickIsExact() {
        XCTAssertEqual(match(existing: ("spacedawg", "spacedawg_"), signal: ("spacedawg", nil)), .exact)
        XCTAssertEqual(match(existing: ("cmdr one", "spacedawg"), signal: ("other", "spacedawg")), .exact)
    }

    func testNearMissIsOnlySimilar() {
        // A one-character difference can be the same client mistyping, or someone else entirely; it must never be
        // treated as the same client.
        XCTAssertEqual(match(existing: ("spacedawg", "spacedawg"), signal: ("spacedawq", "spacedawq")), .similar)
        XCTAssertEqual(match(existing: ("mike", "mike"), signal: ("mika", "mika")), .similar)
    }

    func testMissingNamesNeverMatchEachOther() {
        XCTAssertNil(match(existing: (nil, nil), signal: (nil, nil)))
    }

    func testUnrelatedNamesDoNotMatch() {
        XCTAssertNil(match(existing: ("spacedawg", "spacedawg"), signal: ("rodentia", "rodentia")))
        XCTAssertNil(
            match(existing: ("abc", "abc"), signal: ("abd", "abd")),
            "names under four characters are never fuzzy-matched")
    }
}
