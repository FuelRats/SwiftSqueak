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

class BoardAssignCommands: IRCBotModule {
    var name: String = "Assign Commands"
    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @BotCommand(
        ["assign", "go"],
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

        // Generate a tuple of assigned rats separated by identified rat IDs and unidentified rat names.
        let assigns: ([Rat], [String]) = command.parameters[1...].reduce(([], []), { acc, assign in
            var acc = acc

            guard
                assign.lowercased() != rescue.clientNick?.lowercased()
                && assign.lowercased() != rescue.client?.lowercased()
            else {
                return acc
            }

            guard
                let nick = message.destination.member(named: assign),
                let rat = nick.getRatRepresenting(rescue: rescue)
            else {
                guard acc.1.contains(assign) == false else {
                    return acc
                }

                acc.1.append(assign)
                return acc
            }

            guard acc.0.contains(where: {
                $0.id.rawValue == rat.id.rawValue
            }) == false else {
                return acc
            }
            acc.0.append(rat)
            return acc
        })

        rescue.rats.append(contentsOf: assigns.0)
        rescue.unidentifiedRats.append(contentsOf: assigns.1)

        let allRats = assigns.0.map({ $0.attributes.name.value }) + assigns.1
        guard allRats.count > 0 else {
            command.message.error(key: "board.assign.none", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier!
            ])
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

        if assigns.1.count > 0 && configuration.general.drillMode == false {
            command.message.reply(key: "board.assign.unidentified", fromCommand: command, map: [
                "platform": platform.ircRepresentable,
                "rats": assigns.1.map({
                    "\"\($0)\""
                }).joined(separator: ", ")
            ])
        }

        rescue.syncUpstream(fromBoard: mecha.rescueBoard)
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
            } else if
                let nick = message.destination.member(named: unassign),
                let rat = nick.getRatRepresenting(rescue: rescue),
                let assignIndex = rescue.rats.firstIndex(where: {
                    $0.id.rawValue == rat.id.rawValue
                }) {
                rescue.rats.remove(at: assignIndex)
                removed.append(rat.attributes.name.value)
            } else {
                command.message.reply(key: "board.unassign.notassigned", fromCommand: command, map: [
                    "rats": unassign,
                    "caseId": rescue.commandIdentifier!
                ])
            }
        }

        let unassignedRats = removed.joined(separator: ", ")
        command.message.reply(key: "board.unassign.removed", fromCommand: command, map: [
            "caseId": rescue.commandIdentifier!,
            "rats": unassignedRats
        ])
        rescue.syncUpstream(fromBoard: mecha.rescueBoard)
    }
}
