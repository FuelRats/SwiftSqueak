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
import AsyncHTTPClient
import Regex
import IRCKit
import NIO

class Rescue {
    private static let announcerExpression = "Incoming Client: (.*) - System: (.*) - Platform: ([A-Za-z0-9]+)( \\(Odyssey\\))? - O2: (.*) - Language: .* \\(([a-z]{2}(?:-(?:[A-Z]{2}|[0-9]{3}))?(?:-[A-Za-z0-9]+)?)\\)(?: - IRC Nickname: (.*))?".r!
    
    var channelName: String
    var jumpCalls: [(Rat, Int)]
    var dispatchers: [UUID] = []
    var syncStatus: SyncStatus = .pendingCreation

    let id: UUID

    var client: String?
    var clientNick: String?
    var clientLanguage: Locale?
    var banned: Bool = false
    var codeRed: Bool
    var notes: String
    var platform: GamePlatform?
    var odyssey: Bool
    var quotes: [RescueQuote]
    var status: RescueStatus
    var system: StarSystem?
    var title: String?
    var outcome: RescueOutcome?
    var unidentifiedRats: [String]

    let createdAt: Date
    var updatedAt: Date

    var firstLimpet: Rat?
    var rats: [Rat]

    init? (fromAnnouncer message: IRCPrivateMessage) {
        guard let match = Rescue.announcerExpression.findFirst(in: message.message) else {
            return nil
        }
        guard message.user.channelUserModes.contains(.admin) else {
            return nil
        }

        self.id = UUID()

        let client = match.group(at: 1)!
        self.channelName = message.destination.name
        self.client = client
        self.system = StarSystem(name: match.group(at: 2)!.uppercased())

        let platformString = match.group(at: 3)!
        self.platform = GamePlatform.parsedFromText(text: platformString)
        self.odyssey = match.group(at: 4) != nil

        let o2StatusString = match.group(at: 5)!
        if o2StatusString.uppercased() == "NOT OK" {
            self.codeRed = true
        } else {
            self.codeRed = false
        }

        let languageCode = match.group(at: 6)!
        self.clientLanguage = Locale(identifier: languageCode)

        self.clientNick = match.group(at: 7) ?? client

        self.notes = ""
        self.quotes = [(RescueQuote(
            author: message.user.nickname,
            message: message.message,
            createdAt: Date(),
            updatedAt: Date(),
            lastAuthor: message.user.nickname
        ))]

        self.status = .Open
        self.unidentifiedRats = []

        self.createdAt = Date()
        self.updatedAt = Date()

        self.rats = []
        self.jumpCalls = []
    }

    init? (fromRatsignal message: IRCPrivateMessage) {
        guard let signal = SignalScanner(message: message.message) else {
            return nil
        }

        self.id = UUID()
        self.client = message.user.nickname
        self.clientNick = message.user.nickname
        self.channelName = message.destination.name

        if let systemName = signal.system {
            self.system = StarSystem(name: systemName)
        } else {
            self.system = nil
        }

        if let platformString = signal.platform {
            self.platform = GamePlatform.parsedFromText(text: platformString)
        }
        self.odyssey = signal.odyssey

        self.codeRed = signal.isCodeRed

        self.notes = ""
        self.quotes = [(RescueQuote(
            author: message.user.nickname,
            message: message.message,
            createdAt: Date(),
            updatedAt: Date(),
            lastAuthor: message.user.nickname
        ))]

        self.status = .Open

        self.unidentifiedRats = []
        self.rats = []
        self.jumpCalls = []

        self.createdAt = Date()
        self.updatedAt = Date()
    }

    init? (text: String, clientName: String, fromCommand command: IRCBotCommand) {
        guard let input = SignalScanner(message: text, requireSignal: false) else {
            return nil
        }

        self.id = UUID()

        self.client = clientName
        self.clientNick = clientName

        if let systemName = input.system {
            self.system = StarSystem(name: systemName)
        } else {
            self.system = nil
        }

        self.channelName = command.message.destination.name

        if let platformString = input.platform {
            self.platform = GamePlatform.parsedFromText(text: platformString)
        }
        
        if self.platform == .PC {
            self.odyssey = input.odyssey
        } else {
            self.odyssey = false
        }

        self.codeRed = input.isCodeRed
        self.notes = ""

        self.quotes = []

        self.status = .Open
        self.unidentifiedRats = []
        self.rats = []
        self.jumpCalls = []

        self.createdAt = Date()
        self.updatedAt = Date()
    }

