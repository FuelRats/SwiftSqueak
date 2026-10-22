import XCTest

@testable import mechasqueak

final class CommandRateLimiterTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func testAllowsUpToTheLimitThenNotifiesOnce() {
        let limiter = CommandRateLimiter(window: 30, maximumCommands: 3)
        let decisions = (0..<6).map {
            limiter.decision(identity: "nick:troll", messageId: "m\($0)", now: base.addingTimeInterval(Double($0)))
        }
        XCTAssertEqual(decisions, [
            .allowed, .allowed, .allowed, .limited(notify: true), .limited(notify: false), .limited(notify: false)
        ])
    }

    func testWindowExpiryAllowsAgain() {
        let limiter = CommandRateLimiter(window: 30, maximumCommands: 1)
        XCTAssertEqual(limiter.decision(identity: "acct:rat", messageId: "a", now: base), .allowed)
        XCTAssertEqual(limiter.decision(identity: "acct:rat", messageId: "b", now: base.addingTimeInterval(5)),
                       .limited(notify: true))
        XCTAssertEqual(limiter.decision(identity: "acct:rat", messageId: "c", now: base.addingTimeInterval(31)),
                       .allowed)
    }

    func testSameMessageIsCountedOnce() {
        // The command manager and the fact handler both ask about every "!" message.
        let limiter = CommandRateLimiter(window: 30, maximumCommands: 1)
        XCTAssertEqual(limiter.decision(identity: "nick:a", messageId: "same", now: base), .allowed)
        XCTAssertEqual(limiter.decision(identity: "nick:a", messageId: "same", now: base), .allowed)
        XCTAssertEqual(limiter.decision(identity: "nick:a", messageId: "next", now: base), .limited(notify: true))
    }

    func testLimitNoticeIsSentOncePerMessage() {
        // The command manager and the fact handler both ask about the first limited message; only one may notify.
        let limiter = CommandRateLimiter(window: 30, maximumCommands: 1)
        _ = limiter.decision(identity: "nick:a", messageId: "1", now: base)
        XCTAssertEqual(limiter.decision(identity: "nick:a", messageId: "2", now: base), .limited(notify: true))
        XCTAssertEqual(limiter.decision(identity: "nick:a", messageId: "2", now: base), .limited(notify: false))
    }

    func testIdentitiesAreIndependent() {
        let limiter = CommandRateLimiter(window: 30, maximumCommands: 1)
        XCTAssertEqual(limiter.decision(identity: "nick:a", messageId: "1", now: base), .allowed)
        XCTAssertEqual(limiter.decision(identity: "nick:b", messageId: "2", now: base), .allowed)
    }
}
