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

extension String {
    subscript (index: Int) -> Character {
        return self[self.index(self.startIndex, offsetBy: index)]
    }
}

extension String {
    public func levenshtein (_ other: String) -> Int {
        let sCount = self.count
        let oCount = other.count

        guard sCount != 0 else {
            return oCount
        }

        guard oCount != 0 else {
            return sCount
        }

        let line: [Int]  = Array(repeating: 0, count: oCount + 1)
        var mat: [[Int]] = Array(repeating: line, count: sCount + 1)

        for iter in 0...sCount {
            mat[iter][0] = iter
        }

        for iter2 in 0...oCount {
            mat[0][iter2] = iter2
        }

        for iter in 1...oCount {
            for iter2 in 1...sCount {
                if self[iter - 1] == other[iter2 - 1] {
                    mat[iter][iter2] = mat[iter - 1][iter2 - 1]       // no operation
                } else {
                    let del = mat[iter - 1][iter2] + 1         // deletion
                    let ins = mat[iter][iter2 - 1] + 1         // insertion
                    let sub = mat[iter - 1][iter2 - 1] + 1     // substitution
                    mat[iter][iter2] = min(min(del, ins), sub)
                }
            }
        }

        return mat[sCount][oCount]
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
}
