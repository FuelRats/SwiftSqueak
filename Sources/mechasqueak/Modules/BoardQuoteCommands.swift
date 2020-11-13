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

class BoardQuoteCommands: IRCBotModule {
    static let disallowedInjectNames = ["ratsignal", "drillsignal", "client", "<client>"]
    static var injectRepeatCache = Set<String>()
    var name: String = "Case Quote Commands"
    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @BotCommand(
        ["quote"],
        parameters: 1...1,
        category: .board,
        description: "Show all information about a specific case",
        paramText: "<case id/client name>",
        example: "4",
        permission: .RescueRead
    )
    var didReceiveQuoteCommand = { command in
        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        let format = rescue.title != nil ? "board.quote.operation" : "board.quote.title"

        command.message.replyPrivate(key: format, fromCommand: command, map: [
            "title": rescue.title ?? "",
            "caseId": rescue.commandIdentifier!,
            "client": rescue.client ?? "u\u{200B}nknown client",
            "system": rescue.system ?? "u\u{200B}nknown system",
            "platform": rescue.platform.ircRepresentable,
            "cr": rescue.codeRed ? "(\(IRCFormat.color(.LightRed, "CR")))" : ""
        ])

        command.message.replyPrivate(key: "board.quote.dates", fromCommand: command, map: [
            "created": rescue.createdAt.ircRepresentable,
            "updated": rescue.updatedAt.ircRepresentable
        ])

        if rescue.rats.count == 0 && rescue.unidentifiedRats.count == 0 {
            command.message.replyPrivate(key: "board.quote.noassigned", fromCommand: command)
        } else {
            command.message.replyPrivate(key: "board.quote.assigned", fromCommand: command, map: [
                "rats": rescue.assignList!
            ])
        }

        for (index, quote) in rescue.quotes.enumerated() {
            command.message.replyPrivate(key: "board.quote.quote", fromCommand: command, map: [
                "index": index,
                "author": quote.lastAuthor,
                "time": "\(quote.updatedAt.timeAgo) ago",
                "message": quote.message
            ])
        }
    }

    @BotCommand(
        ["grab"],
        parameters: 1...1,
        category: .board,
        description: "Grab the last message by the client and add it an existing rescue",
        paramText: "<client>",
        example: "SpaceDawg",
        permission: .RescueWriteOwn,
        allowedDestinations: .Channel
    )
    var didReceiveGrabCommand = { command in
        let message = command.message
        let clientParam = command.parameters[0]

        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        let clientNick = rescue.clientNick ?? clientParam

        guard let clientUser = message.destination.member(named: clientNick) else {
            command.message.reply(key: "board.grab.noclient", fromCommand: command, map: [
                "caseId": clientParam
            ])
            return
        }

        guard let lastMessage = clientUser.lastMessage else {
            command.message.reply(key: "board.grab.nomessage", fromCommand: command, map: [
                "client": clientUser.nickname
            ])
            return
        }

        rescue.quotes.append(RescueQuote(
            author: message.user.nickname,
            message: "<\(clientUser.nickname)> \(lastMessage)",
            createdAt: Date(),
            updatedAt: Date(),
            lastAuthor: message.user.nickname
        ))

        command.message.reply(key: "board.grab.updated", fromCommand: command, map: [
            "clientId": rescue.commandIdentifier!,
            "text": lastMessage
        ])

        rescue.syncUpstream(fromBoard: mecha.rescueBoard)
    }

