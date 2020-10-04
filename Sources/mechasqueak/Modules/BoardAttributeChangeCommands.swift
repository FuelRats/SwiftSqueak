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

class BoardAttributeCommands: IRCBotModule {
    var name: String = "Case Attribute Change Commands"
    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @BotCommand(
        ["active", "inactive", "activate", "deactivate"],
        parameters: 1...1,
        category: .board,
        description: "Toggle a case between active or inactive.",
        paramText: "<case id/client>",
        example: "4",
        permission: .RescueWriteOwn,
        allowedDestinations: .Channel
    )
    var didReceiveToggleCaseActiveCommand = { command in
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        if rescue.status == .Inactive {
            rescue.status = .Open
        } else {
            rescue.status = .Inactive
        }

        command.message.reply(key: "board.toggleactive", fromCommand: command, map: [
            "status": String(describing: rescue.status),
            "caseId": rescue.commandIdentifier!,
            "client": rescue.client!
        ])

        rescue.syncUpstream(fromBoard: mecha.rescueBoard)
    }

    @BotCommand(
        ["system", "sys", "loc", "location"],
        parameters: 2...2,
        lastParameterIsContinous: true,
        category: .utility,
        description: "Change the star system of this rescue to a different one.",
        paramText: "<case id/client> <system name>",
        example: "4 NLTT 48288",
        permission: .RescueWriteOwn,
        allowedDestinations: .Channel
    )
    var didReceiveSystemChangeCommand = { command in
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        var system = command.parameters[1].uppercased()
        if system.hasSuffix(" SYSTEM") {
            system.removeLast(7)
        }

        rescue.system = system.uppercased()

        SystemsAPI.performSearchAndLandmarkCheck(
            forSystem: system,
            onComplete: { searchResult, landmarkResult, _ in
                guard let searchResult = searchResult, let landmarkResult = landmarkResult else {
                    command.message.reply(key: "board.syschange.notindb", fromCommand: command, map: [
                        "caseId": rescue.commandIdentifier!,
                        "client": rescue.client!,
                        "system": system
                    ])
                    return
                }

                let format = searchResult.permitRequired ? "board.syschange.permit" : "board.syschange.landmark"

                let distance = NumberFormatter.englishFormatter().string(
                    from: NSNumber(value: landmarkResult.distance)
                )!
                command.message.reply(key: format, fromCommand: command, map: [
                    "caseId": rescue.commandIdentifier!,
                    "client": rescue.client!,
                    "system": system,
                    "distance": distance,
                    "landmark": landmarkResult.name,
                    "permit": searchResult.permitText ?? ""
                ])
            }
        )
        rescue.systemManuallyCorrected = true
        rescue.syncUpstream(fromBoard: mecha.rescueBoard)
    }

    @BotCommand(
        ["cmdr", "client", "commander"],
        parameters: 2...2,
        lastParameterIsContinous: true,
        category: .board,
        description: "Change the CMDR name of the client of this rescue.",
        paramText: "<case id/client> <new name>",
        example: "4 SpaceDawg",
        permission: .RescueWriteOwn,
        allowedDestinations: .Channel
    )
    var didReceiveClientChangeCommand = { command in
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        let oldClient = rescue.client!
        let client = command.parameters[1]

        guard mecha.rescueBoard.rescues.contains(where: {
            $0.client?.lowercased() == client.lowercased()
        }) == false else {
            command.message.error(key: "board.clientchange.exists", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier!,
                "client": client
            ])
            return
        }

        rescue.client = client

        command.message.reply(key: "board.clientchange", fromCommand: command, map: [
            "caseId": rescue.commandIdentifier!,
            "oldClient": oldClient,
            "client": client
        ])

        rescue.syncUpstream(fromBoard: mecha.rescueBoard)
    }

    @BotCommand(
        ["nick", "ircnick", "nickname"],
        parameters: 2...2,
        lastParameterIsContinous: true,
        category: .board,
        description: "Change the IRC nick associated with the client of this rescue.",
        paramText: "<case id/client> <new nick>",
        example: "4 SpaceDawg",
        permission: .RescueWriteOwn,
        allowedDestinations: .Channel
    )
    var didReceiveClientNickChangeCommand = { command in
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        let nick = command.parameters[1]
        guard mecha.rescueBoard.rescues.contains(where: {
            $0.clientNick?.lowercased() == nick.lowercased()
        }) == false else {
            command.message.error(key: "board.nickchange.exists", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier!,
                "nick": nick
            ])
            return
        }
        rescue.clientNick = nick

        command.message.reply(key: "board.nickchange", fromCommand: command, map: [
            "caseId": rescue.commandIdentifier!,
            "client": rescue.client!,
            "nick": nick
        ])

        rescue.syncUpstream(fromBoard: mecha.rescueBoard)
    }

    @BotCommand(
        ["cr", "codered", "casered"],
        parameters: 1...1,
        category: .board,
        description: "Toggle the case between code red (on emergency oxygen) status or not.",
        paramText: "<case id/client>",
        example: "4",
        permission: .RescueWriteOwn,
        allowedDestinations: .Channel
    )
    var didReceiveCodeRedToggleCommand = { command in
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        if rescue.codeRed == true {
            rescue.codeRed = false
            command.message.reply(key: "board.codered.no", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier!,
                "client": rescue.client!
            ])
        } else {
            rescue.codeRed = true
            command.message.reply(key: "board.codered.active", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier!,
                "client": rescue.client!
            ])

            if rescue.rats.count > 0 {
                let rats = rescue.rats.map({
                    $0.attributes.name.value
                }).joined(separator: ", ")

                command.message.reply(key: "board.codered.attention", fromCommand: command, map: [
                    "rats": rats
                ])
            }
        }
        rescue.syncUpstream(fromBoard: mecha.rescueBoard)
    }

    @BotCommand(
        ["title", "operation"],
        parameters: 2...2,
        lastParameterIsContinous: true,
        category: .board,
        description: "Set the operations title of this rescue, used to give a unique name to special rescues",
        paramText: "<case id/client> <operation title>",
        example: "4 Beyond the Void",
        permission: .RescueWriteOwn,
        allowedDestinations: .Channel
    )
    var didReceiveSetTitleCommand = { command in
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        let title = command.parameters[1]
        rescue.title = title

        command.message.reply(key: "board.title.set", fromCommand: command, map: [
            "caseId": rescue.commandIdentifier!,
            "title": title
        ])

        rescue.syncUpstream(fromBoard: mecha.rescueBoard)
    }
}
