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
import SwiftKueryORM
import SwiftKueryPostgreSQL
import IRCKit

class FactCommands: IRCBotModule {
    var name: String = "Fact Commands"
    private var channelMessageObserver: NotificationToken?
    private var privateMessageObserver: NotificationToken?
    private var factsDelimitingCache = Set<String>()
    private var platformFacts = ["wing", "beacon", "fr", "quit", "frcr", "modules"]

    static func parseFromParameter (param: String) -> (String, Locale) {
        let factComponents = param.lowercased().components(separatedBy: "-")
        let name = factComponents[0]
        let locale = Locale(identifier: factComponents.count > 1 ? factComponents[1] : "en")
        return (name, locale)
    }

    @BotCommand(
        ["facts", "fact"],
        parameters: 0...3,
        lastParameterIsContinous: true,
        category: .facts,
        description: "View the list of facts, modify, or delete them.",
        paramText: "set/info/locales/del [fact][-locale] [fact message]",
        example: "set pcwing-es bla bla bla, !facts info pcwing-es, !facts locales, !facts del pcwing-es"
    )
    var didReceiveFactCommand = { command in
        if command.parameters.count == 0 {
            didReceiveFactListCommand(command: command)
            return
        }

        let modifier = command.parameters[0].lowercased()

        switch modifier {
            case "add", "set":
                didReceiveFactSetCommand(command: command)

            case "info":
                didReceiveFactInfoCommand(command: command)

            case "locales":
                didReceiveFactLocalesCommand(command: command)

            case "del", "delete":
                didReceiveFactDeleteCommand(command: command)

            default:
                command.message.error(key: "facts.invalidargument", fromCommand: command, map: [
                    "argument": modifier
                ])
        }
    }

    static func didReceiveFactListCommand (command: IRCBotCommand) {
        let query = FactListQuery(language: command.locale.identifier)
        Fact.findAll(using: Database.default, matching: query, { facts, _ in

            guard let facts = facts else {
                command.message.error(key: "facts.list.error", fromCommand: command)
                return
            }

            guard facts.count > 0 else {
                command.message.reply(key: "facts.list.none", fromCommand: command, map: [
                    "locale": command.locale.englishDescription
                ])
                return
            }

            let factStrings = facts.map({
                $0.name
            })

            let heading = lingo.localize("facts.list.heading", locale: "en-GB", interpolations: [
                "count": facts.count,
                "locale": command.locale.englishDescription
            ])

            command.message.replyPrivate(list: factStrings, separator: ", ", heading: heading)
        })
    }

    static func didReceiveFactInfoCommand (command: IRCBotCommand) {
        guard command.parameters.count == 2 else {
            command.message.error(key: "facts.info.syntax", fromCommand: command)
            return
        }

        let (name, locale) = FactCommands.parseFromParameter(param: command.parameters[1])

        Fact.get(name: name, forLocale: locale, onComplete: { fact in
            guard let fact = fact else {
                command.message.reply(key: "facts.info.notfound", fromCommand: command, map: [
                    "fact": name,
                    "locale": command.locale.englishDescription
                ])
                return
            }

            let excerpt = fact.message.excerpt(maxLength: 100)

            command.message.reply(key: "facts.info.message", fromCommand: command, map: [
                "fact": name,
                "locale": locale.englishDescription,
                "created": fact.createdAt,
                "updated": fact.updatedAt,
                "author": fact.author,
                "excerpt": excerpt
            ])
        }, onError: { _ in
            command.message.reply(key: "facts.info.error", fromCommand: command, map: [
                "fact": command.parameters[1].lowercased()
            ])
        })
    }

    static func didReceiveFactLocalesCommand (command: IRCBotCommand) {
        Fact.findAll({ facts, _ in
            guard let facts = facts else {
                command.message.error(key: "facts.list.error", fromCommand: command)
                return
            }

            let locales = Set(facts.compactMap({
                $0.language
            })).map({ (localeIdentifier) -> String in
                let locale = Locale(identifier: localeIdentifier)
                return "\(locale.identifier) (\(locale.englishDescription))"
            }).joined(separator: ", ")

            command.message.reply(key: "facts.locales", fromCommand: command, map: [
                "locales": locales
            ])
        })
    }

    static func didReceiveFactSetCommand (command: IRCBotCommand) {
        let message = command.message

        guard command.parameters.count == 3 else {
            command.message.error(key: "facts.set.syntax", fromCommand: command)
            return
        }

        guard message.user.hasPermission(permission: .UserWrite) else {
            command.message.error(key: "facts.set.nopermission", fromCommand: command)
            return
        }

        let (name, locale) = FactCommands.parseFromParameter(param: command.parameters[1])

        Fact.get(name: name, forLocale: locale, onComplete: { fact in
            let contents = command.parameters[2]

            // Shorten facts above 100 characters in reply message
            var excerpt = contents
            if excerpt.count > 100 {
                excerpt = "\(excerpt.prefix(98)).."
            }

            if var fact = fact {
                // Fact already exists, update it with new contents and author
                fact.message = contents
                fact.author = message.user.nickname
                fact.updatedAt = Date()

                fact.update(id: fact.id!, { (_, error) in
                    guard error == nil else {
                        command.message.error(key: "facts.set.error", fromCommand: command, map: [
                            "fact": command.parameters[1].lowercased()
                        ])
                        return
                    }

                    command.message.reply(key: "facts.set.updated", fromCommand: command, map: [
                        "fact": command.parameters[1].lowercased(),
                        "locale": locale.englishDescription,
                        "message": excerpt
                    ])
                })
                return
            }

            let fact = Fact(
                name: name,
                language: locale.identifier,
                message: contents,
                author: message.user.nickname,
                createdAt: Date(),
                updatedAt: Date()
            )

            fact.save({ (_, error) in
                guard error == nil else {
                    command.message.error(key: "facts.set.error", fromCommand: command, map: [
                        "fact": command.parameters[1].lowercased()
                    ])
                    return
                }

                command.message.error(key: "facts.set.created", fromCommand: command, map: [
                    "fact": command.parameters[1].lowercased(),
                    "locale": locale.englishDescription,
                    "message": excerpt
                ])
            })
        }, onError: { _ in
            command.message.error(key: "facts.set.error", fromCommand: command, map: [
                "fact": command.parameters[1].lowercased()
            ])
        })
    }

