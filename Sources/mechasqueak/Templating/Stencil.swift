/*
 Copyright 2021 The Fuel Rats Mischief
 
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
import Stencil
import IRCKit
import PathKit

private func makeColorFilter() -> (Any?, [Any?]) throws -> Any? {
    return { (value, arguments) in
        if
            let contents = value as? String,
            let colorNumber = arguments.first as? Int,
            let color = IRCColor(rawValue: colorNumber) {
            if
                arguments.count > 1,
                let backgroundColorNumber = arguments[1] as? Int,
                let backgroundColor = IRCColor(rawValue: backgroundColorNumber) {
                return IRCFormat.color(color, background: backgroundColor, contents)
            }
            return IRCFormat.color(color, contents)
        } else {
            throw TemplateSyntaxError("color filter requires a valid irc color")
        }
    }
}

private func makeBoldFilter() -> (Any?) throws -> Any? {
    return { value in
        if let value = value as? String {
            return IRCFormat.bold(value)
        }
        return value
    }
}

private func makeItalicFilter() -> (Any?) throws -> Any? {
    return { value in
        if let value = value as? String {
            return IRCFormat.italic(value)
        }
        return value
    }
}

private func makeFormatNumberFilter() -> (Any?) throws -> Any? {
    return { value in
        if let value = value as? Double {
            return NumberFormatter.englishFormatter().string(from: NSNumber(value: value))!
        }
        return value
    }
}

private func makeRoundFilter() -> (Any?) throws -> Any? {
    return { value in
        if let value = value as? Double {
            return round(value)
        }
        return value
    }
}

private func makeEliteDistanceFilter() -> (Any?) throws -> Any? {
    return { value in
        if let value = value as? Double {
            return value.eliteDistance
        }
        return value
    }
}

private func makeInGameStatusFilter() -> (Any?) throws -> Any? {
    return { value in
        if let rescue = value as? Rescue {
            return rescue.onlineStatus
        }
        return value
    }
}

private func makeMainStarInfoFilter() -> (Any?) throws -> Any? {
    return { value in
        if let system = value as? StarSystem {
            if let mainStar = system.data?.body.includes?[SystemsAPI.Star.self].first(where: {
                $0.isMainStar == true || $0.distanceToArrival == 0.0
            }) {
                if mainStar.spectralClass?.isRefuelable == true {
                    return "\(IRCFormat.bold(mainStar.spectralClass!.rawValue)) \(mainStar.description)"
                }
                return mainStar.description
            }
        }
        return nil
    }
}

private func makeSecondaryFuelStarFilter() -> (Any?) throws -> Any? {
    return { value in
        if let system = value as? StarSystem {
            return system.hasSecondaryFuelStar
        }
        return false
    }
}

private func makeIsUnderAttackFilter() -> (Any?) throws -> Any? {
    return { value in
        if let system = value as? StarSystem {
            return system.isUnderAttack
        }
        return false
    }
}

private func makeLandmarkFilter() -> (Any?) throws -> Any? {
    return { value in
        if let system = value as? StarSystem {
            return system.landmark
        }
        return nil
    }
}

private func makeCardinalFilter() -> (Any?) throws -> Any? {
    return { value in
        if let system = value as? StarSystem {
            if
                let landmark = system.landmark,
                landmark.distance > 1000,
                let searchResult = system.searchResult,
                let landmarkResult = mecha.landmarks.first(where: { $0.name == landmark.name }) {
                return CardinalDirection(
                    bearing: searchResult.coords.bearing(from: landmarkResult.coordinates)
                ).rawValue
            }
        }
        return nil
    }
}

private func makeProceduralInfoFilter() -> (Any?) throws -> Any? {
    return { value in
        if let system = value as? StarSystem {
            if
                let procedural = system.proceduralCheck,
                let sectordata = procedural.sectordata,
                procedural.isPgSystem == true && (procedural.isPgSector == true
                || procedural.sectordata?.handauthored == true) {
                    guard let (landmark, distanceString, _) = procedural.estimatedLandmarkDistance else {
                        return nil
                    }
                
                    guard regions.count == 0 || procedural.galacticRegion != nil else {
                        return nil
                    }
                    guard let estimatedSolDistance = procedural.estimatedSolDistance else {
                        return nil
                    }
                    guard (1000...80000).contains(estimatedSolDistance.2) else {
                        return nil
                    }
                    let cardinal = CardinalDirection(bearing: sectordata.coords.bearing(from: landmark.coordinates))
                    return "Unconfirmed ~\(distanceString) LY \"\(cardinal.rawValue)\" of \(landmark.name)"
            }
        }
        return nil
    }
}

private func makeCaseColorFilter() -> (Any?, [Any?]) throws -> Any? {
    return { (value, arguments) in
        if let value = value as? String, let rescue = arguments[0] as? Rescue {
            if rescue.status == .Inactive {
                return IRCFormat.italic(IRCFormat.color(.Cyan, value))
            } else if rescue.codeRed {
                return IRCFormat.color(.LightRed, value)
            } else {
                return value
            }
        }
        return nil
    }
}

private func makePlatformFilter() -> (Any?) throws -> Any? {
    return { value in
        if let rat = value as? Rat {
            if rat.platform == .PC {
                let platform = rat.attributes.platform.value.ircRepresentable
                let expansion = rat.attributes.expansion.value.ircRepresentable
                return "\(platform) \(expansion)"
            }
            return rat.attributes.platform.value.ircRepresentable
        }
        if let rescue = value as? Rescue {
            return rescue.platformExpansion
        }
        return nil
    }
}

private func makeIsStarterRatFilter() -> (Any?) throws -> Any? {
    return { value in
        if let rat = value as? Rat {
            return rat.data.permits?.contains("Pilots' Federation District")
        }
        return false
    }
}

private func makeNameFilter() -> (Any?) throws -> Any? {
    return { value in
        if let rat = value as? Rat {
            return rat.name
        }
        return nil
    }
}

private func makeIdFilter() -> (Any?) throws -> Any? {
    return { value in
        if let rat = value as? Rat {
            return rat.id.rawValue.ircRepresentation
        }
        return nil
    }
}

private func generateEnvironment () -> Environment {
    let ext = Extension()
    let environment = Environment(
        loader: FileSystemLoader(paths: [Path("templates")]),
        extensions: [ext]
    )
    
    ext.registerFilter("color", filter: makeColorFilter())
    ext.registerFilter("bold", filter: makeBoldFilter())
    ext.registerFilter("italic", filter: makeItalicFilter())
    ext.registerFilter("formatNumber", filter: makeFormatNumberFilter())
    ext.registerFilter("round", filter: makeRoundFilter())
    ext.registerFilter("eliteDistance", filter: makeEliteDistanceFilter())
    ext.registerFilter("inGameStatus", filter: makeInGameStatusFilter())
    ext.registerFilter("mainStarInfo", filter: makeMainStarInfoFilter())
    ext.registerFilter("secondaryFuelStar", filter: makeSecondaryFuelStarFilter())
    ext.registerFilter("isUnderAttack", filter: makeIsUnderAttackFilter())
    ext.registerFilter("landmark", filter: makeLandmarkFilter())
    ext.registerFilter("cardinal", filter: makeCardinalFilter())
    ext.registerFilter("proceduralInfo", filter: makeProceduralInfoFilter())
    ext.registerFilter("caseColor", filter: makeCaseColorFilter())
    ext.registerFilter("platform", filter: makePlatformFilter())
    ext.registerFilter("isStarterRat", filter: makeIsStarterRatFilter())
    ext.registerFilter("name", filter: makeNameFilter())
    ext.registerFilter("id", filter: makeIdFilter())
    
    return environment
}

let stencil = generateEnvironment()

extension Environment {
    func renderLine (name: String, context: [String: Any]) throws -> String {
        return try self.renderTemplate(name: name, context: context)
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "[\\s]+", with: " ", options: .regularExpression, range: nil)
    }
}
