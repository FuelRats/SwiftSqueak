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

protocol IRCBotModule {
    var name: String { get }

    init (_ moduleManager: IRCBotModuleManager)
}

enum AllowedCommandDestination {
    case Channel
    case PrivateMessage
    case All
}

typealias BotCommandFunction = (IRCBotCommand) -> Void
@propertyWrapper struct BotCommand {
    var wrappedValue: BotCommandFunction

    init <T: AnyRange> (
        wrappedValue value: @escaping BotCommandFunction,
        _ commands: [String],
        parameters: T,
        lastParameterIsContinous: Bool = false,
        category: HelpCategory?,
        description: String,
        paramText: String? = nil,
        example: String? = nil,
        permission: AccountPermission? = nil,
        allowedDestinations: AllowedCommandDestination = .All
    ) {
        self.wrappedValue = value

        let declaration = IRCBotCommandDeclaration(
            commands: commands,
            minParameters: parameters.lower as? Int ?? 0,
            onCommand: self.wrappedValue,
            maxParameters: parameters.upper as? Int,
            lastParameterIsContinous: lastParameterIsContinous,
            category: category,
            description: description,
            paramText: paramText,
            example: example,
            permission: permission,
            allowedDestinations: allowedDestinations
        )

        MechaSqueak.commands.append(declaration)
    }
}

struct IRCBotCommandDeclaration {
    let commands: [String]
    let minimumParameters: Int
    let maximumParameters: Int?
    let permission: AccountPermission?
    let lastParameterIsContinous: Bool
    let allowedDestinations: AllowedCommandDestination
    let category: HelpCategory?
    let description: String
    var paramText: String?
    var example: String?

    var onCommand: BotCommandFunction?

    init (
        commands: [String],
        minParameters: Int,
        onCommand: BotCommandFunction?,
        maxParameters: Int? = nil,
        lastParameterIsContinous: Bool = false,
        category: HelpCategory?,
        description: String,
        paramText: String? = nil,
        example: String? = nil,
        permission: AccountPermission? = nil,
        allowedDestinations: AllowedCommandDestination = .All) {

        self.commands = commands
        self.minimumParameters = minParameters
        self.maximumParameters = maxParameters
        self.lastParameterIsContinous = lastParameterIsContinous
        self.permission = permission
        self.onCommand = onCommand
        self.allowedDestinations = allowedDestinations
        self.category = category
        self.description = description
        self.paramText = paramText
        self.example = example
    }
}

class IRCBotModuleManager {
    private var channelMessageObserver: NotificationToken?
    private var privateMessageObserver: NotificationToken?
    private var registeredModules: [IRCBotModule] = []
    var blacklist: [String]

    init () {
        self.blacklist = configuration.general.blacklist
        self.channelMessageObserver = NotificationCenter.default.addObserver(
            descriptor: IRCChannelMessageNotification(),
            using: onChannelMessage(channelMessage:)
        )
        self.privateMessageObserver = NotificationCenter.default.addObserver(
            descriptor: IRCPrivateMessageNotification(),
            using: onPrivateMessage(privateMessage:)
        )
    }

    func register (module: IRCBotModule) {
        self.registeredModules.append(module)
    }

    func register (command: IRCBotCommandDeclaration) {
        MechaSqueak.commands.append(command)
    }

    func onChannelMessage (channelMessage: IRCChannelMessageNotification.Payload) {
        guard let ircBotCommand = IRCBotCommand(from: channelMessage) else {
            return
        }

        handleIncomingCommand(ircBotCommand: ircBotCommand)
    }

    func onPrivateMessage (privateMessage: IRCPrivateMessageNotification.Payload) {
        guard let ircBotCommand = IRCBotCommand(from: privateMessage) else {
            return
        }

        handleIncomingCommand(ircBotCommand: ircBotCommand)
    }

    func handleIncomingCommand (ircBotCommand: IRCBotCommand) {
        var ircBotCommand = ircBotCommand
        let message = ircBotCommand.message

        guard message.raw.messageTags["batch"] == nil else {
            // Do not interpret commands from playback of old messages
            return
        }

        guard let command = MechaSqueak.commands.first(where: {
            $0.commands.contains(ircBotCommand.command)
        }) else {
            return
        }

        if message.destination.isPrivateMessage && command.allowedDestinations == .Channel {
            message.error(key: "command.publiconly", fromCommand: ircBotCommand, map: [
                "command": ircBotCommand.command
            ])
            return
        }

        if message.destination.isPrivateMessage == false && command.allowedDestinations == .PrivateMessage {
            message.error(key: "command.privateonly", fromCommand: ircBotCommand, map: [
                "command": ircBotCommand.command
            ])
             return
        }

        guard command.minimumParameters <= ircBotCommand.parameters.count else {
            message.error(key: "command.toofewparams", fromCommand: ircBotCommand, map: [
                "command": ircBotCommand.command,
                "usage": command.paramText != nil ? "Usage: !\(ircBotCommand.command) \(command.paramText!)" : "",
                "example": command.example != nil ? "(Example: !\(ircBotCommand.command) \(command.example!))" : ""
            ])
            return
        }

        if
            let maxParameters = command.maximumParameters,
            command.lastParameterIsContinous == true,
            ircBotCommand.parameters.count > 1
        {
            var parameters: [String] = []
            var paramIndex = 0

            while paramIndex < maxParameters && paramIndex < ircBotCommand.parameters.count {
                if paramIndex == maxParameters - 1 {
                    let remainderComponents = ircBotCommand.parameters[paramIndex..<ircBotCommand.parameters.endIndex]
                    let remainder = remainderComponents.joined(separator: " ")
                    parameters.append(remainder)
                    break
                } else {
                    parameters.append(ircBotCommand.parameters[paramIndex])
                }
                paramIndex += 1
            }
            ircBotCommand.parameters = Array(parameters)
        }

        if let maxParameters = command.maximumParameters, ircBotCommand.parameters.count > maxParameters {
            message.error(key: "command.toomanyparams", fromCommand: ircBotCommand, map: [
                "command": ircBotCommand.command,
                "usage": command.paramText != nil ? "Usage: !\(ircBotCommand.command) \(command.paramText!)" : "",
                "example": command.example != nil ? "(Example: !\(ircBotCommand.command) \(command.example!))" : ""
            ])
            return
        }

        if let permission = command.permission {
            guard message.user.hasPermission(permission: permission) else {
                message.error(key: "board.nopermission", fromCommand: ircBotCommand)
                return
            }
        }

        if command.category == .board && blacklist.contains(where: {
            $0.lowercased().range(of: message.user.nickname.lowercased()) != nil
        }) {
            message.client.sendMessage(toChannelName: "#doersofstuff", withKey: "command.blacklist", mapping: [
                "command": ircBotCommand.command,
                "nick": message.user.nickname
            ])
        }

        command.onCommand?(ircBotCommand)
    }
}
