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

class FactCommands: IRCBotModule {
    var name: String = "Fact Commands"
    private var channelMessageObserver: NotificationToken?
    private var privateMessageObserver: NotificationToken?
    private var factsDelimitingCache = Set<String>()
    private var prepFacts = ["prep", "psquit", "pcquit", "xquit", "prepcr", "pqueue", "oreo"]

    static func parseFromParameter (param: String) -> (String, Locale) {
        let factComponents = param.lowercased().components(separatedBy: "-")
        let name = factComponents[0]
        let locale = Locale(identifier: factComponents.count > 1 ? factComponents[1] : "en")
        return (name, locale)
    }
    
    @AsyncBotCommand(
        ["facts", "listfacts", "factlist", "fact"],
        [.argument("locales")],
        category: .facts,
        description: "View the list of facts"
    )
    var didReceiveFactListCommand = { command in
        guard var allFacts = try? await Fact.getAllFacts() else {
            return
        }
        if command.has(argument: "locales") {
            let languages = allFacts.reduce(Set<String>(), { languages, fact in
                var languages = languages
                languages.insert(fact.language)
                return languages
            })
            
            let translations = languages.map({ "\($0) (\(Locale(identifier: $0).englishDescription))" }).joined(separator: ", ")
            command.message.replyPrivate(key: "facts.locales", fromCommand: command, map: [
                "translations": translations
            ])
            return
        }
        var facts = Array(allFacts.grouped.values).sorted(by: { $0.cannonicalName < $1.cannonicalName })
        let filterLanguage = String(command.locale.identifier.prefix(2))
        if filterLanguage != "en" {
            facts = facts.filter({ $0.messages[filterLanguage] != nil })
        }
        
        var platformFacts = facts.filter({ $0.isPlatformFact }).platformGrouped
        facts = facts.filter({ $0.isPlatformFact == false })
        
        command.message.replyPrivate(key: "facts.list", fromCommand: command, map: [
            "language": command.locale.englishDescription,
            "count": facts.count,
            "facts": facts.map({ "!\($0.cannonicalName)" }).joined(separator: ", ")
        ])
        
        if platformFacts.count > 0 {
            command.message.replyPrivate(key: "facts.list.platform", fromCommand: command, map: [
                "count": platformFacts.count,
                "facts": platformFacts.map({ "!\($0.value.platformFactDescription)" }).joined(separator: ", ")
            ])
        }
    }
    
    @AsyncBotCommand(
        ["addfact"],
        [.param("fact-language", "pcquit-en"), .param("fact message", "Get out it's gonna blow!", .continuous)],
        category: .facts,
        description: "Add a new fact or a new language onto an existing fact",
        permission: .UserWrite
    )
    var didReceiveFactAddCommand = { command in
        guard let (commandParam, message) = command.param2 as? (String, String) else {
            return
        }
        guard let factCommand = IRCBotCommand(from: "!\(commandParam)", inMessage: command.message) else {
            command.message.error(key: "addfact.syntax", fromCommand: command, map: [
                "param": command.param1!
            ])
            return
        }
        let author = command.message.user.nickname
        
        do {
            let fact = try await GroupedFact.get(name: factCommand.command)
            
            if fact == nil {
                Fact.create(name: factCommand.command, author: author, message: message, forLocale: factCommand.locale).whenComplete({ result in
                    switch result {
                    case .failure(_):
                        command.message.error(key: "addfact.error", fromCommand: command)
                        
                    case .success(let fact):
                        command.message.reply(key: "addfact.new", fromCommand: command, map: [
                            "fact": factCommand.command,
                            "language": factCommand.locale.englishDescription,
                            "locale": factCommand.locale.short,
                            "message": message.excerpt(maxLength: 350)
                        ])
                    }
                })
            } else if let fact = fact, fact.messages[factCommand.locale.short] == nil {
                try await Fact.create(message: message, forName: factCommand.command, inLocale: factCommand.locale, withAuthor: author)
                
                command.message.reply(key: "addfact.added", fromCommand: command, map: [
                    "fact": factCommand.command,
                    "language": factCommand.locale.englishDescription,
                    "locale": factCommand.locale.short,
                    "message": message.excerpt(maxLength: 350)
                ])
            } else {
                command.message.error(key: "addfact.exists", fromCommand: command)
            }
        } catch {
            command.message.error(key: "addfact.error", fromCommand: command)
            return
        }
    }
    
