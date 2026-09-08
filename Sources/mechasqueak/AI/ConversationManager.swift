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

/// Multi-turn memory for the AI assistant. Sessions are keyed by the authenticated account only —
/// nicks are spoofable, so unidentified users get no cross-message memory (each request is
/// stateless). Each session holds a bounded, recent window of turns and expires after an idle TTL;
/// expired sessions are swept lazily on access.
actor ConversationManager {
    private struct Session {
        var turns: [AITurn]
        var lastActivity: Date
    }

    private var sessions: [String: Session] = [:]
    private let maxTurns: Int
    private let ttl: TimeInterval

    init(maxTurns: Int = 6, ttl: TimeInterval = 300) {
        self.maxTurns = maxTurns
        self.ttl = ttl
    }

    /// Prior turns to replay for this account, or an empty history for an unidentified user.
    func history(account: String?, now: Date = Date()) -> [AITurn] {
        sweep(now: now)
        guard let account, let session = sessions[account] else { return [] }
        return session.turns
    }

    /// Appends a completed exchange. No-op for unidentified users (stateless).
    func record(account: String?, question: String, answer: String, now: Date = Date()) {
        guard let account else { return }
        var session = sessions[account] ?? Session(turns: [], lastActivity: now)
        session.turns.append(AITurn(role: .user, text: question))
        session.turns.append(AITurn(role: .assistant, text: answer))
        if session.turns.count > maxTurns {
            session.turns.removeFirst(session.turns.count - maxTurns)
        }
        session.lastActivity = now
        sessions[account] = session
    }

    /// Number of live sessions (test/diagnostic).
    var sessionCount: Int { sessions.count }

    private func sweep(now: Date) {
        sessions = sessions.filter { now.timeIntervalSince($0.value.lastActivity) <= ttl }
    }
}
