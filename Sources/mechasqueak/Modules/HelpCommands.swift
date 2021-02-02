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

class HelpCommands: IRCBotModule {
    var name: String = "Help Commands"

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @BotCommand(
        ["help"],
        [.param("category/command", "!assign", .continious, .optional)],
        category: nil,
        description: "View help for MechaSqueak."
    )
    var didReceiveHelpCommand = { command in
        let message = command.message
        guard command.parameters.count > 0 else {
            message.replyPrivate(key: "help.howto", fromCommand: command)
            message.replyPrivate(key: "help.nofacts", fromCommand: command)
            message.replyPrivate(message: "-")

            for category in HelpCategory.allCases {
                let categoryDescription = lingo.localize("help.category.\(category)", locale: "en-GB")
                message.replyPrivate(
                    message: "\(IRCFormat.bold(category.rawValue)) - \(categoryDescription)"
                )
                let commands = MechaSqueak.commands.filter({
                    $0.category == category
                })

                let commandList = commands.map({ (command: IRCBotCommandDeclaration) -> String in
                    return "!\(command.commands[0])"
                }).joined(separator: " ")
                message.replyPrivate(message: "Commands: \(commandList)")
            }
            return
        }

        guard command.parameters[0].starts(with: "!") else {
            guard let category = HelpCategory(rawValue: command.parameters[0]) else {
                message.error(key: "help.categoryerror", fromCommand: command, map: [
                    "category": command.parameters[0]
                ])
                return
            }

            message.replyPrivate(key: "help.categorylist", fromCommand: command, map: [
                "category": category.rawValue
            ])

            let commands = MechaSqueak.commands.filter({
                $0.category == category
            })

            for helpCommand in commands {
                message.replyPrivate(key: "help.commandlist", fromCommand: command, map: [
                    "command": helpCommand.commands[0],
                    "params": helpCommand.paramText ?? "",
                    "description": helpCommand.description
                ])
            }
            return
        }

        let commandText = String(command.parameters[0].dropFirst()).lowercased()
        guard let helpCommand = MechaSqueak.commands.first(where: {
            $0.commands.contains(commandText)
        }) else {
            message.error(key: "help.commanderror", fromCommand: command, map: [
                "command": commandText
            ])
            return
        }


        message.replyPrivate(key: "help.commandtitle", fromCommand: command, map: [
            "command": helpCommand.usageDescription(command: nil),
            "example": helpCommand.example != nil
                ? "(Example: !\(helpCommand.commands[0]) \(helpCommand.example!))"
                : ""
        ])
        if helpCommand.commands.count > 1 {
            let aliases = helpCommand.commands.dropFirst().map({
                "!\($0)"
            }).joined(separator: " ")
            message.replyPrivate(key: "help.commandaliases", fromCommand: command, map: [
                "aliases": aliases
            ])
        }

        message.replyPrivate(message: helpCommand.description)

        let commandIdentifier = "help.command.\(helpCommand.commands[0])"
        let fullDescription = lingo.localize(commandIdentifier, locale: "en-GB")
        if fullDescription != commandIdentifier {
            message.replyPrivate(message: fullDescription)
        }

        if helpCommand.options.count > 0 || helpCommand.namedOptions.count > 0 {
            message.replyPrivate(message: "Options:")
        }
        for option in helpCommand.namedOptions {
            let optionDescription = lingo.localize("help.command.\(helpCommand.commands[0]).\(option)", locale: "en-GB")
            message.replyPrivate(message: " --\(option): \(optionDescription)")
        }

        for option in helpCommand.options {
            let optionDescription = lingo.localize("help.command.\(helpCommand.commands[0]).\(option)", locale: "en-GB")
            message.replyPrivate(message: " -\(option): \(optionDescription)")
        }
    }
}

enum HelpCategory: String, CaseIterable {
    case board
    case rescues
    case facts
    case utility
    case management
    case account
    case other
}