    @AsyncBotCommand(
        ["setfact"],
        [.param("fact-language", "pcquit-en"), .param("fact message", "Get out it's gonna blow!", .continuous)],
        category: .facts,
        description: "Update an existing fact",
        permission: .UserWrite
    )
    var didReceiveFactSetCommand = { command in
        let (commandName, message) = command.param2 as! (String, String)
        guard let factCommand = IRCBotCommand(from: "!\(commandName)", inMessage: command.message) else {
            command.message.error(key: "addfact.syntax", fromCommand: command, map: [
                "param": command.param1!
            ])
            return
        }
        
        do {
            let fact = try await GroupedFact.get(name: factCommand.command)
            guard let fact = fact, fact.messages[factCommand.locale.short] != nil else {
                command.message.error(key: "setfact.notfound", fromCommand: command)
                return
            }
            
            try await Fact.update(locale: factCommand.locale, forFact: factCommand.command, withMessage: message, fromAuthor: command.message.user.nickname)
            
            command.message.reply(key: "setfact.set", fromCommand: command, map: [
                "fact": factCommand.command,
                "language": factCommand.locale.englishDescription,
                "locale": factCommand.locale.short,
                "message": message.excerpt(maxLength: 350)
            ])
        } catch {
            debug(String(describing: error))
            command.message.error(key: "addfact.error", fromCommand: command)
        }
    }
    
    @AsyncBotCommand(
        ["delfact"],
        [.param("fact-language", "pcquit-en")],
        category: .facts,
        description: "Delete a fact or an alias",
        permission: .UserWrite
    )
    var didReceiveFactDelCommand = { command in
        guard let factCommand = IRCBotCommand(from: "!\(command.parameters[0])", inMessage: command.message) else {
            command.message.error(key: "addfact.syntax", fromCommand: command, map: [
                "param": command.param1!
            ])
            return
        }
        
        do {
            let fact = try await GroupedFact.get(name: factCommand.command)
            
            guard let fact = fact, let factMessage = fact.messages[factCommand.locale.short] else {
                command.message.error(key: "setfact.notfound", fromCommand: command)
                return
            }
            
            if fact.messages.count == 1 {
                try await Fact.drop(name: fact.cannonicalName)
                command.message.reply(key: "delfact.dropped", fromCommand: command, map: [
                    "fact": fact.cannonicalName
                ])
            } else {
                try await Fact.delete(locale: factCommand.locale, forFact: factCommand.command)
                
                command.message.reply(key: "delfact.deleted", fromCommand: command, map: [
                    "locale": factCommand.locale.short,
                    "language": factCommand.locale.englishDescription,
                    "fact": fact.cannonicalName
                ])
            }
        } catch {
            command.message.error(key: "addfact.error", fromCommand: command)
        }
    }
    
    @AsyncBotCommand(
        ["alias", "aliasfact"],
        [.param("fact", "ircguide"), .param("alias", "ircguides")],
        category: .facts,
        description: "Create an alias of an existing fact",
        permission: .UserWrite
    )
    var didReceiveFactAliasCommand = { command in
        var (cannonicalFact, alias) = command.param2 as! (String, String)
        alias = alias.lowercased()
        
        do {
            let (fact, existingAlias) = try await (GroupedFact.get(name: cannonicalFact), GroupedFact.get(name: alias))
            
            guard let fact = fact else {
                command.message.error(key: "aliasfact.notexist", fromCommand: command, map: [
                    "fact": cannonicalFact
                ])
                return
            }
            
            guard existingAlias == nil && MechaSqueak.commands.contains(where: { $0.commands.contains(alias) }) == false else {
                command.message.error(key: "aliasfact.inuse", fromCommand: command, map: [
                    "alias": alias
                ])
                return
            }
            
            try await Fact.create(alias: alias, forName: fact.cannonicalName)
            command.message.reply(key: "aliasfact.added", fromCommand: command, map: [
                "alias": alias,
                "fact": fact.cannonicalName
            ])
        } catch {
            command.message.error(key: "addfact.error", fromCommand: command)
        }
    }
    
