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

extension IRCPrivateMessage {
    func reply (key: String, fromCommand command: IRCBotCommand, map: [String: Any]? = [:]) {
        self.reply(message: lingo.localize(key, locale: command.locale.identifier, interpolations: map))
    }

    func error (key: String, fromCommand command: IRCBotCommand, map: [String: Any]? = [:]) {
        self.reply(message: "\(command.message.user.nickname): \(lingo.localize(key, locale: command.locale.identifier, interpolations: map))")
    }

    func replyPrivate (message: String) {
        if self.destination.isPrivateMessage || configuration.general.drillMode == true {
            self.reply(message: message)
            return
        }
        if self.user.settings?.preferredPrivateMethod == .Notice {
            self.client.sendNotice(toTarget: self.user.nickname, contents: message)
        }
        self.client.sendMessage(toTarget: self.user.nickname, contents: message)
    }

    func replyPrivate (key: String, fromCommand command: IRCBotCommand, map: [String: Any]? = [:]) {
        let message = lingo.localize(key, locale: command.locale.identifier, interpolations: map)
        self.replyPrivate(message: message)
    }

    public func reply (list: [String], separator: String, heading: String = "") {
        let messages = list.ircList(separator: separator, heading: heading)

        for message in messages {
            self.reply(message: message)
        }
    }

    public func replyPrivate (list: [String], separator: String, heading: String = "") {
        let messages = list.ircList(separator: separator, heading: heading)

        for message in messages {
            self.replyPrivate(message: message)
        }
    }
}
