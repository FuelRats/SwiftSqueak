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
import IRCKit
import NIO

class SystemSearch: IRCBotModule {
    var name: String = "SystemSearch"

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @BotCommand(
        ["search"],
        parameters: 1...1,
        lastParameterIsContinous: true,
        category: .utility,
        description: "Search for a system in the galaxy database.",
        paramText: "<system name>",
        example: "NLTT 48288"
    )
    var didReceiveSystemSearchCommand = { command in
        let system = command.parameters.joined(separator: " ")
        let deadline: NIODeadline = .now() + .seconds(30)
        SystemsAPI.performSearch(forSystem: system, deadline: deadline, onComplete: { searchResults in
            var results = searchResults.data

            results = results.filter({
                $0.name.count < 10
                    || ($0.distance != nil && $0.distance! < $0.name.count)
                    || ($0.similarity != nil && $0.similarity! > 0.3)
            })

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
        }, onError: { _ in
            command.message.error(key: "systemsearch.error", fromCommand: command)
        })
    }

    @BotCommand(
        ["landmark"],
        parameters: 1...1,
        lastParameterIsContinous: true,
        category: .utility,
        description: "Search for a star system's proximity to known landmarks such as Sol, Sagittarius A* or Colonia.",
        paramText: "<system name>",
        example: "NLTT 48288"
    )
    var didReceiveLandmarkCommand = { command in
        var system = command.parameters.joined(separator: " ")

        SystemsAPI.performLandmarkCheck(forSystem: system, onComplete: { result in
            guard result.landmarks.count > 0 else {
                command.message.reply(key: "landmark.noresults", fromCommand: command, map: [
                    "system": system
                ])
                return
            }

            let landmark = result.landmarks[0]

            command.message.reply(key: "landmark.response", fromCommand: command, map: [
                "system": result.meta.name,
                "distance": NumberFormatter.englishFormatter().string(from: NSNumber(value: landmark.distance))!,
                "landmark": landmark.name
            ])
        }, onError: { _ in
            command.message.reply(key: "landmark.noresults", fromCommand: command, map: [
                "system": system
            ])
        })
    }
}