    @AsyncBotCommand(
        ["delalias"],
        [.param("alias", "ircguides")],
        category: .facts,
        description: "Delete an existing alias",
        permission: .UserWrite
    )
    var didReceiveDeleteAliasCommand = { command in
        let alias = command.parameters[0].lowercased()
        
        do {
            let fact = try await GroupedFact.get(name: alias)
            
            guard let fact = fact else {
                command.message.error(key: "delalias.notfound", fromCommand: command, map: [
                    "fact": alias
                ])
                return
            }
            
            guard alias != fact.cannonicalName else {
                command.message.error(key: "delalias.protected", fromCommand: command, map: [
                    "alias": alias
                ])
                return
            }
            
            try await Fact.delete(alias: alias)
            command.message.reply(key: "delalias.deleted", fromCommand: command, map: [
                "alias": alias,
                "fact": fact.cannonicalName
            ])
        } catch {
            command.message.error(key: "addfact.error", fromCommand: command)
        }
    }
    
    @BotCommand(
        ["anyfact"],
        [.argument("info"), .argument("locales"), .param("targets", "SpaceDawg", .multiple, .optional)],
        category: .facts,
        description: "Use a fact in the channel",
        permission: .UserWrite
    )
    var dummyFactHelpEntry = { command in
        
    }

    func onMessage (_ message: IRCPrivateMessage) async {
        guard message.raw.messageTags["batch"] == nil else {
            // Do not interpret commands from playback of old messages
            return
        }
        
        guard var command = IRCBotCommand(from: message) else {
            return
        }
        
        if command.command == "fact" || command.command == "facts" {
            return
        }
        
        if command.locale.identifier == "cn" {
            command.locale = Locale(identifier: "zh")
            mecha.reportingChannel?.send(key: "facts.cncorrection", map: [
                "nick": command.message.user.nickname
            ])
        }
        
        let isPrepFact = prepFacts.contains(where: { $0 == command.command })
        
        if command.parameters.count > 0 {
            let targets: [(String, Rescue?)] = await command.parameters.asyncMap({ target in
                var target = target
                var (_, rescue) = await board.findRescue(withCaseIdentifier: target) ?? (nil, nil)
                if rescue == nil {
                    rescue = await board.recentlyClosed.first(where: { $0.value.clientNick?.lowercased() == target.lowercased() })?.value
                }
                if rescue == nil && Int(target) == nil && command.message.destination.member(named: target) == nil {
                    let targetLowercased = target.lowercased()
                    if let fuzzyTarget = command.message.destination.members.first(where: {
                        $0.nickname.lowercased().levenshtein(targetLowercased) < 3
                    }) {
                        target = fuzzyTarget.nickname
                    }
                }
                if let rescue = rescue {
                    if isPrepFact {
                        await board.cancelPrepTimer(forRescue: rescue)
                    }
                    return (rescue.clientNick ?? target, rescue)
                }
                return (target, nil)
            })
            
            if command.locale.identifier == "auto", targets.count > 0, let firstRescue = targets[0].1 {
                command.locale = firstRescue.clientLanguage ?? Locale(identifier: "en")
            }
            
            if command.command == "prep" && targets.contains(where: { $0.1?.codeRed == true }) && configuration.general.drillMode == false {
                command.command = "quit"
                
                mecha.reportingChannel?.send(key: "facts.prepquitcorrection", map: [
                    "nick": command.message.user.nickname
                ])
            }
            
            
            if command.command == "kgbfoam" && targets.contains(where: { $1?.odyssey == true }) {
                command.command = "newkgbfoam"
            }
            
            if Fact.platformFacts.contains(where: { $0 == command.command }) {
                for platform in GamePlatform.allCases {
                    let platformTargets = targets.filter({ $0.1?.platform == platform })
                    if platformTargets.count == 0 {
                        continue
                    }
                    
                    var smartCommand = command
                    smartCommand.command = "\(platform.factPrefix)\(command.command)"
                    if command.command == "fr" && platform == .PC && targets.contains(where: { $1?.codeRed ?? false == true }) {
                        smartCommand.command += "cr"
                    }
                    if smartCommand.command == "pcteam" && targets.contains(where: { $1?.odyssey == false }) {
                        smartCommand.command = "pcwing"
                    }
                    if smartCommand.command == "pcwing" && targets.contains(where: { $1?.odyssey == true }) {
                        smartCommand.command = "pcteam"
                    }
                    smartCommand.parameters = platformTargets.map({ $0.0 })
                    sendFact(command: smartCommand, message: message)
                }
                if command.command == "quit" {
                    command.command = "prepcr"
                }
                let unknownTargets = targets.compactMap({ target -> String? in
                    if target.1 != nil && target.1?.platform != nil {
                        return nil
                    }
                    return target.0
                })
                if unknownTargets.count > 0 {
                    command.parameters = unknownTargets
                    sendFact(command: command, message: message)
                }
            } else {
                if command.command == "pcteam" && targets.contains(where: { $1?.odyssey == false }) {
                    command.command = "pcwing"
                }
                if command.command == "pcwing" && targets.contains(where: { $1?.odyssey == true }) {
                    command.command = "pcteam"
                }
                
                command.parameters = targets.map({ $0.0 })
                sendFact(command: command, message: message)
            }
        } else if command.has(argument: "locales") {
            factLocales(command: command)
        } else if command.has(argument: "info") {
            factInfo(command: command)
        } else if command.command == "quit" {
            command.command = "prepcr"
            sendFact(command: command, message: message)
        } else if Fact.platformFacts.contains(where: { $0 == command.command }) {
            command.message.error(key: "facts.noclienterror", fromCommand: command)
        } else {
            sendFact(command: command, message: message)
        }
    }
    
