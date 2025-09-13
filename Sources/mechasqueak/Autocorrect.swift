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

func autocorrect(system: StarSystem) -> StarSystem {
    var system = system

    let systemName = system.name
    if let systemForNamedBody = namedBodies[systemName.lowercased()] {
        system.name = systemForNamedBody
        system.clientProvidedBody = systemName
        system.automaticallyCorrected = true
    } else if let procedural = ProceduralSystem(string: systemName),
        let correction = ProceduralSystem.correct(system: systemName) {
        system.name = correction
        if let body = procedural.systemBody {
            system.clientProvidedBody = body
        }
        system.automaticallyCorrected = true
    } else if let systemBodiesMatches = ProceduralSystem.systemBodyPattern.findFirst(
        in: system.name) {
        system.name.removeLast(systemBodiesMatches.matched.count)
        let body = systemBodiesMatches.matched.trimmingCharacters(in: .whitespaces)
        system.clientProvidedBody = body
        system.automaticallyCorrected = true
    }

    if let handauthoredCorrection = HandauthoredCorrection.correct(systemName: system.name),
        handauthoredCorrection != systemName {
        system.name = handauthoredCorrection
        system.automaticallyCorrected = true
    }
    return system
}

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
    var systemBody: String?

    struct CubeID: CustomStringConvertible {
        var part1: Character
        var part2: Character
        var suffix: Character

        var description: String {
            return "\(part1)\(part2)-\(suffix)"
        }
    }

    init?(string systemName: String) {
        var systemName = systemName.uppercased()
        var hasSectorSuffix = false

        let components = systemName.components(separatedBy: CharacterSet.alphanumerics.inverted)
        guard components.count > 2 && components[0].contains("-") == false else {
            return nil
        }
        // Extract sector logic
        var proceduralStart: String.Index?
        proceduralStart = ProceduralSystem.extractSectorName(from: &systemName, hasSectorSuffix: &hasSectorSuffix)
        self.hasSectorSuffix = hasSectorSuffix

        let hyphenIndex = systemName.firstIndex(of: "-")
        if hyphenIndex != nil && proceduralStart == nil {
            proceduralStart =
                systemName.range(
                    of: " ", options: .backwards, range: systemName.startIndex..<hyphenIndex!)?
                .lowerBound
        }
        guard var proceduralStart = proceduralStart else {
            return nil
        }

        if systemName[systemName.index(after: proceduralStart)] == "-" {
            guard
                let adjustStart = systemName.range(
                    of: " ", options: .backwards, range: systemName.startIndex..<proceduralStart)
            else {
                return nil
            }
            proceduralStart = adjustStart.lowerBound
        }

        var procedural = String(
            systemName[systemName.index(after: proceduralStart)..<systemName.endIndex]
        ).trimmingCharacters(in: .whitespaces)
        var sectorName = String(systemName[systemName.startIndex..<proceduralStart])
            .trimmingCharacters(in: .whitespaces)

        while (procedural.components(separatedBy: " ").count < 2
            || sectorName.components(separatedBy: " ").last?.count == 3)
            && sectorName.components(separatedBy: " ").count > 1
            && procedural.components(separatedBy: " ").first?.contains("-") == false {
            proceduralStart =
                systemName.range(
                    of: " ", options: .backwards, range: systemName.startIndex..<proceduralStart)!
                .lowerBound
            procedural = String(
                systemName[systemName.index(after: proceduralStart)..<systemName.endIndex]
            ).trimmingCharacters(in: .whitespaces)
            sectorName = String(systemName[systemName.startIndex..<proceduralStart])
                .trimmingCharacters(in: .whitespaces)
        }

        self.sectorName = sectorName
        var proceduralComponents = procedural.components(
            separatedBy: CharacterSet.alphanumerics.inverted
        ).filter({ $0.count > 0 })

        guard proceduralComponents.count > 2 && proceduralComponents.first!.count > 1 else {
            return nil
        }
        // Use helper for cubeId
        guard let cubeId = ProceduralSystem.parseCubeID(from: &proceduralComponents) else {
            return nil
        }
        self.cubeId = cubeId

        if proceduralComponents.count > 0 && proceduralComponents[0].count == 0 {
            proceduralComponents.removeFirst()
        }

        guard let (massCategory, cubePosition) = parseMassCategoryAndCubePosition(from: &proceduralComponents) else {
            return nil
        }
        self.massCategory = massCategory
        self.cubePosition = cubePosition

        self.systemId = ProceduralSystem.parseSystemId(from: &proceduralComponents)
        if proceduralComponents.count > 0 {
            let remaining = " " + proceduralComponents.joined(separator: " ")
            if let systemBody = ProceduralSystem.systemBodyPattern.findFirst(in: remaining) {
                self.systemBody = systemBody.matched.trimmingCharacters(in: .whitespaces)
            }
        }
    }

    // MARK: - Helper Methods for ProceduralSystem

    private static func extractSectorName(from systemName: inout String, hasSectorSuffix: inout Bool) -> String.Index? {
        var proceduralStart: String.Index?
        if let sectorComponent = systemName.components(separatedBy: CharacterSet.alphanumerics.inverted).first(where: {
            $0.count > 3 && $0.lowercased().levenshtein("sector") <= 2
        }) {
            let sectorRange = systemName.range(of: sectorComponent)!
            if sectorRange.lowerBound > systemName.startIndex && sectorRange.upperBound < systemName.endIndex {
                hasSectorSuffix = true
                proceduralStart = systemName.index(before: sectorRange.lowerBound)
                systemName.removeSubrange(sectorRange)
            }
        }
        return proceduralStart
    }

    private static func parseCubeID(from components: inout [String]) -> CubeID? {
        guard components.count > 0 else { return nil }
        var first = components[0]
        guard first.count >= 2 else { return nil }
        let part1 = first.removeFirst()
        let part2 = first.removeFirst()
        var suffix: Character? = first.isEmpty ? nil : first.removeFirst()
        components.removeFirst()
        if components.first?.isEmpty == true { components.removeFirst() }
        if suffix == nil, var next = components.first, !next.isEmpty {
            suffix = next.removeFirst()
            components.removeFirst()
        }
        guard let suffixUnwrapped = suffix else { return nil }
        return CubeID(part1: part1, part2: part2, suffix: suffixUnwrapped)
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

    static func correct(system: String) -> String? {
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

    static func performNumberSubstitution(value: String) -> String {
        return String(
            value.map({ (char: Character) -> Character in
                if let substitution = numberSubstitutions[char] {
                    return substitution
                }
                return char
            }))
    }

    static func performLetterSubstitution(value: String) -> String {
        return String(
            value.map({ (char: Character) -> Character in
                if let substitution = letterSubstitutions[char] {
                    return substitution
                }
                return char
            }))
    }

    var isValid: Bool {
        if self.hasSectorSuffix
            && mecha.sectors.contains(where: { $0.name == self.sectorName }) == false {
            return false
        }

        if self.cubeId.part1.isLetter == false || self.cubeId.part2.isLetter == false
            || self.cubeId.suffix.isLetter == false {
            return false
        }

        if ProceduralSystem.validMassCategories.contains(self.massCategory) == false {
            return false
        }

        if self.cubePosition.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) != nil {
            return false
        }
        if let systemId = self.systemId,
            systemId.rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) != nil {
            return false
        }
        return true
    }

    var corrected: ProceduralSystem? {
        if mecha.sectors.count < 1 {
            return nil
        }
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

        if (system.sectorName.count > 7 && lastDistance < 3) || lastDistance < 2 {
            system.sectorName = lastCorrection.name
            system.hasSectorSuffix = lastCorrection.hasSector
        }

        if system.cubeId.part1.isLetter == false {
            system.cubeId.part1 = ProceduralSystem.performNumberSubstitution(
                value: String(system.cubeId.part1)
            ).first!
        }
        if system.cubeId.part2.isLetter == false {
            system.cubeId.part2 = ProceduralSystem.performNumberSubstitution(
                value: String(system.cubeId.part2)
            ).first!
        }
        if system.cubeId.suffix.isLetter == false {
            system.cubeId.suffix = ProceduralSystem.performNumberSubstitution(
                value: String(system.cubeId.suffix)
            ).first!
        }

        if system.massCategory.isLetter == false {
            system.massCategory = ProceduralSystem.performNumberSubstitution(
                value: String(system.massCategory)
            ).first!
        }

        if system.cubePosition.rangeOfCharacter(from: .letters) != nil {
            system.cubePosition = ProceduralSystem.performLetterSubstitution(
                value: system.cubePosition)
        }
        if let systemId = system.systemId, systemId.rangeOfCharacter(from: .letters) != nil {
            system.systemId = ProceduralSystem.performLetterSubstitution(value: systemId)
        }

        if system.isValid == false {
            return nil
        }
        return system
    }
    
    private static func parseSystemId(from components: inout [String]) -> String? {
        var systemId = ""
        while components.count > 0 {
            while let first = components[0].first,
                  first.isNumber || (systemId.isEmpty && letterSubstitutions[first] != nil) {
                systemId.append(first)
                components[0].removeFirst()
            }
            if components[0].isEmpty {
                components.removeFirst()
                if systemId.last == "0" {
                    break
                }
            } else {
                break
            }
        }
        return systemId.isEmpty ? nil : systemId
    }
}