    init (fromAPIRescue apiRescue: RemoteRescue, withRats rats: [Rat], firstLimpet: Rat?, onBoard board: RescueBoard) {
        self.id = apiRescue.id.rawValue

        let attr = apiRescue.attributes

        self.client = attr.client.value
        self.clientNick = attr.clientNick.value
        self.clientLanguage = attr.clientLanguage.value != nil ? Locale(identifier: attr.clientLanguage.value!) : nil
        self.channelName = configuration.general.rescueChannel

        self.codeRed = attr.codeRed.value
        self.notes = attr.notes.value
        self.platform = attr.platform.value
        if let systemName = attr.system.value {
            self.system = StarSystem(name: systemName)
        } else {
            self.system = nil
        }
        self.odyssey = attr.odyssey.value
        self.system?.permit = attr.data.value.permit
        self.system?.landmark = attr.data.value.landmark
        self.quotes = attr.quotes.value
        self.status = attr.status.value
        self.title = attr.title.value
        self.outcome = attr.outcome.value
        self.unidentifiedRats = attr.unidentifiedRats.value
        
        self.dispatchers = attr.data.value.dispatchers ?? []

        self.createdAt = attr.createdAt.value
        self.updatedAt = attr.updatedAt.value

        self.rats = rats
        self.firstLimpet = firstLimpet
        self.jumpCalls = []
        
        detach {
            if var system = self.system {
                let newSystem = try await SystemsAPI.performSystemCheck(forSystem: system.name)
                system.merge(newSystem)
                // self.system = system
            }
        }
    }
    
    var ircOxygenStatus: String {
        if self.codeRed {
            return IRCFormat.color(.LightRed, "NOT OK")
        }
        return "OK"
    }

    var clientDescription: String {
        return self.client ?? "u\u{200B}nknown client"
    }
    
    var isRecentDrill: Bool {
        return configuration.general.drillMode && Date().timeIntervalSince(self.createdAt) < 5400 && self.channel != nil
    }

    var channel: IRCChannel? {
        return mecha.reportingChannel?.client.channels.first(where: { $0.name.lowercased() == self.channelName.lowercased() })
    }
    
    var assignList: String? {
        guard self.rats.count > 0 || self.unidentifiedRats.count > 0 else {
            return nil
        }

        var assigns = self.rats.map({
            $0.name
        })

        assigns.append(contentsOf: self.unidentifiedRats.map({
            "\($0) (\(IRCFormat.color(.Grey, "unidentified")))"
        }))

        return assigns.joined(separator: ", ")
    }

    var toApiRescue: RemoteRescue {
        let rats: ToManyRelationship<Rat> = .init(ids: self.rats.map({
            $0.id
        }))

        let firstLimpet: ToOneRelationship<Rat?> = .init(id: self.firstLimpet?.id)

        let rescue = RemoteRescue(
            id: RemoteRescue.ID(rawValue: self.id),
            attributes: RemoteRescue.Attributes.init(
                client: .init(value: self.client),
                clientNick: .init(value: self.clientNick),
                clientLanguage: .init(value: self.clientLanguage?.identifier),
                commandIdentifier: .init(value: 0),
                codeRed: .init(value: self.codeRed),
                data: .init(value: RescueData(
                    permit: self.system?.permit,
                    landmark: self.system?.landmark,
                    dispatchers: self.dispatchers
                )),
                notes: .init(value: self.notes),
                platform: .init(value: self.platform),
                odyssey: .init(value: self.odyssey),
                system: .init(value: self.system?.name),
                quotes: .init(value: self.quotes),
                status: .init(value: self.status),
                title: .init(value: self.title),
                outcome: .init(value: self.outcome),
                unidentifiedRats: .init(value: self.unidentifiedRats),
                createdAt: .init(value: self.createdAt),
                updatedAt: .init(value: self.updatedAt)
            ),
            relationships: RemoteRescue.Relationships.init(rats: rats, firstLimpet: firstLimpet),
            meta: RemoteRescue.Meta.none,
            links: RemoteRescue.Links.none
        )
        return rescue
    }
    
