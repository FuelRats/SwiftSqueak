import XCTest

@testable import mechasqueak

final class AIServiceTests: XCTestCase {
    // MARK: - Name-trigger extraction

    func testExtractQuestionStripsNameAndSeparators() {
        XCTAssertEqual(
            AIService.extractQuestion(from: "MechaSqueak: how do I file a case?", botNick: "MechaSqueak"),
            "how do I file a case?")
        XCTAssertEqual(
            AIService.extractQuestion(from: "MechaSqueak, what's a case", botNick: "MechaSqueak"),
            "what's a case")
        XCTAssertEqual(
            AIService.extractQuestion(from: "MechaSqueak how do I fly", botNick: "MechaSqueak"),
            "how do I fly")
    }

    func testExtractQuestionIsCaseInsensitive() {
        XCTAssertEqual(
            AIService.extractQuestion(from: "mechasqueak tell me things", botNick: "MechaSqueak"),
            "tell me things")
    }

    func testExtractQuestionRejectsNonAddressed() {
        // No name prefix.
        XCTAssertNil(AIService.extractQuestion(from: "hello there everyone", botNick: "MechaSqueak"))
        // Name is a prefix of a longer word — must not match.
        XCTAssertNil(AIService.extractQuestion(from: "MechaSqueakBot is broken", botNick: "MechaSqueak"))
        // Just the name, nothing to answer.
        XCTAssertNil(AIService.extractQuestion(from: "MechaSqueak", botNick: "MechaSqueak"))
        XCTAssertNil(AIService.extractQuestion(from: "MechaSqueak   ", botNick: "MechaSqueak"))
    }

    // MARK: - Relevance prefilter

    func testPrefilterPassesGenuineQuestions() {
        for text in [
            "how do I file a case",
            "tell me how to file a case",   // imperative without '?'
            "is Sol scoopable?",
            "are you alive",                // dumb-but-real still passes
            "what's the nearest station to Fuelum",
            "explain supercruise"
        ] {
            XCTAssertTrue(RelevanceGate.prefilterPasses(text), "should pass: \(text)")
        }
    }

    func testPrefilterRejectsBareReactions() {
        // Only a bare greeting/thanks/reaction (nothing else) is dropped pre-gate.
        for text in ["thanks", "lol", "hi", "o7", "ty", "thx", "gg", "ok", "nah", "bye"] {
            XCTAssertFalse(RelevanceGate.prefilterPasses(text), "should be silent: \(text)")
        }
    }

    func testPrefilterPassesAddressedContent() {
        // Lowered bar: anything with real content (statements, banter) passes to the Haiku gate.
        for text in [
            "that rescue was wild",
            "tell me about Deciat",
            "i think your targeting computer is broken",
            "the fuel gauge is reading zero"
        ] {
            XCTAssertTrue(RelevanceGate.prefilterPasses(text), "should pass to the gate: \(text)")
        }
    }

    func testFormatForIRCCollapsesToOneLineDropsDashesAndConvertsBold() {
        let input = "First part.\n\nSecond part with **emphasis** and an em dash \u{2014} tail."
        let out = AIService.formatForIRC(input)
        XCTAssertFalse(out.contains("\n"), "must be a single line")
        XCTAssertFalse(out.contains("\u{2014}"), "em dashes must be replaced")
        XCTAssertFalse(out.contains("  "), "runs of whitespace must collapse")
        XCTAssertTrue(out.contains("\u{02}emphasis\u{02}"), "**bold** must become the IRC bold code")
        XCTAssertEqual(out, "First part. Second part with \u{02}emphasis\u{02} and an em dash - tail.")
    }

    func testFormatForIRCStripsBackticks() {
        XCTAssertEqual(AIService.formatForIRC("use `!clear` to close"), "use !clear to close")
    }

    func testClampTruncatesLongTextWithEllipsis() {
        let long = String(repeating: "word ", count: 200)
        let out = AIService.clamp(long, to: 50)
        XCTAssertLessThanOrEqual(out.count, 50)
        XCTAssertTrue(out.hasSuffix("\u{2026}"))
    }

    func testClampLeavesShortTextUnchanged() {
        XCTAssertEqual(AIService.clamp("short answer", to: 430), "short answer")
    }

    func testClampEndsAtSentenceBoundaryNotMidSentence() {
        let text = "First sentence is complete. Second sentence runs on well past the limit and should be dropped."
        let out = AIService.clamp(text, to: 40)
        XCTAssertEqual(out, "First sentence is complete.")
        XCTAssertFalse(out.hasSuffix("\u{2026}"), "a clean sentence end needs no ellipsis")
    }
}
