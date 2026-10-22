import XCTest

@testable import mechasqueak

final class RelayedTextTests: XCTestCase {
    func testLineBreaksBecomeSpaces() {
        XCTAssertEqual("Bonjour\nKICK #fuelrats rat :bye".sanitizedForRelay(), "Bonjour KICK #fuelrats rat :bye")
        XCTAssertEqual("one\r\ntwo\u{2028}three".sanitizedForRelay(), "one  two three")
    }

    func testControlCodesAreRemovedExceptBold() {
        XCTAssertEqual("\u{01}VERSION\u{01}".sanitizedForRelay(), "VERSION")
        XCTAssertEqual("\u{03}4red\u{0F} \u{16}rev\u{1D}".sanitizedForRelay(), "4red rev")
        XCTAssertEqual("\u{02}bold\u{02}".sanitizedForRelay(), "\u{02}bold\u{02}")
        XCTAssertEqual("nul\u{00}del\u{7F}".sanitizedForRelay(), "nuldel")
    }

    func testPlatformSignalsAreBroken() {
        for word in ["XB_SIGNAL", "PS_SIGNAL", "LEG_SIGNAL", "HOR_SIGNAL", "ODY_SIGNAL", "RATSIGNAL"] {
            let out = "Case #9 \(word) - CMDR Foo".sanitizedForRelay()
            XCTAssertFalse(out.contains(word), word)
            XCTAssertEqual(out.replacingOccurrences(of: "\u{200B}", with: ""), "Case #9 \(word) - CMDR Foo")
        }
    }

    func testOrdinaryTextIsUnchanged() {
        let text = "Help is on the way! Please stay in the channel, CMDR."
        XCTAssertEqual(text.sanitizedForRelay(), text)
    }
}