    func setClientNick (_ nick: String?) {
        self.clientNick = nick
    }
    
    func setSystem (_ starSystem: StarSystem?) {
        self.system = starSystem
    }
    
    func setQuotes (_ quotes: [RescueQuote]) {
        self.quotes = quotes
    }
    
    func appendQuote (_ quote: RescueQuote) {
        self.quotes.append(quote)
    }
    
    func setNotes (_ notes: String) {
        self.notes = notes
    }
    
    @discardableResult
    func removeQuote (at index: Int) -> RescueQuote? {
        return self.quotes.remove(at: index)
    }
    
    func prep (message: IRCPrivateMessage, initiated: RescueInitiationType) async {
        if initiated == .signal && self.codeRed == false {
            message.reply(message: lingo.localize("board.signal.oxygen", locale: "en-GB", interpolations: [
                "client": self.clientNick ?? self.client ?? ""
            ]))
        } else if initiated != .insertion && self.codeRed == true {
            let factKey = self.platform != nil ? "\(self.platform!.factPrefix)quit" : "prepcr"
            let locale = self.clientLanguage ?? Locale(identifier: "en")
            
            var fact = try? await Fact.get(name: factKey, forLocale: locale)
            if fact == nil && self.platform != nil {
                // If platform specific quit is not available in this language, try !prepcr in this language
                fact = try? await Fact.get(name: "prepcr", forLocale: self.clientLanguage!)
            }
            if fact == nil && self.clientLanguage != nil && self.platform != nil {
                // If neiher quit or prepcr is available in this language, fall back to English.
                fact = try? await Fact.get(name: factKey, forLocale: Locale(identifier: "en"))
            }
            guard let fact = fact else {
                return
            }
            
            let client = self.clientNick ?? self.client ?? ""
            message.reply(message: "\(client) \(fact.message)")
        }
    }
    
    func close (firstLimpet: Rat? = nil) async throws {
        let wasInactive = self.status == .Inactive
        self.status = .Closed
        self.firstLimpet = firstLimpet
        if let firstLimpet = firstLimpet, self.rats.contains(where: {
            $0.id.rawValue == firstLimpet.id.rawValue
        }) == false {
            self.rats.append(firstLimpet)
        }

        if configuration.general.drillMode {
            return
        }

        let patchDocument = SingleDocument(
            apiDescription: .none,
            body: .init(resourceObject: self.toApiRescue),
            includes: .none,
            meta: .none,
            links: .none
        )

        let url = URLComponents(string: "\(configuration.api.url)/rescues/\(self.id.uuidString.lowercased())")!
        var request = try! HTTPClient.Request(url: url.url!, method: .PATCH)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.api.token)")
        request.headers.add(name: "Content-Type", value: "application/vnd.api+json")
        
        request.body = try .encodable(patchDocument)
        
        _ = try await httpClient.execute(request: request, deadline: FuelRatsAPI.deadline, expecting: 200)
        
