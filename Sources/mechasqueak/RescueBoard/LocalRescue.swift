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
import AsyncHTTPClient
import Regex
import IRCKit

class LocalRescue: Codable {
    private static let announcerExpression = "Incoming Client: (.*) - System: (.*) - Platform: (.*) - O2: (.*) - Language: .* \\(([a-z]{2}(?:-[A-Z]{2})?)\\)(?: - IRC Nickname: (.*))?".r!
    var synced = false
    var isClosing = false
    var clientHost: String?
    var channel: String
    var systemCorrections: [SystemsAPISearchDocument.SearchResult]?
    var systemManuallyCorrected = false

    let id: UUID

    var client: String?
    var clientNick: String?
    var clientLanguage: Locale?
    var commandIdentifier: Int?
    var codeRed: Bool
    var notes: String
    var platform: GamePlatform?
    var system: String?
    var quotes: [RescueQuote]
    var status: RescueStatus
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

        let client = match.group(at: 1)!
        self.channel = message.destination.name
        self.client = client
        var system = match.group(at: 2)!.uppercased()
        if system.hasSuffix(" SYSTEM") {
            system.removeLast(7)
        }
        self.system = system

        let platformString = match.group(at: 3)!
        self.platform = GamePlatform.parsedFromText(text: platformString)

        let o2StatusString = match.group(at: 4)!
        if o2StatusString.uppercased() == "NOT OK" {
            self.codeRed = true
        } else {
            self.codeRed = false
        }

        let languageCode = match.group(at: 5)!
        self.clientLanguage = Locale(identifier: languageCode)

        self.clientNick = match.group(at: 6) ?? client

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
    }

    init? (fromRatsignal message: IRCPrivateMessage) {
        guard let signal = SignalScanner(message: message.message) else {
            return nil
        }

        self.id = UUID()
        self.client = message.user.nickname
        self.clientNick = message.user.nickname
        self.clientHost = message.user.hostmask
        self.channel = message.destination.name

        var system = signal.system?.uppercased()
        if system != nil && system!.hasSuffix(" SYSTEM") {
            system?.removeLast(7)
        }
        self.system = system

        if let platformString = signal.platform {
            self.platform = GamePlatform.parsedFromText(text: platformString)
        }

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

        var system = input.system?.uppercased()
        if system != nil && system!.hasSuffix(" SYSTEM") {
            system?.removeLast(7)
        }
        self.system = system
        self.channel = command.message.destination.name

        if let ircUser = command.message.destination.member(named: clientName) {
            self.clientHost = ircUser.hostmask
        }

        if let platformString = input.platform {
            self.platform = GamePlatform.parsedFromText(text: platformString)
        }

        self.codeRed = input.isCodeRed
        self.notes = ""

        self.quotes = []

        self.status = .Open
        self.unidentifiedRats = []
        self.rats = []

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
        self.channel = configuration.general.rescueChannel

        self.codeRed = attr.codeRed.value
        self.notes = attr.notes.value
        self.platform = attr.platform.value
        self.system = attr.system.value
        self.quotes = attr.quotes.value
        self.status = attr.status.value
        self.title = attr.title.value
        self.outcome = attr.outcome.value
        self.unidentifiedRats = attr.unidentifiedRats.value

        self.createdAt = attr.createdAt.value
        self.updatedAt = attr.updatedAt.value

        self.rats = rats
        self.firstLimpet = firstLimpet
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
                notes: .init(value: localRescue.notes),
                platform: .init(value: localRescue.platform),
                system: .init(value: localRescue.system),
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

    func createUpstream (fromBoard board: RescueBoard) {
        let postDocument = SingleDocument(
            apiDescription: .none,
            body: .init(resourceObject: self.toApiRescue),
            includes: .none,
            meta: .none,
            links: .none
        )

        let url = URLComponents(string: "\(configuration.api.url)/rescues")!
        var request = try! HTTPClient.Request(url: url.url!, method: .POST)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.api.token)")
        request.headers.add(name: "Content-Type", value: "application/vnd.api+json")

        request.body = try? .encodable(postDocument)

        httpClient.execute(request: request).whenComplete{ result in
            switch result {
                case .success(let response):
                    if response.status == .created {
                        self.synced = true
                    } else if response.status == .conflict {
                        mecha.rescueBoard.rescues.removeAll(where: { $0.id == self.id })
                    }
                case .failure(let error):
                    debug(String(describing: error))
                    self.synced = false
                    board.synced = false
            }
        }
    }

    func syncUpstream (fromBoard board: RescueBoard, representing: IRCUser? = nil) {
        if board.synced == false {
            self.synced = false
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
        if let user = representing, let userId = user.associatedAPIData?.user?.id.rawValue {
            request.headers.add(name: "x-representing", value: userId.uuidString)
        }

        request.body = try? .encodable(patchDocument)

        httpClient.execute(request: request).whenComplete { result in
            switch result {
                case .success(let response):
                    if response.status.code == 200 {
                        self.synced = true
                        board.checkSynced()
                    } else {
                        self.createUpstream(fromBoard: mecha.rescueBoard)
                    }
                case .failure(let error):
                    debug(String(describing: error))
                    self.synced = false
                    board.synced = false
            }
        }
    }

    func close (
        fromBoard board: RescueBoard,
        firstLimpet: Rat? = nil,
        onComplete: @escaping () -> Void,
        onError: @escaping (Error?) -> Void
    ) {
        self.status = .Closed
        self.firstLimpet = firstLimpet
        if let firstLimpet = firstLimpet, self.rats.contains(firstLimpet) == false {
            self.rats.append(firstLimpet)
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
                    onComplete()
                case .failure(let error):
                    debug(String(describing: error))
                    onError(error)
            }
        }
    }

    func trash (
        fromBoard board: RescueBoard,
        reason: String,
        onComplete: @escaping () -> Void,
        onError: @escaping (Error?) -> Void
    ) {
        self.status = .Closed
        self.outcome = .Purge
        self.notes = reason

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
                    onComplete()
                case .failure(let error):
                    debug(String(describing: error))
                    onError(error)
            }
        }
    }

    func hasConflictingId (inBoard board: RescueBoard) -> Bool {
        return board.rescues.contains(where: {
            debug("Conflict Comparison: \(String(describing: self.commandIdentifier)) = \(String(describing: $0.commandIdentifier))")
            return self.commandIdentifier == nil || $0.commandIdentifier == self.commandIdentifier
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
}