struct HandauthoredCorrection {
    let numberedSectors = ["LTT", "NLTT", "HIP", "LHS", "LFT", "HR", "LAWD"]

    static func correct(systemName: String) -> String? {
        if let numberedSectorMatch = "(LTT|NLTT|HIP|LHS|LFT|HR|LAWD)(?:\\D)?(\\d+)".r!.findFirst(
            in: systemName) {
            return
                "\(numberedSectorMatch.group(at: 1)!.uppercased()) \(numberedSectorMatch.group(at: 2)!)"
        } else if let wiseMatch = "WISE(?:\\D)?([0-9]+)\\D([0-9]+)".r!.findFirst(in: systemName) {
            return "WISE \(wiseMatch.group(at: 1)!)+\(wiseMatch.group(at: 2)!)"
        } else if let lpMatch = "LP(?:\\D)?(\\d+)\\D(\\d+)".r?.findFirst(in: systemName) {
            return "LP \(lpMatch.group(at: 1)!)-\(lpMatch.group(at: 2)!)"
        } else if let cpdMatch = "CPD(?:\\D)?(\\d+)\\D(\\d+)".r?.findFirst(in: systemName) {
            return "CPD-\(cpdMatch.group(at: 1)!) \(cpdMatch.group(at: 2)!)"
        }

        return nil
    }
}

// Helper to parse massCategory and cubePosition from proceduralComponents
private func parseMassCategoryAndCubePosition(from components: inout [String]) -> (Character, String)? {
    guard components.count > 0 else { return nil }

    let massCategory = components[0].removeFirst()
    guard components.count > 0 else { return nil }

    var cubePosition = components[0]
    components.removeFirst()

    if cubePosition.isEmpty, components.count > 0 {
        cubePosition.append(contentsOf: components[0])
        components.removeFirst()
    }

    return (massCategory, cubePosition)
}
