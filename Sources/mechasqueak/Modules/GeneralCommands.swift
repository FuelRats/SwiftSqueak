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

class GeneralCommands: IRCBotModule {
    static let factors: [String: Double] = [
        "ls": 1,
        "ly": 365.25 * 24 * 60 * 60,
        "pc": 3.262 * 365 * 24 * 60 * 60,
        "parsec": 3.262 * 365 * 24 * 60 * 60,
        "parsecs": 3.262 * 365 * 24 * 60 * 60,
        "au": 499,
        "m": 3.336 * pow(10, -9),
        "banana": 5.9 * pow(10, -10),
        "bananas": 5.9 * pow(10, -10),
        "smoot": 5.67 * pow(10, -9),
        "smoots":  5.67 * pow(10, -9),
        "snickers": 6.471 * pow(10, -10)
    ]

    static let SIprefixes: [String: Double] = [
        "n": pow(10, -9),
        "u": pow(10, -6),
        "m": pow(10, -3),
        "c": pow(10, -2),
        "d": pow(10, -1),
        "da": pow(10, 1),
        "h": pow(10, 2),
        "k": pow(10, 3),
        "M": pow(10, 6),
        "G": pow(10, 9),
        "T": pow(10, 12),
        "P": pow(10, 15),
        "E": pow(10, 18),
        "Z": pow(10, 21),
        "Y": pow(10, 24)
    ]
    var name: String = "GeneralCommands"

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }


    @BotCommand(
        ["needsrats", "needrats", "nr"],
        category: .utility,
        description: "Get a list of cases that currently require rats to call jumps",
        permission: .DispatchRead,
        cooldown: .seconds(300)
    )
    var needsRatsCommand = { command in
        let needsRats = mecha.rescueBoard.rescues.filter({ rescue in
            guard rescue.system != nil && rescue.status == .Open else {
                return false
            }
            if rescue.codeRed {
                return rescue.rats.count < 2 && rescue.unidentifiedRats.count < 1 && rescue.jumpCalls.count < 1
            }
            return rescue.rats.count < 1 && rescue.unidentifiedRats.count < 1 && rescue.jumpCalls.count < 1
        })

        guard needsRats.count > 0 else {
            command.message.reply(key: "needsrats.none", fromCommand: command)
            return
        }

        var formattedCases = needsRats.map({ (rescue: LocalRescue) -> String in
            var format = "needsrats.case"

            if rescue.codeRed {
                format += "cr"
            }

            return lingo.localize(format, locale: "en-GB", interpolations: [
                "caseId": rescue.commandIdentifier,
                "client": rescue.client ?? "?",
                "platform": rescue.platform.ircRepresentable,
                "systemInfo": rescue.system.description
            ])
        })

        command.message.reply(key: "needsrats.message", fromCommand: command, map: [
            "cases": formattedCases.joined(separator: ", ")
        ])
    }

    @BotCommand(
        ["sysstats", "syscount", "systems"],
        category: .utility,
        description: "See statistics about the systems API.",
        permission: nil,
        cooldown: .seconds(300)
    )
    var didReceiveSystemStatisticsCommand = { command in
        SystemsAPI.performStatisticsQuery(onComplete: { results in
            let result = results.data[0]
            guard let date = Double(result.id) else {
                return
            }

            let numberFormatter = NumberFormatter.englishFormatter()

            command.message.reply(key: "sysstats.message", fromCommand: command, map: [
                "date": Date(timeIntervalSince1970: date).timeAgo,
                "systems": numberFormatter.string(from: result.attributes.syscount)!,
                "stars": numberFormatter.string(from: result.attributes.starcount)!,
                "bodies": numberFormatter.string(from: result.attributes.bodycount)!
            ])
        }, onError: { _ in
            command.message.error(key: "sysstats.error", fromCommand: command)
        })
    }

    @BotCommand(
        ["sctime", "sccalc", "traveltime"],
        [.options(["g"]), .param("distance", "2500ls", .continuous)],
        category: .utility,
        description: "Calculate supercruise travel time.",
        permission: nil,
        cooldown: .seconds(30)
    )
    var didReceiveTravelTimeCommand = { command in
        var params = command.parameters
        var destinationGravity = command.options.contains("g")

        var distanceString = params.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard let unit = factors.first(where: {
            distanceString.lowercased().hasSuffix($0.key)
        }) else {
            guard var unit = distanceString.components(separatedBy: CharacterSet.letters.inverted).last, unit.count > 0 else {
                command.message.reply(key: "sctime.uniterror", fromCommand: command)
                return
            }

            if unit.hasSuffix("s") && unit.count > 3 {
                unit.removeLast()
            }

            command.message.reply(key: "sctime.unknownunit", fromCommand: command, map: [
                "unit": unit.trimmingCharacters(in: .whitespaces)
            ])
            return
        }
        distanceString.removeLast(unit.key.count)
        var factor = unit.value
        distanceString = distanceString.trimmingCharacters(in: .whitespaces)

        for prefix in SIprefixes {
            if distanceString.hasSuffix(prefix.key) {
                factor = factor * prefix.value
            }
        }

        let nonNumberCharacters = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ".")).inverted

        distanceString = distanceString.components(separatedBy: nonNumberCharacters).joined()
        distanceString = distanceString.trimmingCharacters(in: nonNumberCharacters)
        guard var distance = Double(distanceString) else {
            command.message.reply(key: "sctime.error", fromCommand: command)
            return
        }

        distance = distance * factor
        let displayDistance = distance

        var seconds = distance.distanceToSeconds(destinationGravity: destinationGravity)

        let responseKey = destinationGravity ? "sctime.response.g" : "sctime.response"
        command.message.reply(key: responseKey, fromCommand: command, map: [
            "distance": displayDistance.eliteDistance,
            "time": seconds.timeSpan
        ])
    }

    @BotCommand(
        ["version", "uptime"],
        category: .utility,
        description: "See version information about the bot.",
        permission: nil,
        cooldown: .seconds(120)
    )
    var didReceiveVersionCommand = { command in
        let replyKey = configuration.general.drillMode ? "version.drillmode" : "version.message"

        command.message.reply(key: replyKey, fromCommand: command, map: [
            "version": mecha.version,
            "uptime": mecha.startupTime.timeAgo,
            "startup": mecha.startupTime.description
        ])
    }
    
    @BotCommand(
        ["gametime", "utc"],
        category: .utility,
        description: "See the current time in game time / UTC",
        permission: nil,
        cooldown: .seconds(300)
    )
    var didReceiveGameTimeCommand = { command in
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        timeFormatter.timeZone = TimeZone(abbreviation: "UTC")
        
        let time = timeFormatter.string(from: Date())
        let date = Date().eliteFormattedString

        command.message.reply(key: "gametime", fromCommand: command, map: [
            "date": date,
            "time": time
        ])
    }
    
    @BotCommand(
        ["roll"],
        [.param("dices", "2d8")],
        category: .utility,
        description: "Roll a dice",
        permission: nil,
        cooldown: .seconds(60)
    )
    var didReceiveDiceRollCommand = { command in
        guard let diceParam = "(?<num>[0-9]{1})?d(?<value>[0-9]{1,3})(\\+(?<add>[0-9]{1,4}))?".r!.findFirst(in: command.parameters[0]) else {
            return
        }
        
        let diceValue = Int(diceParam.group(at: 2) ?? "") ?? 20
        let diceNum = Int(diceParam.group(at: 1) ?? "1") ?? 1
        let add = Int(diceParam.group(at: 4) ?? "0") ?? 0
        
        guard diceValue > 1 else {
            return
        }
        
        var value = add
        for roll in 1...diceNum {
            value += Int.random(in: 1...diceValue)
        }
        if add > 0 {
            command.message.reply(message: "\(diceNum)d\(diceValue)+\(add) = \(value)")
        } else {
            command.message.reply(message: "\(diceNum)d\(diceValue) = \(value)")
        }
    }

    @BotCommand(
        ["announce"],
        [.argument("cr"), .param("channel", "#drillrats"), .param("client name", "Space Dawg"), .param("client nick", "SpaceDawg"), .param("PC/XB/PS", "PC"), .param("system", "NLTT 48288", .continuous)],
        category: .utility,
        description: "Create a rescue announcement in a drill channel",
        permission: .AnnouncementWrite
    )
    var didReceiveAnnounceCommand = { command in
        var channel = command.parameters[0].lowercased()
        if channel.starts(with: "#") == false {
            channel = "#" + channel
        }

        guard configuration.general.drillChannels.contains(channel) else {
            command.message.error(key: "announce.invalidchannel", fromCommand: command)
            return
        }

        let clientName = command.parameters[1]
        let clientNick = command.parameters[2]
        var platformString = command.parameters[3]
        guard let platform = GamePlatform.parsedFromText(text: platformString) else {
            command.message.error(key: "announce.invalidplatform", fromCommand: command)
            return
        }
        let system = command.parameters[4]
        let crStatus = command.namedOptions.contains("cr") ? "NOT OK" : "OK"

        command.message.reply(key: "announce.success", fromCommand: command, map: [
            "channel": channel,
            "client": clientName,
            "system": system,
            "platform": platform.ircRepresentable,
            "crStatus": crStatus
        ])

        let announcement = lingo.localize("announcement", locale: "en-GB", interpolations: [
            "client": clientName,
            "system": system,
            "platform": platform.rawValue.uppercased(),
            "crStatus": crStatus
        ])


        command.message.client.sendMessage(toTarget: "BotServ", contents: "SAY \(channel) \(announcement)")
    }
}