    @BotCommand(
        ["inject"],
        parameters: 2...2,
        lastParameterIsContinous: true,
        category: .board,
        description: "Add some new information to the case, if one does not exist, create one with this information",
        paramText: "<case id/client> <text>",
        example: "4 client is 1.1 million ls from main star, rats on the way",
        permission: .RescueWriteOwn,
        allowedDestinations: .Channel
    )
    var didReceiveInjectCommand = { command in
        let message = command.message
        let clientParam = command.parameters[0]

        var rescue = mecha.rescueBoard.findRescue(withCaseIdentifier: clientParam)
        if rescue == nil && Int(clientParam) != nil && clientParam.count < 3 {
            command.message.error(key: "board.casenotfound", fromCommand: command, map: [
                "caseIdentifier": command.parameters[0]
            ])
            return
        }

        let clientNick = rescue?.clientNick ?? clientParam

        let client = message.destination.member(named: clientNick)?.nickname ?? clientNick

        let injectMessage = command.parameters[1]
        if rescue == nil {
            guard isLikelyAccidentalInject(clientParam: clientParam) == false || injectRepeatCache.contains(clientParam.lowercased()) else {
                injectRepeatCache.insert(clientParam.lowercased())
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(60), execute: {
                    injectRepeatCache.remove(clientParam.lowercased())
                })

                message.error(key: "board.inject.ignored", fromCommand: command)
                return
            }

            rescue = LocalRescue(text: injectMessage, clientName: clientNick, fromCommand: command)
            if rescue != nil {
                rescue?.quotes.append(RescueQuote(
                    author: message.user.nickname,
                    message: injectMessage,
                    createdAt: Date(),
                    updatedAt: Date(),
                    lastAuthor: message.user.nickname
                ))
                mecha.rescueBoard.add(rescue: rescue!, fromMessage: message, initiated: .insertion)
            } else {
                command.message.error(key: "board.grab.notcreated", fromCommand: command, map: [
                    "client": client
                ])
                return
            }
        } else {
            rescue?.quotes.append(RescueQuote(
                author: message.user.nickname,
                message: injectMessage,
                createdAt: Date(),
                updatedAt: Date(),
                lastAuthor: message.user.nickname
            ))

            command.message.reply(key: "board.grab.updated", fromCommand: command, map: [
                "clientId": rescue!.commandIdentifier!,
                "text": injectMessage
            ])

            rescue?.syncUpstream(fromBoard: mecha.rescueBoard)
        }
    }

    @BotCommand(
        ["sub"],
        parameters: 2...3,
        lastParameterIsContinous: true,
        category: .board,
        description: "Change a text entry in the rescue replacing its contents with new text",
        paramText: "<case id/client> <line number> [new text]",
        example: "4 1 Client is PC, not Xbox",
        permission: .RescueWriteOwn,
        allowedDestinations: .Channel
    )
    var didReceiveSubstituteCommand = { command in
        let message = command.message

        guard let rescue = BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        guard let quoteIndex = Int(command.parameters[1]) else {
            command.message.error(key: "board.sub.invalidindex", fromCommand: command, map: [
                "index": command.parameters[1]
            ])
            return
        }

        guard quoteIndex >= 0 && quoteIndex < rescue.quotes.count else {
            command.message.error(key: "board.sub.outofbounds", fromCommand: command, map: [
                "index": quoteIndex,
                "caseId": rescue.commandIdentifier!
            ])
            return
        }

        var quote = rescue.quotes[quoteIndex]
        if command.parameters.count > 2 {
            let contents = command.parameters[2]

            quote.message = contents
            quote.lastAuthor = message.user.nickname
            rescue.quotes[quoteIndex] = quote
            command.message.reply(key: "board.sub.updated", fromCommand: command, map: [
                "index": quoteIndex,
                "caseId": rescue.commandIdentifier!,
                "contents": contents
            ])
        } else {
            rescue.quotes.remove(at: quoteIndex)
            command.message.reply(key: "board.sub.deleted", fromCommand: command, map: [
                "index": quoteIndex,
                "caseId": rescue.commandIdentifier!
            ])
        }


        rescue.syncUpstream(fromBoard: mecha.rescueBoard)
    }

    static func isLikelyAccidentalInject (clientParam: String) -> Bool {
        guard disallowedInjectNames.contains(clientParam.lowercased()) == false else {
            return true
        }
        guard let user = mecha.reportingChannel?.client.channels.compactMap({ channel in
            return channel.member(named: clientParam)
        }).first else {
            return true
        }
        return user.account != nil
    }
}
