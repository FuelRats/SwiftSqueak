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

class LocalRescue {
    private static let announcerExpression = "Incoming Client: (.*) - System: (.*) - Platform: ([A-Za-z0-9]+)( \\(Odyssey\\))? - O2: (.*) - Language: .* \\(([a-z]{2}(?:-(?:[A-Z]{2}|[0-9]{3}))?(?:-[A-Za-z0-9]+)?)\\)(?: - IRC Nickname: (.*))?".r!
    var synced = false
    var isClosing = false
    var clientHost: String?
    var channelName: String
    var jumpCalls: [(Rat, Int)]
    var dispatchers: [UUID] = []

    let id: UUID

    var client: String?
    var clientNick: String?
    var clientLanguage: Locale?
    var commandIdentifier: Int
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

    var ircOxygenStatus: String {
        if self.codeRed {
            return IRCFormat.color(.LightRed, "NOT OK")
        }
        return "OK"
    }

    init? (fromAnnouncer message: IRCPrivateMessage) {
        guard let match = LocalRescue.announcerExpression.findFirst(in: message.message) else {
            return nil
        }
        guard message.user.channelUserModes.contains(.admin) else {
            return nil
        }

        self.id = UUID()
        self.commandIdentifier = 0

        let client = match.group(at: 1)!
        self.channelName = message.destination.name
        self.client = client
        var system = match.group(at: 2)!.uppercased()
        if system.hasSuffix(" SYSTEM") {
            system.removeLast(7)
        }
        self.system = StarSystem(name: system)

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
        self.commandIdentifier = 0
        self.client = message.user.nickname
        self.clientNick = message.user.nickname
        self.clientHost = message.user.hostmask
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
        self.commandIdentifier = 0

        self.client = clientName
        self.clientNick = clientName

        if let systemName = input.system {
            self.system = StarSystem(name: systemName)
        } else {
            self.system = nil
        }

        self.channelName = command.message.destination.name

        if let ircUser = command.message.destination.member(named: clientName) {
            self.clientHost = ircUser.hostmask
        }

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

    init (fromAPIRescue apiRescue: Rescue, withRats rats: [Rat], firstLimpet: Rat?, onBoard board: RescueBoard) {
        self.id = apiRescue.id.rawValue
        self.synced = true

        let attr = apiRescue.attributes

        self.client = attr.client.value
        self.clientNick = attr.clientNick.value
        self.clientLanguage = attr.clientLanguage.value != nil ? Locale(identifier: attr.clientLanguage.value!) : nil
        self.commandIdentifier = attr.commandIdentifier.value
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
                self.system = system
            }
        }
    }

    var toApiRescue: Rescue {
        let localRescue = self

        let rats: ToManyRelationship<Rat> = .init(ids: localRescue.rats.map({
            $0.id
        }))

        let firstLimpet: ToOneRelationship<Rat?> = .init(id: localRescue.firstLimpet?.id)

        let rescue = Rescue(
            id: Rescue.ID(rawValue: self.id),
            attributes: Rescue.Attributes.init(
                client: .init(value: localRescue.client),
                clientNick: .init(value: localRescue.clientNick),
                clientLanguage: .init(value: localRescue.clientLanguage?.identifier),
                commandIdentifier: .init(value: localRescue.commandIdentifier),
                codeRed: .init(value: localRescue.codeRed),
                data: .init(value: RescueData(
                    permit: localRescue.system?.permit,
                    landmark: localRescue.system?.landmark,
                    dispatchers: localRescue.dispatchers
                )),
                notes: .init(value: localRescue.notes),
                platform: .init(value: localRescue.platform),
                odyssey: .init(value: localRescue.odyssey),
                system: .init(value: localRescue.system?.name),
                quotes: .init(value: localRescue.quotes),
                status: .init(value: localRescue.status),
                title: .init(value: localRescue.title),
                outcome: .init(value: localRescue.outcome),
                unidentifiedRats: .init(value: localRescue.unidentifiedRats),
                createdAt: .init(value: localRescue.createdAt),
                updatedAt: .init(value: localRescue.updatedAt)
            ),
            relationships: Rescue.Relationships.init(rats: rats, firstLimpet: firstLimpet),
            meta: Rescue.Meta.none,
            links: Rescue.Links.none
        )
        return rescue
    }

    @discardableResult
    func createUpstream () -> EventLoopFuture<LocalRescue> {
        let promise = loop.next().makePromise(of: LocalRescue.self)

        let operation = RescueCreateOperation(rescue: self)
        operation.onCompletion = {
            promise.succeed(self)
        }

        operation.onError = { error in
            promise.fail(error)
        }

        mecha.rescueBoard.queue.addOperation(operation)
        return promise.futureResult
    }
    
    @discardableResult
    func syncUpstream (fromCommand command: IRCBotCommand) -> EventLoopFuture<LocalRescue> {
        return self.syncUpstream(representing: command.message.user)
    }

    @discardableResult
    func syncUpstream (representing: IRCUser? = nil) -> EventLoopFuture<LocalRescue> {
        if let representing = representing, let user = representing.associatedAPIData?.user {
            if self.dispatchers.contains(user.id.rawValue) == false {
                self.dispatchers.append(user.id.rawValue)
            }
        }
        
        let promise = loop.next().makePromise(of: LocalRescue.self)

        let operation = RescueUpdateOperation(rescue: self)
        operation.onCompletion = {
            promise.succeed(self)
        }

        operation.onError = { error in
            promise.fail(error)
        }

        mecha.rescueBoard.queue.addOperation(operation)
        return promise.futureResult
    }

    @available(*, deprecated, message: "Use close(firstLimpet) async instead")
    func close (
        fromBoard board: RescueBoard,
        firstLimpet: Rat? = nil,
        onComplete: @escaping () -> Void,
        onError: @escaping (Error?) -> Void
    ) {
        let wasInactive = self.status == .Inactive
        self.status = .Closed
        self.firstLimpet = firstLimpet
        if let firstLimpet = firstLimpet, self.rats.contains(where: {
            $0.id.rawValue == firstLimpet.id.rawValue
        }) == false {
            self.rats.append(firstLimpet)
        }

        if configuration.general.drillMode {
            onComplete()
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
        
        request.body = try? .encodable(patchDocument)

        httpClient.execute(request: request).whenCompleteExpecting(status: 200) { result in
            switch result {
                case .success:
                    if configuration.queue != nil {
                        QueueAPI.fetchQueue().whenSuccess({
                            $0.first(where: { $0.client.name.lowercased() == self.client?.lowercased() })?.delete()
                        })
                        if wasInactive == false && mecha.rescueBoard.activeCases <= QueueCommands.maxClientsCount {
                            QueueAPI.dequeue()
                        }
                    }
                    onComplete()
                case .failure(let error):
                    debug(String(describing: error))
                    onError(error)
            }
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
            if wasInactive == false && mecha.rescueBoard.activeCases <= QueueCommands.maxClientsCount {
                detach {
                    try? await QueueAPI.dequeue()
                }
            }
        }
    }

    func assign (_ assignParams: [String], fromChannel channel: IRCChannel, force: Bool = false) -> RescueAssignments {
        let assigns: (RescueAssignments) = assignParams.reduce(RescueAssignments(), { assigns, param in
            var assigns = assigns
            guard configuration.general.ratBlacklist.contains(where: { $0.lowercased() == param.lowercased() }) == false else {
                assigns.blacklisted.insert(param)
                return assigns
            }

            guard
                param.lowercased() != self.clientNick?.lowercased()
                && param.lowercased() != self.client?.lowercased()
            else {
                assigns.invalid.insert(param)
                return assigns
            }

            guard let nick = channel.member(named: param) else {
                assigns.notFound.insert(param)
                return assigns
            }

            guard let rat = nick.getRatRepresenting(platform: self.platform), rat.attributes.odyssey.value == self.odyssey else {
                guard assigns.unidentifiedRats.contains(param) == false && self.unidentifiedRats.contains(param) == false else {
                    assigns.unidentifiedDuplicates.insert(param)
                    return assigns
                }

                assigns.unidentifiedRats.insert(param)
                return assigns
            }
            
            if rat.currentJumpCalls.first(where: { $0.id == self.id }) == nil && rat.currentJumpCalls.first(where: { $0.id != self.id }) != nil && force == false {
                assigns.jumpConflicts.append(param)
                return assigns
            }

            guard assigns.rats.contains(where: {
                $0.id.rawValue == rat.id.rawValue
            }) == false && self.rats.contains(where: {
                $0.id.rawValue == rat.id.rawValue
            }) == false else {
                assigns.duplicates.insert(rat)
                return assigns
            }

            self.unidentifiedRats.removeAll(where: { $0.lowercased() == param.lowercased() })
            assigns.rats.insert(rat)

            return assigns
        })

        if assigns.rats.count > 0 || assigns.unidentifiedRats.count > 0 {
            self.rats.append(contentsOf: assigns.rats)
            if force || configuration.general.drillMode {
                self.unidentifiedRats.append(contentsOf: assigns.unidentifiedRats)
            }
            self.syncUpstream()
        }
        return assigns
    }

    @available(*, deprecated, message: "Use trash(reason) async instead")
    func trash (
        fromBoard board: RescueBoard,
        reason: String,
        onComplete: @escaping () -> Void,
        onError: @escaping (Error?) -> Void
    ) {
        let wasInactive = self.status == .Inactive
        self.status = .Closed
        self.outcome = .Purge
        self.notes = reason

        if configuration.general.drillMode {
            onComplete()
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

        request.body = try? .encodable(patchDocument)

        httpClient.execute(request: request).whenCompleteExpecting(status: 200) { result in
            switch result {
                case .success:
                    if configuration.queue != nil {
                        QueueAPI.fetchQueue().whenSuccess({
                            $0.first(where: { $0.client.name.lowercased() == self.client?.lowercased() })?.delete()
                        })
                         if wasInactive == false && mecha.rescueBoard.activeCases <= QueueCommands.maxClientsCount {
                            QueueAPI.dequeue()
                        }
                    }
                    onComplete()
                case .failure(let error):
                    debug(String(describing: error))
                    onError(error)
            }
        }
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
            if wasInactive == false && mecha.rescueBoard.activeCases <= QueueCommands.maxClientsCount {
                detach {
                    try? await QueueAPI.dequeue()
                }
            }
        }
    }

    func hasConflictingId (inBoard board: RescueBoard) -> Bool {
        return board.rescues.contains(where: {
            debug("Conflict Comparison: \(String(describing: self.commandIdentifier)) = \(String(describing: $0.commandIdentifier))")
            return $0.commandIdentifier == self.commandIdentifier
        })
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

    var isPrepped: Bool {
        return mecha.rescueBoard.prepTimers[self.id] == nil
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

    @available(*, deprecated, message: "Use validateSystem() async instead")
    func validateSystem () -> EventLoopFuture<()>? {
        let promise = loop.next().makePromise(of: Void.self)

        guard let system = self.system else {
            return nil
        }

        SystemsAPI.performSystemCheck(forSystem: system.name).whenComplete({ result in
            switch result {
                case .failure(let error):
                    promise.fail(error)

                case .success(let starSystem):
                    self.system?.merge(starSystem)
                    promise.succeed(())
                    guard starSystem.isConfirmed == false && starSystem.isIncomplete == false else {
                        return
                    }

                    SystemsAPI.performSearch(forSystem: system.name).whenSuccess({ result in
                        guard var results = result.data, results.count > 0 else {
                            return
                        }

                        let ratedCorrections = results.map({ ($0, $0.rateCorrectionFor(system: system.name)) })
                        var approvedCorrections = ratedCorrections.filter({ $1 != nil })
                        approvedCorrections.sort(by: { $0.1! < $1.1! })

                        if let autoCorrectableResult = approvedCorrections.first?.0 {
                            SystemsAPI.getSystemInfo(forSystem: autoCorrectableResult).whenSuccess({ starSystem in
                                self.system?.merge(starSystem)
                                self.syncUpstream()
                                mecha.reportingChannel?.client.sendMessage(
                                    toChannelName: self.channelName,
                                    withKey: "sysc.autocorrect",
                                    mapping: [
                                        "caseId": self.commandIdentifier,
                                        "client": self.clientDescription,
                                        "system": self.system.description
                                    ]
                                )
                            })
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
                            "caseId": self.commandIdentifier,
                            "client": self.clientDescription,
                            "systems": resultString
                        ])
                    })

            }
        })
        return promise.futureResult
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
            
            let ratedCorrections = results.map({ ($0, $0.rateCorrectionFor(system: system.name)) })
            var approvedCorrections = ratedCorrections.filter({ $1 != nil })
            approvedCorrections.sort(by: { $0.1! < $1.1! })

            if let autoCorrectableResult = approvedCorrections.first?.0 {
                let starSystem = try await SystemsAPI.getSystemInfo(forSystem: autoCorrectableResult)
                
                self.system?.merge(starSystem)
                self.syncUpstream()
                mecha.reportingChannel?.client.sendMessage(
                    toChannelName: self.channelName,
                    withKey: "sysc.autocorrect",
                    mapping: [
                        "caseId": self.commandIdentifier,
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
                "caseId": self.commandIdentifier,
                "client": self.clientDescription,
                "systems": resultString
            ])
        }
        return
    }
}

struct RescueAssignments {
    var rats = OrderedSet<Rat>()
    var unidentifiedRats = OrderedSet<String>()
    var duplicates = OrderedSet<Rat>()
    var unidentifiedDuplicates = OrderedSet<String>()
    var blacklisted = OrderedSet<String>()
    var notFound = OrderedSet<String>()
    var invalid = OrderedSet<String>()
    var jumpConflicts = OrderedSet<String>()
}

