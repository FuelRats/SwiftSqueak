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

class TweetCommands: IRCBotModule {
    var name: String = "Tweet Commands"

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @BotCommand(
        ["tweet"],
        [.param("message", "Need rats urgently for two PS4 cases in the bubble", .continuous)],
        category: .utility,
        description: "Send a tweet from @FuelRatAlerts",
        permission: .TwitterWrite,
        allowedDestinations: .Channel
    )
    var didReceiveTweetCommand = { command in
        let contents = command.parameters[0]
        guard contents.count >= 20 else {
            command.message.error(key: "tweet.minlength", fromCommand: command)
            return
        }
        if mecha.rescueBoard.rescues.first(where: { rescue in
            if let system = rescue.system {
                if contents.lowercased().contains(system.name.lowercased()) {
                    return true
                }
            }
            if let client = rescue.client {
                if contents.lowercased().contains(client.lowercased()) {
                    return true
                }
            }
            return false
        }) != nil {
            command.message.error(key: "tweet.confidential", fromCommand: command)
            return
        }

        Twitter.tweet(message: contents, complete: {
            command.message.reply(key: "tweet.success", fromCommand: command)
        }, error: { _ in
            command.message.error(key: "tweet.error", fromCommand: command)
        })
    }

    @BotCommand(
        ["tweetcase", "tweetc"],
        [.param("case id/client", "4")],
        category: .utility,
        description: "Tweet information about a case from @FuelRatAlerts",
        permission: .DispatchRead,
        allowedDestinations: .Channel
    )
    var didReceiveTweetCaseCommand = { command in
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        guard let platform = rescue.platform else {
            command.message.error(key: "tweetcase.noplatform", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier
            ])
            return
        }

        guard let system = rescue.system else {
            command.message.reply(key: "tweetcase.missingsystem", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier
            ])
            return
        }

        let shortId = rescue.id.uuidString.suffix(10)

        let description = rescue.system?.twitterDescription
        var format = description != nil  ? "tweetcase.system" : "tweetcase.nosystem"
        if rescue.codeRed {
            format += "cr"
        }

        let url = URL(string: "https://fuelrats.com/paperwork/\(rescue.id)")!
        let tweet = lingo.localize(format, locale: "en-GB", interpolations: [
            "platform": platform,
            "systemDescription": description ?? "",
            "caseId": rescue.commandIdentifier,
            "id": shortId.lowercased(),
            "link": url.absoluteString
        ])

        Twitter.tweet(message: tweet, complete: {
            command.message.reply(key: "tweetcase.success", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier
            ])
            rescue.quotes.append(RescueQuote(
                author: command.message.user.nickname,
                message: "Tweet to @FuelRatAlerts has been posted",
                createdAt: Date(),
                updatedAt: Date(),
                lastAuthor: command.message.user.nickname
            ))
            rescue.syncUpstream(representing: command.message.user)
        }, error: { _ in
            command.message.error(key: "tweetcase.failure", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier
            ])
        })
    }
}
