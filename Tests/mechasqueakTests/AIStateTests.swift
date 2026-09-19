import XCTest

@testable import mechasqueak

final class AIStateTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func testConcurrentReserveForOneKeyAdmitsExactlyOne() async {
        let state = AIState(cooldown: 30, maxInFlight: 100, dailyTokenCap: 1000)
        let now = base
        let reserved = await withTaskGroup(of: ReserveResult.self) { group -> Int in
            for _ in 0..<50 {
                group.addTask { await state.reserve(key: "chan|alice", now: now) }
            }
            var count = 0
            for await result in group where result == .reserved { count += 1 }
            return count
        }
        XCTAssertEqual(reserved, 1, "a burst from one key must admit exactly one pipeline")
    }

    func testInFlightCapIsEnforced() async {
        let state = AIState(cooldown: 30, maxInFlight: 2, dailyTokenCap: 1000)
        let first = await state.reserve(key: "k1", now: base)
        let second = await state.reserve(key: "k2", now: base)
        let third = await state.reserve(key: "k3", now: base)
        XCTAssertEqual(first, .reserved)
        XCTAssertEqual(second, .reserved)
        XCTAssertEqual(third, .overCapacity, "over the in-flight cap must fail fast")
    }

    func testReleaseFreesASlot() async {
        let state = AIState(cooldown: 30, maxInFlight: 1, dailyTokenCap: 1000)
        _ = await state.reserve(key: "k1", now: base)
        let blocked = await state.reserve(key: "k2", now: base)
        XCTAssertEqual(blocked, .overCapacity)
        await state.release()
        let afterRelease = await state.reserve(key: "k2", now: base)
        XCTAssertEqual(afterRelease, .reserved)
    }

    func testCooldownBlocksSameKey() async {
        let state = AIState(cooldown: 30, maxInFlight: 10, dailyTokenCap: 1000)
        _ = await state.reserve(key: "k1", now: base)
        await state.release()
        let again = await state.reserve(key: "k1", now: base.addingTimeInterval(10))
        XCTAssertEqual(again, .cooldown, "same key within the cooldown window is blocked")
        let afterCooldown = await state.reserve(key: "k1", now: base.addingTimeInterval(31))
        XCTAssertEqual(afterCooldown, .reserved)
    }

    func testPerCallCooldownOverridesDefault() async {
        let state = AIState(cooldown: 30, maxInFlight: 10, dailyTokenCap: 1000)
        _ = await state.reserve(key: "chan", cooldown: 300, now: base)
        await state.release()
        // The default 30s has elapsed, but the per-call 5-minute cooldown still blocks the channel key.
        let blocked = await state.reserve(key: "chan", cooldown: 300, now: base.addingTimeInterval(60))
        XCTAssertEqual(blocked, .cooldown)
        let afterFive = await state.reserve(key: "chan", cooldown: 300, now: base.addingTimeInterval(301))
        XCTAssertEqual(afterFive, .reserved)
    }

    func testPerUserBudgetIsEnforcedIndependentlyOfOtherUsers() async {
        let state = AIState(
            cooldown: 0, maxInFlight: 10, dailyTokenCap: 1000, perUserCap: 2, perUserWindow: 3600)
        // Distinct keys avoid the cooldown; the per-user cap should still bite after 2.
        let one = await state.reserve(key: "k1", user: "alice", now: base)
        await state.release()
        let two = await state.reserve(key: "k2", user: "alice", now: base)
        await state.release()
        let three = await state.reserve(key: "k3", user: "alice", now: base)
        XCTAssertEqual([one, two], [.reserved, .reserved])
        XCTAssertEqual(three, .overBudget, "a user past their per-user cap is rejected")

        // A different user is unaffected.
        let otherUser = await state.reserve(key: "k4", user: "bob", now: base)
        XCTAssertEqual(otherUser, .reserved)

        // The per-user window resets.
        let afterWindow = await state.reserve(key: "k5", user: "alice", now: base.addingTimeInterval(3601))
        XCTAssertEqual(afterWindow, .reserved)
    }

    func testDailyTokenBudgetIsEnforcedAndRollsOver() async {
        // Budget is token-based and committed from actual usage, not charged at reserve.
        let state = AIState(cooldown: 0, maxInFlight: 10, dailyTokenCap: 100)
        let first = await state.reserve(key: "k1", now: base)
        await state.recordUsage(tokens: 60, now: base)
        await state.release()
        let second = await state.reserve(key: "k2", now: base)
        await state.recordUsage(tokens: 60, now: base)  // cumulative 120 >= 100
        await state.release()
        XCTAssertEqual([first, second], [.reserved, .reserved])

        let overBudget = await state.reserve(key: "k3", now: base)
        XCTAssertEqual(overBudget, .overBudget, "global token budget exhausted")

        // A new 24h window resets the token counter.
        let nextDay = base.addingTimeInterval(AIState.windowLength + 1)
        let afterRollover = await state.reserve(key: "k4", now: nextDay)
        XCTAssertEqual(afterRollover, .reserved)
    }

    func testNonAnswerDoesNotDrainTokenBudget() async {
        // Reservations that never record usage (gate-rejected chatter) must not consume the budget.
        let state = AIState(cooldown: 0, maxInFlight: 10, dailyTokenCap: 100)
        for index in 0..<50 {
            _ = await state.reserve(key: "k\(index)", user: "u\(index)", now: base)
            await state.release(refundingUser: "u\(index)")  // no recordUsage: not a billable answer
        }
        let stillAvailable = await state.reserve(key: "kfinal", now: base)
        XCTAssertEqual(stillAvailable, .reserved, "non-answers must not exhaust the token budget")
    }

    func testRefundingUserRollsBackTheAttempt() async {
        let state = AIState(
            cooldown: 0, maxInFlight: 10, dailyTokenCap: 1000, perUserCap: 2, perUserWindow: 3600)
        // Two gate-rejected attempts, each refunded — must not count toward the per-user cap.
        _ = await state.reserve(key: "k1", user: "alice", now: base)
        await state.release(refundingUser: "alice")
        _ = await state.reserve(key: "k2", user: "alice", now: base)
        await state.release(refundingUser: "alice")
        // A third attempt still succeeds because the refunded two didn't accumulate.
        let third = await state.reserve(key: "k3", user: "alice", now: base)
        XCTAssertEqual(third, .reserved, "refunded attempts must not lock the user out")
    }

    func testReleaseWithoutRefundKeepsTheAttempt() async {
        let state = AIState(
            cooldown: 0, maxInFlight: 10, dailyTokenCap: 1000, perUserCap: 2, perUserWindow: 3600)
        _ = await state.reserve(key: "k1", user: "alice", now: base)
        await state.release()  // billable answer: attempt stands
        _ = await state.reserve(key: "k2", user: "alice", now: base)
        await state.release()
        let third = await state.reserve(key: "k3", user: "alice", now: base)
        XCTAssertEqual(third, .overBudget, "un-refunded attempts count toward the per-user cap")
    }

    func testStalePerUserBucketsAreSwept() async {
        let state = AIState(cooldown: 0, maxInFlight: 100, dailyTokenCap: 1000, perUserWindow: 3600)
        for index in 0..<100 {
            _ = await state.reserve(key: "k\(index)", user: "u\(index)", now: base)
            await state.release()
        }
        let trackedAtBase = await state.trackedUserCount
        XCTAssertEqual(trackedAtBase, 100)
        // A later reserve past the per-user window must sweep the stale buckets.
        _ = await state.reserve(key: "knew", user: "newuser", now: base.addingTimeInterval(3601))
        let trackedAfter = await state.trackedUserCount
        XCTAssertEqual(trackedAfter, 1, "stale per-user buckets must be swept, not retained forever")
    }

    func testCooldownNoticeIsOneShotPerUserPerWindow() async {
        let state = AIState(cooldown: 30, maxInFlight: 10, dailyTokenCap: 1000)
        _ = await state.reserve(key: "chan", cooldown: 300, now: base)  // opens the window
        await state.release()
        let now = base.addingTimeInterval(60)  // still on cooldown
        // First block for alice -> she is told, with the remaining time.
        let first = await state.cooldownNoticeRemaining(key: "chan", user: "alice", now: now)
        XCTAssertEqual(first, 240, "the first block reports the remaining cooldown")
        // Second block for alice in the same window -> silent.
        let second = await state.cooldownNoticeRemaining(key: "chan", user: "alice", now: now)
        XCTAssertNil(second, "the same user is only notified once per window")
        // A different user still gets their own one-shot notice.
        let other = await state.cooldownNoticeRemaining(key: "chan", user: "bob", now: now)
        XCTAssertEqual(other, 240)
    }

    func testCooldownNoticeNilWhenNotOnCooldown() async {
        let state = AIState(cooldown: 30, maxInFlight: 10, dailyTokenCap: 1000)
        let result = await state.cooldownNoticeRemaining(key: "chan", user: "alice", now: base)
        XCTAssertNil(result, "no notice when the key is not on cooldown")
    }

    func testCooldownNoticeResetsForNewWindow() async {
        let state = AIState(cooldown: 30, maxInFlight: 10, dailyTokenCap: 1000)
        _ = await state.reserve(key: "chan", cooldown: 300, now: base)
        await state.release()
        _ = await state.cooldownNoticeRemaining(key: "chan", user: "alice", now: base.addingTimeInterval(60))
        // A new window opens after the cooldown expires and a fresh reserve succeeds.
        _ = await state.reserve(key: "chan", cooldown: 300, now: base.addingTimeInterval(301))
        await state.release()
        let afterNewWindow = await state.cooldownNoticeRemaining(
            key: "chan", user: "alice", now: base.addingTimeInterval(360))
        XCTAssertNotNil(afterNewWindow, "a new cooldown window lets the user be notified again")
    }

    func testRejectedAttemptOnlyHoldsShortCooldownNotTheFullWindow() async {
        // Reserve applies only the short (30s default) attempt cooldown; if the attempt is refunded
        // (gate reject / error) without setCooldown, the channel frees at 30s — it is NOT locked 5 min.
        let state = AIState(cooldown: 30, maxInFlight: 10, dailyTokenCap: 1000)
        _ = await state.reserve(key: "chan", now: base)
        await state.release(refundingUser: "alice")
        let stillCooling = await state.reserve(key: "chan", now: base.addingTimeInterval(10))
        XCTAssertEqual(stillCooling, .cooldown)
        let freed = await state.reserve(key: "chan", now: base.addingTimeInterval(31))
        XCTAssertEqual(freed, .reserved, "a rejected attempt must not lock the channel beyond the attempt cooldown")
    }

    func testSetCooldownAppliesFullWindow() async {
        let state = AIState(cooldown: 30, maxInFlight: 10, dailyTokenCap: 1000)
        _ = await state.reserve(key: "chan", now: base)
        await state.setCooldown(key: "chan", seconds: 300, now: base)  // applied after a real answer
        await state.release()
        let blocked = await state.reserve(key: "chan", now: base.addingTimeInterval(120))
        XCTAssertEqual(blocked, .cooldown, "the full window blocks past the short attempt cooldown")
        let remaining = await state.cooldownNoticeRemaining(
            key: "chan", user: "bob", now: base.addingTimeInterval(120))
        XCTAssertEqual(remaining, 180)
    }

    func testShouldAnnounceErrorIsOneShotPerWindow() async {
        let state = AIState(cooldown: 30, maxInFlight: 10, dailyTokenCap: 1000)
        _ = await state.reserve(key: "chan", now: base)
        let first = await state.shouldAnnounceError(key: "chan")
        let second = await state.shouldAnnounceError(key: "chan")
        XCTAssertTrue(first, "first error in the window announces")
        XCTAssertFalse(second, "further errors stay silent")
        // A fresh reserve opens a new window and re-enables one announcement.
        _ = await state.reserve(key: "chan", now: base.addingTimeInterval(31))
        let afterNewWindow = await state.shouldAnnounceError(key: "chan")
        XCTAssertTrue(afterNewWindow)
    }

    func testBudgetWindowDoesNotDriftForward() async {
        // After a long quiet gap the window must realign to a whole-window boundary, not snap to now.
        let state = AIState(cooldown: 0, maxInFlight: 10, dailyTokenCap: 100)
        let first = await state.reserve(key: "k1", now: base)
        await state.recordUsage(tokens: 150, now: base)  // over cap
        XCTAssertEqual(first, .reserved)
        let blocked = await state.reserve(key: "k2", now: base.addingTimeInterval(60))
        XCTAssertEqual(blocked, .overBudget)
        // 2.5 windows later: the counter resets exactly once the boundary is crossed.
        let later = base.addingTimeInterval(AIState.windowLength * 2 + 5)
        let afterRollover = await state.reserve(key: "k3", now: later)
        XCTAssertEqual(afterRollover, .reserved)
    }
}
