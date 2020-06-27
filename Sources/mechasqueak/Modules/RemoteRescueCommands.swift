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

class RemoteRescueCommands: IRCBotModule {
    var name: String = "Remote Rescue Commands"
    private var channelMessageObserver: NotificationToken?

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @BotCommand(
        ["closed", "recent"],
        parameters: 0...1,
        category: .rescues,
        description: "Shows recently closed cases.",
        paramText: "[number of cases]",
        example: "10",
        permission: .RescueRead
    )
    var didReceiveRecentlyClosedCommand = { command in
        var closeCount = 3
        if command.parameters.count > 0 {
            guard let count = Int(command.parameters[0]) else {
                command.message.error(key: "rescue.closed.invalid", fromCommand: command, map: [
                    "count": command.parameters[0]
                ])
                return
            }

            guard count <= 10 && count > 0 else {
                command.message.error(key: "rescue.closed.invalid", fromCommand: command, map: [
                    "count": count
                ])
                return
            }
            closeCount = count
        }

        FuelRatsAPI.getRecentlyClosedRescues(count: closeCount, complete: { results in
            let rescueList = results.body.data!.primary.values.enumerated().map({ (index, rescue) in
                return lingo.localize("rescue.closed.entry", locale: command.locale.identifier, interpolations: [
                    "index": index,
                    "client": rescue.client ?? "unknown client",
                    "platform": rescue.platform?.ircRepresentable ?? "unknown platform",
                    "system": rescue.system ?? "unknown system",
                    "id": rescue.id.rawValue.ircRepresentation
                ])
            })

            command.message.reply(key: "rescue.closed.list", fromCommand: command, map: [
                "count": closeCount
            ])

            command.message.reply(list: rescueList, separator: " - ")
        }, error: { _ in
            command.message.error(key: "rescue.closed.error", fromCommand: command)
        })
    }

    @BotCommand(
        ["delete"],
        parameters: 1...1,
        category: .rescues,
        description: "Delete a rescue by UUID, cannot be used on a rescue that is currently on the board.",
        paramText: "<rescue uuid",
        example: "035c1a9a-c066-40d0-bc4a-bee736879fd5",
        permission: .RescueWrite
    )
    var didReceiveDeleteCommand = { command in
        guard let id = UUID(uuidString: command.parameters[0]) else {
            command.message.error(key: "rescue.delete.invalid", fromCommand: command, map: [
                "id": command.parameters[0]
            ])
            return
        }

        if let boardRescue = mecha.rescueBoard.rescues.first(where: { $0.id == id }) {
            command.message.reply(key: "rescue.delete.active", fromCommand: command, map: [
                "id": boardRescue.id.ircRepresentation,
                "caseId": boardRescue.commandIdentifier!
            ])
            return
        }

        FuelRatsAPI.deleteRescue(id: id, complete: {
            command.message.reply(key: "rescue.delete.success", fromCommand: command, map: [
                "id": id.ircRepresentation
            ])
        }, error: { error in
            if error.response!.status == .noContent {
                command.message.reply(key: "rescue.delete.success", fromCommand: command, map: [
                    "id": id.ircRepresentation
                ])
            } else {
                command.message.reply(key: "rescue.delete.failure", fromCommand: command, map: [
                    "id": id.ircRepresentation
                ])
            }
        })
    }

    @BotCommand(
        ["trashlist", "mdlist", "purgelist", "listtrash"],
        parameters: 0...0,
        category: .rescues,
        description: "Shows all the rescues that have been added to the trash list but not yet deleted",
        permission: .RescueRead,
        allowedDestinations: .PrivateMessage
    )
    var didReceiveListTrashcommand = { command in
        FuelRatsAPI.getRescuesInTrash(complete: { results in
            let rescues = results.body.data!.primary.values
            guard rescues.count > 0 else {
                command.message.reply(key: "rescue.trashlist.empty", fromCommand: command)
                return
            }

            command.message.reply(key: "rescue.trashlist.list", fromCommand: command, map: [
                "count": rescues.count
            ])

            for rescue in rescues {
                let format = rescue.attributes.codeRed.value ? "rescue.trashlist.entrycr" : "rescue.trashlist.entry"

                command.message.reply(key: format, fromCommand: command, map: [
                    "id": rescue.id.rawValue.ircRepresentation,
                    "client": rescue.client ?? "unknown client",
                    "platform": rescue.platform?.ircRepresentable ?? "unknown platform",
                    "reason": rescue.notes
                ])
            }
        }, error: { _ in
            command.message.error(key: "rescue.trashlist.error", fromCommand: command)
        })
    }

    @BotCommand(
        ["restore", "mdremove", "trashremove", "mdr", "tlr", "trashlistremove", "mdd", "mddeny"],
        parameters: 1...1,
        category: .rescues,
        description: "Restore a case from the trash list.",
        paramText: "<rescue uuid>",
        example: "035c1a9a-c066-40d0-bc4a-bee736879fd5",
        permission: .RescueWrite
    )
    var didReceiveRestoreTrashCommand = { command in
        guard let id = UUID(uuidString: command.parameters[0]) else {
            command.message.error(key: "rescue.restore.invalid", fromCommand: command, map: [
                "id": command.parameters[0]
            ])
            return
        }

        FuelRatsAPI.getRescue(id: id, complete: { result in
            var rescue = result.body.data!.primary.value

            guard rescue.outcome == .Purge else {
                command.message.error(key: "rescue.restore.nottrash", fromCommand: command, map: [
                    "id": id.ircRepresentation
                ])
                return
            }

            rescue = rescue.tappingAttributes({ $0.outcome = .init(value: nil) })

            rescue.update(complete: {
                command.message.reply(key: "rescue.restore.restored", fromCommand: command, map: [
                    "id": id.ircRepresentation
                ])
            }, error: { _ in
                command.message.error(key: "rescue.restore.error", fromCommand: command, map: [
                    "id": id.ircRepresentation
                ])
            })

        }, error: { _ in
            command.message.error(key: "rescue.restore.error", fromCommand: command, map: [
                "id": id.ircRepresentation
            ])
        })
    }

