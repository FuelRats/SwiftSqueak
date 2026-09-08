import XCTest

@testable import mechasqueak

final class AIStateTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    func testConcurrentReserveForOneKeyAdmitsExactlyOne() async {
        let state = AIState(cooldown: 30, maxInFlight: 100, dailyRequestCap: 1000)
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
        let state = AIState(cooldown: 30, maxInFlight: 2, dailyRequestCap: 1000)
        let first = await state.reserve(key: "k1", now: base)
        let second = await state.reserve(key: "k2", now: base)
        let third = await state.reserve(key: "k3", now: base)
        XCTAssertEqual(first, .reserved)
        XCTAssertEqual(second, .reserved)
        XCTAssertEqual(third, .overCapacity, "over the in-flight cap must fail fast")
    }

    func testReleaseFreesASlot() async {
        let state = AIState(cooldown: 30, maxInFlight: 1, dailyRequestCap: 1000)
        _ = await state.reserve(key: "k1", now: base)
        let blocked = await state.reserve(key: "k2", now: base)
        XCTAssertEqual(blocked, .overCapacity)
        await state.release()
        let afterRelease = await state.reserve(key: "k2", now: base)
        XCTAssertEqual(afterRelease, .reserved)
    }

    func testCooldownBlocksSameKey() async {
        let state = AIState(cooldown: 30, maxInFlight: 10, dailyRequestCap: 1000)
        _ = await state.reserve(key: "k1", now: base)
        await state.release()
        let again = await state.reserve(key: "k1", now: base.addingTimeInterval(10))
        XCTAssertEqual(again, .cooldown, "same key within the cooldown window is blocked")
        let afterCooldown = await state.reserve(key: "k1", now: base.addingTimeInterval(31))
        XCTAssertEqual(afterCooldown, .reserved)
    }

    func testDailyBudgetIsEnforcedAndRollsOver() async {
        let state = AIState(cooldown: 0, maxInFlight: 10, dailyRequestCap: 2)
        _ = await state.reserve(key: "k1", now: base)
        await state.release()
        _ = await state.reserve(key: "k2", now: base)
        await state.release()
        let overBudget = await state.reserve(key: "k3", now: base)
        XCTAssertEqual(overBudget, .overBudget)

        // A new 24h window resets the counter.
        let nextDay = base.addingTimeInterval(AIState.windowLength + 1)
        let afterRollover = await state.reserve(key: "k4", now: nextDay)
        XCTAssertEqual(afterRollover, .reserved)
    }
}
