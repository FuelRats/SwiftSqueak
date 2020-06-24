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

extension BoardCommands {
    func didReceiveQuoteCommand (command: IRCBotCommand) {
        guard let rescue = self.assertGetRescueId(command: command) else {
            return
        }

        let format = rescue.title != nil ? "board.quote.operation" : "board.quote.title"

        command.message.reply(key: format, fromCommand: command, map: [
            "title": rescue.title ?? "",
            "caseId": rescue.commandIdentifier!,
            "client": rescue.client ?? "unknown client",
            "system": rescue.system ?? "unknown system",
            "platform": rescue.platform?.ircRepresentable ?? "unknown platform",
            "created": rescue.createdAt,
            "updated": rescue.updatedAt,
            "id": rescue.id.ircRepresentation,
            "cr": rescue.codeRed ? "(\(IRCFormat.color(.LightRed, "CR")))" : ""
        ])

        if rescue.rats.count == 0 && rescue.unidentifiedRats.count == 0 {
            command.message.reply(key: "board.quote.noassigned", fromCommand: command)
        } else {
            command.message.reply(key: "board.quote.assigned", fromCommand: command, map: [
                "rats": rescue.assignList!
            ])
        }

        for (index, quote) in rescue.quotes.enumerated() {
            command.message.reply(key: "board.quote.quote", fromCommand: command, map: [
                "index": index,
                "author": quote.lastAuthor,
                "time": quote.updatedAt,
                "message": quote.message
            ])
        }
    }

    func didReceiveGrabCommand (command: IRCBotCommand) {
        let message = command.message
        let clientParam = command.parameters[0]

        var rescue = mecha.rescueBoard.findRescue(withCaseIdentifier: clientParam)
        let clientNick = rescue?.clientNick ?? clientParam

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

        if rescue == nil {
            rescue = LocalRescue(text: lastMessage, clientName: clientNick, fromCommand: command)
            if rescue != nil {
                rescue?.quotes.append(RescueQuote(
                    author: clientUser.nickname,
                    message: lastMessage,
                    createdAt: Date(),
                    updatedAt: Date(),
                    lastAuthor: clientUser.nickname
                ))
                mecha.rescueBoard.add(rescue: rescue!, fromMessage: message, manual: true)
            } else {
                command.message.reply(key: "board.grab.notcreated", fromCommand: command, map: [
                    "client": clientUser.nickname
                ])
                return
            }
        } else {
            rescue?.quotes.append(RescueQuote(
                author: clientUser.nickname,
                message: lastMessage,
                createdAt: Date(),
                updatedAt: Date(),
                lastAuthor: clientUser.nickname
            ))

            command.message.reply(key: "board.grab.updated", fromCommand: command, map: [
                "clientId": rescue!.commandIdentifier!,
                "text": lastMessage
            ])

            rescue?.syncUpstream(fromBoard: mecha.rescueBoard)
        }
    }

    func didReceiveInjectCommand (command: IRCBotCommand) {
        let message = command.message
        let clientParam = command.parameters[0]

        var rescue = mecha.rescueBoard.findRescue(withCaseIdentifier: clientParam)
        let clientNick = rescue?.clientNick ?? clientParam

        let client = message.destination.member(named: clientNick)?.nickname ?? clientNick

        let injectMessage = command.parameters[1]

        if rescue == nil {
            rescue = LocalRescue(text: injectMessage, clientName: clientNick, fromCommand: command)
            if rescue != nil {
                rescue?.quotes.append(RescueQuote(
                    author: message.user.nickname,
                    message: injectMessage,
                    createdAt: Date(),
                    updatedAt: Date(),
                    lastAuthor: message.user.nickname
                ))
                mecha.rescueBoard.add(rescue: rescue!, fromMessage: message, manual: true)
            } else {
                command.message.reply(key: "board.grab.notcreated", fromCommand: command, map: [
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

    func didReceiveSubstituteCommand (command: IRCBotCommand) {
        let message = command.message

        guard let rescue = self.assertGetRescueId(command: command) else {
            return
        }

        guard let quoteIndex = Int(command.parameters[1]) else {
            command.message.reply(key: "board.sub.invalidindex", fromCommand: command, map: [
                "index": command.parameters[1]
            ])
            return
        }

        guard quoteIndex >= 0 && quoteIndex < rescue.quotes.count else {
            command.message.reply(key: "board.sub.outofbounds", fromCommand: command, map: [
                "index": quoteIndex,
                "caseId": rescue.commandIdentifier!
            ])
            return
        }

        var quote = rescue.quotes[quoteIndex]
        let contents = command.parameters[2]

        quote.message = contents
        quote.lastAuthor = message.user.nickname
        rescue.quotes[quoteIndex] = quote
        command.message.reply(key: "board.sub.updated", fromCommand: command, map: [
            "index": quoteIndex,
            "caseId": rescue.commandIdentifier!,
            "contents": contents
        ])

        rescue.syncUpstream(fromBoard: mecha.rescueBoard)
    }
}
