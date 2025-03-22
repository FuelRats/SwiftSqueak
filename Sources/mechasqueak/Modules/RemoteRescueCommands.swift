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

import AsyncHTTPClient
import Foundation
import IRCKit

class RemoteRescueCommands: IRCBotModule {
    var name: String = "Remote Rescue Commands"

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @BotCommand(
        ["closed", "recent"],
        [.param("number of cases", "10", .standard, .optional)],
        category: .rescues,
        description: "Shows recently closed cases.",
        permission: .DispatchRead
    )
    var didReceiveRecentlyClosedCommand = { command in
        if command.message.destination.isPrivateMessage == false
            && configuration.general.drillMode == false
        {
            command.message.reply(
                key: "command.replyprivate", fromCommand: command,
                map: [
                    "nick": command.message.user.nickname
                ])
        }
        var closeCount = 3
        if command.parameters.count > 0 {
            guard let count = Int(command.parameters[0]) else {
                command.message.error(
                    key: "rescue.closed.invalid", fromCommand: command,
                    map: [
                        "count": command.parameters[0]
                    ])
                return
            }

            guard count <= 10 && count > 0 else {
                command.message.error(
                    key: "rescue.closed.invalid", fromCommand: command,
                    map: [
                        "count": count
                    ])
                return
            }
            closeCount = count
        }

        do {
            let results = try await FuelRatsAPI.getRecentlyClosedRescues(count: closeCount)
            let rescueList = results.body.data!.primary.values.enumerated().map({ (index, rescue) in
                return lingo.localize(
                    "rescue.closed.entry", locale: command.locale.short,
                    interpolations: [
                        "index": index,
                        "client": rescue.client ?? "unknown client",
                        "platform": rescue.platform.ircRepresentable,
                        "system": rescue.system ?? "unknown system",
                        "id": rescue.id.rawValue.ircRepresentation,
                    ])
            })

            command.message.replyPrivate(
                key: "rescue.closed.list", fromCommand: command,
                map: [
                    "count": closeCount
                ])

            command.message.replyPrivate(list: rescueList, separator: " - ")
        } catch {
            command.message.error(key: "rescue.closed.error", fromCommand: command)
        }
    }

    @BotCommand(
        ["delete"],
        [.param("rescue uuid", "3811e593-160b-45af-bf5e-ab8b5f26b718", .multiple)],
        category: .rescues,
        description:
            "Delete rescues by UUID, cannot be used on any rescue that is currently on the board.",
        permission: .RescueWrite
    )
    var didReceiveDeleteCommand = { command in
        var ids: [UUID] = []
        var invalidIds: [String] = []

        for parameter in command.parameters {
            if let id = UUID(uuidString: parameter) {
                ids.append(id)
            } else {
                invalidIds.append(parameter)
            }
        }

        if invalidIds.count > 0 {
            command.message.error(
                key: "rescue.delete.invalid", fromCommand: command,
                map: [
                    "id": invalidIds.joined(separator: ", ")
                ])
            return
        }

        var successDeletes: [UUID] = []
        var failedDeletes: [UUID] = []
        for id in ids {
            if let (boardId, boardRescue) = board.rescues.first(where: { $0.value.id == id }) {
                command.message.reply(
                    key: "rescue.delete.active", fromCommand: command,
                    map: [
                        "id": boardRescue.id.ircRepresentation,
                        "caseId": boardId,
                    ])
                continue
            }
            do {
                try await FuelRatsAPI.deleteRescue(id: id, command: command)
                successDeletes.append(id)
            } catch {
                failedDeletes.append(id)
            }
        }

        if failedDeletes.count > 0 {
            let failedIds =
                failedDeletes.count == 1
                ? failedDeletes.first!.ircRepresentation
                : failedDeletes.map({ $0.ircRepresentation }).joined(separator: ", ")
            command.message.error(
                key: "rescue.delete.failure", fromCommand: command,
                map: [
                    "id": failedIds
                ])
        }

        if successDeletes.count > 0 {
            let successIds =
                successDeletes.count == 1
                ? successDeletes.first!.ircRepresentation
                : successDeletes.map({ $0.ircRepresentation }).joined(separator: ", ")
            command.message.reply(
                key: "rescue.delete.success", fromCommand: command,
                map: [
                    "id": successIds
                ])
        }
    }

