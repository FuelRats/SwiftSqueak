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

extension Date {
    func timeAgo(
        components: [TimeUnit] = [.year, .month, .day, .hour, .minute, .second],
        maximumUnits: UInt? = nil
    ) -> String {
        let seconds = Double(
            Calendar.current.dateComponents([.second], from: self, to: Date()).second ?? 0)
        return seconds.timeSpan(components: components, maximumUnits: maximumUnits)
    }

    var ircRepresentable: String {
        return DateFormatter.ircFormatter.string(from: self)
    }

    var eliteFormattedString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMMM"
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let dateString = formatter.string(from: self)
        let year = Calendar.current.component(.year, from: self)
        return "\(dateString), \(year + 1286)"
    }
}

extension TimeInterval {
    static func from(string: String) -> TimeInterval? {
        var string = string

        if string == "0" {
            return 3.154 * pow(10, 10)
        }
        let suffix = string.removeLast().lowercased()
        guard let num = Int(string) else {
            return nil
        }

        let seconds = Double(num)

        switch suffix {
        case "s":
            return seconds

        case "m":
            return seconds * 60

        case "h":
            return seconds * 3600

        case "d":
            return seconds * 86400

        case "w":
            return seconds * 604800

        case "y":
            return seconds * 220_903_200

        default:
            return nil
        }
    }
}
