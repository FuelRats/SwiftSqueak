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

class SystemSearch: IRCBotModule {
    var name: String = "SystemSearch"
    private let formatter: NumberFormatter

    var commands: [IRCBotCommandDeclaration] {
        return [
            IRCBotCommandDeclaration(
                commands: ["search"],
                minParameters: 1,
                onCommand: didReceiveSystemSearchCommand(command:),
                maxParameters: 1,
                lastParameterIsContinous: true,
                permission: nil
            ),

            IRCBotCommandDeclaration(
                commands: ["landmark"],
                minParameters: 1,
                onCommand: didReceiveLandmarkCommand(command:),
                maxParameters: 1,
                lastParameterIsContinous: true,
                permission: nil
            )
        ]
    }

    required init(_ moduleManager: IRCBotModuleManager) {
        self.formatter = NumberFormatter()
        self.formatter.numberStyle = .decimal
        self.formatter.groupingSize = 3
        self.formatter.maximumFractionDigits = 1
        self.formatter.roundingMode = .halfUp

        moduleManager.register(module: self)
    }

    func didReceiveSystemSearchCommand(command: IRCBotCommand) {
        let system = command.parameters.joined(separator: " ")

        SystemsAPI.performSearch(forSystem: system, onComplete: { searchResults in
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
            command.message.reply(key: "systemsearch.error", fromCommand: command)
        })
    }

    func didReceiveLandmarkCommand (command: IRCBotCommand) {
        let system = command.parameters.joined(separator: " ")

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
                "distance": self.formatter.string(from: NSNumber(value: landmark.distance))!,
                "landmark": landmark.name
            ])
        }, onError: { _ in
            command.message.reply(key: "landmark.noresults", fromCommand: command, map: [
                "system": system
            ])
        })
    }
}
