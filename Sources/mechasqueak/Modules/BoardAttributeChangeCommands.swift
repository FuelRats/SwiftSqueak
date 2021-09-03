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

class BoardAttributeCommands: IRCBotModule {
    var name: String = "Case Attribute Change Commands"
    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @AsyncBotCommand(
        ["active", "inactive", "activate", "deactivate"],
        [.param("case id/client", "4"), .param("message", "client left irc", .continuous, .optional)],
        category: .board,
        description: "Toggle a case between active or inactive, add an optional message that gets inserted into quotes.",
        permission: .DispatchWrite,
        allowedDestinations: .Channel
    )
    var didReceiveToggleCaseActiveCommand = { command in
        guard let (caseId, rescue) = await BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        if rescue.status == .Inactive {
            rescue.status = .Open
        } else {
            rescue.status = .Inactive
            await board.cancelPrepTimer(forRescue: rescue)
            let activeCases = await board.activeCases
            if activeCases < QueueCommands.maxClientsCount, configuration.queue != nil {
                Task {
                    try? await QueueAPI.dequeue()
                }
            }
        }

        let status = String(describing: rescue.status)

        var message = ""
        if command.parameters.count > 1 {
            message = command.parameters[1]
            rescue.quotes.append(RescueQuote(
                author: command.message.user.nickname,
                message: "(Set \(status)) \(message)",
                createdAt: Date(),
                updatedAt: Date(),
                lastAuthor: command.message.user.nickname
            ))
        }
        try? rescue.save(command)

        let key = command.parameters.count > 1 ? "board.toggleactive" : "board.toggleactivemsg"

        command.message.reply(key: "board.toggleactive", fromCommand: command, map: [
            "status": status,
            "caseId": caseId,
            "client": rescue.client!,
            "message": message
        ])
    }

    @AsyncBotCommand(
        ["system", "sys", "loc", "location"],
        [.options(["f"]), .param("case id/client", "4"), .param("system name", "NLTT 48288", .continuous)],
        category: .utility,
        description: "Change the star system of this rescue to a different one.",
        permission: .DispatchWrite,
        allowedDestinations: .Channel
    )
    var didReceiveSystemChangeCommand = { command in
        guard let (caseId, rescue) = await BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        var systemName = command.parameters[1].uppercased()
        if systemName.hasSuffix(" SYSTEM") {
            systemName.removeLast(7)
        }
        
        if systemName == rescue.system?.name {
            command.message.error(key: "board.syschange.nochange", fromCommand: command, map: [
                "caseId": caseId
            ])
            return
        }
        
        var key = "board.syschange"
        if let correction = ProceduralSystem.correct(system: systemName), command.forceOverride == false {
            key += ".autocorrect"
            systemName = correction
        }

        do {
            let system = try await SystemsAPI.performSystemCheck(forSystem: systemName)
            if rescue.system != nil {
                rescue.system?.merge(system)
            } else {
                rescue.system = system
            }
            rescue.system?.manuallyCorrected = true
        } catch {
            rescue.system = StarSystem(
                name: systemName,
                manuallyCorrected: true
            )
        }
        try? rescue.save(command)
        
        command.message.reply(key: key, fromCommand: command, map: [
            "caseId": caseId,
            "client": rescue.client!,
            "systemInfo": rescue.system.description
        ])
    }

    @AsyncBotCommand(
        ["cmdr", "client", "commander"],
        [.param("case id/client", "4"), .param("new name", "SpaceDawg", .continuous)],
        category: .board,
        description: "Change the CMDR name of the client of this rescue.",
        permission: .DispatchWrite,
        allowedDestinations: .Channel
    )
    var didReceiveClientChangeCommand = { command in
        guard let (caseId, rescue) = await BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        let oldClient = rescue.client!
        let client = command.parameters[1]

        rescue.client = client
        if configuration.queue != nil {
            _ = try? await QueueAPI.fetchQueue().first(where: { $0.client.name == oldClient })?.changeName(name: client)
        }

        command.message.reply(key: "board.clientchange", fromCommand: command, map: [
            "caseId": caseId,
            "oldClient": oldClient,
            "client": client
        ])
        
        try? rescue.save(command)


        if let existingCase = await board.rescues.first(where: {
            $0.1.client?.lowercased() == client.lowercased() && $0.1.id != rescue.id
        }) {
            command.message.error(key: "board.clientchange.exists", fromCommand: command, map: [
                "caseId": existingCase.key,
                "client": client
            ])
        }
    }

