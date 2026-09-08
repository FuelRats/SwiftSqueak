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

    func testPrefilterRejectsChatter() {
        for text in ["thanks", "thank you", "lol", "hi", "o7", "nice one", "gg wp", "ok cool"] {
            XCTAssertFalse(RelevanceGate.prefilterPasses(text), "should be silent: \(text)")
        }
    }
}
