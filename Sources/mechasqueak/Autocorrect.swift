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

struct ProceduralSystem: CustomStringConvertible {
    static let proceduralSystemExpression =
        "([\\w\\s'.()/-]+) ([A-Za-z])([A-Za-z])-([A-Za-z]) ([A-Za-z])(?:(\\d+)-)?(\\d+)".r!
    static let validMassCategories = "ABCDEFGH"
    private static let numberSubstitutions: [Character: Character] = [
        "1": "I",
        "4": "A",
        "5": "S",
        "8": "B",
        "0": "O"
    ]
    private static let letterSubstitutions: [Character: Character] = [
        "L": "1",
        "I": "1",
        "S": "5",
        "B": "8",
        "D": "0",
        "O": "0",
        "A": "4"
    ]
    
    var sectorName: String
    var hasSectorSuffix: Bool
    
    var cubeId: CubeID
    
    var massCategory: Character
    var cubePosition: String
    var systemId: String?
    
    struct CubeID: CustomStringConvertible {
        var part1: Character
        var part2: Character
        var suffix: Character
        
        var description: String {
            return "\(part1)\(part2)-\(suffix)"
        }
    }
    
    init? (string systemName: String) {
        var systemName = systemName.uppercased()
        
        var hasSectorSuffix = false
        
        let components = systemName.components(separatedBy: CharacterSet.alphanumerics.inverted)
        guard components.count > 2 && components[0].contains("-") == false else {
            return nil
        }
        var proceduralStart: String.Index? = nil
        if let sectorComponent = components.first(where: { $0.lowercased().levenshtein("sector") <= 3 }) {
            hasSectorSuffix = true
            let sectorRange = systemName.range(of: sectorComponent)!
            proceduralStart = systemName.index(before: sectorRange.lowerBound)
            systemName.removeSubrange(sectorRange)
        }
        self.hasSectorSuffix = hasSectorSuffix
        
        let hyphenIndex = systemName.firstIndex(of: "-")
        if hyphenIndex != nil && proceduralStart == nil {
            proceduralStart = systemName.range(of: " ", options: .backwards, range: systemName.startIndex..<hyphenIndex!)?.lowerBound
        }
        guard proceduralStart != nil else {
            return nil
        }
        
        self.sectorName = String(systemName[systemName.startIndex..<proceduralStart!]).trimmingCharacters(in: .whitespaces)
        let proceduralStartIndex = systemName.index(after: proceduralStart!)
        let procedural = String(systemName[proceduralStartIndex..<systemName.endIndex]).trimmingCharacters(in: .whitespaces)
        var proceduralComponents = procedural.components(separatedBy: CharacterSet.alphanumerics.inverted)
        
        guard proceduralComponents.count > 2 && proceduralComponents.first!.count > 1 else {
            return nil
        }
        let part1: Character = proceduralComponents[0].removeFirst()
        let part2: Character = proceduralComponents[0].removeFirst()
        var suffix: Character? = proceduralComponents[0].count > 0 ? proceduralComponents[0].removeFirst() : nil
        proceduralComponents.removeFirst()
        
        if suffix == nil {
            suffix = proceduralComponents[0].removeFirst()
            proceduralComponents.removeFirst()
        }
        self.cubeId = CubeID(part1: part1, part2: part2, suffix: suffix!)
        
        guard proceduralComponents.count > 1 else {
            return nil
        }
        
        if proceduralComponents[0].count == 0 {
            proceduralComponents.removeFirst()
        }
        self.massCategory = proceduralComponents[0].removeFirst()
        var cubePosition: String = proceduralComponents[0]
        proceduralComponents.removeFirst()
        if cubePosition.count == 0 {
            cubePosition.append(proceduralComponents[0])
            if proceduralComponents[0].count > 0 {
                proceduralComponents[0].removeFirst()
            } else {
                proceduralComponents.removeFirst()
            }
        }
        self.cubePosition = cubePosition
        
        if proceduralComponents.count > 0 {
            self.systemId = proceduralComponents[0]
        }
    }
    
    var description: String {
        var system = sectorName
        if hasSectorSuffix {
            system += " SECTOR"
        }
        system += " \(cubeId) \(massCategory)\(cubePosition)"
        if let systemId = systemId {
            system += "-\(systemId)"
        }
        return system
    }
    
    static func correct (system: String) -> String? {
        if let procedural = ProceduralSystem(string: system), let correction = procedural.corrected {
            if correction.description != system {
                let correctionName = correction.description
                if correctionName != system {
                    return correctionName
                }
            }
        }
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

    static func performLetterSubstitution (value: String) -> String {
        return String(value.map({ (char: Character) -> Character in
            if let substitution = letterSubstitutions[char] {
                return substitution
            }
            return char
        }))
    }
    
    var isValid: Bool {
        if self.hasSectorSuffix && sectors.contains(where: { $0.name == self.sectorName }) == false {
            return false
        }
        
        if self.cubeId.part1.isLetter == false || self.cubeId.part2.isLetter == false || self.cubeId.suffix.isLetter == false {
            return false
        }
        
        if ProceduralSystem.validMassCategories.contains(self.massCategory) == false {
            return false
        }
        
        if self.cubePosition.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) != nil {
            return false
        }
        if let systemId = self.systemId, systemId.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) != nil {
            return false
        }
        return true
    }
    
    // TRIANGULI SECTOR AB-N A7-0
    var corrected: ProceduralSystem? {
        var system = self
        if system.hasSectorSuffix {
            var lastDistance = self.sectorName.levenshtein(sectors[0].name)
            var lastCorrection = sectors[0]

            for entry in sectors {
                let distance = system.sectorName.levenshtein(entry.name)
                if distance < lastDistance || (distance == lastDistance && entry.count > lastCorrection.count) {
                    lastDistance = distance
                    lastCorrection = entry
                }
            }

            system.sectorName = lastCorrection.name
        }
        
        if system.cubeId.part1.isLetter == false {
            system.cubeId.part1 = ProceduralSystem.performNumberSubstitution(value: String(system.cubeId.part1)).first!
        }
        if system.cubeId.part2.isLetter == false {
            system.cubeId.part2 = ProceduralSystem.performNumberSubstitution(value: String(system.cubeId.part2)).first!
        }
        if system.cubeId.suffix.isLetter == false {
            system.cubeId.suffix = ProceduralSystem.performNumberSubstitution(value: String(system.cubeId.suffix)).first!
        }
        
        if system.massCategory.isLetter == false {
            system.massCategory = ProceduralSystem.performNumberSubstitution(value: String(system.massCategory)).first!
        }
        
        if system.cubePosition.rangeOfCharacter(from: .letters) != nil {
            system.cubePosition = ProceduralSystem.performLetterSubstitution(value: system.cubePosition)
        }
        if let systemId = system.systemId, systemId.rangeOfCharacter(from: .letters) != nil {
            system.systemId = ProceduralSystem.performLetterSubstitution(value: systemId)
        }
        
        if system.isValid == false {
            return nil
        }
        return system
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
