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

class GeneralCommands: IRCBotModule {
    static let factors: [String: Double] = [
        "ls": 1,
        "ly": 365 * 24 * 60 * 60,
        "pc": 3.262 * 365 * 24 * 60 * 60,
        "parsec": 3.262 * 365 * 24 * 60 * 60,
        "parsecs": 3.262 * 365 * 24 * 60 * 60,
        "au": 499,
        "m": 3.336 * pow(10, -9)
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
        ["sysstats", "syscount", "systems"],
        parameters: 0...0,
        category: .utility,
        description: "See statistics about the systems API.",
        permission: nil
    )
    var didReceiveSystemStatisticsCommand = { command in
        SystemsAPI.performStatisticsQuery(onComplete: { results in
            let result = results.data[0]
            guard let date = try? Double(value: result.id) else {
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
        parameters: 1...,
        category: .utility,
        description: "Calculate supercruise travel time",
        paramText: "<distance>",
        example: "2500ls",
        permission: nil
    )
    var didReceiveTravelTimeCommand = { command in
        var distanceString = command.parameters.joined(separator: " ").trimmingCharacters(in: .whitespaces)
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

        var seconds = 0.0
        if distance < 500000 {
            seconds = 4.4708*pow(distance, 0.3899)
        } else if distance > 5100000 {
            seconds = (distance - 5100000.0) / 2001 + 3420
        }
        else {
            /*
                Thank you to RadLock for creating the original equation.
             */
           let part1 = 33.7+1.87*pow(10 as Double, -3)*Double(distance)
           let part2 = -8.86*pow(10 as Double, -10) * pow(Double(distance), 2)
           let part3 = 2.37*pow(10 as Double, -16) * pow(Double(distance), 3)
           let part4 = -2.21*pow(10 as Double, -23) * pow(Double(distance), 4)
           seconds = part1 + part2 + part3 + part4
        }

        var time = ""
        if seconds < 0 {
            return
        }

        let formatter = NumberFormatter.englishFormatter()
        let yearFormatter = NumberFormatter.englishFormatter()
        yearFormatter.maximumFractionDigits = 0
        if seconds > 31536000 {
            let years = seconds / 31536000
            let days = seconds.truncatingRemainder(dividingBy: 31536000) / 86400
            time = "\(yearFormatter.string(from: years) ?? "\(years)") years, and \(days.clean) days"
        } else if seconds > 86400 {
            let days = seconds / 86400
            let hours = seconds.truncatingRemainder(dividingBy: 86400) / 3600
            time = "\(days.clean) days, and \(hours.clean) hours"
        } else if seconds > 3600 {
            let hours = seconds / 3600
            let minutes = seconds.truncatingRemainder(dividingBy: 3600) / 60
            time = "\(hours.clean) hours, and \(minutes.clean) minutes"
        } else if seconds > 60 {
            let minutes = seconds / 60
            let seconds = (seconds.truncatingRemainder(dividingBy: 60))
            time = "\(minutes.clean) minutes, and \(seconds.clean) seconds"
        } else {
            time = "\(seconds.clean) seconds"
        }

        let lightYears = distance / 60/60/24/365
        var formattedDistance = (formatter.string(from: distance) ?? "\(distance)") + "ls"
        if distance > 3.1*pow(10, 13) {
            let scientificFormatter = NumberFormatter()
            scientificFormatter.numberStyle = .scientific
            scientificFormatter.positiveFormat = "0.###E+0"
            scientificFormatter.exponentSymbol = "E"
            formattedDistance = "\(scientificFormatter.string(from: lightYears) ?? "\(lightYears)") ly"
        } else if distance > 3.6*pow(10, 6) {
            formattedDistance = (formatter.string(from: lightYears)  ?? "\(lightYears)") + "ly"
        }
 
        command.message.reply(key: "sctime.response", fromCommand: command, map: [
            "distance": formattedDistance,
            "time": time
        ])
    }

    @BotCommand(
        ["version", "uptime"],
        parameters: 0...0,
        category: .utility,
        description: "See version information about the bot.",
        permission: nil
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
        ["whoami"],
        parameters: 0...0,
        category: .utility,
        description: "Check the Fuel Rats account information the bot is currently associating with your nick"
    )
    var didReceiveWhoAmICommand = { command in
        let message = command.message
        let user = message.user
        guard let account = user.account else {
            command.message.reply(key: "whoami.notloggedin", fromCommand: command)
            return
        }

        guard let associatedNickname = user.associatedAPIData else {
            command.message.reply(key: "whoami.nodata", fromCommand: command, map: [
                "account": account
            ])
            return
        }

        guard let apiUser = associatedNickname.body.includes![User.self].first(where: {
            return $0.id.rawValue == associatedNickname.body.data?.primary.values[0].relationships.user?.id.rawValue
        }) else {
            command.message.reply(key: "whoami.noaccount", fromCommand: command, map: [
                "account": account
            ])
            return
        }

        let rats = associatedNickname.ratsBelongingTo(user: apiUser).map({
            "\($0.attributes.name.value) (\($0.attributes.platform.value.ircRepresentable))"
        }).joined(separator: ", ")

        let joinedDate = associatedNickname.ratsBelongingTo(user: apiUser).reduce(nil, { (acc: Date?, rat: Rat) -> Date? in
            if acc == nil || rat.attributes.createdAt.value < acc! {
                return rat.attributes.createdAt.value
            }
            return acc
        })

        let verifiedStatus = associatedNickname.permissions.contains(.UserVerified) ?
            IRCFormat.color(.LightGreen, "Verified") :
            IRCFormat.color(.Orange, "Unverified")

        command.message.reply(key: "whoami.response", fromCommand: command, map: [
            "account": account,
            "userId": apiUser.id.rawValue.ircRepresentation,
            "rats": rats,
            "joined": joinedDate?.eliteFormattedString ?? "u\u{200B}nknown",
            "verified": verifiedStatus
        ])
    }

    @BotCommand(
        ["whois", "ratid", "who", "id"],
        parameters: 1...1,
        category: .utility,
        description: "Check the Fuel Rats account information the bot is associating with someone's nick.",
        paramText: "<nickname>",
        example: "SpaceDawg",
        permission: .RatReadOwn
    )
    var didReceiveWhoIsCommand = { command in
        let message = command.message
        let nick = command.parameters[0]

        guard let user = message.client.channels.compactMap({ channel in
            return channel.member(named: nick)
        }).first else {
            command.message.error(key: "whois.notfound", fromCommand: command, map: [
                "nick": nick
            ])
            return
        }

        guard let account = user.account else {
            command.message.reply(key: "whois.notloggedin", fromCommand: command, map: [
                "nick": nick
            ])
            return
        }

        guard let associatedNickname = user.associatedAPIData else {
            command.message.reply(key: "whois.nodata", fromCommand: command, map: [
                "nick": nick,
                "account": account
            ])
            return
        }

        guard let apiUser = associatedNickname.body.includes![User.self].first(where: {
            return $0.id.rawValue == associatedNickname.body.data?.primary.values[0].relationships.user?.id.rawValue
        }) else {
            command.message.reply(key: "whois.noaccount", fromCommand: command, map: [
                "nick": nick,
                "account": account
            ])
            return
        }

        let rats = associatedNickname.ratsBelongingTo(user: apiUser).map({
            "\($0.attributes.name.value) (\($0.attributes.platform.value.ircRepresentable))"
        }).joined(separator: ", ")

        let joinedDate = associatedNickname.ratsBelongingTo(user: apiUser).reduce(nil, { (acc: Date?, rat: Rat) -> Date? in
            if acc == nil || rat.attributes.createdAt.value < acc! {
                return rat.attributes.createdAt.value
            }
            return acc
        })

        let verifiedStatus = associatedNickname.permissions.contains(.UserVerified) ?
            IRCFormat.color(.LightGreen, "Verified") :
            IRCFormat.color(.Orange, "Unverified")

        command.message.reply(key: "whois.response", fromCommand: command, map: [
            "nick": nick,
            "account": account,
            "userId": apiUser.id.rawValue.ircRepresentation,
            "rats": rats,
            "joined": joinedDate?.eliteFormattedString ?? "u\u{200B}nknown",
            "verified": verifiedStatus
        ])
    }

    @BotCommand(
        ["msg", "say"],
        parameters: 2...2,
        lastParameterIsContinous: true,
        category: .utility,
        description: "Make the bot send an IRC message somewhere.",
        paramText: "<destination> <message>",
        example: "#ratchat Squeak!",
        permission: .UserWrite
    )
    var didReceiveSayCommand = { command in
        command.message.reply(key: "say.sending", fromCommand: command, map: [
            "target": command.parameters[0],
            "contents": command.parameters[1]
        ])
        command.message.client.sendMessage(toChannelName: command.parameters[0], contents: command.parameters[1])
    }

    @BotCommand(
        ["me", "action", "emote"],
        parameters: 2...2,
        lastParameterIsContinous: true,
        category: .utility,
        description: "Make the bot send an IRC action (/me) somewhere.",
        paramText: "<destination> <action message>",
        example: "#ratchat noms popcorn.",
        permission: .UserWrite
    )
    var didReceiveMeCommand = { command in
        command.message.reply(key: "me.sending", fromCommand: command, map: [
            "target": command.parameters[0],
            "contents": command.parameters[1]
        ])
        command.message.client.sendActionMessage(toChannelName: command.parameters[0], contents: command.parameters[1])
    }
}
