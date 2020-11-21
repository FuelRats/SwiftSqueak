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

class MessageScanner: IRCBotModule {
    var name: String = "Message Scanner"
    static let jumpCallExpression = try! Regex(pattern: "([0-9]{1,3})[jJ] #([0-9]{1,3})", groupNames: ["jumps", "case"])
    static let caseMentionExpression = try! Regex(pattern: "(?:^|\\s+)#([0-9]{1,3})(?:$|\\s+)")
    static let systemExpression = "(([A-Z][A-Z\\s]+) SECTOR ([A-Za-z])([A-Za-z])-([A-Za-z]) ([A-Za-z])(?:(\\d+)-)?(\\d+))"
    static let jumpCallExpressionCaseAfter = try! Regex(
        pattern: "#([0-9]{1,3}) ([0-9]{1,3})[jJ]",
        groupNames: ["case", "jumps"]
    )

    static let caseRelevantPhrases = [
        "fr+", "fr-", "wr+", "wr-", "bc+", "bc-", "fuel+", "fuel-", "sys-", "sysconf", "destroyed", "exploded",
        "code red", "oxygen", "supercruise", "prep-", "prep+", "ez", "inst-", "open", "menu", "private", "actual",
        "solo", "ready", "pos+", "rdy", "stand down", "stnd", "log off", "mmconf", "sys", "system"
    ]

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @IRCListener<IRCChannelMessageNotification>
    var onChannelMessage = { channelMessage in
        guard channelMessage.raw.messageTags["batch"] == nil && channelMessage.destination.channelModes.keys.contains(.isSecret) == false else {
            // Do not interpret commands from playback of old messages or in secret channels
            return
        }

        if let jumpCallMatch = MessageScanner.jumpCallExpression.findFirst(in: channelMessage.message)
            ?? MessageScanner.jumpCallExpressionCaseAfter.findFirst(in: channelMessage.message) {
            let caseId = jumpCallMatch.group(named: "case")!
            guard channelMessage.message.count < 20 else {
                return
            }

            guard let rescue = mecha.rescueBoard.findRescue(withCaseIdentifier: caseId) else {
                if configuration.general.drillMode == false {
                    channelMessage.replyPrivate(message: lingo.localize(
                        "jumpcall.notfound",
                        locale: "en-GB",
                        interpolations: [
                            "case": caseId
                        ]
                    ))
                }
                return
            }

            if rescue.isPrepped == false && configuration.general.drillMode == false && rescue.codeRed == false {
                // User called jumps for a case where the client has not been prepped, yell at them.
                channelMessage.replyPrivate(message: lingo.localize(
                    "jumpcall.notprepped",
                    locale: "en-GB",
                    interpolations: [:]
                ))
            }

            if rescue.permitRequired {
                channelMessage.replyPrivate(message: lingo.localize(
                    "jumpcall.permit",
                    locale: "en-GB",
                    interpolations: [
                        "case": caseId,
                        "permit": rescue.permitName ?? rescue.system ?? "unknown"
                    ])
                )
            }

            if let accountInfo = channelMessage.user.associatedAPIData, let user = accountInfo.user {
                let rats = accountInfo.ratsBelongingTo(user: user)
                if rats.first(where: { (rat: Rat) -> Bool in
                    return rat.attributes.platform.value == rescue.platform
                }) == nil {
                    if configuration.general.drillMode == false {
                        channelMessage.client.sendMessage(
                            toChannelName: channelMessage.destination.name,
                            withKey: "jumpcall.wrongplatform",
                            mapping: [
                                "case": caseId,
                                "nick": channelMessage.user.nickname,
                                "platform": rescue.platform.ircRepresentable
                            ]
                        )
                    }
                }
            } else if configuration.general.drillMode == false {
                channelMessage.replyPrivate(message: lingo.localize(
                    "jumpcall.noaccount",
                    locale: "en-GB",
                    interpolations: [
                        "case": caseId
                    ]
                ))
            }



            rescue.quotes.append(RescueQuote(
                author: channelMessage.client.currentNick,
                message: "<\(channelMessage.user.nickname)> \(channelMessage.message)",
                createdAt: Date(),
                updatedAt: Date(),
                lastAuthor: channelMessage.client.currentNick
            ))

            rescue.syncUpstream(fromBoard: mecha.rescueBoard)
        }

        if channelMessage.message.starts(with: "Incoming Client: ") {
            guard let rescue = LocalRescue(fromAnnouncer: channelMessage) else {
                return
            }
            mecha.rescueBoard.add(rescue: rescue, fromMessage: channelMessage, initiated: .announcer)
            return
        }

        if channelMessage.message.lowercased().contains(configuration.general.signal.lowercased())
            && channelMessage.message.starts(with: "!") == false
        {
            guard let rescue = LocalRescue(fromRatsignal: channelMessage) else {
                return
            }

            mecha.rescueBoard.add(rescue: rescue, fromMessage: channelMessage, initiated: .signal)
            return
        }

        if let rescue = caseMentionedInMessage(message: channelMessage), channelMessage.user.isAssignedTo(rescue: rescue) {
            if
                let systemRange = channelMessage.message.range(of: systemExpression, options: .regularExpression)
            {
                let system = String(channelMessage.message[systemRange])
                SystemsAPI.performSearchAndLandmarkCheck(forSystem: system, onComplete: { searchResult, landmarkResult, _ in
                    guard let searchResult = searchResult, let landmarkResult = landmarkResult else {
                        return
                    }

                    rescue.system = searchResult.name.uppercased()
                    rescue.permitRequired = searchResult.permitRequired
                    rescue.permitName = searchResult.permitName
                    rescue.syncUpstream(fromBoard: mecha.rescueBoard)

                    let distance = NumberFormatter.englishFormatter().string(
                        from: NSNumber(value: landmarkResult.distance)
                    )!

                    let format = searchResult.permitRequired ? "board.syschange.permit" : "board.syschange.landmark"
                    channelMessage.reply(message: lingo.localize(format, locale: "en-GB", interpolations: [
                        "caseId": rescue.commandIdentifier,
                        "client": rescue.client!,
                        "system": system,
                        "distance": distance,
                        "landmark": landmarkResult.name,
                        "permit": searchResult.permitText ?? ""
                    ]))
                })
            }

            if channelMessage.message.contains("<") && channelMessage.message.contains(">") {
                return
            }
            guard MessageScanner.caseRelevantPhrases.first(where: {
                channelMessage.message.lowercased().contains($0)
            }) != nil else {
                return
            }

            rescue.quotes.append(RescueQuote(
                author: channelMessage.client.currentNick,
                message: "<\(channelMessage.user.nickname)> \(channelMessage.message)",
                createdAt: Date(),
                updatedAt: Date(),
                lastAuthor: channelMessage.client.currentNick
            ))

            rescue.syncUpstream(fromBoard: mecha.rescueBoard)
        }
    }

    static func caseMentionedInMessage (message: IRCPrivateMessage) -> LocalRescue? {
        if let caseMentionMatch = MessageScanner.caseMentionExpression.findFirst(in: message.message) {
            let caseId = caseMentionMatch.group(at: 1)!
            guard let rescue = mecha.rescueBoard.findRescue(withCaseIdentifier: caseId) else {
                return nil
            }

            return rescue
        }
        return nil

//        return mecha.rescueBoard.rescues.first(where: { rescue in
//            guard let clientNick = rescue.clientNick else {
//                return false
//            }
//            return message.message.lowercased().contains(clientNick.lowercased())
//        })
    }
}
