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
import Regex

class BoardCommands: IRCBotModule {
    var name: String = "Rescue Board"
    internal let distanceFormatter: NumberFormatter

    required init(_ moduleManager: IRCBotModuleManager) {
        self.distanceFormatter = NumberFormatter()
        self.distanceFormatter.numberStyle = .decimal
        self.distanceFormatter.groupingSize = 3
        self.distanceFormatter.maximumFractionDigits = 1
        self.distanceFormatter.roundingMode = .halfUp

        moduleManager.register(module: self)
    }

    @BotCommand(
        ["sync", "fbr", "refreshboard", "reindex", "resetboard", "forcerestartboard",
                   "forcerefreshboard", "frb", "boardrefresh"],
        category: .rescues,
        description: "Force MechaSqueak to perform a synchronization of data between itself and the rescue server.",
        permission: .RescueWrite,
        allowedDestinations: .Channel
    )
    var didReceiveSyncCommand = { command in
        mecha.rescueBoard.syncBoard()
    }

    @BotCommand(
        ["list"],
        [.options(["i", "a", "q", "r", "u", "@"]), .argument("pc"), .argument("xb"), .argument("ps"), .argument("horizons"), .argument("odyssey")],
        category: .board,
        description: "List all the rescues on the board. Use flags to filter results or change what is displayed",
        permission: .DispatchRead,
        cooldown: .seconds(120)
    )
    var didReceiveListCommand = { command in
        var arguments: [ListCommandArgument] = command.options.compactMap({
            return ListCommandArgument(rawValue: String($0))
        })
        
        arguments.append(contentsOf: command.namedOptions.compactMap({
            return ListCommandArgument(rawValue: $0)
        }))
        
        let filteredPlatforms = command.namedOptions.compactMap({
            GamePlatform(rawValue: $0)
        })

        let rescues = mecha.rescueBoard.rescues.filter({
            if filteredPlatforms.count > 0 && ($0.platform == nil || filteredPlatforms.contains($0.platform!)) == false {
                return false
            }
            if arguments.contains(.showOnlyAssigned) && $0.rats.count == 0 && $0.unidentifiedRats.count == 0 {
                return false
            }

            if arguments.contains(.showOnlyUnassigned) && ($0.rats.count > 0 || $0.unidentifiedRats.count > 0) {
                return false
            }

            if arguments.contains(.showOnlyQueued) && $0.status != .Queued {
                return false
            }

            if arguments.contains(.showOnlyInactive) && $0.status != .Inactive {
                return false
            }

            if arguments.contains(.showOnlyActive) && $0.status != .Open {
                return false
            }
            
            if command.namedOptions.contains("horizons") && command.namedOptions.contains("odyssey") == false && $0.odyssey == true {
                return false
            }
            
            if command.namedOptions.contains("horizons") == false && command.namedOptions.contains("odyssey") && $0.odyssey == false {
                return false
            }

            return true
        }).sorted(by: {
             $1.commandIdentifier > $0.commandIdentifier
        }).sorted(by: { $0.status == .Open && $1.status == .Inactive })

        guard rescues.count > 0 else {
            var flags = ""
            if arguments.count > 0 {
                flags = "(Flags: \(arguments.map({ $0.description }).joined(separator: ", ")))"
            }
            command.message.reply(key: "board.list.none", fromCommand: command, map: [
                "flags": flags
            ])
            return
        }

        let generatedList = rescues.map({ (rescue: LocalRescue) -> String in
            let output = try! stencil.renderLine(name: "list.stencil", context: [
                "rescue": rescue,
                "platform": rescue.platform.ircRepresentable
            ])
            return output
        })
        
        command.message.reply(list: generatedList, separator: ", ", heading: "\(generatedList.count) rescues found: ")
    }

    @AsyncBotCommand(
        ["clear", "close"],
        [.options(["f", "p"]), .param("case id/client", "4"), .param("first limpet rat", "SpaceDawg", .standard, .optional)],
        category: .board,
        description: "Closes a case and posts the paperwork link. Optional parameter takes the nick of the person that got first limpet (fuel+).",
        permission: .DispatchWrite,
        allowedDestinations: .Channel
    )
    var didReceiveCloseCommand = { command in
        let message = command.message
        let override = command.forceOverride
        let noFirstLimpet = command.options.contains("p")
        
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }
        
        if rescue.isRecentDrill && command.message.destination != rescue.channel {
            command.message.error(key: "board.close.drill", fromCommand: command, map: [ "channel": rescue.channel?.name ?? "?" ])
            return
        }

        var firstLimpet: Rat?
        let target = command.parameters[safe: 1] ?? ""
        if command.parameters.count > 1 && configuration.general.drillMode == false {
            guard
                let rat = message.destination.member(named: command.parameters[1])?.getRatRepresenting(platform: rescue.platform)
            else {
                command.message.error(key: "board.close.notfound", fromCommand: command, map: [
                    "caseId": rescue.commandIdentifier,
                    "firstLimpet": command.parameters[1]
                ])
                return
            }
            
            firstLimpet = rat
            
            let currentRescues = rat.currentRescues
            if currentRescues.contains(where: { $0.id == rescue.id }) == false, let conflictCase = currentRescues.first, override == false {
                command.message.error(key: "board.close.conflict", fromCommand: command, map: [
                    "rat": target,
                    "closeCaseId": rescue.commandIdentifier,
                    "conflictId": conflictCase.commandIdentifier
                ])
                return
            }
         }

