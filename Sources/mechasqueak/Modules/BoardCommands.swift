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
import Regex

class BoardCommands: IRCBotModule {
    var name: String = "Rescue Board"
    private var channelMessageObserver: NotificationToken?
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
        parameters: 0...0,
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
        parameters: 0...1,
        category: .board,
        description: "List all the rescues on the board. Use flags to filter results or change what is displayed",
        paramText: "[-iaru@]",
        example: "-i",
        permission: .RescueRead
    )
    var didReceiveListCommand = { command in
        var arguments: [ListCommandArgument] = []
        if command.parameters.count > 0 && command.parameters[0].starts(with: "-") {
            var args = command.parameters[0]
            args = String(args.suffix(from: args.index(after: args.startIndex))).lowercased()

            arguments = args.compactMap({
                return ListCommandArgument(rawValue: $0)
            })
        }

        if arguments.contains(.displayHelpInfo) {
            var helpCommand = command
            helpCommand.command = "!help"
            helpCommand.parameters = ["!list"]
            mecha.helpModule.didReceiveHelpCommand(helpCommand)
            return
        }

        let rescues = mecha.rescueBoard.rescues.filter({
            if arguments.contains(.showOnlyAssigned) && $0.rats.count == 0 && $0.unidentifiedRats.count == 0 {
                return false
            }

            if arguments.contains(.showOnlyUnassigned) && ($0.rats.count > 0 || $0.unidentifiedRats.count > 0) {
                return false
            }

            if arguments.contains(.showOnlyInactive) && $0.status != .Inactive {
                return false
            }

            if arguments.contains(.showOnlyActive) && $0.status != .Open {
                return false
            }

            return true
        }).sorted(by: {
            $1.commandIdentifier! > $0.commandIdentifier!
        })

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

        let format = arguments.contains(.includeCaseIds) ? "includeid" : "default"

        let generatedList = rescues.map({ (rescue: LocalRescue) -> String in
            let inactiveFormat = rescue.status == .Inactive ?
                "board.list.inactivecase.\(format)" : "board.list.case.\(format)"

            return lingo.localize(inactiveFormat, locale: "en-GB", interpolations: [
                "caseId": rescue.commandIdentifier!,
                "id": rescue.id.ircRepresentation,
                "client": rescue.client ?? "?",
                "platform": rescue.platform.ircRepresentable,
                "cr": rescue.codeRed ? "(\(IRCFormat.color(.LightRed, "CR")))" : "",
                "assigned": rescue.assignList != nil
                    && arguments.contains(.showOnlyAssigned) ? "Assigned: \(rescue.assignList!)" : ""
            ])
        }).joined(separator: ", ")

        command.message.reply(key: "board.list.cases", fromCommand: command, map: [
            "cases": generatedList,
            "count": rescues.count
        ])
    }

    @BotCommand(
        ["clear", "close"],
        parameters: 1...2,
        category: .board,
        description: "Closes a case and posts the paperwork link.",
        permission: .RescueWriteOwn,
        allowedDestinations: .Channel
    )
    var didReceiveCloseCommand = { command in
        let message = command.message
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        var firstLimpet: Rat?
        if command.parameters.count > 1 && configuration.general.drillMode == false {
            guard
                let rat = message.destination.member(named: command.parameters[1])?.getRatRepresenting(rescue: rescue)
            else {
                command.message.reply(key: "board.close.notfound", fromCommand: command, map: [
                    "caseId": rescue.commandIdentifier!,
                    "firstLimpet": command.parameters[1]
                ])
                return
            }

            firstLimpet = rat
        }

        rescue.close(fromBoard: mecha.rescueBoard, firstLimpet: firstLimpet, onComplete: {
            mecha.rescueBoard.rescues.removeAll(where: {
                $0.id == rescue.id
            })

            if let timer = mecha.rescueBoard.prepTimers[rescue.id] {
                timer?.cancel()
                mecha.rescueBoard.prepTimers.removeValue(forKey: rescue.id)
            }

            command.message.reply(key: "board.close.success", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier!,
                "client": rescue.client ?? "u\u{200B}nknown client"
            ])

            guard configuration.general.drillMode == false else {
                return
            }

            URLShortener.attemptShorten(
                url: URL(string: "https://fuelrats.com/paperwork/\(rescue.id.uuidString.lowercased())/edit")!,
                complete: { shortUrl in
                if let firstLimpet = firstLimpet {
                    message.client.sendMessage(
                        toChannelName: configuration.general.reportingChannel,
                        withKey: "board.close.reportFirstlimpet",
                        mapping: [
                            "caseId": rescue.commandIdentifier!,
                            "firstLimpet": firstLimpet.attributes.name.value,
                            "client": rescue.client ?? "u\u{200B}nknown client",
                            "link": shortUrl
                        ]
                    )

                    message.client.sendMessage(
                        toChannelName: command.parameters[1],
                        withKey: "board.close.firstLimpetPaperwork",
                        mapping: [
                            "caseId": rescue.commandIdentifier!,
                            "client": rescue.client ?? "u\u{200B}nknown client",
                            "link": shortUrl
                        ]
                    )
                    return
                }
                message.client.sendMessage(
                    toChannelName: configuration.general.reportingChannel,
                    withKey: "board.close.report",
                    mapping: [
                        "caseId": rescue.commandIdentifier!,
                        "link": shortUrl,
                        "client": rescue.client ?? "unknown client"
                    ]
                )
            })

        }, onError: { _ in
            command.message.reply(key: "board.close.error", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier!
            ])
        })
    }

    @BotCommand(
        ["trash", "md", "purge", "mdadd"],
        parameters: 2...2,
        lastParameterIsContinous: true,
        category: .board,
        description: "Moves a case to the trash list with a message describing why it was deleted",
        paramText: "<case id/client> <message>",
        example: "4 client left before rats were assigned ",
        permission: .RescueWriteOwn
    )
    var didReceiveTrashCommand = { command in
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        let reason = command.parameters[1]

        rescue.trash(fromBoard: mecha.rescueBoard, reason: reason, onComplete: {
            mecha.rescueBoard.rescues.removeAll(where: {
                $0.id == rescue.id
            })
            command.message.reply(key: "board.trash.success", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier!
            ])
            if let timer = mecha.rescueBoard.prepTimers[rescue.id] {
                timer?.cancel()
                mecha.rescueBoard.prepTimers.removeValue(forKey: rescue.id)
            }
        }, onError: { _ in
            command.message.reply(key: "board.trash.error", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier!
            ])
        })
    }

    @BotCommand(
        ["paperwork", "pwl"],
        parameters: 1...1,
        category: .board,
        description: "Retrieves the paperwork link for a case on the board.",
        paramText: "<case id/client>",
        example: "4",
        permission: .RescueRead
    )
    var didReceivePaperworkLinkCommand = { command in
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        URLShortener.attemptShorten(
            url: URL(string: "https://fuelrats.com/paperwork/\(rescue.id.uuidString.lowercased())/edit")!,
            complete: { shortUrl in
            command.message.reply(key: "board.pwl.generated", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier!,
                "link": shortUrl
            ])
        })
    }

    @BotCommand(
        ["quiet", "last"],
        parameters: 0...0,
        category: .other,
        description: "Displays the amount of time since the last rescue",
        permission: .RescueRead
    )
    var didReceiveQuietCommand = { command in
        guard let lastSignalDate = mecha.rescueBoard.lastSignalReceived else {
            command.message.reply(key: "board.quiet.unknown", fromCommand: command)
            return
        }

        guard mecha.rescueBoard.rescues.first(where: { $0.status == .Open }) == nil else {
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

    @BotCommand(
        ["sysc"],
        parameters: 2...2,
        category: .board,
        description: "Correct the system of a case to one of the options provided by the system correction search.",
        paramText: "<case id/client> <number>",
        example: "2",
        permission: .RescueWriteOwn,
        allowedDestinations: .Channel
    )
    var didReceiveSystemCorrectionCommand = { command in
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        guard let corrections = rescue.systemCorrections, corrections.count > 0 else {
            command.message.error(key: "sysc.nocorrections", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier!,
                "client": rescue.client ?? "u\u{200B}nknown client"
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

        SystemsAPI.performLandmarkCheck(forSystem: selectedCorrection.name, onComplete: { result in
            switch result {
                case .success(let landmarkResults):
                    guard landmarkResults.landmarks.count > 0 else {
                        return
                    }

                    rescue.system = selectedCorrection.name.uppercased()
                    rescue.syncUpstream(fromBoard: mecha.rescueBoard)

                    let landmarkResult = landmarkResults.landmarks[0]
                    let format = selectedCorrection.permitRequired ? "board.syschange.permit" : "board.syschange.landmark"
                    let distance = NumberFormatter.englishFormatter().string(
                        from: NSNumber(value: landmarkResult.distance) 
                    )!
                    command.message.reply(key: format, fromCommand: command, map: [
                        "caseId": rescue.commandIdentifier!,
                        "client": rescue.client ?? "u\u{200B}nknown client",
                        "system": selectedCorrection.name,
                        "distance": distance,
                        "landmark": landmarkResult.name,
                        "permit": selectedCorrection.permitText ?? ""
                    ])

                case .failure:
                    command.message.error(key: "sysc.seterror", fromCommand: command, map: [
                        "system": selectedCorrection,
                        "caseId": rescue.commandIdentifier!,
                        "client": rescue.client ?? "u\u{200B}nknown client"
                    ])
            }
        })
    }

    @BotCommand(
        ["prep", "psquit", "pcquit", "xquit"],
        parameters: 0...,
        category: nil,
        description: ""
    )
    var didReceivePrepCommand = { command in
        guard command.parameters.count > 0 else {
            return
        }
        let nick = command.parameters.joined(separator: " ").lowercased()

        guard let rescue = mecha.rescueBoard.rescues.first(where: {
            $0.client?.lowercased() == nick || $0.clientNick?.lowercased() == nick
        }) else {
            return
        }

        if let timer = mecha.rescueBoard.prepTimers[rescue.id] {
            timer?.cancel()
            mecha.rescueBoard.prepTimers.removeValue(forKey: rescue.id)
        }
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
}

enum ListCommandArgument: Character {
    case showOnlyInactive = "i"
    case showOnlyActive = "a"
    case showOnlyAssigned = "r"
    case showOnlyUnassigned = "u"
    case includeCaseIds = "@"
    case displayHelpInfo = "h"

    var description: String {
        let maps: [ListCommandArgument: String] = [
            .showOnlyActive: "Show Only Active",
            .showOnlyInactive: "Show only Inactive",
            .showOnlyAssigned: "Show only Assigned",
            .showOnlyUnassigned: "Show only Unassigned",
            .includeCaseIds: "Include UUIDs"
        ]
        return maps[self]!
    }
}
