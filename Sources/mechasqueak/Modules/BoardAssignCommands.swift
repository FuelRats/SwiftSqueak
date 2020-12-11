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

class BoardAssignCommands: IRCBotModule {
    var name: String = "Assign Commands"
    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @BotCommand(
        ["go", "assign", "add"],
        parameters: 2...,
        category: .board,
        description: "Add rats to the rescue and instruct the client to add them as friends.",
        paramText: "<case id/client> ...rats",
        example: "4 SpaceDawg StuffedRat",
        permission: .RescueWriteOwn,
        allowedDestinations: .Channel
    )
    var didReceiveAssignCommand = { command in
        let message = command.message

        // Find case by rescue ID or client name
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        // Disallow assigns on rescues without a platform set
        guard let platform = rescue.platform else {
            command.message.error(key: "board.assign.noplatform", fromCommand: command)
            return
        }

        let assigns = rescue.assign(Array(command.parameters[1...]), fromChannel: command.message.destination)

        sendAssignMessages(assigns: assigns, forRescue: rescue, fromCommand: command)
    }

    @BotCommand(
        ["gofr", "assignfr", "frgo"],
        parameters: 2...,
        category: .board,
        description: "Add rats to the rescue and instruct the client to add them as friends, also inform the client how to add friends.",
        paramText: "<case id/client> ...rats",
        example: "4 SpaceDawg StuffedRat",
        permission: .RescueWriteOwn,
        allowedDestinations: .Channel
    )
    var didReceiveAssignWithInstructionsCommand = { command in
        let message = command.message

        // Find case by rescue ID or client name
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        // Disallow assigns on rescues without a platform set
        guard let platform = rescue.platform else {
            command.message.error(key: "board.assign.noplatform", fromCommand: command)
            return
        }

        let assigns = rescue.assign(Array(command.parameters[1...]), fromChannel: command.message.destination)

        sendAssignMessages(assigns: assigns, forRescue: rescue, fromCommand: command)

        var factName = rescue.codeRed && rescue.platform == .PC ? "\(platform.factPrefix)frcr" : "\(platform.factPrefix)fr"

        Fact.get(name: factName, forLocale: command.locale).flatMap({ (fact) -> EventLoopFuture<Fact?> in
            guard let fact = fact else {
                return Fact.get(name: factName, forLocale: Locale(identifier: "en"))
            }

            return loop.next().makeSucceededFuture(fact)
        }).whenSuccess { fact in
            guard fact != nil else {
                return
            }

            let client = rescue.clientNick ?? rescue.client ?? ""
            message.reply(message: "\(client) \(fact!.message)")
        }
    }

    static func sendAssignMessages (assigns: RescueAssignments, forRescue rescue: LocalRescue, fromCommand command: IRCBotCommand) {
        if assigns.blacklisted.count > 0 {
            command.message.error(key: "board.assign.banned", fromCommand: command, map: [
                "rats": assigns.blacklisted.joined(separator: ", ")
            ])
        }

        if assigns.notFound.count > 0 {
            command.message.error(key: "board.assign.notexist", fromCommand: command, map: [
                "rats": assigns.notFound.joined(separator: ", ")
            ])
        }

        if assigns.invalid.count > 0 {
            command.message.error(key: "board.assign.invalid", fromCommand: command, map: [
                "rats": assigns.notFound.joined(separator: ", ")
            ])
        }

        let allRats = assigns.rats.union(assigns.duplicates).map({ $0.attributes.name.value })
            + assigns.unidentifiedRats.union(assigns.unidentifiedDuplicates)
        guard allRats.count > 0 else {
            return
        }

        let format = rescue.codeRed ? "board.assign.gocr" : "board.assign.go"

        command.message.reply(key: format, fromCommand: command, map: [
            "client": rescue.clientNick!,
            "rats": allRats.map({
                "\"\($0)\""
            }).joined(separator: ", "),
            "count": allRats.count
        ])

        if assigns.unidentifiedRats.count > 0 && configuration.general.drillMode == false {
            command.message.reply(key: "board.assign.unidentified", fromCommand: command, map: [
                "platform": rescue.platform!.ircRepresentable,
                "rats": assigns.unidentifiedRats.map({
                    "\"\($0)\""
                }).joined(separator: ", ")
            ])
        }
    }

    @BotCommand(
        ["unassign", "deassign", "rm", "remove", "standdown"],
        parameters: 2...,
        category: .board,
        description: "Remove rats from the rescue",
        paramText: "<case id/client> ...rats",
        example: "4 SpaceDawg StuffedRat",
        permission: .RescueWriteOwn,
        allowedDestinations: .Channel
    )
    var didReceiveUnassignCommand = { command in
        let message = command.message

        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        let unassigns = command.parameters[1...]

        var removed: [String] = []

        for unassign in unassigns {
            if let assignIndex = rescue.unidentifiedRats.firstIndex(where: {
                $0.lowercased() == unassign.lowercased()
            }) {
                rescue.unidentifiedRats.remove(at: assignIndex)
                removed.append(unassign)
                continue
            } else if
                let nick = message.destination.member(named: unassign),
                let apiData = nick.associatedAPIData,
                let user = apiData.user {
                if let rat = apiData.ratsBelongingTo(user: user).first(where: { rat in
                    return rescue.rats.contains(where: {
                        $0.id.rawValue == rat.id.rawValue
                    })
                }), let ratIndex = rescue.rats.firstIndex(of: rat) {
                    rescue.rats.remove(at: ratIndex)
                    removed.append(rat.attributes.name.value)
                    continue
                }
            } else if
                let ratIndex = rescue.rats.firstIndex(where: { $0.attributes.name.value.lowercased() == unassign.lowercased() })
            {
                removed.append(rescue.rats[ratIndex].attributes.name.value)
                rescue.rats.remove(at: ratIndex)
                continue
            }
            command.message.reply(key: "board.unassign.notassigned", fromCommand: command, map: [
                "rats": unassign,
                "caseId": rescue.commandIdentifier
            ])
        }

        guard removed.count > 0 else {
            return
        }
        let unassignedRats = removed.joined(separator: ", ")
        command.message.reply(key: "board.unassign.removed", fromCommand: command, map: [
            "caseId": rescue.commandIdentifier,
            "rats": unassignedRats
        ])
        rescue.syncUpstream()
    }
}
