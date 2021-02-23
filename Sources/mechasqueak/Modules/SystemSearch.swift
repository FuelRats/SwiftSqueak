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
        description: "Search for a system in the galaxy database."
    )
    var didReceiveSystemSearchCommand = { command in
        let system = command.parameters.joined(separator: " ")
        SystemsAPI.performSearch(forSystem: system).whenComplete({ request in
            switch request {
                case .success(let searchResults):
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

                case .failure:
                    command.message.error(key: "systemsearch.error", fromCommand: command)
            }
        })
    }

    @BotCommand(
        ["landmark"],
        [.argument("sol"), .param("system name", "NLTT 48288", .continuous)],
        category: .utility,
        description: "Search for a star system's proximity to known landmarks such as Sol, Sagittarius A* or Colonia."
    )
    var didReceiveLandmarkCommand = { command in
        var system = command.parameters.joined(separator: " ")
        if system.lowercased().starts(with: "near ") {
            system.removeFirst(5)
        }
        
        let landmarkPreference = command.namedOptions.contains("sol") ? "Sol" : nil
        if let autocorrect = ProceduralSystem.correct(system: system) {
            system = autocorrect
        }

        SystemsAPI.performSystemCheck(forSystem: system).whenComplete { apiResult in
            switch apiResult {
                case .failure(_):
                    command.message.reply(key: "landmark.noresults", fromCommand: command, map: [
                        "system": system
                    ])
                case .success(let result):
                    guard let landmark = result.landmark else {
                        if let procedural = result.proceduralCheck, procedural.isPgSystem == true && (procedural.isPgSector || procedural.sectordata.handauthored) {
                            var (landmark, distance) = procedural.estimatedLandmarkDistance
                            var landmarkName = landmark.name
                            
                            if landmarkPreference != nil {
                                landmarkName = "Sol"
                                distance = procedural.estimatedSolDistance
                            }
                            command.message.reply(key: "landmark.procedural", fromCommand: command, map: [
                                "system": system,
                                "distance": distance,
                                "landmark": landmarkName
                            ])
                            return
                        }
                        command.message.reply(key: "landmark.noresults", fromCommand: command, map: [
                            "system": system
                        ])
                        return
                    }
                    command.message.reply(message: result.getInfo(preferredLandmarkName: landmarkPreference))
            }
        }
    }
}
