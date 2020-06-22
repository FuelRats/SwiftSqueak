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

class TweetCommands: IRCBotModule {
    var name: String = "Tweet Commands"
    private var channelMessageObserver: NotificationToken?

    var commands: [IRCBotCommandDeclaration] {
        return [
            IRCBotCommandDeclaration(
                commands: ["tweetcase", "tweetc"],
                minParameters: 1,
                onCommand: didReceiveTweetCaseCommand(command:fromMessage:),
                maxParameters: 1,
                permission: .RescueWriteOwn
            )
        ]
    }

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    func didReceiveTweetCaseCommand (command: IRCBotCommand, fromMessage message: IRCPrivateMessage) {
        guard let rescue = BoardCommands.assertGetRescueId(command: command, fromMessage: message) else {
            return
        }

        guard let platform = rescue.platform else {
            message.reply(key: "tweetcase.noplatform", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier!
            ])
            return
        }

        guard let system = rescue.system else {
            message.reply(key: "tweetcase.missingsystem", fromCommand: command, map: [
                "caseId": rescue.commandIdentifier!
            ])
            return
        }

        let shortId = rescue.id.uuidString.suffix(10)

        generateSystemDescription(system: system, complete: { description in
            var format = description != nil  ? "tweetcase.system" : "tweetcase.nosystem"
            if rescue.codeRed {
                format += "cr"
            }

            let url = URL(string: "https://fuelrats.com/paperwork/\(rescue.id)")!
            let tweet = lingo.localize(format, locale: "en-GB", interpolations: [
                "platform": platform,
                "systemDescription": description ?? "",
                "caseId": rescue.commandIdentifier!,
                "id": shortId.lowercased(),
                "link": url.absoluteString
            ])

            Twitter.tweet(message: tweet, complete: {
                message.reply(key: "tweetcase.success", fromCommand: command, map: [
                    "caseId": rescue.commandIdentifier!
                ])
            }, error: { _ in
                message.reply(key: "tweetcase.failure", fromCommand: command, map: [
                    "caseId": rescue.commandIdentifier!
                ])
            })
        })
    }

    func generateSystemDescription (system: String, complete: @escaping (String?) -> Void) {
        SystemsAPI.performSearchAndLandmarkCheck(
                forSystem: system, onComplete: { _, landmarkResult, _ in
                guard let result = landmarkResult else {
                    complete(nil)
                    return
                }

                if result.distance < 50 {
                    complete("near \(result.name)")
                    return
                }

                if result.distance < 500 {
                    complete("~\(ceil(result.distance / 10) * 10)LY from \(result.name)")
                    return
                }

                if result.distance < 2000 {
                    complete("~\(ceil(result.distance / 100) * 100)LY from \(result.name)")
                    return
                }

                complete("~\(ceil(result.distance / 1000))kLY from \(result.name)")
            }
        )
    }
}
