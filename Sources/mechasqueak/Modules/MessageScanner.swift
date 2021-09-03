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
import Regex

class MessageScanner: IRCBotModule {
    var name: String = "Message Scanner"
    static let jumpCallExpression = try! Regex(pattern: "([0-9]{1,3})[jJ] #([0-9]{1,3})", groupNames: ["jumps", "case"])
    static let caseMentionExpression = try! Regex(pattern: "(?:^|\\s+)#([0-9]{1,3})(?:$|\\s+)")
    static let systemExpression = "(([A-Za-z0-9\\s]+) (SECTOR|sector) ([A-Za-z])([A-Za-z])-([A-Za-z]) ([A-Za-z])(?:(\\d+)-)?(\\d+))"
    static let jumpCallExpressionCaseAfter = try! Regex(
        pattern: "#([0-9]{1,3}) ([0-9]{1,3})[jJ]",
        groupNames: ["case", "jumps"]
    )

    static let caseRelevantPhrases = [
        "fr+", "fr-", "friend+", "wr+", "wing+", "wr-", "bc+", "bc-", "fuel+", "fuel-", "sys-", "sysconf", "destroyed", "exploded",
        "code red", "oxygen", "supercruise", "prep-", "prep+", "ez", "inst-", "open", "menu", "private", "actual",
        "solo", "ready", "pos+", "rdy", "stand down", "stnd", "stdn", "log off", "mmconf", "sys", "system", "tm-", "tm+",
        "horizons", "odyssey"
    ]
    private static let standDownPhrases = ["stand down", "stnd", "stdn"]
    private static let carrierPhrases = ["fc", "carrier"]

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @AsyncEventListener<IRCChannelMessageNotification>
    var onChannelMessage = { channelMessage in
        guard channelMessage.raw.messageTags["batch"] == nil && channelMessage.destination.channelModes.keys.contains(.isSecret) == false else {
            // Do not interpret commands from playback of old messages or in secret channels
            return
        }
        
        guard channelMessage.message.starts(with: "!") == false else {
            return
        }
        
        if configuration.general.drillChannels.contains(channelMessage.destination.name.lowercased()), let range = channelMessage.message.range(of: "ch[o]{2,} ch[o]{2,}", options: .regularExpression) {
            let trainCarriages = String(channelMessage.message[range].filter({ $0 == "O" || $0 == "o" }).map({ _ in return "🚃" })).prefix(50)
            channelMessage.reply(message: "🚂" + trainCarriages)
        }
        
        var casesUpdatedForMessage: [Rescue] = []

        if let jumpCallMatch = MessageScanner.jumpCallExpression.findFirst(in: channelMessage.message)
            ?? MessageScanner.jumpCallExpressionCaseAfter.findFirst(in: channelMessage.message) {
            let caseId = jumpCallMatch.group(named: "case")!
            let jumps = Int(jumpCallMatch.group(named: "jumps")!)!
            
            guard let (_, rescue) = await board.findRescue(withCaseIdentifier: caseId) else {
                if configuration.general.drillMode == false, channelMessage.destination.name.lowercased() == configuration.general.rescueChannel {
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

            if await rescue.isPrepped() == false && configuration.general.drillMode == false && rescue.codeRed == false {
                // User called jumps for a case where the client has not been prepped, yell at them.
                channelMessage.replyPrivate(message: lingo.localize(
                    "jumpcall.notprepped",
                    locale: "en-GB",
                    interpolations: [:]
                ))
            }
            
            let rat = channelMessage.user.getRatRepresenting(platform: rescue.platform ?? .PC)
            if let system = rescue.system, let permit = rescue.system?.permit {
                
                if (rat?.hasPermitFor(system: rescue.system!) ?? false) == false {
                    if rat?.attributes.data.value.permits?.count ?? 0 > 0 {
                        channelMessage.reply(message: lingo.localize(
                            "jumpcall.publicpermit",
                            locale: "en-GB",
                            interpolations: [
                                "nick": channelMessage.user.nickname,
                                "case": caseId,
                                "permit": permit.name ?? system.name
                            ])
                        )
                    } else {
                        channelMessage.replyPrivate(message: lingo.localize(
                            "jumpcall.permit",
                            locale: "en-GB",
                            interpolations: [
                                "caseId": caseId,
                                "permit": permit.name ?? system.name
                            ])
                        )
                    }
                }
            }

            if rescue.system?.isIncomplete == true && channelMessage.message.components(separatedBy: " ").count < 4 {
                channelMessage.client.sendMessage(
                    toChannelName: channelMessage.destination.name,
                    withKey: "jumpcall.incompletesys",
                    mapping: [
                        "case": caseId,
                        "nick": channelMessage.user.nickname
                    ]
                )
            }
            
            let containsCarrierPhrase = carrierPhrases.contains(where: { channelMessage.message.lowercased().contains($0) })

            if let accountInfo = channelMessage.user.associatedAPIData, let user = accountInfo.user {
                let rats = accountInfo.ratsBelongingTo(user: user)
                if rats.first(where: { (rat: Rat) -> Bool in
                    return rat.attributes.platform.value == rescue.platform
                }) == nil {
                    if configuration.general.drillMode == false && containsCarrierPhrase == false {
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

            var message = "<\(channelMessage.user.nickname)> \(channelMessage.message)"

            let isDrilled = channelMessage.user.hasPermission(permission: .DispatchRead)
            if channelMessage.user.account == nil {
                message += " (Unidentified)"
            } else if isDrilled == false {
                message += " (Not Drilled)"
            }
            
            if let system = rescue.system, system.permit != nil {
                if rat?.hasPermitFor(system: system) == false {
                    message += " (MISSING PERMIT)"
                }
            }
            
            let platform = rescue.platform
            if configuration.general.drillMode == false && platform == .PC, let rat = channelMessage.user.getRatRepresenting(platform: platform!) {
                if rescue.odyssey && rat.attributes.odyssey.value == false && containsCarrierPhrase == false {
                    channelMessage.client.sendMessage(
                        toChannelName: channelMessage.destination.name,
                        withKey: "jumpcall.clientodyssey",
                        mapping: [
                            "caseId": caseId,
                            "nick": channelMessage.user.nickname
                        ]
                    )
                    
                    message += " (Missing Odyssey)"
                }
                if rescue.odyssey == false && rat.attributes.odyssey.value {
                    channelMessage.client.sendMessage(
                        toChannelName: channelMessage.destination.name,
                        withKey: "jumpcall.ratodyssey",
                        mapping: [
                            "caseId": caseId,
                            "nick": channelMessage.user.nickname
                        ]
                    )
                    
                    message += " (Using Odyssey)"
                }
            }

            if let jumpRat = rat ?? channelMessage.user.currentRat {
                rescue.jumpCalls.append((jumpRat, jumps))
            }
            if casesUpdatedForMessage.contains(where: { $0.id == rescue.id }) == false {
                rescue.quotes.append(RescueQuote(
                    author: channelMessage.client.currentNick,
                    message: message,
                    createdAt: Date(),
                    updatedAt: Date(),
                    lastAuthor: channelMessage.client.currentNick
                ))
                try? rescue.save()
                casesUpdatedForMessage.append(rescue)

            }
        }

        if channelMessage.message.starts(with: "Incoming Client: ") {
            guard let rescue = Rescue(fromAnnouncer: channelMessage) else {
                return
            }
            try? await board.insert(rescue: rescue, fromMessage: channelMessage, initiated: .announcer)
            return
        }

        if channelMessage.message.lowercased().contains(configuration.general.signal.lowercased())
            && channelMessage.message.trimmingCharacters(in: .whitespaces).starts(with: "!") == false
        {
            guard let rescue = Rescue(fromRatsignal: channelMessage) else {
                return
            }

            try? await board.insert(rescue: rescue, fromMessage: channelMessage, initiated: .signal)
            return
        }

        let mentionedRescues = await board.findMentionedCasesIn(message: channelMessage)
        for (caseId, rescue) in mentionedRescues {
            let rescueChannel = rescue.channel
            guard await channelMessage.user.isAssignedTo(rescue: rescue) || channelMessage.destination == rescueChannel else {
                continue
            }
            
            guard casesUpdatedForMessage.contains(where: { $0.id == rescue.id }) == false else {
                continue
            }
            
            if channelMessage.message.contains("<") && channelMessage.message.contains(">") {
                continue
            }
            guard MessageScanner.caseRelevantPhrases.first(where: {
                channelMessage.message.lowercased().contains($0)
            }) != nil else {
                continue
            }
            
            if standDownPhrases.contains(where: { channelMessage.message.lowercased().contains($0) }) {
                if let callQuoteIndex = rescue.quotes.firstIndex(where: {
                    $0.message.starts(with: "<\(channelMessage.user.nickname)>") && MessageScanner.jumpCallExpression.findFirst(in: $0.message) != nil
                }) {
                    rescue.quotes[callQuoteIndex].message = rescue.quotes[callQuoteIndex].message + " (Rat has called stand down)"
                }
            }

            rescue.appendQuote(RescueQuote(
                author: channelMessage.client.currentNick,
                message: "<\(channelMessage.user.nickname)> \(channelMessage.message)",
                createdAt: Date(),
                updatedAt: Date(),
                lastAuthor: channelMessage.client.currentNick
            ))
            try? rescue.save()
            casesUpdatedForMessage.append(rescue)
        }
    }
}