        var closeFl = noFirstLimpet ? nil : firstLimpet
        
        do {
            try await rescue.close(firstLimpet: closeFl)
            
            mecha.rescueBoard.rescues.removeAll(where: {
                $0.id == rescue.id
            })

            mecha.rescueBoard.recentlyClosed[rescue.commandIdentifier] = rescue

            if let timer = mecha.rescueBoard.prepTimers[rescue.id] {
                timer?.cancel()
                mecha.rescueBoard.prepTimers.removeValue(forKey: rescue.id)
            }

            command.message.reply(key: "board.close.success", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier,
                "client": rescue.clientDescription
            ])

            guard configuration.general.drillMode == false else {
                return
            }
            
            let shortUrl = await URLShortener.attemptShorten(url: URL(string: "https://fuelrats.com/paperwork/\(rescue.id.uuidString.lowercased())/edit")!)
            
            if let firstLimpet = firstLimpet {
                var key = "board.close.reportFirstlimpet"
                if firstLimpet.id.rawValue == UUID(uuidString: "75c90d14-5b45-4054-a391-47c70162de78") {
                    key += ".aleethia"
                }
                message.client.sendMessage(
                    toChannelName: configuration.general.reportingChannel,
                    withKey: key,
                    mapping: [
                        "caseId": rescue.commandIdentifier,
                        "firstLimpet": target,
                        "client": rescue.clientDescription,
                        "link": shortUrl
                    ]
                )

                message.client.sendMessage(
                    toChannelName: command.parameters[1],
                    withKey: "board.close.firstLimpetPaperwork",
                    mapping: [
                        "caseId": rescue.commandIdentifier,
                        "client": rescue.clientDescription,
                        "link": shortUrl
                    ]
                )
                return
            } else {
                message.client.sendMessage(
                    toChannelName: command.message.user.nickname,
                    withKey: "board.close.firstLimpetPaperwork",
                    mapping: [
                        "caseId": rescue.commandIdentifier,
                        "client": rescue.clientDescription,
                        "link": shortUrl
                    ]
                )
            }
            message.client.sendMessage(
                toChannelName: configuration.general.reportingChannel,
                withKey: "board.close.report",
                mapping: [
                    "caseId": rescue.commandIdentifier,
                    "link": shortUrl,
                    "client": rescue.clientDescription
                ]
            )
        } catch {
            command.message.reply(key: "board.close.error", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier
            ])
        }
    }

    @AsyncBotCommand(
        ["trash", "md", "purge", "mdadd"],
        [.options(["f"]), .param("case id/client", "4"), .param("message", "client left before rats were assigned", .continuous)],
        category: .board,
        description: "Moves a case to the trash list with a message describing why it was deleted",
        permission: .DispatchWrite
    )
    var didReceiveTrashCommand = { command in
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }
        
        if rescue.isRecentDrill && command.message.destination != rescue.channel {
            command.message.error(key: "board.close.drill", fromCommand: command, map: [ "channel": rescue.channel?.name ?? "?" ])
            return
        }
        let forced = command.forceOverride
        
        guard rescue.banned == false else {
            command.message.reply(key: "board.trash.banned", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier
            ])
            return
        }

        guard (rescue.rats.count == 0 && rescue.unidentifiedRats.count == 0) || forced else {
            command.message.reply(key: "board.trash.assigned", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier
            ])
            return
        }

        let reason = command.parameters[1]

        do {
            try await rescue.trash(reason: reason)
            
            mecha.rescueBoard.rescues.removeAll(where: {
                $0.id == rescue.id
            })
            mecha.rescueBoard.recentlyClosed[rescue.commandIdentifier] = rescue

            command.message.reply(key: "board.trash.success", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier,
                "client": rescue.clientDescription
            ])
            if let timer = mecha.rescueBoard.prepTimers[rescue.id] {
                timer?.cancel()
                mecha.rescueBoard.prepTimers.removeValue(forKey: rescue.id)
            }
        } catch {
            command.message.reply(key: "board.trash.error", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier
            ])
        }
    }

    @AsyncBotCommand(
        ["paperwork", "pwl"],
        [.param("case id/client", "4")],
        category: .board,
        description: "Retrieves the paperwork link for a case on the board.",
        permission: .DispatchRead
    )
    var didReceivePaperworkLinkCommand = { command in
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        let shortUrl = await URLShortener.attemptShorten(url: URL(string: "https://fuelrats.com/paperwork/\(rescue.id.uuidString.lowercased())/edit")!)
        command.message.reply(key: "board.pwl.generated", fromCommand: command, map: [
            "caseId": rescue.commandIdentifier,
            "link": shortUrl
        ])
    }

    @BotCommand(
        ["quiet", "last"],
        category: .other,
        description: "Displays the amount of time since the last rescue",
        permission: .DispatchRead,
        cooldown: .seconds(300)
    )
    var didReceiveQuietCommand = { command in
        guard let lastSignalDate = mecha.rescueBoard.lastSignalReceived else {
            command.message.reply(key: "board.quiet.unknown", fromCommand: command)
            return
        }

        guard mecha.rescueBoard.rescues.first(where: { rescue in
            return rescue.status != .Inactive && rescue.unidentifiedRats.count == 0 && rescue.rats.count == 0 &&
                command.message.user.getRatRepresenting(platform: rescue.platform) != nil
        }) == nil else {
            command.message.reply(key: "board.quiet.currentcalljumps", fromCommand: command)
            return
        }

        guard mecha.rescueBoard.rescues.first(where: { rescue in
            return rescue.status != .Inactive
        }) == nil else {
            command.message.reply(key: "board.quiet.current", fromCommand: command)
            return
        }

        let timespan = Date().timeIntervalSince(lastSignalDate)

        let timespanString = lastSignalDate.timeAgo

        if timespan >= 12 * 60 * 60 {
            command.message.reply(key: "board.quiet.quiet", fromCommand: command, map: [
                "timespan": timespanString
            ])
            return
        }

        if timespan >= 15 * 60 {
            command.message.reply(key: "board.quiet.notrecent", fromCommand: command, map: [
                "timespan": timespanString
            ])
            return
        }

        command.message.reply(key: "board.quiet.recent", fromCommand: command, map: [
            "timespan": timespanString
        ])
    }

    @AsyncBotCommand(
        ["sysc"],
        [.param("case id/client", "4"), .param("number", "1")],
        category: .board,
        description: "Correct the system of a case to one of the options provided by the system correction search.",
        permission: .RescueWriteOwn,
        allowedDestinations: .Channel
    )
    var didReceiveSystemCorrectionCommand = { command in
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        guard let corrections = rescue.system?.availableCorrections, corrections.count > 0 else {
            command.message.error(key: "sysc.nocorrections", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier,
                "client": rescue.clientDescription
            ])
            return
        }

        guard let index = Int(command.parameters[1]), index <= corrections.count, index > 0 else {
            command.message.error(key: "sysc.invalidindex", fromCommand: command, map: [
                "index": command.parameters[1]
            ])
            return
        }
        let selectedCorrection = corrections[index - 1]
        
        guard let starSystem = try? await SystemsAPI.getSystemInfo(forSystem: selectedCorrection) else {
            return
        }
        rescue.system?.merge(starSystem)
        try? await rescue.syncUpstream(fromCommand: command)

        command.message.reply(key: "board.syschange", fromCommand: command, map: [
            "caseId": rescue.commandIdentifier,
            "client": rescue.clientDescription,
            "systemInfo": rescue.system.description
        ])
    }

    static func assertGetRescueId (command: IRCBotCommand) -> LocalRescue? {
        guard let rescue = mecha.rescueBoard.findRescue(withCaseIdentifier: command.parameters[0]) else {
            command.message.error(key: "board.casenotfound", fromCommand: command, map: [
                "caseIdentifier": command.parameters[0]
            ])
            return nil
        }

        return rescue
    }
    
    @BotCommand(
        ["sprep"],
        [.param("case id/client", "4")],
        category: .board,
        description: "Silences the prep warning on a case",
        permission: .DispatchWrite,
        allowedDestinations: .Channel
    )
    var didReceiveSilencePrepCommand = { command in
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        if let timer = mecha.rescueBoard.prepTimers[rescue.id] {
            timer?.cancel()
            mecha.rescueBoard.prepTimers.removeValue(forKey: rescue.id)
        }
        command.message.reply(key: "board.sprep", fromCommand: command, map: [
            "caseId": rescue.commandIdentifier
        ])
    }
}

enum ListCommandArgument: String {
    case showOnlyInactive = "i"
    case showOnlyActive = "a"
    case showOnlyQueued = "q"
    case showOnlyAssigned = "r"
    case showOnlyUnassigned = "u"
    case includeCaseIds = "@"
    case showOnlyPC = "pc"
    case showOnlyXbox = "xb"
    case showOnlyPS = "ps"
    case showOnlyHorizons = "horizons"
    case showOnlyOdyssey = "odyssey"

    var description: String {
        let maps: [ListCommandArgument: String] = [
            .showOnlyActive: "Show Only Active",
            .showOnlyInactive: "Show only Inactive",
            .showOnlyQueued: "Show only Queued",
            .showOnlyAssigned: "Show only Assigned",
            .showOnlyUnassigned: "Show only Unassigned",
            .includeCaseIds: "Include UUIDs",
            .showOnlyPC: "Show only PC cases",
            .showOnlyXbox: "Show only Xbox cases",
            .showOnlyPS: "Show only Playstation cases",
            .showOnlyHorizons: "Show only Horizons cases",
            .showOnlyOdyssey: "Show only Odyssey cases"
        ]
        return maps[self]!
    }
}
