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

class Autocorrect {
    private static let proceduralSystemExpression =
        "([\\w\\s'.()/-]+) ([A-Za-z])([A-Za-z])-([A-Za-z]) ([A-Za-z])(?:(\\d+)-)?(\\d+)".r!
    private static let numberSubstitutions: [Character: Character] = [
        "1": "L",
        "4": "A",
        "5": "S",
        "8": "B",
        "0": "O"
    ]
    private static let letterSubstitutions: [Character: Character] = [
        "L": "1",
        "S": "5",
        "B": "8",
        "D": "0",
        "O": "0",
        "A": "4"
    ]

    static func check (system: String) -> String? {
        let system = system.uppercased()

        guard system.contains(" SECTOR ") else {
            // Not a special system, and not a sector system, nothing we can do with this input
            return nil
        }

        let components = system.components(separatedBy: " SECTOR ")
        guard components.count == 2 else {
            // Only the sector itself was entered nothing after it, there is nothing we can do here, exit
            return nil
        }
 
        var sector = components[0]
        var fragments = components[1].components(separatedBy: " ")
        if sectors.contains(where: { $0.name == sector }) == false {
            var lastDistance = sector.levenshtein(sectors[0].name)
            var lastCorrection = sectors[0]

            for entry in sectors {
                let distance = sector.levenshtein(entry.name)
                if distance < lastDistance || (distance == lastDistance && entry.count > lastCorrection.count) {
                    lastDistance = distance
                    lastCorrection = entry
                }
            }

            sector = lastCorrection.name
        }

        let sectorCorrectedSystem = "\(sector) SECTOR \(fragments.joined(separator: " "))"
        if proceduralSystemExpression.findFirst(in: system) != nil && system != sectorCorrectedSystem {
            // If the last part of the system name looks correct, return it with corrected sector name
            return sectorCorrectedSystem
        }

        /* This section of procedural system names do never contain digits, if there are one, replace them with letters
         that are commonly mistaken for these numbers. */
        if fragments[0].rangeOfCharacter(from: .decimalDigits) != nil {
            fragments[0] = Autocorrect.performNumberSubstitution(value: fragments[0])
        }
        var secondFragment = fragments[1]
        if secondFragment.first!.isNumber {
            /*  The first character of the second fragment of a procedural system name is always a letter.
             If it is a number in the input, replace it with letters that are commonly mistaken for numbers.  */
            secondFragment = secondFragment.replacingCharacters(
                in: ...secondFragment.startIndex,
                with: Autocorrect.performNumberSubstitution(value: String(secondFragment.first!))
            )
            fragments[1] = secondFragment
        }

        let correctedSystem = "\(sector) SECTOR \(fragments.joined(separator: " "))"

        // Check that our corrected name now passes the check for valid procedural system
        if proceduralSystemExpression.findFirst(in: correctedSystem) != nil && system != correctedSystem {
            return correctedSystem
        }

        // We were not able to correct this
        return nil
    }

    static func performNumberSubstitution (value: String) -> String {
        return String(value.map({ (char: Character) -> Character in
            if let substitution = numberSubstitutions[char] {
                return substitution
            }
            return char
        }))
    }

    static func performLetterrSubstitution (value: String) -> String {
        return String(value.map({ (char: Character) -> Character in
            if let substitution = letterSubstitutions[char] {
                return substitution
            }
            return char
        }))
    }
}

func loadSectors () -> [StarSector] {
    let sectorPath = URL(
        fileURLWithPath: FileManager.default.currentDirectoryPath
    ).appendingPathComponent("sectors.json")

    guard let sectorData = try? Data(contentsOf: sectorPath) else {
        fatalError("Could not locate sector file in \(sectorPath.absoluteString)")
    }

    let sectorDecoder = JSONDecoder()
    return try! sectorDecoder.decode([StarSector].self, from: sectorData)
}

let sectors = loadSectors()

struct StarSector: Codable {
    let name: String
    let count: Int
}
