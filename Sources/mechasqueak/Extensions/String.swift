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

extension Character {
    var value: Int32 {
        return Int32(String(self).unicodeScalars.first!.value)
    }
    var isSpace: Bool {
        return isspace(value) != 0
    }
    var isAlphanumeric: Bool {
        return isalnum(value) != 0 || self == "_"
    }
}

extension String {
    subscript (index: Int) -> Character {
        return self[self.index(self.startIndex, offsetBy: index)]
    }
    
    init (localized keyAndValue: String.LocalizationValue, table: String? = nil, command: IRCBotCommand, comment: StaticString? = nil) {
        let locale = command.locale
        let path = Bundle.module.path(forResource: locale.languageCode, ofType: "lproj")
        let bundle = Bundle(path: path ?? "") ?? Bundle.module
        self.init(localized: keyAndValue, table: table, bundle: bundle, locale: locale, comment: comment)
    }
    
    init (localized keyAndValue: String.LocalizationValue, locale: Locale = Locale.current, comment: StaticString? = nil) {
        let path = Bundle.module.path(forResource: locale.languageCode, ofType: "lproj")
        let bundle = Bundle(path: path ?? "") ?? Bundle.module
        self.init(localized: keyAndValue, bundle: bundle, locale: locale, comment: comment)
    }
}

extension AttributedString {
    init (localized keyAndValue: String.LocalizationValue, command: IRCBotCommand, comment: StaticString? = nil) {
        let locale = command.locale
        let path = Bundle.module.path(forResource: locale.languageCode, ofType: "lproj")
        let bundle = Bundle(path: path ?? "") ?? Bundle.module
        self.init(localized: keyAndValue, bundle: bundle, locale: locale, comment: comment)
    }
    
    var ircFormattedString: String {
        var output = ""
        for run in self.runs {
            var text = String(self.characters[run.range])
            print(run.attributes)
        }
        return ""
    }
}

extension String {
    public func levenshtein (_ other: String) -> Int {
        let a = self
        let b = other
        if (a.count == 0) {
            return b.count
        }
        if (b.count == 0) {
            return a.count
        }

        // Create an empty distance matrix with dimensions len(a)+1 x len(b)+1
        var dists = Array(repeating: Array(repeating: 0, count: b.count+1), count: a.count+1)

        // a's default distances are calculated by removing each character
        for i in 1...(a.count) {
            dists[i][0] = i
        }
        // b's default distances are calulated by adding each character
        for j in 1...(b.count) {
            dists[0][j] = j
        }

        // Find the remaining distances using previous distances
        for i in 1...(a.count) {
            for j in 1...(b.count) {
                // Calculate the substitution cost
                let cost = (a[i-1] == b[j-1]) ? 0 : 1

                dists[i][j] = Swift.min(
                    // Removing a character from a
                    dists[i-1][j] + 1,
                    // Adding a character to b
                    dists[i][j-1] + 1,
                    // Substituting a character from a to b
                    dists[i-1][j-1] + cost
                )
            }
        }
        return dists.last!.last!
    }

    var strippingNonAlphanumeric: String {
        return self.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }

    var strippingNonLetters: String {
        return self.components(separatedBy: CharacterSet.letters.inverted).joined()
    }

    func excerpt (maxLength: Int) -> String {
        if maxLength > 3 && self.count > maxLength {
            return self.prefix(maxLength - 2) + ".."
        }
        return self
    }

}

extension Array where Element == String {
    func ircList (separator: String, heading: String = "") -> [String] {
        return self.reduce([String](), { (acc: [String], entry: String) -> [String] in
            var acc = acc
            var entry = entry

            if acc.last == nil {
                entry = heading + entry
            }

            if acc.last == nil || acc.last!.count + separator.count + self.count > 400 {
                acc.append(entry)
                return acc
            }

            acc[acc.count - 1] = acc[acc.count - 1] + separator + entry
            return acc
        })
    }

    var englishList: String {
        guard self.count > 0 else {
            return ""
        }

        guard self.count > 1 else {
            return self[0] + "."
        }

        return self.dropLast(1).joined(separator: ", ") + " and " + self.last! + "."
    }
}

extension StringProtocol {
    var firstCapitalized: String { prefix(1).capitalized + dropFirst() }
}
