/*
 Copyright 2020 The Fuel Rats Mischief

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
import Regex

struct SignalScanner {
    private static let platformExpression = "\\b(?:platform(?:\\: )?)?(pc|xbox one|xbox|xb1|xb|playstation(?: 4)?|ps4|ps)\\b".r!
    private static let systemExpression = "\\b(?:system(?:\\: )?)?([A-Z][A-Za-z0-9- ]+)\\b".r!
    private static let oxygenExpression = "\\b(?:(?:o2|oxygen)(?:\\:)? )?(ok|not ok|code red|cr)\\b".r!

    let system: String?
    let platform: String?
    let crStatus: String?

    var isCodeRed: Bool {
        if let crText = self.crStatus {
            if crText.contains("not ok") || crText.contains("code red") || crText.contains("cr") {
                return true
            }
        }
        return false
    }

    init? (message: String, requireSignal: Bool = false) {
        var message = message.trimmingCharacters(in: .whitespacesAndNewlines)

        let signalIndex = message.range(of: configuration.general.signal, options: .caseInsensitive)?.upperBound
        if requireSignal == true && signalIndex == nil {
            return nil
        }
        message = message.replacingOccurrences(
            of: "\(configuration.general.signal)",
            with: "|",
            options: .caseInsensitive
        )


        if let platformMatch = SignalScanner.platformExpression.findFirst(in: message) {
            self.platform = platformMatch.group(at: 1)
            print(platformMatch.group(at: 0)!)
            message = message.replacingOccurrences(of: platformMatch.group(at: 0)!, with: "|", options: .caseInsensitive)
        } else {
            self.platform = nil
        }
        message = message.trimmingCharacters(in: .whitespacesAndNewlines)

        if let oxygenMatch = SignalScanner.oxygenExpression.findFirst(in: message) {
            self.crStatus = oxygenMatch.group(at: 1)?.lowercased()
            message = message.replacingOccurrences(of: oxygenMatch.group(at: 0)!, with: "|", options: .caseInsensitive)
        } else {
            self.crStatus = nil
        }
        message = message.trimmingCharacters(in: .whitespacesAndNewlines)

        if let range = message.range(of: "\\b(?:system(?:\\: )?)?([A-Z][A-Za-z0-9- ]+)\\b", options: .regularExpression) {
            self.system = String(message[range])
        } else {
            self.system = nil
        }
    }
}
