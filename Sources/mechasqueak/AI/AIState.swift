/*
 Copyright 2026 The Fuel Rats Mischief

 Redistribution and use in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice,
 this list of conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following
 disclaimer in the documentation and/or other materials provided with the distribution.

 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote
 products derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
 INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import Foundation

/// Outcome of an atomic reserve attempt. Distinct cases so the caller can stay silent in-channel
/// but tell a PM user why nothing happened.
enum ReserveResult: Sendable, Equatable {
    /// A slot was reserved; the caller must `release()` exactly once when done.
    case reserved
    /// The key is within its cooldown window.
    case cooldown
    /// Too many answer pipelines are already in flight.
    case overCapacity
    /// The daily request budget is exhausted.
    case overBudget
}

/// Shared, actor-isolated state for the always-listening AI surface. Because IRCKit delivers each
/// message notification on its own detached task, cooldown and capacity checks must be atomic —
/// `reserve` does check-and-reserve in a single actor hop so a burst from one user admits exactly
/// one pipeline. Also enforces a global in-flight cap, a per-user attempt budget, and a global daily
/// *token* budget (cost control — committed from actual usage via `recordUsage`, not at reserve).
actor AIState {
    private let cooldown: TimeInterval
    private let maxInFlight: Int
    private let dailyTokenCap: Int
    private let perUserCap: Int
    private let perUserWindow: TimeInterval

    private var cooldownUntil: [String: Date] = [:]
    private var inFlight = 0
    private var tokensInWindow = 0
    private var windowStart: Date?
    private var perUser: [String: (start: Date, count: Int)] = [:]

    static let windowLength: TimeInterval = 24 * 60 * 60

    init(
        cooldown: TimeInterval = 30,
        maxInFlight: Int = 3,
        dailyTokenCap: Int = 2_000_000,
        perUserCap: Int = 60,
        perUserWindow: TimeInterval = 3600
    ) {
        self.cooldown = cooldown
        self.maxInFlight = maxInFlight
        self.dailyTokenCap = dailyTokenCap
        self.perUserCap = perUserCap
        self.perUserWindow = perUserWindow
    }

    /// Atomically reserves a slot for `key`/`user` if it is off cooldown, under the in-flight cap,
    /// within the per-user attempt budget, and within the global daily token budget. On `.reserved`
    /// the caller owns one in-flight slot and must `release()` it exactly once — passing the `user`
    /// and `refundingUser: true` if the reservation produced no billable answer. `user` is the
    /// identity budget bucket (across channels); `key` is the per-channel cooldown bucket.
    func reserve(key: String, user: String = "global", now: Date = Date()) -> ReserveResult {
        rolloverIfNeeded(now: now)
        sweepExpired(now: now)

        if tokensInWindow >= dailyTokenCap {
            return .overBudget
        }
        if let until = cooldownUntil[key], until > now {
            return .cooldown
        }

        var userBudget = perUser[user] ?? (start: now, count: 0)
        if now.timeIntervalSince(userBudget.start) > perUserWindow {
            userBudget = (start: now, count: 0)
        }
        if userBudget.count >= perUserCap {
            return .overBudget
        }

        if inFlight >= maxInFlight {
            return .overCapacity
        }

        cooldownUntil[key] = now.addingTimeInterval(cooldown)
        inFlight += 1
        userBudget.count += 1
        perUser[user] = userBudget
        return .reserved
    }

    /// Releases one in-flight slot. Idempotent-safe against underflow. When the reservation produced
    /// no billable answer (relevance gate rejected it, or the pipeline threw), pass the `user` as
    /// `refundingUser` to roll back that user's attempt count so idle chatter can't lock a real
    /// questioner out of their per-user budget.
    func release(refundingUser user: String? = nil) {
        inFlight = max(0, inFlight - 1)
        if let user, var budget = perUser[user] {
            budget.count = max(0, budget.count - 1)
            perUser[user] = budget
        }
    }

    /// Commits actual token spend (input + output) against the global daily cost budget, after a
    /// completed answer. The reserve check is a soft ceiling: up to `maxInFlight` answers can be in
    /// flight before any of them records usage, so the cap can overshoot by that bounded amount.
    func recordUsage(tokens: Int, now: Date = Date()) {
        rolloverIfNeeded(now: now)
        tokensInWindow += max(0, tokens)
    }

    /// Test/diagnostic accessor for the current in-flight count.
    var inFlightCount: Int { inFlight }

    /// Test/diagnostic accessor for the number of tracked per-user buckets (for leak testing).
    var trackedUserCount: Int { perUser.count }

    /// Drops expired cooldown entries and stale per-user buckets so neither dictionary grows
    /// unbounded over the bot's uptime (entries are otherwise created per distinct nick forever).
    private func sweepExpired(now: Date) {
        cooldownUntil = cooldownUntil.filter { $0.value > now }
        perUser = perUser.filter { now.timeIntervalSince($0.value.start) <= perUserWindow }
    }

    private func rolloverIfNeeded(now: Date) {
        guard let start = windowStart else {
            windowStart = now
            return
        }
        let elapsed = now.timeIntervalSince(start)
        guard elapsed > AIState.windowLength else { return }
        // Advance by whole windows so the budget boundary doesn't drift forward by the inter-request
        // gap on each rollover (a quiet period must not stretch the window past its length).
        let periods = (elapsed / AIState.windowLength).rounded(.down)
        windowStart = start.addingTimeInterval(periods * AIState.windowLength)
        tokensInWindow = 0
    }
}
