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
    subscript(index: Int) -> Character {
        return self[self.index(self.startIndex, offsetBy: index)]
    }
}

extension String {
    public func levenshtein(_ other: String) -> Int {
        let str1 = self
        let str2 = other
        if str1.count == 0 {
            return str2.count
        }
        if str2.count == 0 {
            return str1.count
        }

        // Create an empty distance matrix with dimensions len(a)+1 x len(b)+1
        var dists = Array(repeating: Array(repeating: 0, count: str2.count + 1), count: str1.count + 1)

        // a's default distances are calculated by removing each character
        for distance1 in 1...(str1.count) {
            dists[distance1][0] = distance1
        }
        // b's default distances are calulated by adding each character
        for distance2 in 1...(str2.count) {
            dists[0][distance2] = distance2
        }

        // Find the remaining distances using previous distances
        for distance1 in 1...(str1.count) {
            for distance2 in 1...(str2.count) {
                // Calculate the substitution cost
                let cost = (str1[distance1 - 1] == str2[distance2 - 1]) ? 0 : 1

                dists[distance1][distance2] = Swift.min(
                    // Removing a character from a
                    dists[distance1 - 1][distance2] + 1,
                    // Adding a character to b
                    dists[distance1][distance2 - 1] + 1,
                    // Substituting a character from a to b
                    dists[distance1 - 1][distance2 - 1] + cost
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

    func excerpt(maxLength: Int) -> String {
        if maxLength > 3 && self.count > maxLength {
            return self.prefix(maxLength - 2) + ".."
        }
        return self
    }

}

extension Array where Element == String {
    func ircList(separator: String, heading: String = "") -> [String] {
        return self.reduce(
            [String](),
            { (acc: [String], entry: String) -> [String] in
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
