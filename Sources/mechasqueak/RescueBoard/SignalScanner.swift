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

struct SignalScanner {
    private let platformVariations = ["pc", "xbox one", "xbox", "xb1", "xb",
                                      "playstation 4", "playstation", "ps4", "ps"]

    private let crVariations = ["not ok", "code red"]

    let system: String?
    let platform: String?
    let crStatus: String?

    var isCodeRed: Bool {
        if let crText = self.crStatus {
            if crText.contains("not ok") || crText.contains("code red") {
                return true
            }
        }
        return false
    }

    init? (message: String, requireSignal: Bool = false) {
        var punctuationSet = CharacterSet.punctuationCharacters
        punctuationSet.remove(charactersIn: "-")
        var message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        message = message.components(separatedBy: punctuationSet).joined()

        let signalIndex = message.range(of: configuration.general.signal, options: .caseInsensitive)?.upperBound
        if requireSignal == true && signalIndex == nil {
            return nil
        }

        let startIndex = signalIndex ?? message.startIndex

        var systemEndIndex = message.endIndex

        var platformString: String?

        for platform in platformVariations {
            if let range = message.range(of: platform, options: .caseInsensitive) {
                systemEndIndex = range.lowerBound
                platformString = String(message[range])
                break
            }
        }

        self.platform = platformString
        var crString: String?

        for crVariation in crVariations {
            if let range = message.range(of: crVariation, options: .caseInsensitive) {
                crString = String(message[range])
                break
            }
        }

        self.crStatus = crString?.lowercased()


        let system = String(message[startIndex..<systemEndIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        if system.count > 0 {
            self.system = system
        } else {
            self.system = nil
        }
    }
}