    static func didReceiveFactDeleteCommand (command: IRCBotCommand) {
        let message = command.message

        guard command.parameters.count == 2 else {
            command.message.error(key: "facts.del.syntax", fromCommand: command)
            return
        }

        guard message.user.hasPermission(permission: .UserWrite) else {
            command.message.error(key: "facts.del.nopermission", fromCommand: command)
            return
        }

        let (name, locale) = FactCommands.parseFromParameter(param: command.parameters[1])

        Fact.get(name: name, forLocale: locale, onComplete: { fact in
            guard fact != nil else {
                command.message.reply(key: "facts.del.notfound", fromCommand: command, map: [
                    "fact": command.parameters[1].lowercased()
                ])
                return
            }

            let query = FactQuery(name: name, language: locale.identifier)

            Fact.deleteAll(using: Database.default, matching: query, { error in
                guard error == nil else {
                    command.message.error(key: "facts.del.error", fromCommand: command, map: [
                        "fact": command.parameters[1].lowercased()
                    ])
                    return
                }

                command.message.reply(key: "facts.del.success", fromCommand: command, map: [
                    "fact": command.parameters[1].lowercased()
                ])
            })
        }, onError: { _ in
            command.message.error(key: "facts.del.error", fromCommand: command, map: [
                "fact": command.parameters[1].lowercased()
            ])
        })
    }

    func onMessage (_ message: IRCPrivateMessage) {
        guard message.raw.messageTags["batch"] == nil else {
            // Do not interpret commands from playback of old messages
            return
        }
        
        guard var command = IRCBotCommand(from: message) else {
            return
        }

        var rescue: LocalRescue? = nil
        if command.parameters.count > 0 {
            rescue = mecha.rescueBoard.findRescue(withCaseIdentifier: command.parameters[0])
        }

        if command.parameters.count > 0, rescue == nil, let member = message.destination.member(named: command.parameters[0]) {
            if let correctedRescue = mecha.rescueBoard.fuzzyFindRescue(forChannelMember: member) {
                let newNick = command.parameters[0]
                correctedRescue.clientNick = newNick
                rescue = correctedRescue

                command.message.reply(key: "board.nickcorrected", fromCommand: command, map: [
                    "caseId": correctedRescue.commandIdentifier,
                    "client": correctedRescue.client ?? "u\u{200B}nknown client",
                    "newNick": newNick
                ])
            }
        }


        if platformFacts.contains(where: { $0 == command.command }) {
            guard
                command.parameters.count > 0,
                let rescue = rescue,
                let platform = rescue.platform
                else {
                return
            }

            command.command = "\(platform.factPrefix)\(command.command)"
        }

        if message.destination.isPrivateMessage == false {
            let factHash = hashFact(command: command)

            guard self.factsDelimitingCache.contains(factHash) == false else {
                return
            }

            self.factsDelimitingCache.insert(factHash)
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(5), execute: {
                self.factsDelimitingCache.remove(factHash)
            })
        }

        Fact.get(name: command.command, forLocale: command.locale, onComplete: { fact in
            guard let fact = fact else {
                Fact.get(name: command.command, forLocale: Locale(identifier: "en"), onComplete: { fallbackFact in
                    guard let fallbackFact = fallbackFact else {
                        return
                    }

                    command.message.replyPrivate(key: "fact.fallback", fromCommand: command, map: [
                        "fact": command.command,
                        "identifier": command.locale.identifier,
                        "language": command.locale.englishDescription
                    ])
                    self.messageFact(command: command, fact: fallbackFact)
                })
                return
            }

            self.messageFact(command: command, fact: fact)
        })
    }

    func messageFact (command: IRCBotCommand, fact: Fact) {
        if command.parameters.count > 0 {
            if command.parameters.count > 0 && command.parameters[0].lowercased() == command.message.client.currentNick.lowercased() {
                command.message.reply(message: "\(command.message.user.nickname) what are you playing at?")
                return
            }

            let target = command.parameters.joined(separator: " ")
            command.message.reply(message: "\(target): \(fact.message)")
        } else {
            command.message.reply(message: fact.message)
        }
    }

    func hashFact (command: IRCBotCommand) -> String {
        var string = command.command
        for param in command.parameters {
            string += param.lowercased()
        }
        string += command.locale.identifier

        return string.sha256()
    }

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)

        self.channelMessageObserver = NotificationCenter.default.addObserver(
            descriptor: IRCChannelMessageNotification(),
            using: onMessage(_:)
        )
        self.privateMessageObserver = NotificationCenter.default.addObserver(
            descriptor: IRCPrivateMessageNotification(),
            using: onMessage(_:)
        )

        let pool = PostgreSQLConnection.createPool(
            host: configuration.database.host,
            port: configuration.database.port,
            options: [
                .databaseName(configuration.database.database),
                .userName(configuration.database.username)
            ],
            poolOptions: ConnectionPoolOptions(initialCapacity: 10, maxCapacity: 50)
        )
        Database.default = Database(pool)
        do {
            try Fact.createTableSync()
        } catch let error {
            debug(String(describing: error))
        }
    }
}
