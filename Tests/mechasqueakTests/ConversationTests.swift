import XCTest

@testable import mechasqueak

final class ConversationTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - ConversationManager

    func testIdentifiedUserAccumulatesBoundedHistory() async {
        let manager = ConversationManager(maxTurns: 4, ttl: 300)
        await manager.record(account: "alice", question: "q1", answer: "a1", now: base)
        await manager.record(account: "alice", question: "q2", answer: "a2", now: base)
        await manager.record(account: "alice", question: "q3", answer: "a3", now: base)

        let history = await manager.history(account: "alice", now: base)
        // maxTurns 4 keeps the last two exchanges (q2/a2, q3/a3).
        XCTAssertEqual(history.count, 4)
        XCTAssertEqual(history.map(\.text), ["q2", "a2", "q3", "a3"])
        XCTAssertEqual(history.first?.role, .user)
    }

    func testUnidentifiedUserIsStateless() async {
        let manager = ConversationManager()
        await manager.record(account: nil, question: "q", answer: "a", now: base)
        let history = await manager.history(account: nil, now: base)
        XCTAssertTrue(history.isEmpty)
        let count = await manager.sessionCount
        XCTAssertEqual(count, 0, "unidentified users create no session")
    }

    func testSessionExpiresAfterTTL() async {
        let manager = ConversationManager(maxTurns: 6, ttl: 300)
        await manager.record(account: "bob", question: "q", answer: "a", now: base)
        let stillThere = await manager.history(account: "bob", now: base.addingTimeInterval(299))
        XCTAssertEqual(stillThere.count, 2)
        let expired = await manager.history(account: "bob", now: base.addingTimeInterval(301))
        XCTAssertTrue(expired.isEmpty, "history expires after the idle TTL")
    }

    func testSessionsAreIsolatedPerAccount() async {
        let manager = ConversationManager()
        await manager.record(account: "alice", question: "qa", answer: "aa", now: base)
        await manager.record(account: "bob", question: "qb", answer: "ab", now: base)
        let alice = await manager.history(account: "alice", now: base)
        XCTAssertEqual(alice.map(\.text), ["qa", "aa"])
    }

    // MARK: - ScrollbackBuffer

    private func line(_ nick: String, _ text: String) -> ScrollbackLine {
        ScrollbackLine(nick: nick, text: text, isAction: false)
    }

    func testScrollbackCapsAndReturnsChronological() async {
        let buffer = ScrollbackBuffer(capacity: 3)
        for index in 1...5 {
            await buffer.record(key: "net|#fuelrats", line: line("u\(index)", "m\(index)"))
        }
        let recent = await buffer.recent(key: "net|#fuelrats", count: 10)
        XCTAssertEqual(recent.map(\.text), ["m3", "m4", "m5"], "capped to last 3, oldest first")
    }

    func testScrollbackRespectsCountAndKeys() async {
        let buffer = ScrollbackBuffer(capacity: 200)
        await buffer.record(key: "net|#a", line: line("x", "a1"))
        await buffer.record(key: "net|#a", line: line("y", "a2"))
        await buffer.record(key: "net|#b", line: line("z", "b1"))

        let lastOne = await buffer.recent(key: "net|#a", count: 1)
        XCTAssertEqual(lastOne.map(\.text), ["a2"])
        let channelB = await buffer.recent(key: "net|#b", count: 10)
        XCTAssertEqual(channelB.map(\.text), ["b1"], "channels are isolated by key")
        let empty = await buffer.recent(key: "net|#missing", count: 10)
        XCTAssertTrue(empty.isEmpty)
    }

    func testScrollbackToolSchema() {
        let tool = ScrollbackTool.tool
        XCTAssertEqual(tool.name, "read_channel_scrollback")
        guard case let .object(pairs) = tool.inputSchema else {
            return XCTFail("schema must be an object")
        }
        let keyed = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        // count is optional (empty required list).
        XCTAssertEqual(keyed["required"], .array([]))
        XCTAssertEqual(keyed["additionalProperties"], .bool(false))
    }
}
