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

    @BotCommand(
        ["search"],
        [.param("system name", "NLTT 48288", .continuous)],
        category: .utility,
        description: "Search for a system in the galaxy database.",
        cooldown: .seconds(30)
    )
    var didReceiveSystemSearchCommand = { command in
        let system = command.parameters.joined(separator: " ")

        let extendedSearchWarningTimer = loop.next().scheduleTask(in: .seconds(45)) {
            command.message.reply(
                key: "systemsearch.long", fromCommand: command,
                map: [
                    "system": system
                ])
        }
        do {
            let searchResults = try await SystemsAPI.performSearch(forSystem: system)
            extendedSearchWarningTimer.cancel()

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

            command.message.reply(
                key: "systemsearch.nearestmatches", fromCommand: command,
                map: [
                    "system": system,
                    "results": resultString,
                ])

        } catch {
            extendedSearchWarningTimer.cancel()
            command.message.error(key: "systemsearch.error", fromCommand: command)
        }
    }

    @BotCommand(
        ["landmark", "sysinfo", "edsm"],
        [.param("system name", "NLTT 48288", .continuous)],
        category: .utility,
        description:
            "Search for a star system's proximity to known landmarks such as Sol, Sagittarius A* or Colonia.",
        cooldown: .seconds(15)
    )
    var didReceiveLandmarkCommand = { command in
        var system = command.parameters.joined(separator: " ")
        if let (_, rescue) = await board.findRescue(
            withCaseIdentifier: system, includingRecentlyClosed: true)
        {
            system = rescue.system?.name ?? system
        }
        if system.lowercased().starts(with: "near ") {
            system.removeFirst(5)
        }
        if system.lowercased() == "seer" {
            command.message.retaliate()
            return
        }

        var starSystem = StarSystem(name: system)

        do {

            var result = try await SystemsAPI.performSystemCheck(forSystem: starSystem.name)
            if result.landmark == nil && result.proceduralCheck?.isPgSystem != true {
                starSystem = autocorrect(system: starSystem)
                result = try await SystemsAPI.performSystemCheck(forSystem: starSystem.name)
            }

            guard let landmarkDescription = result.landmarkDescription else {
                command.message.reply(
                    key: "landmark.noresults", fromCommand: command,
                    map: [
                        "system": system
                    ])
                return
            }
            command.message.reply(message: await result.info)
        } catch {
            print(String(describing: error))
            command.message.reply(
                key: "landmark.noresults", fromCommand: command,
                map: [
                    "system": system
                ])
        }
    }

    @BotCommand(
        ["distance", "plot", "distanceto"],
        [
            .argument("range", "jump range", example: "68"),
            .param("departure system / case id / client name", "NLTT 48288"),
            .param("arrival system / case id / client name", "Sagittarius A*", .continuous),
        ],
        category: .utility,
        description: "Calculate the distance between two star systems",
        cooldown: .seconds(30)
    )
    var didReceiveDistanceCommand = { command in
        var (depSystem, arrSystem) = command.param2 as! (String, String)
        let range = command.argumentValue(for: "range")

        if let (_, rescue) = await board.findRescue(
            withCaseIdentifier: depSystem, includingRecentlyClosed: true)
        {
            depSystem = rescue.system?.name ?? depSystem
        }

        if let (_, rescue) = await board.findRescue(
            withCaseIdentifier: arrSystem, includingRecentlyClosed: true)
        {
            arrSystem = rescue.system?.name ?? arrSystem
        }

        do {
            let (departure, arrival) = try await (
                SystemsAPI.performSystemCheck(forSystem: depSystem),
                SystemsAPI.performSystemCheck(forSystem: arrSystem)
            )

            guard let depCoords = departure.coordinates, let arrCoords = arrival.coordinates else {
                command.message.error(key: "distance.notfound", fromCommand: command)
                return
            }

            let distance = arrCoords.distance(from: depCoords)

            let positionsAreApproximated = departure.landmark == nil || arrival.landmark == nil
            var plotDepName = departure.name
            var plotArrName = arrival.name
            if let proceduralCheck = departure.proceduralCheck,
                let sectordata = proceduralCheck.sectordata
            {
                if let nearestKnown = try? await SystemsAPI.getNearestSystem(
                    forCoordinates: sectordata.coords)?.data
                {
                    plotDepName = nearestKnown.name
                }
            }

            if let proceduralCheck = arrival.proceduralCheck,
                let sectordata = proceduralCheck.sectordata
            {
                if let nearestKnown = try? await SystemsAPI.getNearestSystem(
                    forCoordinates: sectordata.coords)?.data
                {
                    plotArrName = nearestKnown.name
                }
            }

            var spanshUrl: URL? = nil
            if distance > 1000 || range != nil {
                spanshUrl = try? await generateSpanshRoute(
                    from: plotDepName, to: plotArrName, range: Int(range ?? "65") ?? 65)
            }

            var key = positionsAreApproximated ? "distance.resultapprox" : "distance.result"
            if spanshUrl != nil {
                key += ".plotter"
            }

            let displayDistance = distance * 60 * 60 * 24 * 365.25

            command.message.reply(
                key: key, fromCommand: command,
                map: [
                    "departure": departure.name,
                    "arrival": arrival.name,
                    "distance": displayDistance.eliteDistance,
                    "plotterUrl": spanshUrl?.absoluteString ?? "",
                ])
        } catch {
            print(error)
            command.message.error(key: "distance.error", fromCommand: command)
        }
    }

    @BotCommand(
        ["station", "stations"],
        [
            .param("reference system / case id / client name", "Sagittarius A*", .continuous),
            .options(["p", "l"]), .argument("legacy"),
        ],
        category: .utility,
        description:
            "Get the nearest station to a system, use a system name, case ID, or client name",
        cooldown: .seconds(30)
    )
    var didReceiveStationCommand = { command in
        var systemName = command.param1!
        let requireLargePad = command.options.contains("l")
        let requireSpace = !(command.options.contains("p"))
        let legacyStations = command.arguments["legacy"] != nil

        if let (_, rescue) = await board.findRescue(
            withCaseIdentifier: systemName, includingRecentlyClosed: true)
        {
            systemName = rescue.system?.name ?? ""
        }

        var proceduralCheck: SystemsAPI.ProceduralCheckDocument? = nil
        var nearestSystem: SystemsAPI.NearestSystemDocument.NearestSystem? = nil
        let systemCheck = try? await SystemsAPI.performSystemCheck(forSystem: systemName)
        if systemCheck?.landmark == nil, let sectordata = systemCheck?.proceduralCheck?.sectordata {
            let cords = sectordata.coords
            if let nearestSystemSearch = try? await SystemsAPI.getNearestSystem(
                forCoordinates: cords)?.data
            {
                systemName = nearestSystemSearch.name
                proceduralCheck = systemCheck?.proceduralCheck
                nearestSystem = nearestSystemSearch
            } else {
                command.message.error(key: "station.notfound", fromCommand: command)
                return
            }
        }

        do {
            var stationResult = try await SystemsAPI.getNearestPreferableStation(
                forSystem: systemName,
                limit: 10,
                requireLargePad: requireLargePad,
                requireSpace: requireSpace,
                legacyStations: legacyStations
            )

            if stationResult == nil {
                stationResult = try await SystemsAPI.getNearestPreferableStation(
                    forSystem: systemName,
                    limit: 1000,
                    requireLargePad: requireLargePad,
                    requireSpace: requireSpace,
                    legacyStations: legacyStations
                )
            }

            guard let (system, station) = stationResult else {
                command.message.error(key: "station.notfound", fromCommand: command)
                return
            }

            var approximatedDistance: String? = nil
            if let proc = proceduralCheck, let nearest = nearestSystem,
                let sectordata = proc.sectordata
            {
                let formatter = NumberFormatter.englishFormatter()
                formatter.usesSignificantDigits = true
                // Round of output distance based on uncertainty provided by SystemsAPI
                formatter.maximumSignificantDigits = sectordata.uncertainty.significandWidth
                // Pythagoras strikes again, he won't ever leave me alone
                let calculatedDistance = (pow(nearest.distance, 2) + pow(system.distance, 2))
                    .squareRoot()
                approximatedDistance = formatter.string(from: calculatedDistance)
            }

            command.message.reply(
                message: (try? stencil.renderLine(
                    name: "station.stencil",
                    context: [
                        "system": system,
                        "approximatedDistance": approximatedDistance as Any,
                        "station": station,
                        "travelTime": (station.distance ?? 0).distanceToSeconds(
                            destinationGravity: true
                        ).timeSpan(maximumUnits: 1),
                        "services": station.allServices,
                        "notableServices": station.notableServices,
                        "stationType": station.type?.rawValue as Any,
                        "showAllServices": command.options.contains("s"),
                        "additionalServices": station.services.count
                            - station.notableServices.count,
                        "hasLargePad": station.hasLargePad,
                    ])) ?? "")
        } catch {
            debug(String(describing: error))
            command.error(error)
        }
    }
}
