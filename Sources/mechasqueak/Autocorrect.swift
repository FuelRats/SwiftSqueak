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
    static let proceduralEndPattern = "^[a-zA-Z]{2,4}[0-9]{1,5}$".r!
    static let systemBodyPattern = "(\\s(?:[A-Ga-g]{1,2}(?: [0-9]{1,2})?))+$".r!
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
    var systemBody: String? = nil
    
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
        if let sectorComponent = components.first(where: { $0.count > 3 && $0.lowercased().levenshtein("sector") <= 2 }) {
            hasSectorSuffix = true
            let sectorRange = systemName.range(of: sectorComponent)!
            guard sectorRange.lowerBound > systemName.startIndex else {
                return nil
            }
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
        var proceduralComponents = procedural.components(separatedBy: CharacterSet.alphanumerics.inverted).filter({ $0.count > 0 })
        
        guard proceduralComponents.count > 2 && proceduralComponents.first!.count > 1 else {
            return nil
        }
        let part1: Character = proceduralComponents[0].removeFirst()
        let part2: Character = proceduralComponents[0].removeFirst()
        var suffix: Character? = proceduralComponents[0].count > 0 ? proceduralComponents[0].removeFirst() : nil
        proceduralComponents.removeFirst()
        if proceduralComponents[0].count == 0 {
            proceduralComponents.removeFirst()
        }
        
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
            proceduralComponents.removeFirst()
        }
        self.cubePosition = cubePosition
        
        var systemId = ""
        while proceduralComponents.count > 0 {
            let comp = proceduralComponents[0]
            if comp.allSatisfy({ $0.isNumber }) == false {
                break
            }
            systemId += comp
            proceduralComponents.removeFirst()
        }
        if systemId.count > 0 {
            self.systemId = systemId
        }
        if proceduralComponents.count > 0 {
            let remaining = " " + proceduralComponents.joined(separator: " ")
            if let systemBody = ProceduralSystem.systemBodyPattern.findFirst(in: remaining) {
                self.systemBody = systemBody.matched.trimmingCharacters(in: .whitespaces)
            }
        }
        if ProceduralSystem.proceduralSystemExpression.matches(self.description) == false {
            return nil
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
        if self.hasSectorSuffix && mecha.sectors.contains(where: { $0.name == self.sectorName }) == false {
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
    
    var corrected: ProceduralSystem? {
        var system = self
        var lastDistance = self.sectorName.levenshtein(mecha.sectors[0].name)
        var lastCorrection = mecha.sectors[0]

        for entry in mecha.sectors {
            let distance = system.sectorName.levenshtein(entry.name)
            if distance < lastDistance {
                lastDistance = distance
                lastCorrection = entry
            }
        }

        if lastDistance < 4 {
            system.sectorName = lastCorrection.name
            system.hasSectorSuffix = lastCorrection.hasSector
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
//        if let systemId = system.systemId, systemId.rangeOfCharacter(from: .letters) != nil {
//            system.systemId = ProceduralSystem.performLetterSubstitution(value: systemId)
//        }
        
        if system.isValid == false {
            return nil
        }
        return system
    }
}