    @BotCommand(
        ["deleteall", "cleartrash"],
        [.param("time ago", "48h", .standard, .optional)],
        category: .rescues,
        description: "Delete all rescues currently in the trashlist",
        permission: .UserWrite
    )
    var didReceiveDeleteAllCommand = { command in
        do {
            let results = try await FuelRatsAPI.getRescuesInTrash()

            let rescues = results.body.data!.primary.values
            guard rescues.count > 0 else {
                command.message.replyPrivate(key: "rescue.trashlist.empty", fromCommand: command)
                return
            }
            
            var timeAgo = Date.now
            if let argument = command.parameters.first {
                if let parsedTimeAgo = TimeInterval.parse(argument) {
                    timeAgo = Date.now - parsedTimeAgo
                } else {
                    command.message.error(
                        key: "general.invalid-argument", fromCommand: command,
                        map: ["argument": argument])
                    return
                }
            }

            for rescue in rescues.filter({
                $0.createdAt < timeAgo
            }) {
                do {
                    try await FuelRatsAPI.deleteRescue(id: rescue.id.rawValue, command: command)
                    command.message.replyPrivate(
                        key: "rescue.delete.success", fromCommand: command,
                        map: [
                            "id": rescue.id.rawValue.ircRepresentation
                        ])
                } catch {
                    command.message.error(
                        key: "rescue.delete.failure", fromCommand: command,
                        map: [
                            "id": rescue.id.rawValue.ircRepresentation
                        ])
                }
            }
        } catch {
            command.message.error(key: "rescue.trashlist.error", fromCommand: command)
        }
    }

    @BotCommand(
        ["trashlist", "mdlist", "purgelist", "listtrash"],
        category: .rescues,
        description:
            "Shows all the rescues that have been added to the trash list but not yet deleted",
        permission: .DispatchRead
    )
    var didReceiveListTrashcommand = { command in
        do {
            let results = try await FuelRatsAPI.getRescuesInTrash()

            let rescues = results.body.data!.primary.values
            guard rescues.count > 0 else {
                command.message.replyPrivate(key: "rescue.trashlist.empty", fromCommand: command)
                return
            }

            command.message.replyPrivate(
                key: "rescue.trashlist.list", fromCommand: command,
                map: [
                    "count": rescues.count
                ])

            for rescue in rescues {
                let format =
                    rescue.attributes.codeRed.value
                    ? "rescue.trashlist.entrycr" : "rescue.trashlist.entry"

                let (lastEditUser, lastEditRat) = results.lastEditUserFor(rescue: rescue)
                command.message.replyPrivate(
                    key: format, fromCommand: command,
                    map: [
                        "id": rescue.id.rawValue.ircRepresentation,
                        "client": rescue.client ?? "unknown client",
                        "platform": rescue.platform.ircRepresentable,
                        "reason": rescue.notes,
                        "timeAgo": rescue.attributes.updatedAt.value.timeAgo(maximumUnits: 1),
                        "by": lastEditRat?.name ?? "unknown",
                    ])
            }
        } catch {
            debug("TRASH" + String(describing: error))
            command.message.error(key: "rescue.trashlist.error", fromCommand: command)
        }
    }

    @BotCommand(
        ["restore", "mdremove", "trashremove", "mdr", "tlr", "trashlistremove", "mdd", "mddeny"],
        [.param("rescue uuid", "3811e593-160b-45af-bf5e-ab8b5f26b718")],
        category: .rescues,
        description: "Restore a case from the trash list.",
        permission: .RescueWrite
    )
    var didReceiveRestoreTrashCommand = { command in
        guard let id = UUID(uuidString: command.parameters[0]) else {
            command.message.error(
                key: "rescue.restore.invalid", fromCommand: command,
                map: [
                    "id": command.parameters[0]
                ])
            return
        }

        do {
            guard let result = try await FuelRatsAPI.getRescue(id: id) else {
                command.message.error(
                    key: "rescue.restore.error", fromCommand: command,
                    map: [
                        "id": id.ircRepresentation
                    ])
                return
            }

            var rescue = result.body.data!.primary.value

            guard rescue.outcome == .Purge else {
                command.message.error(
                    key: "rescue.restore.nottrash", fromCommand: command,
                    map: [
                        "id": id.ircRepresentation
                    ])
                return
            }

            rescue = rescue.tappingAttributes({ $0.outcome = .init(value: nil) })

            try await rescue.update(command: command)
        } catch {
            command.message.error(
                key: "rescue.restore.error", fromCommand: command,
                map: [
                    "id": id.ircRepresentation
                ])
        }
    }

