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
    private static let announcerExpression = "Incoming Client: (.*) - System: (.*) - Platform: ([A-Za-z0-9]+)( (Horizons 3.8|Horizons 4.0|Odyssey))? - O2: (.*) - Language: .* \\(([a-z]{2}(?:-(?:[A-Z]{2}|[0-9]{3}))?(?:-[A-Za-z0-9]+)?)\\)(?: - IRC Nickname: (.*))?".r!

    let id: UUID

    var client: String?             { didSet { property(\.client, didChangeFrom: oldValue) } }
    var clientNick: String?         { didSet { property(\.clientNick, didChangeFrom: oldValue) } }
    var clientLanguage: Locale?     { didSet { property(\.clientLanguage, didChangeFrom: oldValue) } }
    var codeRed: Bool               { didSet { property(\.codeRed, didChangeFrom: oldValue) } }
    var notes: String               { didSet { property(\.notes, didChangeFrom: oldValue) } }
    var platform: GamePlatform?     { didSet { property(\.platform, didChangeFrom: oldValue) } }
    var expansion: GameMode    { didSet { property(\.expansion, didChangeFrom: oldValue) } }
    var quotes: [RescueQuote]       { didSet { property(\.quotes, didChangeFrom: oldValue) } }
    var status: RescueStatus        { didSet { property(\.status, didChangeFrom: oldValue) } }
    var system: StarSystem?         { didSet { property(\.system, didChangeFrom: oldValue) } }
    var title: String?              { didSet { property(\.title, didChangeFrom: oldValue) } }
    var outcome: RescueOutcome?     { didSet { property(\.outcome, didChangeFrom: oldValue) } }
    var unidentifiedRats: [String]  { didSet { property(\.unidentifiedRats, didChangeFrom: oldValue) } }
    
    var firstLimpet: Rat?           { didSet { property(\.firstLimpet, didChangeFrom: oldValue) } }
    var rats: [Rat]                 { didSet { property(\.rats, didChangeFrom: oldValue) } }

    let createdAt: Date
    var updatedAt: Date
    
    var channelName: String
    var clientLastHostName: String?
    var jumpCalls: [(Rat, Int)]
    var dispatchers: [UUID] = []
    var xboxProfile: XboxLive.ProfileLookup? = nil
    var psnProfile: (PSN.ProfileLookup, PSN.PresenceResponse?)? = nil
    var banned: Bool = false
    var synced: Bool = false
    var uploaded: Bool
    var uploadOperation: RescueCreateOperation? = nil

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
        if let expansionText = match.group(at: 5) {
            self.expansion = GameMode.parsedFromText(text: expansionText) ?? .legacy
        } else {
            self.expansion = .legacy
        }
        

        let o2StatusString = match.group(at: 6)!
        if o2StatusString.uppercased() == "NOT OK" {
            self.codeRed = true
        } else {
            self.codeRed = false
        }

        let languageCode = match.group(at: 7)!
        self.clientLanguage = Locale(identifier: languageCode)

        self.clientNick = match.group(at: 8) ?? client

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
        self.uploaded = false
        self.clientLastHostName = nil
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
        if let expansionString = signal.expansion {
            self.expansion = GameMode.parsedFromText(text: expansionString) ?? .legacy
        } else {
            self.expansion = .legacy
        }
        self.clientLanguage = Locale(identifier: "en")

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
        self.clientLastHostName = message.user.hostmask

        self.createdAt = Date()
        self.updatedAt = Date()
        self.uploaded = false
        
        if message.user.associatedAPIData != nil {
            if let providedPlatform = GamePlatform.parsedFromText(text: signal.platform ?? ""), let rat = message.user.getRatRepresenting(platform: providedPlatform) {
                self.client = rat.name
                self.platform = rat.platform
                self.expansion = rat.expansion
            } else if let rat = message.user.currentRat {
                self.client = rat.name
                self.platform = rat.platform
                self.expansion = rat.expansion
            }
        }
    }

    init? (text: String, clientName: String, fromCommand command: IRCBotCommand) {
        guard let input = SignalScanner(message: text, requireSignal: false) else {
            return nil
        }

        self.id = UUID()

        self.client = clientName
        self.clientNick = clientName
        self.clientLanguage = Locale(identifier: "en")

        if let systemName = input.system {
            self.system = StarSystem(name: systemName)
        } else {
            self.system = nil
        }

        self.channelName = command.message.destination.name

        if let platformString = input.platform {
            let platform = GamePlatform.parsedFromText(text: platformString)
            self.platform = platform
        }
        
        if let expansionString = input.expansion, self.platform == .PC {
            self.expansion = GameMode.parsedFromText(text: expansionString) ?? .legacy
        } else {
            self.expansion = .legacy
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
        self.uploaded = false
        self.clientLastHostName = nil
    }
    
    init (client: String, nick: String, platform: GamePlatform?, system: String? = nil, locale: Locale? = nil, codeRed: Bool = false, expansion: GameMode?, fromCommand command: IRCBotCommand) {
        self.id = UUID()

        self.client = client
        self.clientNick = nick
        self.clientLanguage = locale ?? Locale(identifier: "en")

        if let systemName = system {
            self.system = StarSystem(name: systemName)
        } else {
            self.system = nil
        }

        self.channelName = command.message.destination.name

        self.platform = platform
        self.expansion = expansion ?? .legacy

        self.codeRed = codeRed
        self.notes = ""

        self.quotes = []

        self.status = .Open
        self.unidentifiedRats = []
        self.rats = []
        self.jumpCalls = []
        self.clientLastHostName = nil

        self.createdAt = Date()
        self.updatedAt = Date()
        self.uploaded = false
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
        self.expansion = attr.expansion.value ?? .legacy
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
        self.clientLastHostName = attr.data.value.clientLastHostname
        
        self.system?.permit = attr.data.value.permit
        self.uploaded = true
        self.synced = true
        
        Task {
            if var system = self.system {
                let newSystem = try await SystemsAPI.performSystemCheck(forSystem: system.name)
                system.merge(newSystem)
                self.system = system
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
        return self.client ?? "unknown client"
    }
    
    var onlineStatus: String? {
        switch self.platform {
        case .Xbox:
            return self.xboxLiveStatus
        case .PS:
            return self.psnStatus
        default:
            return nil
        }
    }
    
    var xboxLiveStatus: String? {
        guard case let .found(profile) = self.xboxProfile else {
            if case .notFound = self.xboxProfile {
                return IRCFormat.color(.Orange, " (XBL Profile not found)")
            }
            return nil
        }
        guard profile.presence.state == .Online else {
            if let lastSeen = profile.presence.lastSeen {
                let lastSeenAgo = lastSeen.timestamp.timeAgo(maximumUnits: 1)
                return IRCFormat.color(.Grey, " (Last online \(lastSeenAgo) ago)")
            }
            return IRCFormat.color(.Grey, " (Offline)")
        }
        if let presence = self.xboxProfile?.elitePresence {
            if let system = self.xboxProfile?.systemName, system.uppercased() == self.system?.name.uppercased() {
                return IRCFormat.color(.LightGreen, " (Confirmed)")
            } else if presence == "Is blazing their own trail" {
                return IRCFormat.color(.LightGreen, " (In game, location hidden)")
            }
            return IRCFormat.color(.LightGreen, " (\(presence))")
        }
        return IRCFormat.color(.Yellow, " (Online, not in-game)")
    }
    
    var psnStatus: String? {
        guard case .found(_) = self.psnProfile?.0 else {
            if case .notFound = self.xboxProfile {
                return IRCFormat.color(.Orange, " (PSN Profile not found)")
            }
            return nil
        }
        guard let presence = self.psnProfile?.1 else {
            return IRCFormat.color(.LightRed, " (Unavailable)")
        }
        guard presence.basicPresence.primaryPlatformInfo?.onlineStatus == .online else {
            if let lastSeenAgo = presence.basicPresence.primaryPlatformInfo?.lastOnlineDate.timeAgo(maximumUnits: 1) {
                return IRCFormat.color(.Grey, " (Last online \(lastSeenAgo) ago)")
            }
            return IRCFormat.color(.Grey, " (Offline)")
        }
        
        if presence.elitePresence != nil {
            return IRCFormat.color(.LightGreen, " (In game)")
        }
        return IRCFormat.color(.Yellow, " (Online, not in-game)")
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
    
    var platformExpansion: String {
        if platform == .PC {
            return "\(self.platform.ircRepresentable) \(self.expansion.shortIRCRepresentable)"
        }
        return self.platform.ircRepresentable
    }
    
    var signal: String {
        if configuration.general.drillMode {
            return ""
        }
        switch self.platform {
            case .PC:
                return self.expansion.signal

            case .Xbox:
                return "(XB_SIGNAL)"

            case .PS:
                return "(PS_SIGNAL)"
            
            default:
                return ""
        }
    }

    func toApiRescue (withIdentifier identifier: Int) -> RemoteRescue {
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
                commandIdentifier: .init(value: identifier),
                codeRed: .init(value: self.codeRed),
                data: .init(value: RescueData(
                    permit: self.system?.permit,
                    landmark: self.system?.landmark,
                    dispatchers: self.dispatchers,
                    clientLastHostname: self.clientLastHostName
                )),
                notes: .init(value: self.notes),
                platform: .init(value: self.platform),
                expansion: .init(value: self.expansion),
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
    
    func setQuotes (_ quotes: [RescueQuote]) {
        self.quotes = quotes
    }
    
    func appendQuote (_ quote: RescueQuote) {
        self.quotes.append(quote)
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
    
    func close (firstLimpet: Rat? = nil, paperworkOnly: Bool = false, command: IRCBotCommand?) async throws {
        let wasInactive = self.status == .Inactive
        self.status = .Closed
        if paperworkOnly == false {
            self.firstLimpet = firstLimpet
        }
        if let firstLimpet = firstLimpet, self.rats.contains(where: {
            $0.id.rawValue == firstLimpet.id.rawValue
        }) == false {
            self.rats.append(firstLimpet)
        }

        if configuration.general.drillMode {
            return
        }
        let identifier = await board.getId(forRescue: self) ?? 0
        let patchDocument = SingleDocument(
            apiDescription: .none,
            body: .init(resourceObject: self.toApiRescue(withIdentifier: identifier)),
            includes: .none,
            meta: .none,
            links: .none
        )

        var request = try HTTPClient.Request(apiPath: "/rescues/\(self.id.uuidString.lowercased())", method: .PATCH)
        request.headers.add(name: "Content-Type", value: "application/vnd.api+json")
        if let command = command, let user = command.message.user.associatedAPIData?.user {
            request.headers.add(name: "x-representing", value: user.id.rawValue.uuidString)
        }
        
        request.body = try .encodable(patchDocument)
        
        _ = try await httpClient.execute(request: request, deadline: FuelRatsAPI.deadline, expecting: 200)
        
        if configuration.queue != nil {
            _ = try? await QueueAPI.fetchQueue().first(where: { $0.client.name == self.client?.lowercased() })?.delete()
            let activeCases = await board.activeCases
            if wasInactive == false && activeCases <= QueueCommands.maxClientsCount {
                Task {
                    _ = try? await QueueAPI.dequeue()
                    if let platform = self.platform, await board.lastSignalsReceived[PlatformExpansion(platform: platform, expansion: self.expansion)] ?? Date(timeIntervalSince1970: 0) < self.createdAt {
                        await board.setLastSignalReceived(platform: platform, expansion: self.expansion, date: self.createdAt)
                    }
                }
            }
        }
    }
    
    func assign (
        _ param: String,
        fromChannel channel: IRCChannel,
        force: Bool = false,
        carrier: Bool = false
    ) async -> Result<AssignmentResult, RescueAssignError> {
        let param = param.lowercased()
        guard configuration.general.ratBlacklist.contains(where: { $0.lowercased() == param }) == false else {
            return Result.failure(RescueAssignError.blacklisted(param))
        }
        
        guard
            (param != self.clientNick?.lowercased()
            && param != self.client?.lowercased()) || force
        else {
            return Result.failure(RescueAssignError.invalid(param))
        }
        
        guard let nick = channel.member(named: param) else {
            return Result.failure(RescueAssignError.notFound(param))
        }
        if self.codeRed == true && nick.hasPermission(permission: .DispatchRead) == false && !force {
            return Result.failure(.unqualified(nick.nickname))
        }
        
        guard nick.associatedAPIData != nil else {
            return Result.failure(.notLoggedIn(nick.nickname))
        }
        
        var rat: Rat? = nil
        if carrier && nick.currentRat?.expansion.hasSharedUniverse(with: self.expansion) == true {
            rat = nick.currentRat
        } else {
            let assignRat = nick.getRatRepresenting(platform: self.platform)
            if assignRat?.attributes.expansion.value == self.expansion {
                rat = assignRat
            }
        }
        
        let boardSynced = await board.isSynced
        guard let rat = rat else {
            guard force || configuration.general.drillMode || boardSynced == false else {
                return Result.failure(.unidentified(param))
            }
            guard self.unidentifiedRats.contains(param) == false else {
                return Result.success(.unidentifiedDuplicate(param))
            }
            
            self.unidentifiedRats.append(param)
            return Result.success(.unidentified(param))
        }

        guard self.rats.contains(where: { $0.id.rawValue == rat.id.rawValue }) == false else {
            return Result.success(.duplicate(rat))
        }

        self.unidentifiedRats.removeAll(where: { $0.lowercased() == param.lowercased() })
        self.rats.append(rat)

        return Result.success(.assigned(rat))
    }
    
    func trash (reason: String, command: IRCBotCommand?) async throws {
        let wasInactive = self.status == .Inactive
        self.status = .Closed
        self.outcome = .Purge
        self.notes = reason

        if configuration.general.drillMode {
            return
        }
        
        let identifier = await board.getId(forRescue: self) ?? 0

        let patchDocument = SingleDocument(
            apiDescription: .none,
            body: .init(resourceObject: self.toApiRescue(withIdentifier: identifier)),
            includes: .none,
            meta: .none,
            links: .none
        )

        var request = try HTTPClient.Request(apiPath: "/rescues/\(self.id.uuidString.lowercased())", method: .PATCH)
        request.headers.add(name: "Content-Type", value: "application/vnd.api+json")
        if let command = command, let user = command.message.user.associatedAPIData?.user {
            request.headers.add(name: "x-representing", value: user.id.rawValue.uuidString)
        }

        request.body = try .encodable(patchDocument)
        
        _ = try await httpClient.execute(request: request, deadline: FuelRatsAPI.deadline, expecting: 200)
        
        if configuration.queue != nil {
            _ = try? await QueueAPI.fetchQueue().first(where: { $0.client.name == self.client?.lowercased() })?.delete()
            let activeCases = await board.activeCases
            if wasInactive == false && activeCases <= QueueCommands.maxClientsCount {
                Task {
                    try? await QueueAPI.dequeue()
                }
            }
        }
    }

    func isPrepped () async -> Bool {
        return await board.prepTimers[self.id] == nil
    }
    
    func validateSystem () async throws {
        guard let system = self.system else {
            return
        }
        
        let starSystem = try await SystemsAPI.performSystemCheck(forSystem: system.name)
        self.system?.merge(starSystem)
        if starSystem.isConfirmed == false {
            let autoCorrectedSystem = autocorrect(system: starSystem)
            if autoCorrectedSystem.name != starSystem.name {
                let verifiedAutocorrectSystem = try await SystemsAPI.performSystemCheck(forSystem: autoCorrectedSystem.name)
                self.system?.merge(verifiedAutocorrectSystem)
            }
        }
        Task {
            guard starSystem.isConfirmed == false && starSystem.isIncomplete == false else {
                return
            }
            
            guard var results = try await SystemsAPI.performSearch(forSystem: system.name).data, results.count > 0 else {
                return
            }
            
            guard self.system?.isConfirmed != true else {
                return
            }
            let ratedCorrections = results.map({ ($0, $0.rateCorrectionFor(system: system.name)) })
            var approvedCorrections = ratedCorrections.filter({ $1 != nil })
            approvedCorrections.sort(by: { $0.1! < $1.1! })

            let caseId = await board.getId(forRescue: self) ?? 0
            if let autoCorrectableResult = approvedCorrections.first?.0 {
                let starSystem = try await SystemsAPI.getSystemInfo(forSystem: autoCorrectableResult)
                
                self.system?.merge(starSystem)
                try? self.save(nil)
                
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

            self.system?.availableCorrections = results

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
    
    func save (_ command: IRCBotCommand?) throws {
        Task {
            try await saveAndWait(command)
        }
    }
    
    func saveAndWait (_ command: IRCBotCommand?) async throws {
        guard configuration.general.drillMode == false else {
            return
        }
        let identifier = await board.getId(forRescue: self) ?? 0
        guard self.uploaded || self.uploadOperation != nil else {
            return try await withCheckedThrowingContinuation { continuation in
                let operation = RescueCreateOperation(rescue: self, withCaseId: identifier, representing: command?.message.user)
                operation.onCompletion = {
                    self.uploadOperation = nil
                    continuation.resume(returning: ())
                }
                
                operation.onError = { error in
                    self.uploadOperation = nil
                    print(String(describing: error))
                    continuation.resume(throwing: error)
                }
                
                board.queue.addOperation(operation)
                self.uploadOperation = operation
            }
        }
        
        if let representing = command?.message.user, let user = representing.associatedAPIData?.user {
            if self.dispatchers.contains(user.id.rawValue) == false {
                self.dispatchers.append(user.id.rawValue)
            }
        }
        
        let caseId = await board.getId(forRescue: self) ?? 0
        return try await withCheckedThrowingContinuation { continuation in
            let operation = RescueUpdateOperation(rescue: self, withCaseId: caseId, representing: command?.message.user)
            
            if let uploadOperation = self.uploadOperation {
                operation.addDependency(uploadOperation)
            }
            
            operation.onCompletion = {
                continuation.resume(returning: ())
            }
            
            operation.onError = { error in
                print(String(describing: error))
                continuation.resume(throwing: error)
            }
            
            board.queue.addOperation(operation)
        }
    }
    
    private func property<T: Equatable>(_ keyPath: KeyPath<Rescue, T>, didChangeFrom oldValue: T) {
        guard self[keyPath: keyPath] != oldValue else {
            return
        }
        
        if keyPath == \.platform {
            if platform != .PC && expansion != .legacy {
                expansion = .legacy
            }
        }
        synced = false
    }
}

enum RescueAssignError: Error {
    case blacklisted(String)
    case invalid(String)
    case notFound(String)
    case jumpCallConflict(Rat)
    case unidentified(String)
    case unqualified(String)
    case notLoggedIn(String)
}

enum AssignmentResult {
    case assigned(Rat)
    case unidentified(String)
    case unidentifiedDuplicate(String)
    case duplicate(Rat)
}