    @AsyncBotCommand(
        ["nick", "ircnick", "nickname"],
        [.param("case id/client", "4"), .param("new nick", "SpaceDawg")],
        category: .board,
        description: "Change the IRC nick associated with the client of this rescue.",
        permission: .DispatchWrite,
        allowedDestinations: .Channel
    )
    var didReceiveClientNickChangeCommand = { command in
        guard let (caseId, rescue) = await BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        let nick = command.parameters[1]
        rescue.clientNick = nick
        try? rescue.save(command)

        command.message.reply(key: "board.nickchange", fromCommand: command, map: [
            "caseId": caseId,
            "client": rescue.client!,
            "nick": nick
        ])


        if let existingCase = await board.rescues.first(where: {
            $0.1.clientNick?.lowercased() == nick.lowercased() && $0.1.id != rescue.id
        }) {
            command.message.error(key: "board.nickchange.exists", fromCommand: command, map: [
                "caseId": existingCase.key,
                "nick": nick
            ])
        }
    }

    @AsyncBotCommand(
        ["lang", "language"],
        [.param("case id/client", "4"), .param("language code", "de")],
        category: .board,
        description: "Change the language of the client of this rescue.",
        permission: .DispatchWrite,
        allowedDestinations: .Channel
    )
    var didReceiveLanguageChangeCommand = { command in
        guard let (caseId, rescue) = await BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        let newLanguage = Locale(identifier: command.parameters[1])
        guard newLanguage.isValid else {
            command.message.error(key: "board.languagechange.error", fromCommand: command, map: [
                "language": command.parameters[1]
            ])
            return
        }

        rescue.clientLanguage = newLanguage
        try? rescue.save(command)

        command.message.reply(key: "board.languagechange", fromCommand: command, map: [
            "caseId": caseId,
            "client": rescue.client!,
            "language": "\(newLanguage.identifier) (\(newLanguage.englishDescription))"
        ])

    }

    @AsyncBotCommand(
        ["cr", "codered", "casered"],
        [.param("case id/client", "4")],
        category: .board,
        description: "Toggle the case between code red (on emergency oxygen) status or not.",
        permission: .DispatchWrite,
        allowedDestinations: .Channel
    )
    var didReceiveCodeRedToggleCommand = { command in
        guard let (caseId, rescue) = await BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        if rescue.codeRed == true {
            rescue.codeRed = false
            command.message.reply(key: "board.codered.no", fromCommand: command, map: [
                "caseId": caseId,
                "client": rescue.client!
            ])
        } else {
            rescue.codeRed = true
            command.message.reply(key: "board.codered.active", fromCommand: command, map: [
                "caseId": caseId,
                "client": rescue.client!
            ])

            if rescue.rats.count > 0 {
                let rats = rescue.rats.map({
                    $0.currentNick(inIRCChannel: command.message.destination) ?? $0.attributes.name.value
                }).joined(separator: ", ")

                command.message.reply(key: "board.codered.attention", fromCommand: command, map: [
                    "rats": rats
                ])
            }
        }
        try? rescue.save(command)
    }

    @AsyncBotCommand(
        ["title", "operation"],
        [.param("case id/client", "4"), .param("operation title", "Beyond the Void", .continuous)],
        category: .board,
        description: "Set the operations title of this rescue, used to give a unique name to special rescues",
        permission: .DispatchWrite,
        allowedDestinations: .Channel
    )
    var didReceiveSetTitleCommand = { command in
        guard let (caseId, rescue) = await BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        let title = command.parameters[1]
        rescue.title = title
        try? rescue.save(command)

        command.message.reply(key: "board.title.set", fromCommand: command, map: [
            "caseId": caseId,
            "title": title
        ])
    }
    
    @AsyncBotCommand(
        ["odyssey", "horizon", "horizons"],
        [.param("case id/client", "4")],
        category: .board,
        description: "Toggle a case between odyssey or not odyssey",
        permission: .DispatchWrite,
        allowedDestinations: .Channel
    )
    var didReceiveToggleOdysseycommand = { command in
        guard let (caseId, rescue) = await BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        rescue.odyssey = !rescue.odyssey
        try? rescue.save(command)
        
        if rescue.odyssey && rescue.platform != .PC {
            command.message.error(key: "board.toggleodyssey.platform", fromCommand: command)
            return
        }
        
        let key = "board.toggleodyssey." + (rescue.odyssey ? "on" : "off")
        command.message.reply(key: key, fromCommand: command, map: [
            "caseId": caseId,
            "client": rescue.clientDescription
        ])
    }
}
