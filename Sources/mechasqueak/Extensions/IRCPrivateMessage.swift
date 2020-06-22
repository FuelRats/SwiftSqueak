//
//  IRCPrivateMessage.swift
//  mechasqueak
//
//  Created by Alex Sørlie Glomsaas on 2020-05-27.
//

import Foundation
import IRCKit

extension IRCPrivateMessage {
    func reply (key: String, fromCommand command: IRCBotCommand, map: [String: Any]? = [:]) {
        self.reply(message: lingo.localize(key, locale: command.locale.identifier, interpolations: map))
    }

    func error (key: String, fromCommand command: IRCBotCommand, map: [String: Any]? = [:]) {
        if command.message.destination.isPrivateMessage {
            self.reply(message: lingo.localize(key, locale: command.locale.identifier, interpolations: map))
        } else {
            client.sendNotice(
                toTarget: command.message.user.nickname,
                contents: lingo.localize(key, locale: command.locale.identifier, interpolations: map)
            )
        }
    }
}
