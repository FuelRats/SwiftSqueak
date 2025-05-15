/*
 Copyright 2022 The Fuel Rats Mischief

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
import HTMLKit

class TweetCommands: IRCBotModule {
    var name: String = "Alert Commands"

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @BotCommand(
        ["alert", "tweet"],
        [.param("message", "Need rats urgently for two PS4 cases in the bubble", .continuous)],
        category: .utility,
        description: "Send a message via Mastodon & BlueSky",
        tags: ["twitter", "bluesky", "blue sky", "mastodon", "notification", "notify"],
        permission: .TwitterWrite,
        allowedDestinations: .Channel,
        helpExtra: {
            return
                "The mastodon is at @fuelratsalerts@mastodon.localecho.net and BlueSky at https://alerts.fuelrats.com/"
        },
        helpView: {
            HTMLKit.Group {
                "The Mastodon is at "
                Anchor("fuelratsalerts@mastodon.localecho.net")
                    .reference("https://mastodon.localecho.net/@fuelratsalerts")
                    .target(.blank)
                " and the BlueSky at "
                Anchor("alerts.fuelrats.com")
                    .reference("https://alerts.fuelrats.com/")
                    .target(.blank)
            }
        }
    )
    var didReceiveTweetCommand = { command in
        let contents = command.parameters[0]
        guard contents.count >= 20 else {
            command.message.error(key: "tweet.minlength", fromCommand: command)
            return
        }
        if await board.first(where: { (_, rescue) in
            if let system = rescue.system {
                if contents.lowercased().contains(system.name.lowercased()) {
                    return true
                }
            }
            if let clientName = rescue.client,
                contents.lowercased().contains(clientName.lowercased()) {
                return true
            }
            return false
        }) != nil {
            command.message.error(key: "tweet.confidential", fromCommand: command)
            return
        }

        do {
            try await Mastodon.post(message: contents)
            try await BlueSky.post(message: contents)
            command.message.reply(key: "tweet.success", fromCommand: command)
        } catch {
            debug(String(describing: error))
            command.message.error(key: "tweet.error", fromCommand: command)
        }
    }

    @BotCommand(
        ["alertcase", "alertc", "tweetcase", "tweetc"],
        [.param("case id/client", "4")],
        category: .utility,
        description:
            "Notify users that rats are needed on a case via Mastodon & Bluesky",
        tags: ["twitter", "bluesky", "blue sky", "mastodon", "notification", "notify"],
        permission: .DispatchRead,
        allowedDestinations: .Channel,
        helpExtra: {
            return
                "The mastodon is at @fuelratsalerts@mastodon.localecho.net and BlueSky at https://alerts.fuelrats.com/"
        },
        helpView: {
            HTMLKit.Group {
                "The Mastodon is at "
                Anchor("fuelratsalerts@mastodon.localecho.net")
                    .reference("https://mastodon.localecho.net/@fuelratsalerts")
                    .target(.blank)
                " and the BlueSky at "
                Anchor("alerts.fuelrats.com")
                    .reference("https://alerts.fuelrats.com/")
                    .target(.blank)
            }
        }
    )
    var didReceiveTweetCaseCommand = { command in
        guard let (caseId, rescue) = await BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        if let clientNick = rescue.clientNick, let user = rescue.channel?.member(named: clientNick) {
            if user.lastMessage == nil {
                command.message.reply(
                    message: "!alertc cannot be used on a case before the client has spoken")
                return
            }
        }

        guard var platform = rescue.platform else {
            command.message.error(
                key: "tweetcase.noplatform", fromCommand: command,
                map: [
                    "caseId": caseId
                ])
            return
        }

        guard let system = rescue.system else {
            command.message.reply(
                key: "tweetcase.missingsystem", fromCommand: command,
                map: [
                    "caseId": caseId
                ])
            return
        }

        let shortId = rescue.id.uuidString.suffix(10)

        let description = rescue.system?.twitterDescription
        var format = description != nil ? "tweetcase.system" : "tweetcase.nosystem"
        if rescue.codeRed {
            format += "cr"
        }

        var platformDescription = String(describing: platform)
        if rescue.platform == .PC {
            platformDescription += " (\(rescue.expansion.englishDescription))"
        }

        let url = URL(string: "https://fuelrats.com/paperwork/\(rescue.id)")!
        let tweet = lingo.localize(
            format, locale: "en-GB",
            interpolations: [
                "platform": platformDescription,
                "systemDescription": description ?? "",
                "caseId": caseId,
                "id": shortId.lowercased(),
                "link": url.absoluteString
            ])

        do {
            try await Mastodon.post(message: tweet)
            try await BlueSky.post(message: tweet, link: url.absoluteString)

            command.message.reply(
                key: "tweetcase.success", fromCommand: command,
                map: [
                    "tweet": tweet
                ])
            rescue.appendQuote(
                RescueQuote(
                    author: command.message.user.nickname,
                    message: "Tweet to @FuelRatAlerts has been posted",
                    createdAt: Date(),
                    updatedAt: Date(),
                    lastAuthor: command.message.user.nickname
                ))
            try? rescue.save(command)
        } catch {
            debug(String(describing: error))
            command.message.error(
                key: "tweetcase.failure", fromCommand: command,
                map: [
                    "caseId": caseId
                ])
        }
    }
}
