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
    var name: String = "GeneralCommands"

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @BotCommand(
        ["sysstats", "syscount", "systems"],
        parameters: 0...0,
        permission: nil
    )
    var didReceiveSystemStatisticsCommand = { command in
        SystemsAPI.performStatisticsQuery(onComplete: { results in
            let result = results.data[0]
            guard let date = try? Double(value: result.id) else {
                return
            }

            let numberFormatter = NumberFormatter.englishFormatter()
            let timespanFormatter = DateComponentsFormatter()
            timespanFormatter.allowedUnits = [.hour, .minute, .second]
            timespanFormatter.maximumUnitCount = 1
            timespanFormatter.unitsStyle = .full

            let updatedTimespan = Date().timeIntervalSince(Date(timeIntervalSince1970: date))

            command.message.reply(key: "sysstats.message", fromCommand: command, map: [
                "date": timespanFormatter.string(from: updatedTimespan)!,
                "systems": numberFormatter.string(from: result.attributes.syscount)!,
                "stars": numberFormatter.string(from: result.attributes.starcount)!,
                "bodies": numberFormatter.string(from: result.attributes.bodycount)!
            ])
        }, onError: { _ in
            command.message.reply(key: "sysstats.error", fromCommand: command)
        })
    }

    @BotCommand(
        ["version", "uptime"],
        parameters: 0...0,
        permission: nil
    )
    var didReceiveVersionCommand = { command in
        let timespan = Date().timeIntervalSince(mecha.startupTime)

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .full

        command.message.reply(key: "version.message", fromCommand: command, map: [
            "version": mecha.version,
            "uptime": formatter.string(from: timespan)!,
            "startup": mecha.startupTime.description
        ])
    }

    @BotCommand(
        ["whoami"],
        parameters: 0...0
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
            return $0.id.rawValue == associatedNickname.body.data?.primary.values[0].relationships.user.id.rawValue
        }) else {
            command.message.reply(key: "whoami.noaccount", fromCommand: command, map: [
                "account": account
            ])
            return
        }

        let rats = associatedNickname.ratsBelongingTo(user: apiUser).map({
            "\($0.attributes.name.value) (\($0.attributes.platform.value.ircRepresentable))"
        }).joined(separator: ", ")

        command.message.reply(key: "whoami.response", fromCommand: command, map: [
            "account": account,
            "userId": apiUser.id.rawValue.ircRepresentation,
            "rats": rats
        ])
    }

    @BotCommand(
        ["whois", "who", "ratid", "id"],
        parameters: 1...1,
        permission: .RatRead
    )
    var didReceiveWhoIsCommand = { command in
        let message = command.message
        let nick = command.parameters[0]

        guard let user = message.destination.member(named: nick) else {
            command.message.reply(key: "whois.notfound", fromCommand: command, map: [
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
            return $0.id.rawValue == associatedNickname.body.data?.primary.values[0].relationships.user.id.rawValue
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

        command.message.reply(key: "whois.response", fromCommand: command, map: [
            "nick": nick,
            "account": account,
            "userId": apiUser.id.rawValue.ircRepresentation,
            "rats": rats
        ])
    }

    @BotCommand(
        ["msg", "say"],
        parameters: 2...2,
        lastParameterIsContinous: true,
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