    @BotCommand(
        ["unfiled", "pwn", "paperworkneeded", "needspaperwork", "npw"],
        category: .rescues,
        description: "Get a list of rescues that have not had their paperwork completed.",
        permission: .DispatchRead,
        allowedDestinations: .PrivateMessage
    )
    var didReceiveUnfiledListCommand = { command in
        if command.message.destination.isPrivateMessage == false
            && configuration.general.drillMode == false
        {
            command.message.reply(
                key: "command.replyprivate", fromCommand: command,
                map: [
                    "nick": command.message.user.nickname
                ])
        }
        do {
            let results = try await FuelRatsAPI.getUnfiledRescues()

            let rescues = results.body.data!.primary.values
            guard rescues.count > 0 else {
                command.message.replyPrivate(key: "rescue.unfiled.empty", fromCommand: command)
                return
            }

            command.message.replyPrivate(
                key: "rescue.unfiled.list", fromCommand: command,
                map: [
                    "count": rescues.count
                ])

            for rescue in rescues {
                let firstLimpet = results.body.includes![Rat.self].first(where: {
                    $0.id.rawValue == rescue.relationships.firstLimpet?.id?.rawValue
                })

                command.message.replyPrivate(
                    key: "rescue.unfiled.entry", fromCommand: command,
                    map: [
                        "client": rescue.client ?? "unknown client",
                        "system": rescue.system ?? "unknown system",
                        "platform": rescue.platform.ircRepresentable,
                        "firstLimpet": firstLimpet?.attributes.name.value ?? "unknown rat",
                        "link":
                            "https://fuelrats.com/paperwork/\(rescue.id.rawValue.uuidString.lowercased())/edit",
                        "timeAgo": rescue.attributes.updatedAt.value.timeAgo(maximumUnits: 1),
                    ])
            }
        } catch {
            command.message.error(key: "rescue.unfiled.error", fromCommand: command)
        }
    }

    @BotCommand(
        ["quoteid"],
        [.param("rescue uuid", "3811e593-160b-45af-bf5e-ab8b5f26b718")],
        category: .rescues,
        description: "Show all information about a case by UUID",
        permission: .DispatchRead
    )
    var didReceiveQuoteRemoteCommand = { command in
        guard let id = UUID(uuidString: command.parameters[0]) else {
            command.message.error(
                key: "rescue.quoteid.invalid", fromCommand: command,
                map: [
                    "id": command.parameters[0]
                ])
            return
        }

        do {
            guard let rescue = try await FuelRatsAPI.getRescue(id: id)?.body.data?.primary.value
            else {
                command.message.error(
                    key: "rescue.quoteid.error", fromCommand: command,
                    map: [
                        "id": id.ircRepresentation
                    ])
                return
            }

            if command.message.destination.isPrivateMessage == false
                && configuration.general.drillMode == false
            {
                command.message.reply(
                    key: "command.replyprivate", fromCommand: command,
                    map: [
                        "nick": command.message.user.nickname
                    ])
            }

            command.message.replyPrivate(
                key: "rescue.quoteid.title", fromCommand: command,
                map: [
                    "client": rescue.client ?? "unknown client",
                    "system": rescue.system ?? "unknown system",
                    "platform": rescue.platform.ircRepresentable,
                    "created": rescue.createdAt.ircRepresentable,
                    "updated": rescue.updatedAt.ircRepresentable,
                    "id": rescue.id.rawValue.ircRepresentation,
                ])

            for (index, quote) in rescue.quotes.enumerated() {
                command.message.replyPrivate(
                    key: "rescue.quoteid.quote", fromCommand: command,
                    map: [
                        "index": index,
                        "author": quote.lastAuthor,
                        "time": quote.updatedAt,
                        "message": quote.message,
                    ])
            }
        } catch {
            command.message.error(
                key: "rescue.quoteid.error", fromCommand: command,
                map: [
                    "id": id.ircRepresentation
                ])
        }
    }

