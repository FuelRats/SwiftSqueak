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

/// Aggregated counters for the AI assistant, updated as requests flow through. Actor-isolated so
/// the concurrent listener tasks can increment safely.
actor AIMetrics {
    struct Snapshot: Sendable, Equatable {
        var gatePassed = 0
        var gateRejected = 0
        var gateFailures = 0
        var answers = 0
        var refusals = 0
        var toolRounds = 0
        var timeouts = 0
        var pipelineErrors = 0
        var overBudget = 0
        var overCapacity = 0
        var inputTokens = 0
        var outputTokens = 0
        var cacheReadTokens = 0
        var cacheWriteTokens = 0
    }

    private var snapshot = Snapshot()

    func recordGate(passed: Bool) {
        if passed {
            snapshot.gatePassed += 1
        } else {
            snapshot.gateRejected += 1
        }
    }

    /// The paid gate classification itself failed (upstream outage) — the signal that the bot is
    /// silently dropping questions, not that people stopped asking.
    func recordGateFailure() { snapshot.gateFailures += 1 }
    func recordTimeout() { snapshot.timeouts += 1 }
    func recordPipelineError() { snapshot.pipelineErrors += 1 }
    func recordOverBudget() { snapshot.overBudget += 1 }
    func recordOverCapacity() { snapshot.overCapacity += 1 }

    func recordAnswer(_ reply: AIReply) {
        if reply.refused {
            snapshot.refusals += 1
        } else {
            snapshot.answers += 1
        }
        snapshot.toolRounds += reply.toolRounds
    }

    /// Records token spend from any paid call (the gate as well as each answer round), so the summary
    /// reflects total cost, not just the answer pipeline.
    func recordUsage(_ usage: LLMUsage) {
        snapshot.inputTokens += usage.inputTokens
        snapshot.outputTokens += usage.outputTokens
        snapshot.cacheReadTokens += usage.cacheReadInputTokens
        snapshot.cacheWriteTokens += usage.cacheCreationInputTokens
    }

    var current: Snapshot { snapshot }

    /// One-line summary for periodic ops logging; `reset()` zeroes the window afterward so each line
    /// reads as "since the last report" and a spike or outage stands out.
    func summary() -> String {
        let snap = snapshot
        return "gate=\(snap.gatePassed)/\(snap.gatePassed + snap.gateRejected) gateFail=\(snap.gateFailures) "
            + "answers=\(snap.answers) refusals=\(snap.refusals) rounds=\(snap.toolRounds) "
            + "timeouts=\(snap.timeouts) errors=\(snap.pipelineErrors) "
            + "overBudget=\(snap.overBudget) overCapacity=\(snap.overCapacity) "
            + "in=\(snap.inputTokens) out=\(snap.outputTokens) "
            + "cacheR=\(snap.cacheReadTokens) cacheW=\(snap.cacheWriteTokens)"
    }

    func reset() { snapshot = Snapshot() }
}