    func factLocales (command: IRCBotCommand) {
        Task {
            let fact = try await GroupedFact.get(name: command.command)
            
            guard let fact = fact else {
                command.message.error(key: "anyfact.notafact", fromCommand: command, map: [
                    "command": command.command
                ])
                return
            }
            
            let locales = fact.messages.keys.map({ "\($0) (\(Locale(identifier: $0).englishDescription))" }).joined(separator: ", ")
            command.message.replyPrivate(key: "anyfact.locales", fromCommand: command, map: [
                "fact": fact.cannonicalName,
                "locales": locales
            ])
        }
    }
    
    func factInfo (command: IRCBotCommand) {
        Task {
            let fact = try await Fact.get(name: command.command, forLocale: command.locale)
            
            guard let fact = fact else {
                command.message.error(key: "anyfact.notafact", fromCommand: command, map: [
                    "command": "\(command.command)-\(command.locale.short)"
                ])
                return
            }
            
            command.message.replyPrivate(key: "anyfact.info", fromCommand: command, map: [
                "fact": fact.id,
                "language": Locale(identifier: fact.language).englishDescription,
                "created": fact.createdAt.eliteFormattedString,
                "updated": fact.updatedAt.eliteFormattedString,
                "author": fact.author
            ])
        }
    }

    func sendFact (command: IRCBotCommand, message: IRCPrivateMessage) {
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
        
        Task {
            let fact = try await Fact.get(name: command.command, forLocale: command.locale)
            
            guard let fact = fact else {
                let fallbackFact = try await Fact.get(name: command.command, forLocale: Locale(identifier: "en"))
                guard let fallbackFact = fallbackFact else {
                    return
                }

                command.message.replyPrivate(key: "fact.fallback", fromCommand: command, map: [
                    "fact": command.command,
                    "identifier": command.locale.identifier,
                    "language": command.locale.englishDescription
                ])
                self.messageFact(command: command, fact: fallbackFact)
                return
            }

            self.messageFact(command: command, fact: fact)
        } 
    }

    func messageFact (command: IRCBotCommand, fact: Fact) {
        if command.parameters.count > 0 {
            let firstTarget = command.param1?.lowercased()
            if (firstTarget == command.message.client.currentNick.lowercased() || firstTarget == "xlexious") && command.message.destination != mecha.rescueChannel {
                command.message.retaliate()
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

        self.channelMessageObserver = NotificationCenter.default.addAsyncObserver(
            descriptor: IRCChannelMessageNotification(),
            using: onMessage(_:)
        )
        self.privateMessageObserver = NotificationCenter.default.addAsyncObserver(
            descriptor: IRCPrivateMessageNotification(),
            using: onMessage(_:)
        )
    }
}
