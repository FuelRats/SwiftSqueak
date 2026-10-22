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

extension String {
    /// Matches highlight words rats, ops and techs are pinged on: RATSIGNAL, OPSIGNAL, TECHSIGNAL and the platform
    /// signals (XB_SIGNAL, PS_SIGNAL, LEG_SIGNAL, HOR_SIGNAL, ODY_SIGNAL).
    private static let highlightSignalPattern = try? NSRegularExpression(
        pattern: "(rat|op|tech|[a-z]{2,3}_)(signal)", options: [.caseInsensitive])

    /// IRC formatting and control characters that relayed text must not carry. Bold (0x02) is kept because the AI
    /// formatter emits it for emphasis; everything else (CTCP 0x01, colour 0x03, reset 0x0F, reverse 0x16, ...) is not.
    private static func isRelayControl(_ scalar: Unicode.Scalar) -> Bool {
        return (scalar.value < 0x20 && scalar != "\u{02}") || scalar.value == 0x7F
    }

    /**
     Prepares text the bot relays but did not write (LLM answers, translations) for IRC: line breaks become spaces,
     control codes that could make it CTCP or restyle the channel are removed, and highlight words get a zero-width
     space so relaying them can't ping every rat. The text reads the same.
     */
    func sanitizedForRelay() -> String {
        let flattened = String(String.UnicodeScalarView(self.unicodeScalars.compactMap({ scalar -> Unicode.Scalar? in
            if scalar.properties.isWhitespace && (scalar.value < 0x20 || scalar == "\u{2028}" || scalar == "\u{2029}") {
                return scalar == "\t" ? scalar : " "
            }
            return String.isRelayControl(scalar) ? nil : scalar
        })))

        guard let pattern = String.highlightSignalPattern else {
            return flattened
        }
        return pattern.stringByReplacingMatches(
            in: flattened, range: NSRange(flattened.startIndex..., in: flattened), withTemplate: "$1\u{200B}$2")
    }
}
