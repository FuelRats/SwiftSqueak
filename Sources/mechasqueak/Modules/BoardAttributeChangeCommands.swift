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

    @BotCommand(
        ["active", "inactive", "activate", "deactivate"],
        [.param("case id/client", "4"), .param("message", "client left irc", .continuous, .optional)],
        category: .board,
        description: "Toggle a case between active or inactive, add an optional message that gets inserted into quotes.",
        permission: .DispatchWrite,
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

        let key = command.parameters.count > 1 ? "board.toggleactive" : "board.toggleactivemsg"

        command.message.reply(key: "board.toggleactive", fromCommand: command, map: [
            "status": status,
            "caseId": rescue.commandIdentifier,
            "client": rescue.client!,
            "message": message
        ])

        rescue.syncUpstream(fromCommand: command)
    }

    @BotCommand(
        ["queue"],
        [.param("case id/client", "4")],
        category: .board,
        description: "Add a rescue to the queue list, informing the client.",
        permission: .DispatchWrite,
        allowedDestinations: .Channel
    )
    var didReceiveQueueCommand = { command in
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        guard rescue.status != .Queued else {
            command.message.error(key: "board.queue.already", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier
            ])
            return
        }
        rescue.status = .Queued

        Fact.getWithFallback(name: "pqueue", forLcoale: command.locale).whenSuccess { fact in
            guard let fact = fact else {
                return
            }

            let target = rescue.clientNick ?? ""
            command.message.reply(message: "\(target): \(fact.message)")
        }

        rescue.syncUpstream(fromCommand: command)
    }

    @BotCommand(
        ["dequeue", "unqueue"],
        [.param("case id/client", "4")],
        category: .board,
        description: "Remove a rescue from the queue list, informing the client.",
        permission: .DispatchWrite,
        allowedDestinations: .Channel
    )
    var didReceiveDequeueCommand = { command in
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        guard rescue.status == .Queued else {
            command.message.error(key: "board.dequeue.already", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier
            ])
            return
        }
        rescue.status = .Open

        command.message.reply(key: "board.dequeue.response", fromCommand: command, map: [
            "caseId": rescue.commandIdentifier,
            "client": rescue.client!
        ])

        rescue.syncUpstream(fromCommand: command)
    }

    @BotCommand(
        ["system", "sys", "loc", "location"],
        [.options(["f"]), .param("case id/client", "4"), .param("system name", "NLTT 48288", .continuous)],
        category: .utility,
        description: "Change the star system of this rescue to a different one.",
        permission: .DispatchWrite,
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
        
        var key = "board.syschange"
        if let correction = ProceduralSystem.correct(system: system), command.forceOverride == false {
            key += ".autocorrect"
            system = correction
        }

        SystemsAPI.performSystemCheck(forSystem: system).whenComplete({ result in
            switch result {
                case .failure(_):
                    rescue.system = StarSystem(
                        name: system,
                        manuallyCorrected: true
                    )
                case .success(let system):
                    if rescue.system != nil {
                        rescue.system?.merge(system)
                    } else {
                        rescue.system = system
                    }
                    rescue.system?.manuallyCorrected = true
            }
            
            rescue.syncUpstream(fromCommand: command)
            command.message.reply(key: key, fromCommand: command, map: [
                "caseId": rescue.commandIdentifier,
                "client": rescue.client!,
                "systemInfo": rescue.system.description
            ])
        })
    }

    @BotCommand(
        ["cmdr", "client", "commander"],
        [.param("case id/client", "4"), .param("new name", "SpaceDawg", .continuous)],
        category: .board,
        description: "Change the CMDR name of the client of this rescue.",
        permission: .DispatchWrite,
        allowedDestinations: .Channel
    )
    var didReceiveClientChangeCommand = { command in
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        let oldClient = rescue.client!
        let client = command.parameters[1]

        rescue.client = client

        command.message.reply(key: "board.clientchange", fromCommand: command, map: [
            "caseId": rescue.commandIdentifier,
            "oldClient": oldClient,
            "client": client
        ])


        if let existingCase = mecha.rescueBoard.rescues.first(where: {
            $0.client?.lowercased() == client.lowercased() && $0.id != rescue.id
        }) {
            command.message.error(key: "board.clientchange.exists", fromCommand: command, map: [
                "caseId": existingCase.commandIdentifier,
                "client": client
            ])
        }

        rescue.syncUpstream(fromCommand: command)
    }

    @BotCommand(
        ["nick", "ircnick", "nickname"],
        [.param("case id/client", "4"), .param("new nick", "SpaceDawg")],
        category: .board,
        description: "Change the IRC nick associated with the client of this rescue.",
        permission: .DispatchWrite,
        allowedDestinations: .Channel
    )
    var didReceiveClientNickChangeCommand = { command in
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        let nick = command.parameters[1]
        rescue.clientNick = nick

        command.message.reply(key: "board.nickchange", fromCommand: command, map: [
            "caseId": rescue.commandIdentifier,
            "client": rescue.client!,
            "nick": nick
        ])


        if let existingCase = mecha.rescueBoard.rescues.first(where: {
            $0.clientNick?.lowercased() == nick.lowercased() && $0.id != rescue.id
        }) {
            command.message.error(key: "board.nickchange.exists", fromCommand: command, map: [
                "caseId": existingCase.commandIdentifier,
                "nick": nick
            ])
        }

        rescue.syncUpstream(fromCommand: command)
    }

    @BotCommand(
        ["lang", "language"],
        [.param("case id/client", "4"), .param("language code", "de")],
        category: .board,
        description: "Change the language of the client of this rescue.",
        permission: .DispatchWrite,
        allowedDestinations: .Channel
    )
    var didReceiveLanguageChangeCommand = { command in
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
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

        command.message.reply(key: "board.languagechange", fromCommand: command, map: [
            "caseId": rescue.commandIdentifier,
            "client": rescue.client!,
            "language": "\(newLanguage.identifier) (\(newLanguage.englishDescription))"
        ])

        rescue.syncUpstream(fromCommand: command)
    }

    @BotCommand(
        ["cr", "codered", "casered"],
        [.param("case id/client", "4")],
        category: .board,
        description: "Toggle the case between code red (on emergency oxygen) status or not.",
        permission: .DispatchWrite,
        allowedDestinations: .Channel
    )
    var didReceiveCodeRedToggleCommand = { command in
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        if rescue.codeRed == true {
            rescue.codeRed = false
            command.message.reply(key: "board.codered.no", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier,
                "client": rescue.client!
            ])
        } else {
            rescue.codeRed = true
            command.message.reply(key: "board.codered.active", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier,
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
        rescue.syncUpstream(fromCommand: command)
    }

    @BotCommand(
        ["title", "operation"],
        [.param("case id/client", "4"), .param("operation title", "Beyond the Void", .continuous)],
        category: .board,
        description: "Set the operations title of this rescue, used to give a unique name to special rescues",
        permission: .DispatchWrite,
        allowedDestinations: .Channel
    )
    var didReceiveSetTitleCommand = { command in
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        let title = command.parameters[1]
        rescue.title = title

        command.message.reply(key: "board.title.set", fromCommand: command, map: [
            "caseId": rescue.commandIdentifier,
            "title": title
        ])

        rescue.syncUpstream(fromCommand: command)
    }
}
