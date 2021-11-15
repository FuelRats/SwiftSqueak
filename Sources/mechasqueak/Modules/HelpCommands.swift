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

    @AsyncBotCommand(
        ["help"],
        [.param("category/command", "!assign", .continuous, .optional)],
        category: nil,
        description: "View help for MechaSqueak."
    )
    var didReceiveHelpCommand = { command in
        let message = command.message
        guard command.parameters.count > 0 else {
            command.replyPrivate(localized: "This is a list of MechaSqueak's command categories, to see a detailed view of all the commands in a category, do **!help <category>**, (e.g !help board). To see information about a specific command, do **!help !command** (e.g !help !assign).")
            command.replyPrivate(localized: "A list of commands are also available at: https://t.fuelr.at/mechacmd")
            command.replyPrivate(localized: "Information commands such as !prep and !pcwing are not listed here, to see a list of those, use **!facts** or **!help facts**.")
            command.replyPrivate(message: "-")

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
                command.error(localized: "\(command.parameters[0]) is not in the categories list. To list all categories, do !help. To see help for a specific command, add a ! before the command.")
                return
            }

            command.replyPrivate(localized: "Showing commands in the **\(category.rawValue)** category. To see see more information about the command, do !help !command (e.g !help !assign).")

            let commands = MechaSqueak.commands.filter({
                $0.category == category
            })

            for helpCommand in commands {
                command.replyPrivate(localized: "**!\(helpCommand.commands[0])** \(helpCommand.paramText) - \(helpCommand.description)")
            }
            
            if category == .facts {
                guard let facts = try? await Fact.getAllFacts() else {
                    return
                }
                
                var groupedFacts = Array(facts.grouped.values).sorted(by: { $0.cannonicalName < $1.cannonicalName })
                
                var platformFacts = groupedFacts.filter({ $0.isPlatformFact }).platformGrouped
                groupedFacts = groupedFacts.filter({ $0.isPlatformFact == false })
                
                let lang = command.locale.englishDescription
                let factList = groupedFacts.map({ "!\($0.cannonicalName)" }).joined(separator: ", ")
                command.replyPrivate(localized: "Listing \(groupedFacts.count) facts for \(lang) locale: \(factList)")
                
                
                if platformFacts.count > 0 {
                    let factList = platformFacts.map({ "!\($0.value.platformFactDescription)" }).joined(separator: ", ")
                    command.replyPrivate(localized: "There are also \(platformFacts.count) platform specific facts: \(factList)")
                }
            }
            return
        }
        

        let commandText = String(command.parameters[0].dropFirst()).lowercased()
        guard let helpCommand = MechaSqueak.commands.first(where: {
            $0.commands.contains(commandText)
        }) else {
            if let fact = try? await Fact.get(name: commandText, forLocale: Locale(identifier: "en")) {
                let lang = Locale(identifier: fact.language).englishDescription
                let created = fact.createdAt.eliteFormattedString
                let updated = fact.updatedAt.eliteFormattedString
                command.replyPrivate(localized: "!\(fact.id) (\(lang) translation). Created \(created). Updated \(updated). Last updated by \(fact.author).")
                command.replyPrivate(message: fact.message)
                return
            }
            command.error(localized: "!\(commandText) is not a known command")
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
    
    @AsyncBotCommand(
        ["sendhelp"],
        [.param("nick", "SpaceDawg"), .param("command", "!assign", .continuous)],
        category: nil,
        description: "Send help information about a MechaSqueak command to another user",
        permission: .AnnouncementWrite,
        allowedDestinations: .Channel
    )
    var didReceiveSendHelpCommand = { command in
        guard let user = command.message.destination.member(named: command.parameters[0]) else {
            command.error(localized: "Could not find \(command.parameters[0]) in the channel")
            return
        }
        
        var commandText = String(command.parameters[1]).lowercased()
        if commandText.starts(with: "!") {
            commandText.removeFirst()
        }
        
        guard let helpCommand = MechaSqueak.commands.first(where: {
            $0.commands.contains(commandText)
        }) else {
            command.error(localized: "!\(commandText) is not a known command")
            return
        }
        
        let destination = IRCChannel(privateMessage: user, onClient: command.message.client)
        sendCommandHelp(helpCommand: helpCommand, destination: destination)
    }
    
    static func sendCommandHelp (helpCommand: IRCBotCommandDeclaration, destination: IRCChannel) {
        let command = helpCommand.usageDescription(command: nil)
        let example = helpCommand.example.count > 0
        ? "(Example: !\(helpCommand.commands[0]) \(helpCommand.example))"
        : ""
        
        destination.send(localized: "**\(command)** \(example)")
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
        
        if helpCommand.options.count > 0 || helpCommand.namedOptions.count > 0 {
            destination.send(message: "Options:")
        }
        for option in helpCommand.namedOptions {
            let optionDescription = lingo.localize("help.command.\(helpCommand.commands[0]).\(option)", locale: "en-GB")
            destination.send(message: " --\(option): \(optionDescription)")
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