    @BotCommand(
        ["reopen"],
        [.param("rescue uuid/client name", "3811e593-160b-45af-bf5e-ab8b5f26b718")],
        category: .rescues,
        description: "Add a previously closed case back onto the board",
        permission: .RescueWrite
    )
    var didReceiveReopenCommand = { command in
        if Int(command.parameters[0]) != nil {
            var correctedCommand = command
            correctedCommand.command = "unclose"
            await IRCBotModuleManager.handleIncomingCommand(ircBotCommand: correctedCommand)
            return
        }

        guard configuration.general.drillMode == false else {
            command.message.error(key: "rescue.reopen.drillmode", fromCommand: command)
            return
        }

        var rescue: Rescue? = nil
        var caseId = 0
        if let id = UUID(uuidString: command.parameters[0]) {
            if let (existingId, existingRescue) = board.rescues.first(where: {
                $0.value.id == id
            }) {
                command.message.error(
                    key: "rescue.reopen.exists", fromCommand: command,
                    map: [
                        "id": id,
                        "caseId": existingId,
                    ])
                return
            }

            guard let result = try? await FuelRatsAPI.getRescue(id: id) else {
                command.message.error(
                    key: "rescue.reopen.error", fromCommand: command,
                    map: [
                        "id": id.ircRepresentation
                    ])
                return
            }
            let apiRescue = result.body.data!.primary.value

            caseId = apiRescue.commandIdentifier
            let rats = result.assignedRats()
            let (lastEditUser, lastEditRat) = result.lastEditUser()
            let firstLimpet = result.firstLimpet()

            rescue = Rescue(
                fromAPIRescue: apiRescue,
                withRats: rats,
                firstLimpet: firstLimpet,
                lastEditUser: lastEditUser,
                onBoard: board
            )
        } else {
            let clientRescues = try? await FuelRatsAPI.getRescues(forClient: command.parameters[0])
            guard let apiRescue = clientRescues?.body.data?.primary.values.first else {
                command.message.error(
                    key: "rescue.reopen.error", fromCommand: command,
                    map: [
                        "id": command.parameters[0]
                    ])
                return
            }

            caseId = apiRescue.commandIdentifier
            let rats = clientRescues?.assignedRatsFor(rescue: apiRescue) ?? []
            let (lastEditUser, _) = clientRescues!.lastEditUserFor(rescue: apiRescue)
            let firstLimpet = clientRescues?.firstLimpetFor(rescue: apiRescue)
            rescue = Rescue(
                fromAPIRescue: apiRescue,
                withRats: rats,
                firstLimpet: firstLimpet,
                lastEditUser: lastEditUser,
                onBoard: board
            )
        }
        guard let rescue = rescue else {
            command.message.error(
                key: "rescue.reopen.invalid", fromCommand: command,
                map: [
                    "id": command.parameters[0]
                ])
            return
        }

        rescue.outcome = nil
        rescue.status = .Open
        let newCaseId = await board.insert(rescue: rescue, preferringIdentifier: caseId)
        try? rescue.save(command)

        command.message.reply(
            key: "rescue.reopen.opened", fromCommand: command,
            map: [
                "id": rescue.id.ircRepresentation,
                "caseId": newCaseId,
            ])
    }

    @BotCommand(
        ["unclose"],
        [.param("recently closed case number", "5")],
        category: .rescues,
        description:
            "Add a previously closed case back onto the board by its previous case number.",
        permission: .DispatchWrite
    )
    var didReceiveUncloseCommand = { command in
        guard let caseNumber = Int(command.parameters[0]),
            let closedRescue = board.recentlyClosed[caseNumber]
        else {
            command.message.error(
                key: "board.casenotfound", fromCommand: command,
                map: [
                    "caseIdentifier": command.parameters[0]
                ])
            return
        }

        if let existingRescue = board.rescues.first(where: {
            $0.value.id == closedRescue.id
        }) {
            command.message.error(
                key: "rescue.reopen.exists", fromCommand: command,
                map: [
                    "id": closedRescue.id,
                    "caseId": existingRescue.key,
                ])
            return
        }

        guard configuration.general.drillMode == false else {
            guard let rescue = board.recentlyClosed[caseNumber] else {
                command.message.error(
                    key: "rescue.reopen.error", fromCommand: command,
                    map: [
                        "id": caseNumber
                    ])
                return
            }

            rescue.outcome = nil
            rescue.status = .Open

            let caseId = await board.insert(rescue: rescue, preferringIdentifier: caseNumber)
            command.message.reply(
                key: "rescue.reopen.opened", fromCommand: command,
                map: [
                    "id": rescue.id.ircRepresentation,
                    "caseId": caseId,
                ])
            return
        }

        guard let result = try? await FuelRatsAPI.getRescue(id: closedRescue.id) else {
            command.message.error(
                key: "rescue.reopen.error", fromCommand: command,
                map: [
                    "id": closedRescue.id
                ])
            return
        }

        let apiRescue = result.body.data!.primary.value
        let rats = result.assignedRats()
        let (lastEditUser, lastEditRat) = result.lastEditUser()
        let firstLimpet = result.firstLimpet()

        let rescue = Rescue(
            fromAPIRescue: apiRescue,
            withRats: rats,
            firstLimpet: firstLimpet,
            lastEditUser: lastEditUser,
            onBoard: board
        )
        rescue.outcome = nil
        rescue.status = .Open
        rescue.uploaded = true

        let caseID = await board.insert(
            rescue: rescue, preferringIdentifier: apiRescue.commandIdentifier)
        try? rescue.save(command)
        command.message.reply(
            key: "rescue.reopen.opened", fromCommand: command,
            map: [
                "id": closedRescue.id.ircRepresentation,
                "caseId": caseID,
            ])
    }

