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

extension Locale {
    var englishDescription: String {
        let englishLocale = Locale(identifier: "en-GB")
        return englishLocale.localizedString(forIdentifier: self.identifier) ?? "unknown locale"
    }

    var isValid: Bool {
        let englishLocale = Locale(identifier: "en-GB")
        return englishLocale.localizedString(forIdentifier: self.identifier) != nil
    }

    var short: String {
        return String(self.identifier.prefix(2))
    }

    var flagEmoji: String? {
        // Extract region code from locale identifier like "en-US", "fr_FR"
        let parts = self.identifier.split(whereSeparator: { $0 == "-" || $0 == "_" })
        guard parts.count >= 2,
              let regionPart = parts.last,
              regionPart.count == 2,
              regionPart.allSatisfy({ $0.isLetter })
        else {
            return nil
        }
        let regionCode = regionPart.uppercased()
        let base: UInt32 = 0x1F1E6 - 65 // Regional Indicator Symbol Letter A - 'A'
        var emoji = ""
        for scalar in regionCode.unicodeScalars {
            guard let flagScalar = Unicode.Scalar(base + scalar.value) else {
                return nil
            }
            emoji.unicodeScalars.append(flagScalar)
        }
        return emoji
    }
}
