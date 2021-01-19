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

class AccountCommands: IRCBotModule {
    var name: String = "AccountCommands"

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @BotCommand(
        ["whoami"],
        parameters: 0...0,
        category: .account,
        description: "Check the Fuel Rats account information the bot is currently associating with your nick",
        allowedDestinations: .PrivateMessage
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
        category: .account,
        description: "Check the Fuel Rats account information the bot is associating with someone's nick.",
        paramText: "<nickname>",
        example: "SpaceDawg",
        permission: .RatReadOwn,
        allowedDestinations: .PrivateMessage
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
        ["activerat", "assigncheck", "assigntest"],
        parameters: 1...1,
        category: .account,
        description: "Check what CMDR name mecha would currently assign to a case based on your nickname",
        paramText: "<platform>",
        example: "PC",
        permission: .RatReadOwn,
        allowedDestinations: .PrivateMessage
    )
    var didReceiveAssignCheckCommand = { command in
        let message = command.message
        let user = message.user

        guard let platform = GamePlatform(rawValue: command.parameters[0].lowercased()) else {
            command.message.reply(key: "activerat.invalidplatform", fromCommand: command)
            return
        }

        guard let rat = user.getRatRepresenting(platform: platform) else {
            command.message.reply(key: "activerat.none", fromCommand: command, map: [
                "platform": platform.ircRepresentable
            ])
            return
        }

        command.message.reply(key: "activerat.response", fromCommand: command, map: [
            "platform": platform.ircRepresentable,
            "id": rat.id.rawValue.ircRepresentation,
            "name": rat.attributes.name.value
        ])
    }
}
