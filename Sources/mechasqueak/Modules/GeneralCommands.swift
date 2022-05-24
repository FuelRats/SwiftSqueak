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


    @AsyncBotCommand(
        ["needsrats", "needrats", "nr"],
        category: .utility,
        description: "Get a list of cases that currently require rats to call jumps",
        permission: .DispatchRead,
        cooldown: .seconds(300)
    )
    var needsRatsCommand = { command in
        let needsRats = await board.rescues.filter({ (_, rescue) in
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

        var formattedCases = needsRats.map({ (caseId: Int, rescue: Rescue) -> String in
            var format = "needsrats.case"

            if rescue.codeRed {
                format += "cr"
            }

            return lingo.localize(format, locale: "en-GB", interpolations: [
                "caseId": caseId,
                "client": rescue.client ?? "?",
                "platform": rescue.platform.ircRepresentable,
                "systemInfo": rescue.system.description
            ])
        })

        command.message.reply(key: "needsrats.message", fromCommand: command, map: [
            "cases": formattedCases.joined(separator: ", ")
        ])
    }

    @AsyncBotCommand(
        ["sysstats", "syscount", "systems"],
        category: .utility,
        description: "See statistics about the systems API.",
        permission: nil,
        cooldown: .seconds(300)
    )
    var didReceiveSystemStatisticsCommand = { command in
        do {
            let results = try await SystemsAPI.getStatistics()
            
            let result = results.data[0]
            guard let date = Double(result.id) else {
                return
            }

            let numberFormatter = NumberFormatter.englishFormatter()

            command.message.reply(key: "sysstats.message", fromCommand: command, map: [
                "date": Date(timeIntervalSince1970: date).timeAgo(maximumUnits: 1),
                "systems": numberFormatter.string(from: result.attributes.syscount)!,
                "stars": numberFormatter.string(from: result.attributes.starcount)!,
                "bodies": numberFormatter.string(from: result.attributes.bodycount)!
            ])
        } catch {
            command.message.error(key: "sysstats.error", fromCommand: command)
        }
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

        let nonNumberCharacters = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ".,")).inverted

        distanceString = distanceString.components(separatedBy: nonNumberCharacters).joined()
        distanceString = distanceString.trimmingCharacters(in: nonNumberCharacters)
        
        let numberParser = NumberFormatter()
        numberParser.locale = Locale(identifier: "en-GB")
        numberParser.numberStyle = .decimal
        
        if distanceString.contains(",") && distanceString.contains(".") == false {
            numberParser.decimalSeparator = ","
        }
        
        guard var number = numberParser.number(from: distanceString), var distance = Double(exactly: number) else {
            command.message.reply(key: "sctime.error", fromCommand: command)
            return
        }

        distance = distance * factor
        let displayDistance = distance

        var seconds = distance.distanceToSeconds(destinationGravity: destinationGravity)

        command.message.reply(key: "sctime.response", fromCommand: command, map: [
            "distance": displayDistance.eliteDistance,
            "time": seconds.timeSpan(maximumUnits: 2)
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
            "uptime": mecha.startupTime.timeAgo(maximumUnits: 2),
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
    
    @AsyncBotCommand(
        ["timezone", "tz"],
        [.param("time in timezone", "3pm EST in CET", .continuous)],
        category: .utility,
        description: "Convert a time to another timezone",
        permission: nil,
        cooldown: .seconds(300)
    )
    var didReceiveTimeZoneCommand = { command in
        guard let chrono = configuration.chrono else {
            return
        }
        var components = command.param1?.components(separatedBy: " ") ?? []
        guard components.count > 2, let index = components.firstIndex(of: "in") ?? components.firstIndex(of: "to") else {
            command.message.reply(message: "Error: Could not understand the request, usage: !timezone <time> in <timezone>. e.g !timezone 3pm EST in CET")
            return
        }
        let timeZoneIdentifier = components[components.index(after: index)..<components.endIndex].joined(separator: " ")
        components = Array(components[components.startIndex..<index])
        let timeInput = components.joined(separator: " ")
        var offsetTimeZone: TimeZone?
        if var tzOffset = Double(timeZoneIdentifier) {
            offsetTimeZone = TimeZone(secondsFromGMT: Int(tzOffset * 60 * 60))
        }
        guard let timeZone: TimeZone = offsetTimeZone ?? TimeZone(abbreviation: timeZoneIdentifier.uppercased()) ?? TimeZone(identifier: timeZoneIdentifier) ?? timeZoneAbbreviations[timeZoneIdentifier.uppercased()] else {
            command.message.reply(message: "Error: Could not interpret time zone")
            return
        }
        
        let output = shell(chrono.nodePath, [
            chrono.file,
            timeInput
        ])
        guard let interpretedDate = DateFormatter.iso8601Full.date(from: output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") else {
            command.message.reply(message: "Error: Could not interpret date/time value")
            return
        }
        
        let outputFormatter = DateFormatter()
        outputFormatter.timeZone = timeZone
        outputFormatter.dateFormat = "EEEE, MMMM d, yyyy 'at' HH:mm"
        
        let tzName = timeZone.localizedName(for: .standard, locale: Locale.current) ?? timeZone.description
        command.message.reply(message: "\(outputFormatter.string(from: interpretedDate)) in \(tzName)")
    }
    
    @BotCommand(
        ["roll"],
        [.param("dices", "2d8")],
        category: .utility,
        description: "Roll a dice",
        permission: nil,
        cooldown: .seconds(90)
    )
    var didReceiveDiceRollCommand = { command in
        guard let diceParam = "(?<num>[0-9]{1})?d(?<value>[0-9]{1,3})(\\+(?<add>[0-9]{1,4}))?".r!.findFirst(in: command.parameters[0]) else {
            return
        }
        
        let diceValue = Int(diceParam.group(at: 2) ?? "") ?? 20
        let diceNum = Int(diceParam.group(at: 1) ?? "1") ?? 1
        let add = Int(diceParam.group(at: 4) ?? "0") ?? 0
        
        guard diceValue > 1 && diceNum > 0 else {
            return
        }
        
        var value = 0
        for roll in 1...diceNum {
            value += Int.random(in: 1...diceValue)
        }
        var unmodified = value
        value += add
        var output = String(value)
        if diceValue >= 6 {
            if unmodified == diceNum * diceValue {
                output = IRCFormat.color(.Green, output)
            } else if unmodified == diceNum {
                output = IRCFormat.color(.LightRed, output)
            }
        }
        if add > 0 {
            command.message.reply(message: "\(diceNum)d\(diceValue)+\(add) = \(output)")
        } else {
            command.message.reply(message: "\(diceNum)d\(diceValue) = \(output)")
        }
    }

    @BotCommand(
        ["announce"],
        [
            .argument("cr"),
            .argument("odyssey"),
            .argument("lang", "language code", example: "ru"),
            .param("channel", "#drillrats"),
            .param("client name", "Space Dawg"),
            .param("client nick", "SpaceDawg"),
            .param("PC/XB/PS", "PC"),
            .param("system", "NLTT 48288", .continuous)
        ],
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
        let crStatus = command.has(argument: "cr") ? "NOT OK" : "OK"
        
        var key = "announcement"
        if command.has(argument: "odyssey") {
            if platform != .PC {
                command.message.error(key: "announce.invalidplatform", fromCommand: command)
                return
            }
            key += ".odyssey"
        }
        
        var locale = Locale(identifier: "en")
        if let langCode = command.argumentValue(for: "lang") {
            locale = Locale(identifier: langCode)
        }

        command.message.reply(key: "announce.success", fromCommand: command, map: [
            "channel": channel,
            "client": clientName,
            "system": system,
            "platform": platform.ircRepresentable,
            "crStatus": crStatus
        ])

        let announcement = lingo.localize(key, locale: "en-GB", interpolations: [
            "client": clientName,
            "system": system,
            "platform": platform.rawValue.uppercased(),
            "crStatus": crStatus,
            "nick": clientNick,
            "language": locale.englishDescription,
            "langCode": locale.identifier
        ])


        command.message.client.sendMessage(toTarget: "BotServ", contents: "SAY \(channel) \(announcement)")
    }
    
    @AsyncBotCommand(
        ["xbl", "gamertag"],
        [.param("case id/gamertag", "SpaceDawg", .continuous)],
        category: .utility,
        description: "See information about an xbox gamertag",
        permission: nil,
        cooldown: .seconds(30)
    )
    var didReceiveXboxLiveCommand = { command in
        var gamertag = command.parameters[0]
        if let (_, rescue) = await board.findRescue(withCaseIdentifier: gamertag), rescue.platform == .Xbox {
            gamertag = rescue.client ?? gamertag
        }
        
        let profileLookup = await XboxLive.performLookup(gamertag: gamertag)
        guard case let .found(profile) = profileLookup else {
            if case .notFound = profileLookup {
                command.message.error(key: "xbl.notfound", fromCommand: command)
                return
            }
            command.message.error(key: "xbl.error", fromCommand: command)
            return
        }
        
        let privacy = profile.privacy.isAllowed ? IRCFormat.color(.LightGreen, "OK") : IRCFormat.color(.LightRed, "Communication Blocked")
        
        guard let currentActivity = profileLookup.currentActivity else {
            if profile.presence.state == .Online {
                command.message.reply(message: "\(gamertag) \(IRCFormat.color(.LightGreen, "(Online)")). Privacy Settings: \(privacy)")
            } else {
                command.message.reply(message: "\(gamertag) \(IRCFormat.color(.LightGrey, "(Offline)")). Privacy Settings: \(privacy)")
            }
            return
        }
        command.message.reply(message: "\(gamertag) \(IRCFormat.color(.LightGreen, "(Online)")) playing \(currentActivity). Privacy Settings: \(privacy)")
    }
    
    @AsyncBotCommand(
        ["psn"],
        [.param("case id/username", "SpaceDawg", .continuous)],
        category: .utility,
        description: "See information about a playstation user",
        permission: nil,
        cooldown: .seconds(30)
    )
    var didReceivePSNCommand = { command in
        var username = command.parameters[0]
        if let (_, rescue) = await board.findRescue(withCaseIdentifier: username), rescue.platform == .PS {
            username = rescue.client ?? username
        }
        
        let (profileLookup, presence) = await PSN.performLookup(name: username)
        guard case let .found(profile) = profileLookup else {
            if case .notFound = profileLookup {
                command.message.error(key: "psn.notfound", fromCommand: command)
                return
            }
            command.message.error(key: "psn.error", fromCommand: command)
            return
        }
        
        guard let presence = presence else {
            command.message.reply(message: "\(profile.onlineId) \(IRCFormat.color(.LightGrey, "(Offline)")) \(profile.psPlusStatus). Privacy Settings: \(IRCFormat.color(.LightRed, "Communication Blocked"))")
            return
        }
        
        guard let currentActivity = presence.currentActivity else {
            command.message.reply(message: "\(profile.onlineId) \(presence.status) \(profile.psPlusStatus). Privacy Settings: \(IRCFormat.color(.LightGreen, "OK"))")
            return
        }
        
        command.message.reply(message: "\(profile.onlineId) \(presence.status) \(profile.psPlusStatus) playing \(currentActivity). Privacy Settings: \(IRCFormat.color(.LightGreen, "OK"))")
    }
}

func shell (_ command: String, arguments: [String] = []) -> String? {
    let task = Process()
    let pipe = Pipe()
    
    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = arguments
    task.launchPath = command
    task.launch()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)
}

let timeZoneAbbreviations: [String: TimeZone] = [
    "ACDT": TimeZone(secondsFromGMT: Int(+10.5 * 60 * 60))!,
    "ACST": TimeZone(secondsFromGMT: Int(+9.5 * 60 * 60))!,
    "ACT": TimeZone(secondsFromGMT: Int(-5 * 60 * 60))!,
    "ACWST": TimeZone(secondsFromGMT: Int(+8.75 * 60 * 60))!,
    "ADT": TimeZone(secondsFromGMT: Int(+4 * 60 * 60))!,
    "AEDT": TimeZone(secondsFromGMT: Int(+11 * 60 * 60))!,
    "AEST": TimeZone(secondsFromGMT: Int(+10 * 60 * 60))!,
    "AET": TimeZone(secondsFromGMT: Int(+10 * 60 * 60))!,
    "AFT": TimeZone(secondsFromGMT: Int(+4.5 * 60 * 60))!,
    "AKDT": TimeZone(secondsFromGMT: Int(-8 * 60 * 60))!,
    "AKST": TimeZone(secondsFromGMT: Int(-9 * 60 * 60))!,
    "ALMT": TimeZone(secondsFromGMT: Int(+6 * 60 * 60))!,
    "AMST": TimeZone(secondsFromGMT: Int(-3 * 60 * 60))!,
    "AMT": TimeZone(secondsFromGMT: Int(-4 * 60 * 60))!,
    "ANAST": TimeZone(secondsFromGMT: Int(+12 * 60 * 60))!,
    "ANAT": TimeZone(secondsFromGMT: Int(+12 * 60 * 60))!,
    "AQTT": TimeZone(secondsFromGMT: Int(+5 * 60 * 60))!,
    "ART": TimeZone(secondsFromGMT: Int(-3 * 60 * 60))!,
    "AST": TimeZone(secondsFromGMT: Int(+3 * 60 * 60))!,
    "AT": TimeZone(secondsFromGMT: Int(-4 * 60 * 60))!,
    "AWDT": TimeZone(secondsFromGMT: Int(+9 * 60 * 60))!,
    "AWST": TimeZone(secondsFromGMT: Int(+8 * 60 * 60))!,
    "AZOST": TimeZone(secondsFromGMT: Int(+0 * 60 * 60))!,
    "AZOT": TimeZone(secondsFromGMT: Int(-1 * 60 * 60))!,
    "AZST": TimeZone(secondsFromGMT: Int(+5 * 60 * 60))!,
    "AZT": TimeZone(secondsFromGMT: Int(+4 * 60 * 60))!,
    "AOE": TimeZone(secondsFromGMT: Int(-12 * 60 * 60))!,
    "BNT": TimeZone(secondsFromGMT: Int(+8 * 60 * 60))!,
    "BOT": TimeZone(secondsFromGMT: Int(-4 * 60 * 60))!,
    "BRST": TimeZone(secondsFromGMT: Int(-2 * 60 * 60))!,
    "BRT": TimeZone(secondsFromGMT: Int(-3 * 60 * 60))!,
    "BST": TimeZone(secondsFromGMT: Int(+1 * 60 * 60))!,
    "CAST": TimeZone(secondsFromGMT: Int(+8 * 60 * 60))!,
    "CAT": TimeZone(secondsFromGMT: Int(+2 * 60 * 60))!,
    "CCT": TimeZone(secondsFromGMT: Int(+6.5 * 60 * 60))!,
    "CDT": TimeZone(secondsFromGMT: Int(-5 * 60 * 60))!,
    "CEST": TimeZone(secondsFromGMT: Int(+2 * 60 * 60))!,
    "CET": TimeZone(secondsFromGMT: Int(+1 * 60 * 60))!,
    "CHADT": TimeZone(secondsFromGMT: Int(+13.75 * 60 * 60))!,
    "CHAST": TimeZone(secondsFromGMT: Int(+12.75 * 60 * 60))!,
    "CHOST": TimeZone(secondsFromGMT: Int(+9 * 60 * 60))!,
    "CHOT": TimeZone(secondsFromGMT: Int(+8 * 60 * 60))!,
    "CHUT": TimeZone(secondsFromGMT: Int(+10 * 60 * 60))!,
    "CIDST": TimeZone(secondsFromGMT: Int(-4 * 60 * 60))!,
    "CIST": TimeZone(secondsFromGMT: Int(-5 * 60 * 60))!,
    "CKT": TimeZone(secondsFromGMT: Int(-10 * 60 * 60))!,
    "CLST": TimeZone(secondsFromGMT: Int(-3 * 60 * 60))!,
    "CLT": TimeZone(secondsFromGMT: Int(-4 * 60 * 60))!,
    "COT": TimeZone(secondsFromGMT: Int(-5 * 60 * 60))!,
    "CST": TimeZone(secondsFromGMT: Int(-6 * 60 * 60))!,
    "CT": TimeZone(secondsFromGMT: Int(-6 * 60 * 60))!,
    "CVT": TimeZone(secondsFromGMT: Int(-1 * 60 * 60))!,
    "CXT": TimeZone(secondsFromGMT: Int(+7 * 60 * 60))!,
    "CHST": TimeZone(secondsFromGMT: Int(+10 * 60 * 60))!,
    "DAVT": TimeZone(secondsFromGMT: Int(+7 * 60 * 60))!,
    "DDUT": TimeZone(secondsFromGMT: Int(+10 * 60 * 60))!,
    "EASST": TimeZone(secondsFromGMT: Int(-5 * 60 * 60))!,
    "EAST": TimeZone(secondsFromGMT: Int(-6 * 60 * 60))!,
    "EAT": TimeZone(secondsFromGMT: Int(+3 * 60 * 60))!,
    "ECT": TimeZone(secondsFromGMT: Int(-5 * 60 * 60))!,
    "EDT": TimeZone(secondsFromGMT: Int(-4 * 60 * 60))!,
    "EEST": TimeZone(secondsFromGMT: Int(+3 * 60 * 60))!,
    "EET": TimeZone(secondsFromGMT: Int(+2 * 60 * 60))!,
    "EGST": TimeZone(secondsFromGMT: Int(+0 * 60 * 60))!,
    "EGT": TimeZone(secondsFromGMT: Int(-1 * 60 * 60))!,
    "EST": TimeZone(secondsFromGMT: Int(-5 * 60 * 60))!,
    "ET": TimeZone(secondsFromGMT: Int(-5 * 60 * 60))!,
    "FET": TimeZone(secondsFromGMT: Int(+3 * 60 * 60))!,
    "FJST": TimeZone(secondsFromGMT: Int(+13 * 60 * 60))!,
    "FJT": TimeZone(secondsFromGMT: Int(+12 * 60 * 60))!,
    "FKST": TimeZone(secondsFromGMT: Int(-3 * 60 * 60))!,
    "FKT": TimeZone(secondsFromGMT: Int(-4 * 60 * 60))!,
    "FNT": TimeZone(secondsFromGMT: Int(-2 * 60 * 60))!,
    "GALT": TimeZone(secondsFromGMT: Int(-6 * 60 * 60))!,
    "GAMT": TimeZone(secondsFromGMT: Int(-9 * 60 * 60))!,
    "GET": TimeZone(secondsFromGMT: Int(+4 * 60 * 60))!,
    "GFT": TimeZone(secondsFromGMT: Int(-3 * 60 * 60))!,
    "GILT": TimeZone(secondsFromGMT: Int(+12 * 60 * 60))!,
    "GST": TimeZone(secondsFromGMT: Int(+4 * 60 * 60))!,
    "GYT": TimeZone(secondsFromGMT: Int(-4 * 60 * 60))!,
    "HDT": TimeZone(secondsFromGMT: Int(-9 * 60 * 60))!,
    "HKT": TimeZone(secondsFromGMT: Int(+8 * 60 * 60))!,
    "HOVST": TimeZone(secondsFromGMT: Int(+8 * 60 * 60))!,
    "HOVT": TimeZone(secondsFromGMT: Int(+7 * 60 * 60))!,
    "HST": TimeZone(secondsFromGMT: Int(-10 * 60 * 60))!,
    "ICT": TimeZone(secondsFromGMT: Int(+7 * 60 * 60))!,
    "IDT": TimeZone(secondsFromGMT: Int(+3 * 60 * 60))!,
    "IOT": TimeZone(secondsFromGMT: Int(+6 * 60 * 60))!,
    "IRDT": TimeZone(secondsFromGMT: Int(+4.5 * 60 * 60))!,
    "IRKST": TimeZone(secondsFromGMT: Int(+9 * 60 * 60))!,
    "IRKT": TimeZone(secondsFromGMT: Int(+8 * 60 * 60))!,
    "IRST": TimeZone(secondsFromGMT: Int(+3.5 * 60 * 60))!,
    "IST": TimeZone(secondsFromGMT: Int(+5.5 * 60 * 60))!,
    "JST": TimeZone(secondsFromGMT: Int(+9 * 60 * 60))!,
    "KGT": TimeZone(secondsFromGMT: Int(+6 * 60 * 60))!,
    "KOST": TimeZone(secondsFromGMT: Int(+11 * 60 * 60))!,
    "KRAST": TimeZone(secondsFromGMT: Int(+8 * 60 * 60))!,
    "KRAT": TimeZone(secondsFromGMT: Int(+7 * 60 * 60))!,
    "KST": TimeZone(secondsFromGMT: Int(+9 * 60 * 60))!,
    "KUYT": TimeZone(secondsFromGMT: Int(+4 * 60 * 60))!,
    "LHDT": TimeZone(secondsFromGMT: Int(+11 * 60 * 60))!,
    "LHST": TimeZone(secondsFromGMT: Int(+10.5 * 60 * 60))!,
    "LINT": TimeZone(secondsFromGMT: Int(+14 * 60 * 60))!,
    "MAGST": TimeZone(secondsFromGMT: Int(+12 * 60 * 60))!,
    "MAGT": TimeZone(secondsFromGMT: Int(+11 * 60 * 60))!,
    "MART": TimeZone(secondsFromGMT: Int(-9.5 * 60 * 60))!,
    "MAWT": TimeZone(secondsFromGMT: Int(+5 * 60 * 60))!,
    "MDT": TimeZone(secondsFromGMT: Int(-6 * 60 * 60))!,
    "MHT": TimeZone(secondsFromGMT: Int(+12 * 60 * 60))!,
    "MMT": TimeZone(secondsFromGMT: Int(+6.5 * 60 * 60))!,
    "MSD": TimeZone(secondsFromGMT: Int(+4 * 60 * 60))!,
    "MSK": TimeZone(secondsFromGMT: Int(+3 * 60 * 60))!,
    "MST": TimeZone(secondsFromGMT: Int(-7 * 60 * 60))!,
    "MT": TimeZone(secondsFromGMT: Int(-7 * 60 * 60))!,
    "MUT": TimeZone(secondsFromGMT: Int(+4 * 60 * 60))!,
    "MVT": TimeZone(secondsFromGMT: Int(+5 * 60 * 60))!,
    "MYT": TimeZone(secondsFromGMT: Int(+8 * 60 * 60))!,
    "NCT": TimeZone(secondsFromGMT: Int(+11 * 60 * 60))!,
    "NDT": TimeZone(secondsFromGMT: Int(-2.5 * 60 * 60))!,
    "NFT": TimeZone(secondsFromGMT: Int(+11 * 60 * 60))!,
    "NOVST": TimeZone(secondsFromGMT: Int(+7 * 60 * 60))!,
    "NOVT": TimeZone(secondsFromGMT: Int(+6 * 60 * 60))!,
    "NPT": TimeZone(secondsFromGMT: Int(+5.75 * 60 * 60))!,
    "NRT": TimeZone(secondsFromGMT: Int(+12 * 60 * 60))!,
    "NST": TimeZone(secondsFromGMT: Int(-3.5 * 60 * 60))!,
    "NUT": TimeZone(secondsFromGMT: Int(-11 * 60 * 60))!,
    "NZDT": TimeZone(secondsFromGMT: Int(+13 * 60 * 60))!,
    "NZST": TimeZone(secondsFromGMT: Int(+12 * 60 * 60))!,
    "OMSST": TimeZone(secondsFromGMT: Int(+7 * 60 * 60))!,
    "OMST": TimeZone(secondsFromGMT: Int(+6 * 60 * 60))!,
    "ORAT": TimeZone(secondsFromGMT: Int(+5 * 60 * 60))!,
    "PDT": TimeZone(secondsFromGMT: Int(-7 * 60 * 60))!,
    "PET": TimeZone(secondsFromGMT: Int(-5 * 60 * 60))!,
    "PETST": TimeZone(secondsFromGMT: Int(+12 * 60 * 60))!,
    "PETT": TimeZone(secondsFromGMT: Int(+12 * 60 * 60))!,
    "PGT": TimeZone(secondsFromGMT: Int(+10 * 60 * 60))!,
    "PHOT": TimeZone(secondsFromGMT: Int(+13 * 60 * 60))!,
    "PHT": TimeZone(secondsFromGMT: Int(+8 * 60 * 60))!,
    "PKT": TimeZone(secondsFromGMT: Int(+5 * 60 * 60))!,
    "PMDT": TimeZone(secondsFromGMT: Int(-2 * 60 * 60))!,
    "PMST": TimeZone(secondsFromGMT: Int(-3 * 60 * 60))!,
    "PONT": TimeZone(secondsFromGMT: Int(+11 * 60 * 60))!,
    "PST": TimeZone(secondsFromGMT: Int(-8 * 60 * 60))!,
    "PT": TimeZone(secondsFromGMT: Int(-8 * 60 * 60))!,
    "PWT": TimeZone(secondsFromGMT: Int(+9 * 60 * 60))!,
    "PYST": TimeZone(secondsFromGMT: Int(-3 * 60 * 60))!,
    "PYT": TimeZone(secondsFromGMT: Int(-4 * 60 * 60))!,
    "QYZT": TimeZone(secondsFromGMT: Int(+6 * 60 * 60))!,
    "RET": TimeZone(secondsFromGMT: Int(+4 * 60 * 60))!,
    "ROTT": TimeZone(secondsFromGMT: Int(-3 * 60 * 60))!,
    "SAKT": TimeZone(secondsFromGMT: Int(+11 * 60 * 60))!,
    "SAMT": TimeZone(secondsFromGMT: Int(+4 * 60 * 60))!,
    "SAST": TimeZone(secondsFromGMT: Int(+2 * 60 * 60))!,
    "SBT": TimeZone(secondsFromGMT: Int(+11 * 60 * 60))!,
    "SCT": TimeZone(secondsFromGMT: Int(+4 * 60 * 60))!,
    "SGT": TimeZone(secondsFromGMT: Int(+8 * 60 * 60))!,
    "SRET": TimeZone(secondsFromGMT: Int(+11 * 60 * 60))!,
    "SRT": TimeZone(secondsFromGMT: Int(-3 * 60 * 60))!,
    "SST": TimeZone(secondsFromGMT: Int(-11 * 60 * 60))!,
    "SYOT": TimeZone(secondsFromGMT: Int(+3 * 60 * 60))!,
    "TAHT": TimeZone(secondsFromGMT: Int(-10 * 60 * 60))!,
    "TFT": TimeZone(secondsFromGMT: Int(+5 * 60 * 60))!,
    "TJT": TimeZone(secondsFromGMT: Int(+5 * 60 * 60))!,
    "TKT": TimeZone(secondsFromGMT: Int(+13 * 60 * 60))!,
    "TLT": TimeZone(secondsFromGMT: Int(+9 * 60 * 60))!,
    "TMT": TimeZone(secondsFromGMT: Int(+5 * 60 * 60))!,
    "TOST": TimeZone(secondsFromGMT: Int(+14 * 60 * 60))!,
    "TOT": TimeZone(secondsFromGMT: Int(+13 * 60 * 60))!,
    "TRT": TimeZone(secondsFromGMT: Int(+3 * 60 * 60))!,
    "TVT": TimeZone(secondsFromGMT: Int(+12 * 60 * 60))!,
    "ULAST": TimeZone(secondsFromGMT: Int(+9 * 60 * 60))!,
    "ULAT": TimeZone(secondsFromGMT: Int(+8 * 60 * 60))!,
    "UYST": TimeZone(secondsFromGMT: Int(-2 * 60 * 60))!,
    "UYT": TimeZone(secondsFromGMT: Int(-3 * 60 * 60))!,
    "UZT": TimeZone(secondsFromGMT: Int(+5 * 60 * 60))!,
    "VET": TimeZone(secondsFromGMT: Int(-4 * 60 * 60))!,
    "VLAST": TimeZone(secondsFromGMT: Int(+11 * 60 * 60))!,
    "VLAT": TimeZone(secondsFromGMT: Int(+10 * 60 * 60))!,
    "VOST": TimeZone(secondsFromGMT: Int(+6 * 60 * 60))!,
    "VUT": TimeZone(secondsFromGMT: Int(+11 * 60 * 60))!,
    "WAKT": TimeZone(secondsFromGMT: Int(+12 * 60 * 60))!,
    "WARST": TimeZone(secondsFromGMT: Int(-3 * 60 * 60))!,
    "WAST": TimeZone(secondsFromGMT: Int(+2 * 60 * 60))!,
    "WAT": TimeZone(secondsFromGMT: Int(+1 * 60 * 60))!,
    "WEST": TimeZone(secondsFromGMT: Int(+1 * 60 * 60))!,
    "WET": TimeZone(secondsFromGMT: Int(+0 * 60 * 60))!,
    "WFT": TimeZone(secondsFromGMT: Int(+12 * 60 * 60))!,
    "WGST": TimeZone(secondsFromGMT: Int(-2 * 60 * 60))!,
    "WGT": TimeZone(secondsFromGMT: Int(-3 * 60 * 60))!,
    "WIB": TimeZone(secondsFromGMT: Int(+7 * 60 * 60))!,
    "WIT": TimeZone(secondsFromGMT: Int(+9 * 60 * 60))!,
    "WITA": TimeZone(secondsFromGMT: Int(+8 * 60 * 60))!,
    "WST": TimeZone(secondsFromGMT: Int(+13 * 60 * 60))!,
    "WT": TimeZone(secondsFromGMT: Int(+0 * 60 * 60))!,
    "YAKST": TimeZone(secondsFromGMT: Int(+10 * 60 * 60))!,
    "YAKT": TimeZone(secondsFromGMT: Int(+9 * 60 * 60))!,
    "YAPT": TimeZone(secondsFromGMT: Int(+10 * 60 * 60))!,
    "YEKST": TimeZone(secondsFromGMT: Int(+6 * 60 * 60))!,
    "YEKT": TimeZone(secondsFromGMT: Int(+5 * 60 * 60))!
]


