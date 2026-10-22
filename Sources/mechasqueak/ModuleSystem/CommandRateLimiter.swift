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
import IRCKit

/// Limits how fast someone without rat permissions can make the bot act, in channels and private messages alike.
/// Command cooldowns only cover channels, so without this one user could flood the bot's send queue (delaying
/// rescue announcements) or spend its third-party API quota from a private message.
final class CommandRateLimiter: @unchecked Sendable {
    enum Decision: Equatable {
        case allowed
        case limited(notify: Bool)
    }

    static let shared = CommandRateLimiter()

    let window: TimeInterval
    let maximumCommands: Int
    private static let sweepThreshold = 500

    private struct Bucket {
        var times: [Date] = []
        var notified = false
    }

    private struct State {
        var buckets: [String: Bucket] = [:]
        /// The command manager and the fact handler both see every "!" message; the first to ask records the
        /// decision so the second gets the same answer without counting the message twice.
        var decisions: [String: (Date, Decision)] = [:]
    }

    private let state = Locked(State())

    init(window: TimeInterval = 30, maximumCommands: Int = 8) {
        self.window = window
        self.maximumCommands = maximumCommands
    }

    func decision(for message: IRCPrivateMessage, now: Date = Date()) -> Decision {
        guard message.user.hasPermission(permission: .DispatchRead) == false else {
            return .allowed
        }
        let identity = message.user.account.map({ "acct:\($0)" }) ?? "nick:\(message.user.nickname.lowercased())"
        return self.decision(identity: identity, messageId: message.raw.messageId ?? message.raw.label, now: now)
    }

    func decision(identity: String, messageId: String, now: Date = Date()) -> Decision {
        return state.withValue({ state in
            if let (_, decision) = state.decisions[messageId] {
                return decision
            }
            if state.buckets.count > CommandRateLimiter.sweepThreshold
                || state.decisions.count > CommandRateLimiter.sweepThreshold {
                sweep(&state, now: now)
            }

            var bucket = state.buckets[identity] ?? Bucket()
            bucket.times.removeAll(where: { now.timeIntervalSince($0) >= window })
            if bucket.times.isEmpty {
                bucket.notified = false
            }

            let decision: Decision
            if bucket.times.count < maximumCommands {
                bucket.times.append(now)
                decision = .allowed
            } else {
                decision = .limited(notify: bucket.notified == false)
                bucket.notified = true
            }
            state.buckets[identity] = bucket
            // Whoever asks about this message second must not repeat the notice.
            state.decisions[messageId] = (now, decision == .allowed ? .allowed : .limited(notify: false))
            return decision
        })
    }

    private func sweep(_ state: inout State, now: Date) {
        state.buckets = state.buckets.filter({ _, bucket in
            bucket.times.contains(where: { now.timeIntervalSince($0) < window })
        })
        state.decisions = state.decisions.filter({ _, entry in now.timeIntervalSince(entry.0) < window })
    }
}

extension CommandRateLimiter {
    /// Whether to act on `message`; tells the sender once per window when they are being limited.
    func allows(_ message: IRCPrivateMessage, fromCommand command: IRCBotCommand) -> Bool {
        switch self.decision(for: message) {
            case .allowed:
                return true
            case .limited(let notify):
                if notify {
                    message.replyPrivate(key: "command.ratelimited", fromCommand: command)
                }
                return false
        }
    }
}
