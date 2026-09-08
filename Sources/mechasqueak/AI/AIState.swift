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
/// one pipeline. Also enforces a global in-flight cap and a rolling daily request budget.
actor AIState {
    private let cooldown: TimeInterval
    private let maxInFlight: Int
    private let dailyRequestCap: Int
    private let perUserCap: Int
    private let perUserWindow: TimeInterval

    private var cooldownUntil: [String: Date] = [:]
    private var inFlight = 0
    private var requestsInWindow = 0
    private var windowStart: Date?
    private var perUser: [String: (start: Date, count: Int)] = [:]

    static let windowLength: TimeInterval = 24 * 60 * 60

    init(
        cooldown: TimeInterval = 30,
        maxInFlight: Int = 3,
        dailyRequestCap: Int = 500,
        perUserCap: Int = 60,
        perUserWindow: TimeInterval = 3600
    ) {
        self.cooldown = cooldown
        self.maxInFlight = maxInFlight
        self.dailyRequestCap = dailyRequestCap
        self.perUserCap = perUserCap
        self.perUserWindow = perUserWindow
    }

    /// Atomically reserves a slot for `key`/`user` if it is off cooldown, under the in-flight cap,
    /// within the per-user budget, and within the global daily budget. On `.reserved` the caller
    /// owns one in-flight slot and must `release()` it exactly once. `user` is the identity budget
    /// bucket (across channels); `key` is the per-channel cooldown bucket.
    func reserve(key: String, user: String = "global", now: Date = Date()) -> ReserveResult {
        rolloverIfNeeded(now: now)

        if requestsInWindow >= dailyRequestCap {
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
        requestsInWindow += 1
        userBudget.count += 1
        perUser[user] = userBudget
        return .reserved
    }

    /// Releases one in-flight slot. Idempotent-safe against underflow.
    func release() {
        inFlight = max(0, inFlight - 1)
    }

    /// Test/diagnostic accessor for the current in-flight count.
    var inFlightCount: Int { inFlight }

    private func rolloverIfNeeded(now: Date) {
        guard let start = windowStart else {
            windowStart = now
            return
        }
        if now.timeIntervalSince(start) > AIState.windowLength {
            windowStart = now
            requestsInWindow = 0
        }
    }
}
