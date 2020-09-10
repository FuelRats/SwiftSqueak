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
import Regex
import IRCKit

struct IRCBotCommand {
    var command: String
    var parameters: [String]
    let locale: Locale
    let message: IRCPrivateMessage
    private static let ircFormattingExpression = "(\\x03([0-9]{1,2})?(,[0-9]{1,2})?|\\x02|\\x1F|\\x1E|\\x11)".r!

    init? (from channelMessage: IRCPrivateMessage) {
        var message = channelMessage.message
        message = IRCBotCommand.ircFormattingExpression.replaceAll(in: message, with: "")
        message = message.trimmingCharacters(in: .whitespacesAndNewlines)

        var hasCommand = false

        var tokens = message.split(separator: " ").map({ substr -> Token in
            let str = String(substr).trimmingCharacters(in: .whitespacesAndNewlines)
            if CommandToken.regex.matches(str) && hasCommand == false {
                hasCommand = true
                guard let token = CommandToken(fromString: str) else {
                    return Token.Parameter(str)
                }
                return Token.Command(token)
            }
            return Token.Parameter(str)
        })

        guard tokens.count > 0 else {
            return nil
        }

        guard case let .Command(commandToken) = tokens[0] else {
            return nil
        }

        tokens.removeFirst()

        self.message = channelMessage
        self.command = commandToken.identifier
        self.locale = Locale(identifier: commandToken.languageCode ?? "en")
        self.parameters = tokens.compactMap({
            guard case let .Parameter(param) = $0 else {
                return nil
            }
            return param
        })
    }

    init? (
        from channelMessage: IRCPrivateMessage,
        withIdentifier identifier: String,
        usage usageMessage: String,
        minParameters: Int = 0,
        maxParameters: Int? = nil
    ) {
        self.init(from: channelMessage)

        guard self.command == identifier.lowercased() else {
            return nil
        }

        if let maxParameters = maxParameters, self.parameters.count > maxParameters {
            channelMessage.reply(message: "Command was given too many parameters, usage: \(usageMessage)")
            return nil
        }

        if self.parameters.count < minParameters {
            channelMessage.reply(message: "Command was given too few parameters, usage: \(usageMessage)")
            return nil
        }
    }
}

enum Token {
    case Command(CommandToken)
    case Label(String)
    case Parameter(String)
}

struct CommandToken {
    static let regex = "^(!)([A-Za-z0-9_]*)(?:-([A-Za-z]{2}))?".r!

    let declaration: String
    let identifier: String
    let languageCode: String?

    init? (fromString token: String) {
        let match = CommandToken.regex.findFirst(in: token)!
        guard
            let declaration = match.group(at: 1),
            let identifier = match.group(at: 2)?.lowercased() else {
            return nil
        }

        self.declaration = declaration
        self.identifier = identifier
        self.languageCode = match.group(at: 3)?.lowercased()
    }
}
