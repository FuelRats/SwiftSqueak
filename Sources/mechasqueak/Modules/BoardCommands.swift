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

class BoardCommands: IRCBotModule {
    var name: String = "Rescue Board"
    private var channelMessageObserver: NotificationToken?
    internal let distanceFormatter: NumberFormatter

    var commands: [IRCBotCommandDeclaration] {
        return [
            IRCBotCommandDeclaration(
                commands: ["sync", "refreshboard", "reindex", "resetboard", "forcerestartboard",
                           "forcerefreshboard", "frb", "fbr", "boardrefresh"],
                minParameters: 0,
                onCommand: didReceiveSyncCommand(command:),
                maxParameters: 0,
                permission: .RescueWrite,
                allowedDestinations: .Channel
            ),

            IRCBotCommandDeclaration(
                commands: ["list"],
                minParameters: 0,
                onCommand: didReceiveListCommand(command:),
                maxParameters: 1,
                permission: .RescueRead
            ),

            IRCBotCommandDeclaration(
                commands: ["clear", "close"],
                minParameters: 1,
                onCommand: didReceiveCloseCommand(command:),
                maxParameters: 2,
                permission: .RescueWriteOwn,
                allowedDestinations: .Channel
            ),

            IRCBotCommandDeclaration(
                commands: ["active", "inactive", "activate", "deactivate"],
                minParameters: 1,
                onCommand: didReceiveToggleCaseActiveCommand(command:),
                maxParameters: 1,
                permission: .RescueWriteOwn,
                allowedDestinations: .Channel
            ),

            IRCBotCommandDeclaration(
                commands: ["cr", "codered", "casered"],
                minParameters: 1,
                onCommand: didReceiveCodeRedToggleCommand(command:),
                maxParameters: 1,
                permission: .RescueWriteOwn,
                allowedDestinations: .Channel
            ),

            IRCBotCommandDeclaration(
                commands: ["grab"],
                minParameters: 1,
                onCommand: didReceiveGrabCommand(command:),
                maxParameters: 1,
                permission: .RescueWriteOwn,
                allowedDestinations: .Channel
            ),

            IRCBotCommandDeclaration(
                commands: ["quote"],
                minParameters: 1,
                onCommand: didReceiveQuoteCommand(command:),
                maxParameters: 1,
                permission: .RescueRead,
                allowedDestinations: .PrivateMessage
            ),

            IRCBotCommandDeclaration(
                commands: ["inject"],
                minParameters: 1,
                onCommand: didReceiveInjectCommand(command:),
                maxParameters: 2,
                lastParameterIsContinous: true,
                permission: .RescueWriteOwn,
                allowedDestinations: .Channel
            ),

            IRCBotCommandDeclaration(
                commands: ["sub"],
                minParameters: 3,
                onCommand: didReceiveSubstituteCommand(command:),
                maxParameters: 3,
                lastParameterIsContinous: true,
                permission: .RescueWriteOwn,
                allowedDestinations: .Channel
            ),

            IRCBotCommandDeclaration(
                commands: ["system", "sys", "loc", "location"],
                minParameters: 2,
                onCommand: didReceiveSystemChangeCommand(command:),
                maxParameters: 2,
                lastParameterIsContinous: true,
                permission: .RescueWriteOwn,
                allowedDestinations: .Channel
            ),

            IRCBotCommandDeclaration(
                commands: ["title", "operation"],
                minParameters: 2,
                onCommand: didReceiveSetTitleCommand(command:),
                maxParameters: 2,
                lastParameterIsContinous: true,
                permission: .RescueWriteOwn,
                allowedDestinations: .Channel
            ),

            IRCBotCommandDeclaration(
                commands: ["cmdr", "client", "commander"],
                minParameters: 2,
                onCommand: didReceiveClientChangeCommand(command:),
                maxParameters: 2,
                lastParameterIsContinous: true,
                permission: .RescueWriteOwn,
                allowedDestinations: .Channel
            ),

            IRCBotCommandDeclaration(
                commands: ["assign", "go"],
                minParameters: 2,
                onCommand: didReceiveAssignCommand(command:),
                maxParameters: nil,
                permission: .RescueWriteOwn,
                allowedDestinations: .Channel
            ),

            IRCBotCommandDeclaration(
                commands: ["unassign", "deassign", "rm", "remove", "standdown"],
                minParameters: 2,
                onCommand: didReceiveUnassignCommand(command:),
                maxParameters: nil,
                permission: .RescueWriteOwn,
                allowedDestinations: .Channel
            ),

            IRCBotCommandDeclaration(
                commands: ["nick", "ircnick", "nickname"],
                minParameters: 2,
                onCommand: didReceiveClientNickChangeCommand(command:),
                maxParameters: 2,
                lastParameterIsContinous: true,
                permission: .RescueWriteOwn,
                allowedDestinations: .Channel
            ),

            IRCBotCommandDeclaration(
                commands: ["md", "trash", "purge", "mdadd"],
                minParameters: 2,
                onCommand: didReceiveTrashCommand(command:),
                maxParameters: 2,
                lastParameterIsContinous: true,
                permission: .RescueWriteOwn
            ),

            IRCBotCommandDeclaration(
                commands: ["pwl", "paperwork"],
                minParameters: 1,
                onCommand: didReceivePaperworkLinkCommand(command:),
                maxParameters: 1,
                permission: .RescueRead
            ),

            IRCBotCommandDeclaration(
                commands: ["quiet"],
                minParameters: 0,
                onCommand: didReceiveQuietcommand(command:),
                maxParameters: 0,
                permission: .RescueRead
            ),

            IRCBotCommandDeclaration(
                commands: ["prep"],
                minParameters: 0,
                onCommand: didReceivePrepCommand(command:),
                maxParameters: 1,
                permission: nil
            ),

            IRCBotCommandDeclaration(
                commands: ["xb"],
                minParameters: 1,
                onCommand: didReceiveXboxPlatformCommand(command:),
                maxParameters: 1,
                permission: .RescueWriteOwn,
                allowedDestinations: .Channel
            ),

            IRCBotCommandDeclaration(
                commands: ["pc"],
                minParameters: 1,
                onCommand: didReceivePCPlatformCommand(command:),
                maxParameters: 1,
                permission: .RescueWriteOwn,
                allowedDestinations: .Channel
            ),

            IRCBotCommandDeclaration(
                commands: ["ps"],
                minParameters: 1,
                onCommand: didReceivePS4PlatformCommand(command:),
                maxParameters: 1,
                permission: .RescueWriteOwn,
                allowedDestinations: .Channel
            )
        ]
    }

