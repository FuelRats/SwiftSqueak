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
        [.param("category/command", "!assign", .continuous, .optional)],
        category: nil,
        description: "View help for MechaSqueak."
    )
    var didReceiveHelpCommand = { command in
        if command.message.destination.isPrivateMessage == false && configuration.general.drillMode == false {
            command.message.reply(key: "command.replyprivate", fromCommand: command, map: [
                "nick": command.message.user.nickname,
            ])
        }
        let message = command.message
        guard command.parameters.count > 0 else {
            message.replyPrivate(key: "help.howto", fromCommand: command)
            message.replyPrivate(key: "help.webpage", fromCommand: command)
            message.replyPrivate(key: "help.nofacts", fromCommand: command)
            message.replyPrivate(message: "-")

            for category in HelpCategory.allCases {
                let categoryDescription = lingo.localize("help.category.\(category)", locale: "en-GB")
                message.replyPrivate(
                    message: "\(IRCFormat.bold(category.rawValue.firstCapitalized)) - \(categoryDescription)"
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
                    "command": "!" + helpCommand.commands[0],
                    "params": helpCommand.paramText,
                    "description": helpCommand.description
                ])
            }
            
            if category == .facts {
                guard let facts = try? await Fact.getAllFacts() else {
                    return
                }
                
                var groupedFacts = Array(facts.grouped.values).sorted(by: { $0.cannonicalName < $1.cannonicalName })
                
                var platformFacts = groupedFacts.filter({ $0.isPlatformFact }).platformGrouped
                groupedFacts = groupedFacts.filter({ $0.isPlatformFact == false })
                
                command.message.replyPrivate(key: "facts.list", fromCommand: command, map: [
                    "language": command.locale.englishDescription,
                    "count": groupedFacts.count,
                    "facts": groupedFacts.map({ "!\($0.cannonicalName)" }).joined(separator: ", ")
                ])
                
                if platformFacts.count > 0 {
                    command.message.replyPrivate(key: "facts.list.platform", fromCommand: command, map: [
                        "count": platformFacts.count,
                        "facts": platformFacts.map({ "!\($0.value.platformFactDescription)" }).joined(separator: ", ")
                    ])
                }
            }
            return
        }
        

        let commandText = String(command.parameters[0].dropFirst()).lowercased()
        guard let helpCommand = MechaSqueak.commands.first(where: {
            $0.commands.contains(commandText)
        }) else {
            if let fact = try? await Fact.get(name: commandText, forLocale: Locale(identifier: "en")) {
                command.message.replyPrivate(key: "anyfact.info", fromCommand: command, map: [
                    "fact": fact.id,
                    "language": Locale(identifier: fact.language).englishDescription,
                    "created": fact.createdAt.eliteFormattedString,
                    "updated": fact.updatedAt.eliteFormattedString,
                    "author": fact.author
                ])
                command.message.replyPrivate(message: fact.message)
                return
            }
            if Fact.platformFacts.contains(commandText) {
                command.message.replyPrivate(key: "help.smartfact", fromCommand: command, map: [
                    "command": commandText
                ])
                command.message.replyPrivate(key: "help.smartfact.seeall", fromCommand: command)
                return
            }
            message.error(key: "help.commanderror", fromCommand: command, map: [
                "command": commandText
            ])
            return
        }
        
        if configuration.general.drillMode {
            let destination = command.message.destination
            sendCommandHelp(helpCommand: helpCommand, destination: destination)
        } else {
            let destination = IRCChannel(privateMessage: command.message.user, onClient: command.message.client)
            sendCommandHelp(helpCommand: helpCommand, destination: destination)
        }
    }
    
    @BotCommand(
        ["sendhelp"],
        [.param("nick", "SpaceDawg"), .param("command", "!assign", .continuous)],
        category: nil,
        description: "Send help information about a MechaSqueak command to another user",
        permission: .AnnouncementWrite,
        allowedDestinations: .Channel
    )
    var didReceiveSendHelpCommand = { command in
        guard let user = command.message.destination.member(named: command.parameters[0]) else {
            command.message.error(key: "sendhelp.nouser", fromCommand: command, map: [
                "nick": command.parameters[0]
            ])
            return
        }
        
        var commandText = String(command.parameters[1]).lowercased()
        if commandText.starts(with: "!") {
            commandText.removeFirst()
        }
        if commandText == "sendhelp" {
            command.message.retaliate()
            return
        }
        
        guard let helpCommand = MechaSqueak.commands.first(where: {
            $0.commands.contains(commandText)
        }) else {
            command.message.error(key: "help.commanderror", fromCommand: command, map: [
                "command": commandText
            ])
            return
        }
        
        let destination = IRCChannel(privateMessage: user, onClient: command.message.client)
        sendCommandHelp(helpCommand: helpCommand, destination: destination)
        command.message.reply(message: "Help message for \"!\(commandText)\" sent")
    }
    
    static func sendCommandHelp (helpCommand: IRCBotCommandDeclaration, destination: IRCChannel) {
        destination.send(key: "help.commandtitle", map: [
            "command": helpCommand.usageDescription(command: nil),
            "example": helpCommand.example.count > 0
            ? "(Example: !\(helpCommand.commands[0]) \(helpCommand.example))"
            : ""
        ])
        let permissionGroups = helpCommand.permission?.groups
            .sorted(by: { $0.priority < $1.priority })
            .map({ $0.groupDescription }) ?? []
        
        var secondLine = ""
        if helpCommand.commands.count > 1 {
            let aliases = helpCommand.commands.dropFirst().map({
                "!\($0)"
            }).joined(separator: " ")
            secondLine += "\(IRCFormat.bold("Aliases:")) \(aliases). "
        }
        
        if permissionGroups.count > 0 {
            secondLine += "\(IRCFormat.bold("Permission:")) \(permissionGroups.joined(separator: ", ")). "
        }
        
        if secondLine.count > 0 {
            destination.send(message: secondLine)
        }
        
        destination.send(message: helpCommand.description)
        
        let commandIdentifier = "help.command.\(helpCommand.commands[0])"
        let fullDescription = lingo.localize(commandIdentifier, locale: "en-GB")
        if fullDescription != commandIdentifier {
            destination.send(message: fullDescription)
        }
        
        if helpCommand.options.count > 0 || helpCommand.arguments.count > 0 {
            destination.send(message: "Options:")
        }
        for (option, valueDescription, _) in helpCommand.helpArguments {
            let optionDescription = lingo.localize("help.command.\(helpCommand.commands[0]).\(option)", locale: "en-GB")
            if let valueDescription = valueDescription {
                destination.send(message: " --\(option) <\(valueDescription)>: \(optionDescription)")
            } else {
                destination.send(message: " --\(option): \(optionDescription)")
            }
        }
        
        for option in helpCommand.options {
            let optionDescription = lingo.localize("help.command.\(helpCommand.commands[0]).\(option)", locale: "en-GB")
            destination.send(message: " -\(option): \(optionDescription)")
        }
    }
}

enum HelpCategory: String, CaseIterable {
    case board
    case rescues
    case queue
    case facts
    case utility
    case account
    case other
    case management
}