    @BotCommand(
        ["clientpw", "pwclient"],
        [.argument("all"), .param("client name", "SpaceDawg", .continuous)],
        category: .rescues,
        description: "Get paperwork link for a previous client by name.",
        permission: .RescueWrite
    )
    var didReceiveClientPaperworkCommand = { command in
        do {
            let results = try await FuelRatsAPI.getRescues(forClient: command.parameters[0])

            let rescues = results.body.data!.primary.values
            guard rescues.count > 0 else {
                command.message.error(
                    key: "rescue.clientpw.error", fromCommand: command,
                    map: [
                        "client": command.parameters[0]
                    ])
                return
            }

            if command.has(argument: "all") {
                if command.message.destination.isPrivateMessage == false
                    && configuration.general.drillMode == false
                {
                    command.message.reply(
                        key: "command.replyprivate", fromCommand: command,
                        map: [
                            "nick": command.message.user.nickname
                        ])
                }
                command.message.replyPrivate(
                    key: "rescue.clientpw.heading", fromCommand: command,
                    map: [
                        "client": command.parameters[0]
                    ])
                for (index, rescue) in rescues.enumerated() {
                    let url =
                        "https://fuelrats.com/paperwork/\(rescue.id.rawValue.uuidString.lowercased())/edit"
                    command.message.replyPrivate(
                        key: "rescue.clientpw.entry", fromCommand: command,
                        map: [
                            "index": index,
                            "system": rescue.attributes.system.value ?? "?",
                            "created": rescue.attributes.createdAt.value.ircRepresentable,
                            "link": url,
                        ])
                }
                return
            }

            let rescue = rescues[0]

            let shortUrl = await URLShortener.attemptShorten(
                url: URL(
                    string:
                        "https://fuelrats.com/paperwork/\(rescue.id.rawValue.uuidString.lowercased())/edit"
                )!)
            command.message.reply(
                key: "rescue.clientpw.response", fromCommand: command,
                map: [
                    "client": rescue.attributes.client.value ?? "unknown client",
                    "created": rescue.attributes.createdAt.value.ircRepresentable,
                    "link": shortUrl,
                ])
        } catch {
            command.error(error)
        }
    }

    @BotCommand(
        ["renameid"],
        [
            .param("rescue uuid", "3811e593-160b-45af-bf5e-ab8b5f26b718"),
            .param("client name", "SpaceDawg", .continuous),
        ],
        category: .rescues,
        description: "Change the client name of a closed case",
        permission: .RescueWrite
    )
    var didReceiveRenameIDCommand = { command in
        guard let id = UUID(uuidString: command.parameters[0]) else {
            command.message.error(
                key: "rescue.restore.invalid", fromCommand: command,
                map: [
                    "id": command.parameters[0]
                ])
            return
        }

        do {
            guard let result = try await FuelRatsAPI.getRescue(id: id) else {
                command.message.error(
                    key: "rescue.restore.error", fromCommand: command,
                    map: [
                        "id": id.ircRepresentation
                    ])
                return
            }
            var rescue = result.body.data!.primary.value

            rescue = rescue.tappingAttributes({ $0.client = .init(value: command.parameters[1]) })
            try await rescue.update(command: command)

            command.message.reply(
                key: "rescue.renameid.renamed", fromCommand: command,
                map: [
                    "id": id.ircRepresentation
                ])
        } catch {
            command.message.error(
                key: "rescue.restore.error", fromCommand: command,
                map: [
                    "id": id.ircRepresentation
                ])
        }
    }
}