        if configuration.queue != nil {
            _ = try? await QueueAPI.fetchQueue().first(where: { $0.client.name == self.client?.lowercased() })?.delete()
            let activeCases = await mecha.rescueBoard.activeCases
            if wasInactive == false && activeCases <= QueueCommands.maxClientsCount {
                detach {
                    try? await QueueAPI.dequeue()
                }
            }
        }
    }
    
    func assign (_ param: String, fromChannel channel: IRCChannel, force: Bool = false) async -> Result<AssignmentResult, RescueAssignError> {
        let param = param.lowercased()
        guard configuration.general.ratBlacklist.contains(where: { $0.lowercased() == param }) == false else {
            return Result.failure(RescueAssignError.blacklisted(param))
        }
        
        guard
            param != self.clientNick?.lowercased()
            && param != self.client?.lowercased()
        else {
            return Result.failure(RescueAssignError.invalid(param))
        }
        
        guard let nick = channel.member(named: param) else {
            return Result.failure(RescueAssignError.notFound(param))
        }
        
        guard let rat = nick.getRatRepresenting(platform: self.platform), rat.attributes.odyssey.value == self.odyssey else {
            guard self.unidentifiedRats.contains(param) == false else {
                return Result.success(.duplicate(param))
            }

            self.unidentifiedRats.append(param)
            return Result.success(.unidentified(param))
        }
        
        let currentJumpCalls = await rat.getCurrentJumpCalls()
        let existingCallsForCase = await currentJumpCalls.first(where: { $0.1.id == self.id })
        let existingCallsForOtherCase = await currentJumpCalls.first(where: { $0.1.id != self.id })
        
        if existingCallsForCase == nil && existingCallsForOtherCase != nil && force == false {
            return Result.failure(RescueAssignError.jumpCallConflict(rat))
        }

        guard self.rats.contains(where: { $0.id.rawValue == rat.id.rawValue }) == false else {
            return Result.success(.duplicate(rat.name))
        }

        self.unidentifiedRats.removeAll(where: { $0.lowercased() == param.lowercased() })
        self.rats.append(rat)

        return Result.success(.assigned(rat))
    }
    
    func trash (reason: String) async throws {
        let wasInactive = self.status == .Inactive
        self.status = .Closed
        self.outcome = .Purge
        self.notes = reason

        if configuration.general.drillMode {
            return
        }

        let patchDocument = SingleDocument(
            apiDescription: .none,
            body: .init(resourceObject: self.toApiRescue),
            includes: .none,
            meta: .none,
            links: .none
        )

        let url = URLComponents(string: "\(configuration.api.url)/rescues/\(self.id.uuidString.lowercased())")!
        var request = try! HTTPClient.Request(url: url.url!, method: .PATCH)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.api.token)")
        request.headers.add(name: "Content-Type", value: "application/vnd.api+json")

        request.body = try .encodable(patchDocument)
        
        _ = try await httpClient.execute(request: request, deadline: FuelRatsAPI.deadline, expecting: 200)
        
        if configuration.queue != nil {
            _ = try? await QueueAPI.fetchQueue().first(where: { $0.client.name == self.client?.lowercased() })?.delete()
            let activeCases = await mecha.rescueBoard.activeCases
            if wasInactive == false && activeCases <= QueueCommands.maxClientsCount {
                detach {
                    try? await QueueAPI.dequeue()
                }
            }
        }
    }

    func isPrepped () async -> Bool {
        return await mecha.rescueBoard.prepTimers[self.id] == nil
    }
    
    func validateSystem () async throws {
        guard let system = self.system else {
            return
        }
        
        let starSystem = try await SystemsAPI.performSystemCheck(forSystem: system.name)
        self.system?.merge(starSystem)
        detach {
            guard starSystem.isConfirmed == false && starSystem.isIncomplete == false else {
                return
            }
            
            guard var results = try await SystemsAPI.performSearch(forSystem: system.name).data, results.count > 0 else {
                return
            }
            
            let ratedCorrections = await results.map({ ($0, $0.rateCorrectionFor(system: system.name)) })
            var approvedCorrections = ratedCorrections.filter({ $1 != nil })
            approvedCorrections.sort(by: { $0.1! < $1.1! })

            let caseId = await mecha.rescueBoard.getId(forRescue: self)
            if let autoCorrectableResult = approvedCorrections.first?.0 {
                let starSystem = try await SystemsAPI.getSystemInfo(forSystem: autoCorrectableResult)
                
                // self.system?.merge(starSystem)
                // try? await self.syncUpstream()
                
                self.channel?.send(
                    key: "sysc.autocorrect",
                    map: [
                        "caseId": caseId,
                        "client": self.clientDescription,
                        "system": self.system.description
                    ]
                )
                return
            }
            
            if results.count > 9 {
                results.removeSubrange(9...)
            }

            // self.system?.availableCorrections = results

            let resultString = results.enumerated().map({
                $0.element.correctionRepresentation(index: $0.offset + 1)
            }).joined(separator: ", ")

            self.channel?.send(key: "sysc.nearestmatches", map: [
                "caseId": caseId,
                "client": self.clientDescription,
                "systems": resultString
            ])
        }
        return
    }
}

enum RescueAssignError: Error {
    case blacklisted(String)
    case invalid(String)
    case notFound(String)
    case jumpCallConflict(Rat)
    case unidentified(String)
    
}

enum AssignmentResult {
    case assigned(Rat)
    case unidentified(String)
    case duplicate(String)
}

enum SyncStatus {
    case pendingCreation
    case synced
    case pendingChanges
    case needsUpdate
}