    @BotCommand(
        ["unfiled", "pwn", "paperworkneeded", "needspaperwork", "npw"],
        parameters: 0...0,
        category: .rescues,
        description: "Get a list of rescues that have not had their paperwork completed.",
        permission: .RescueRead,
        allowedDestinations: .PrivateMessage
    )
    var didReceiveUnfiledListCommand = { command in
        FuelRatsAPI.getUnfiledRescues(complete: { results in
            let rescues = results.body.data!.primary.values
            guard rescues.count > 0 else {
                command.message.reply(key: "rescue.unfiled.empty", fromCommand: command)
                return
            }

            command.message.reply(key: "rescue.unfiled.list", fromCommand: command, map: [
                "count": rescues.count
            ])

            for rescue in rescues {
                command.message.reply(key: "rescue.unfiled.entry", fromCommand: command, map: [
                    "client": rescue.client ?? "unknown client",
                    "system": rescue.system ?? "unknown system",
                    "platform": rescue.platform?.ircRepresentable ?? "unknown platform",
                    "link": "https://fuelrats.com/paperwork/\(rescue.id.rawValue.uuidString.lowercased())"
                ])
            }
        }, error: { _ in
            command.message.error(key: "rescue.unfiled.error", fromCommand: command)
        })
    }

    @BotCommand(
        ["quoteid"],
        parameters: 1...1,
        category: .rescues,
        description: "Show all information about a case by UUID",
        paramText: "<rescue uuid>",
        example: "035c1a9a-c066-40d0-bc4a-bee736879fd5",
        permission: .RescueRead
    )
    var didReceiveQuoteRemoteCommand = { command in
        guard let id = UUID(uuidString: command.parameters[0]) else {
            command.message.error(key: "rescue.quoteid.invalid", fromCommand: command, map: [
                "id": command.parameters[0]
            ])
            return
        }

        FuelRatsAPI.getRescue(id: id, complete: { result in
            let rescue = result.body.data!.primary.value

            command.message.reply(key: "rescue.quoteid.title", fromCommand: command, map: [
                "client": rescue.client ?? "unknown client",
                "system": rescue.system ?? "unknown system",
                "platform": rescue.platform?.ircRepresentable ?? "unknown platform",
                "created": rescue.createdAt,
                "updated": rescue.updatedAt,
                "id": rescue.id.rawValue.ircRepresentation
            ])

            for (index, quote) in rescue.quotes.enumerated() {
                command.message.reply(key: "rescue.quoteid.quote", fromCommand: command, map: [
                    "index": index,
                    "author": quote.lastAuthor,
                    "time": quote.updatedAt,
                    "message": quote.message
                ])
            }
        }, error: { _ in
            command.message.error(key: "rescue.quoteid.error", fromCommand: command, map: [
                "id": id.ircRepresentation
            ])
        })
    }

    @BotCommand(
        ["reopen"],
        parameters: 1...1,
        category: .rescues,
        description: "Add a previously closed case back onto the board.",
        paramText: "<rescue uuid>",
        example: "035c1a9a-c066-40d0-bc4a-bee736879fd5",
        permission: .RescueWrite
    )
    var didReceiveReopenCommand = { command in
        guard let id = UUID(uuidString: command.parameters[0]) else {
            command.message.error(key: "rescue.reopen.invalid", fromCommand: command, map: [
                "id": command.parameters[0]
            ])
            return
        }

        if let existingRescue = mecha.rescueBoard.rescues.first(where: {
            $0.id == id
        }) {
            command.message.error(key: "rescue.reopen.exists", fromCommand: command, map: [
                "id": id,
                "caseId": existingRescue.commandIdentifier!
            ])
            return
        }

        FuelRatsAPI.getRescue(id: id, complete: { result in
            let apiRescue = result.body.data!.primary.value
            let rats = result.assignedRats()
            let firstLimpet = result.firstLimpet()

            let rescue = LocalRescue(
                fromAPIRescue: apiRescue,
                withRats: rats,
                firstLimpet: firstLimpet,
                onBoard: mecha.rescueBoard
            )
            if rescue.hasConflictingId(inBoard: mecha.rescueBoard) {
                rescue.commandIdentifier = mecha.rescueBoard.getNewIdentifier()
            }
            rescue.outcome = nil
            rescue.status = .Open

            mecha.rescueBoard.rescues.append(rescue)
            rescue.syncUpstream(fromBoard: mecha.rescueBoard)
            command.message.reply(key: "rescue.reopen.opened", fromCommand: command, map: [
                "id": id.ircRepresentation,
                "caseId": rescue.commandIdentifier!
            ])
        }, error: { _ in
            command.message.error(key: "rescue.reopen.error", fromCommand: command)
        })
    }
}
