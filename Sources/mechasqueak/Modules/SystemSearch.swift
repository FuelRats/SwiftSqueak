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
import IRCKit
import NIO

class SystemSearch: IRCBotModule {
    var name: String = "SystemSearch"

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @AsyncBotCommand(
        ["search"],
        [.param("system name", "NLTT 48288", .continuous)],
        category: .utility,
        description: "Search for a system in the galaxy database.",
        cooldown: .seconds(30)
    )
    var didReceiveSystemSearchCommand = { command in
        let system = command.parameters.joined(separator: " ")
        
        do {
            let searchResults = try await SystemsAPI.performSearch(forSystem: system)
            
            guard var results = searchResults.data else {
                command.message.error(key: "systemsearch.error", fromCommand: command)
                return
            }

            guard results.count > 0 else {
                command.message.reply(key: "systemsearch.noresults", fromCommand: command)
                return
            }

            let resultString = results.map({
                $0.textRepresentation
            }).joined(separator: ", ")

            command.message.reply(key: "systemsearch.nearestmatches", fromCommand: command, map: [
                "system": system,
                "results": resultString
            ])

        } catch {
            command.message.error(key: "systemsearch.error", fromCommand: command)
        }
    }

    @AsyncBotCommand(
        ["landmark"],
        [.param("system name", "NLTT 48288", .continuous)],
        category: .utility,
        description: "Search for a star system's proximity to known landmarks such as Sol, Sagittarius A* or Colonia.",
        cooldown: .seconds(30)
    )
    var didReceiveLandmarkCommand = { command in
        var system = command.parameters.joined(separator: " ")
        if system.lowercased().starts(with: "near ") {
            system.removeFirst(5)
        }
        
        if let autocorrect = ProceduralSystem.correct(system: system) {
            system = autocorrect
        }
        
        do {
            let result = try await SystemsAPI.performSystemCheck(forSystem: system)
            
            guard let landmarkDescription = result.landmarkDescription else {
                command.message.reply(key: "landmark.noresults", fromCommand: command, map: [
                    "system": system
                ])
                return
            }
            command.message.reply(message: result.info)
        } catch {
            command.message.reply(key: "landmark.noresults", fromCommand: command, map: [
                "system": system
            ])
        }
    }
    
    @AsyncBotCommand(
        ["distance", "distanceto"],
        [.param("departure system", "NLTT 48288"), .param("arrival system", "Sagittarius A*")],
        category: .utility,
        description: "Calculate the distance between two star systems",
        cooldown: .seconds(30)
    )
    var didReceiveDistanceCommand = { command in
        let (depSystem, arrSystem) = command.param2 as! (String, String)
        
        do {
            let (departure, arrival) = try await (SystemsAPI.performSystemCheck(forSystem: depSystem, includeEdsm: false), SystemsAPI.performSystemCheck(forSystem: arrSystem, includeEdsm: false))
            
            guard let depCoords = departure.coordinates, let arrCoords = arrival.coordinates else {
                command.message.error(key: "distance.notfound", fromCommand: command)
                return
            }
            
            let distance = arrCoords.distance(from: depCoords)
            let formatter = NumberFormatter.englishFormatter()
            
            let positionsAreApproximated = departure.landmark == nil || arrival.landmark == nil
            
            var key = positionsAreApproximated ? "distance.resultapprox" : "distance.result"
            command.message.reply(key: key, fromCommand: command, map: [
                "departure": departure.name,
                "arrival": arrival.name,
                "distance": formatter.string(from: distance)!
            ])
        } catch {
            command.message.error(key: "distance.error", fromCommand: command)
        }
    }
    
    @AsyncBotCommand(
        ["station"],
        [.param("reference system", "Sagittarius A*", .continuous), .options(["s", "l"])],
        category: .utility,
        description: "Get the nearest station to a system",
        cooldown: .seconds(30)
    )
    var didReceiveStationCommand = { command in
        do {
            let response = try await SystemsAPI.getNearestStations(forSystem: command.param1!)
            
            let requireLargePad = command.options.contains("l")
            
            guard
                let system = requireLargePad ? response.largePadSystem : response.preferableSystem,
                let station = requireLargePad ? system.largePadStation : system.preferableStation
            else {
                command.message.error(key: "station.notfound", fromCommand: command)
                return
            }
            
            command.message.reply(message: try! stencil.renderLine(name: "station.stencil", context: [
                "system": system,
                "station": station,
                "travelTime": station.distance.distanceToSeconds(destinationGravity: true).timeSpan,
                "services": station.allServices,
                "notableServices": station.notableServices,
                "stationType": station.type.rawValue,
                "showAllServices": command.options.contains("s"),
                "additionalServices": station.services.count - station.notableServices.count
            ]))
        } catch {
            command.error(error)
        }
    }
}