    required init(_ moduleManager: IRCBotModuleManager) {
        self.distanceFormatter = NumberFormatter()
        self.distanceFormatter.numberStyle = .decimal
        self.distanceFormatter.groupingSize = 3
        self.distanceFormatter.maximumFractionDigits = 1
        self.distanceFormatter.roundingMode = .halfUp

        moduleManager.register(module: self)
        self.channelMessageObserver = NotificationCenter.default.addObserver(
            descriptor: IRCChannelMessageNotification(),
            using: onChannelMessage(channelMessage:)
        )
    }

    func didReceiveSyncCommand(command: IRCBotCommand) {
        mecha.rescueBoard.syncBoard()
    }

    func didReceiveListCommand (command: IRCBotCommand) {
        var arguments: [ListCommandArgument] = []
        if command.parameters.count > 0 && command.parameters[0].starts(with: "-") {
            var args = command.parameters[0]
            args = String(args.suffix(from: args.index(after: args.startIndex))).lowercased()

            arguments = args.compactMap({
                return ListCommandArgument(rawValue: $0)
            })
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
                "platform": rescue.platform?.ircRepresentable ?? "unknown",
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

    func didReceiveCloseCommand (command: IRCBotCommand) {
        let message = command.message
        guard let rescue = self.assertGetRescueId(command: command) else {
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

            guard rescue.rats.contains(rat) else {
                command.message.reply(key: "board.close.notassigned", fromCommand: command, map: [
                    "caseId": rescue.commandIdentifier!,
                    "firstLimpet": rat.attributes.name.value
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
                "client": rescue.client ?? "unknown client"
            ])

            guard configuration.general.drillMode == false else {
                return
            }

            URLShortener.attemptShorten(
                url: URL(string: "https://fuelrats.com/paperwork/\(rescue.id)")!,
                complete: { shortUrl in
                if let firstLimpet = firstLimpet {
                    message.client.sendMessage(
                        toChannelName: configuration.general.reportingChannel,
                        withKey: "board.close.reportFirstlimpet",
                        mapping: [
                            "caseId": rescue.commandIdentifier!,
                            "firstLimpet": firstLimpet.attributes.name.value,
                            "client": rescue.client ?? "unknown client",
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

    func didReceiveTrashCommand (command: IRCBotCommand) {
        guard let rescue = self.assertGetRescueId(command: command) else {
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

    func didReceivePaperworkLinkCommand (command: IRCBotCommand) {
        guard let rescue = self.assertGetRescueId(command: command) else {
            return
        }

        URLShortener.attemptShorten(
            url: URL(string: "https://fuelrats.com/paperwork/\(rescue.id)")!,
            complete: { shortUrl in
            command.message.reply(key: "board.pwl.generated", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier!,
                "link": shortUrl
            ])
        })
    }

    func didReceiveQuietcommand (command: IRCBotCommand) {
        guard let lastSignalDate = mecha.rescueBoard.lastSignalReceived else {
            command.message.reply(key: "board.quiet.unknown", fromCommand: command)
            return
        }

        let timespan = Date().timeIntervalSince(lastSignalDate)

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.maximumUnitCount = 1
        formatter.unitsStyle = .full

        let timespanString = formatter.string(from: timespan) ?? ""

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

    func didReceivePrepCommand (command: IRCBotCommand) {
        let nick = command.parameters[0]

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
            command.message.reply(key: "board.casenotfound", fromCommand: command, map: [
                "caseIdentifier": command.parameters[0]
            ])
            return nil
        }

        return rescue
    }

    func assertGetRescueId (command: IRCBotCommand) -> LocalRescue? {
        BoardCommands.assertGetRescueId(command: command)
    }

    func onChannelMessage (channelMessage: IRCChannelMessageNotification.Payload) {
        if channelMessage.message.starts(with: "Incoming Client: ") {
            guard let rescue = LocalRescue(fromAnnouncer: channelMessage) else {
                return
            }
            mecha.rescueBoard.add(rescue: rescue, fromMessage: channelMessage)
        }

        if channelMessage.message.lowercased().contains(configuration.general.signal.lowercased()) {
            guard let rescue = LocalRescue(fromRatsignal: channelMessage) else {
                return
            }

            mecha.rescueBoard.add(rescue: rescue, fromMessage: channelMessage, manual: true)
        }
    }
}

enum ListCommandArgument: Character {
    case showOnlyInactive = "i"
    case showOnlyActive = "a"
    case showOnlyAssigned = "r"
    case showOnlyUnassigned = "u"
    case includeCaseIds = "@"

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
