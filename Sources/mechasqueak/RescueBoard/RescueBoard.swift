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
@preconcurrency import IRCKit
import NIO
import Regex

struct PlatformExpansion: Codable, Hashable {
    let platform: GamePlatform
    let expansion: GameMode
}

actor RescueBoard {
    private var rescues: [Int: Rescue] = [:]
    private let queue = OperationQueue()
    private var isSynced = true
    private var syncTimer: RepeatedTask?
    private var lastSignalsReceived: [PlatformExpansion: Date] = [:]
    private var prepTimers: [UUID: Scheduled<()>?] = [:]
    private var recentIdentifiers: [Int] = []
    private var recentlyClosed = [Int: Rescue]()
    private var pendingClientJoins: [String: (EventLoopPromise<Void>, Rescue)] = [:]

    private var lastPaperworkReminder: [UUID: Date] = [:]

    nonisolated func startUpRoutines() {
        if configuration.general.drillMode == false {
            loop.next().scheduleRepeatedTask(
                initialDelay: .minutes(15), delay: .minutes(15), { @Sendable task in
                    self.checkElapsedPaperwork(task: task)
                }
            )
        }

        Task {
            guard let rescues = try? await FuelRatsAPI.getLastRescues().body.primaryResource,
                rescues.values.count > 0
            else {
                return
            }

            for platform in GamePlatform.allCases {
                if platform != .PC {
                    guard
                        let createdAt = rescues.values.first(where: {
                            $0.platform == platform && $0.outcome != .Purge
                        })?.createdAt
                    else {
                        continue
                    }
                    let lastSignalReceived = await self.lastSignalsReceived[
                        PlatformExpansion(platform: platform, expansion: .legacy)]
                    if lastSignalReceived == nil || createdAt > lastSignalReceived! {
                        await self.setLastSignalReceived(
                            platform: platform, expansion: .legacy, createdAt)
                    }
                    continue
                }

                for expansion in GameMode.allCases {
                    guard
                        let createdAt = rescues.values.first(where: {
                            $0.platform == platform && $0.expansion == expansion
                                && $0.outcome != .Purge
                        })?.createdAt
                    else {
                        continue
                    }
                    let lastSignalReceived = await self.lastSignalsReceived[
                        PlatformExpansion(platform: platform, expansion: expansion)]
                    if lastSignalReceived == nil || createdAt > lastSignalReceived! {
                        await self.setLastSignalReceived(
                            platform: platform, expansion: expansion, date: createdAt)
                    }
                }
            }
        }
    }
    
    nonisolated func getIsSynced() async -> Bool {
        return await self.isSynced
    }
    
    nonisolated func getRescues () async -> [Int: Rescue] {
        return await self.rescues
    }
    
    nonisolated func getLastSignalsRecieved() async -> [PlatformExpansion: Date] {
        return await self.lastSignalsReceived
    }
    
    nonisolated func getRecentlyClosed() async -> [Int: Rescue] {
        return await self.recentlyClosed
    }
    
    nonisolated func getPendingClientJoins() async -> [String: (EventLoopPromise<Void>, Rescue)] {
        return await self.pendingClientJoins
    }
    
    nonisolated func getPrepTimers() async -> [UUID: Scheduled<()>?] {
        return await self.prepTimers
    }
    
    nonisolated func addSyncOperation(_ operation: Operation) async {
        queue.addOperation(operation)
    }
    
    func addPendingClientJoin(key: String, promise: EventLoopPromise<Void>, rescue: Rescue) async {
        pendingClientJoins[key] = (promise, rescue)
    }
    
    func removePendingJoin(key: String) async {
        pendingClientJoins.removeValue(forKey: key)
    }

    func setIsSynced(_ synced: Bool) {
        self.isSynced = synced
    }

    func sync() async throws {
        self.queue.cancelAllOperations()
        guard configuration.general.drillMode == false else {
            return
        }
        let remoteRescues = try await FuelRatsAPI.getOpenRescues().convertToLocalRescues()

        var upload = 0
        var download = 0
        var updateRemote = 0
        var updateLocal = 0
        var conflicts = 0

        for remoteRescue in remoteRescues {
            if let (localKey, localRescue) = rescues.first(where: {
                $0.value.id == remoteRescue.1.id
            }) {
                if localRescue.updatedAt > remoteRescue.1.updatedAt {
                    updateRemote += 1
                    try? await localRescue.saveAndWait(nil)
                } else if remoteRescue.1.updatedAt > localRescue.updatedAt {
                    updateLocal += 1
                    self.rescues.removeValue(forKey: localKey)
                    let caseId = await self.insert(
                        rescue: remoteRescue.1, preferringIdentifier: remoteRescue.0)
                    if caseId != remoteRescue.0 {
                        conflicts += 1
                    }
                }
            } else {
                download += 1
                let caseId = await self.insert(
                    rescue: remoteRescue.1, preferringIdentifier: remoteRescue.0)
                if caseId != remoteRescue.0 {
                    conflicts += 1
                }
            }
        }

        for (_, localRescue) in self.rescues where
            remoteRescues.contains(where: { $0.1.id == localRescue.id }) == false {
            upload += 1
            localRescue.uploaded = false
            try? await localRescue.saveAndWait(nil)
        }

        var updates = [String]()

        if download > 0 {
            updates.append(
                lingo.localize(
                    "board.synced.downstreamNew", locale: "en-GB",
                    interpolations: [
                        "count": download
                    ]))
        }

        if upload > 0 {
            updates.append(
                lingo.localize(
                    "board.synced.upstreamNew", locale: "en-GB",
                    interpolations: [
                        "count": upload
                    ]))
        }

        if updateRemote > 0 {
            updates.append(
                lingo.localize(
                    "board.synced.upstreamUpdate", locale: "en-GB",
                    interpolations: [
                        "count": updateRemote
                    ]))
        }

        if updateLocal > 0 {
            updates.append(
                lingo.localize(
                    "board.synced.downstreamUpdate", locale: "en-GB",
                    interpolations: [
                        "count": updateLocal
                    ]))
        }

        if conflicts > 0 {
            updates.append(
                lingo.localize(
                    "board.synced.conflicts", locale: "en-GB",
                    interpolations: [
                        "count": conflicts
                    ]))
        }

        let syncMessage = lingo.localize(
            "board.synced", locale: "en-GB",
            interpolations: [
                "api": configuration.api.url,
                "updates": updates.englishList
            ])
        isSynced = true
        mecha.reportingChannel?.send(message: syncMessage)
    }

    func getId(forRescue rescue: Rescue) -> Int? {
        return self.rescues.first(where: { $0.value.id == rescue.id })?.key
    }

    func getRescue(byCommandIdentifier identifier: Int) async -> Rescue? {
        return self.rescues[identifier]
    }

    nonisolated var activeCases: Int {
        get async {
            return await self.rescues.filter({ $0.value.status == .Open }).count
        }
    }

    func findRescue(
        withCaseIdentifier caseIdentifier: String, includingRecentlyClosed: Bool = false
    ) async -> (Int, Rescue)? {
        var caseIdentifier = caseIdentifier
        if caseIdentifier.starts(with: "#") {
            caseIdentifier = String(
                caseIdentifier.suffix(
                    from: caseIdentifier.index(caseIdentifier.startIndex, offsetBy: 1)
                ))
        }

        if let caseIdNumber = Int(caseIdentifier), let rescue = self.rescues[caseIdNumber] {
            return (key: caseIdNumber, value: rescue)
        }

        if let (caseId, rescue) = await self.first(where: { (_, rescue) in
            let client = rescue.client?.lowercased()
            let clientNick = rescue.clientNick?.lowercased()
            return client == caseIdentifier.lowercased()
                || clientNick == caseIdentifier.lowercased()
        }) {
            return (key: caseId, value: rescue)
        }
        if includingRecentlyClosed {
            if let caseIdNumber = Int(caseIdentifier),
                let rescue = self.recentlyClosed[caseIdNumber] {
                return (key: caseIdNumber, value: rescue)
            }
            if let (caseId, rescue) = self.recentlyClosed.first(where: { (_, rescue) in
                return rescue.client?.lowercased() == caseIdentifier.lowercased()
                    || rescue.clientNick?.lowercased() == caseIdentifier.lowercased()
            }) {
                return (key: caseId, value: rescue)
            }
        }
        return nil
    }

    nonisolated func findMentionedCasesIn(message: IRCPrivateMessage) async -> ([(Int, Rescue)], Set<Int>) {
        let caseIds = MessageScanner.caseMentionExpression.findAll(in: message.message).compactMap(
            { (match: Match) -> Int? in
            if let id = match.group(at: 1) {
                return Int(id)
            }
            return nil
        })
        
        let rescues = await self.getRescues()
        let (validCases, invalidCaseIds): ([(Int, Rescue)], Set<Int>) = caseIds.reduce(
            into: ([], [])
        ) { result, caseId in
            if let rescue = rescues[caseId] {
                result.0.append((caseId, rescue))
            } else {
                result.1.insert(caseId)
            }
        }
        
        return (validCases, invalidCaseIds)
    }

    func fuzzyFindRescue(forChannelMember member: IRCUser) async -> (Int, Rescue)? {
        return await self.first(where: { (_, rescue) in
            let memberString = member.nickname.lowercased()
            guard let client = rescue.client else {
                return false
            }
            guard let nickname = rescue.clientNick else {
                return client.lowercased().levenshtein(memberString) < 3
            }
            return client.lowercased().levenshtein(memberString) < 3
                || nickname.lowercased().levenshtein(memberString) < 3
        })
    }
    
    func restoreRecentlyClosed (id: UUID) async -> Int? {
        guard let result = try? await FuelRatsAPI.getRescue(id: id) else {
            return nil
        }

        let apiRescue = result.body.data!.primary.value
        let rats = result.assignedRats()
        let (lastEditUser, _) = result.lastEditUser()
        let firstLimpet = result.firstLimpet()

        let rescue = Rescue(
            fromAPIRescue: apiRescue,
            withRats: rats,
            firstLimpet: firstLimpet,
            lastEditUser: lastEditUser,
            onBoard: board
        )
        rescue.outcome = nil
        rescue.status = .Open

        let caseId = await board.insert(
            rescue: rescue, preferringIdentifier: apiRescue.commandIdentifier)
        
        try? rescue.save(nil)
        return caseId
    }

    func insert(
        rescue: Rescue,
        preferringIdentifier preferredIdentifier: Int? = nil,
        preferringEvenness: Bool? = nil
    ) async -> Int {
        var identifier = preferredIdentifier ?? getNewIdentifier(even: preferringEvenness)
        if self.rescues[identifier] != nil {
            identifier = getNewIdentifier()
        }
        self.rescues[identifier] = rescue
        return identifier
    }

    private func insert(rescue: Rescue, withIdentifier identifier: Int) async {
        if self.rescues[identifier] != nil {
            return
        }
        self.rescues[identifier] = rescue
    }

    func insert(
        rescue: Rescue, fromMessage message: IRCPrivateMessage, initiated: RescueInitiationType,
        force: Bool = false
    ) async throws {
        let clientName = rescue.client?.lowercased()
        let clientNick = rescue.clientNick?.lowercased()

        if let (_, existingRescue) = await self.first(where: {
            let currentClientName = $0.value.client?.lowercased()
            let currentClientNick = $0.value.clientNick?.lowercased()
            return currentClientName == clientName
                || (currentClientNick != nil && currentClientNick == clientNick)
        }) {
            try? await announceExistingRescue(
                existingRescue, conflictingWith: rescue, initiated: initiated, inMessage: message)
            return
        }

        if force == false {
            do {
                try await anticipateClientJoin(
                    name: clientNick ?? clientName ?? "", forRescue: rescue, initiated: initiated)
            } catch {
                message.reply(message: lingo.localize("board.signal.ignore", locale: "en-GB"))
                return
            }

        }
        if let lastHostname = rescue.clientLastHostName {
            if let (_, existingRescue) = await self.first(where: {
                $0.value.clientLastHostName == lastHostname
            }) {
                try? await announceExistingRescue(
                    existingRescue, conflictingWith: rescue, initiated: initiated,
                    inMessage: message)
                return
            }
        }

        if initiated == .announcer && configuration.queue != nil {
            if let promise = QueueAPI.pendingQueueJoins.first(where: {
                $0.key.lowercased() == clientName
            }) {
                promise.value.succeed(())
                QueueAPI.pendingQueueJoins.removeValue(forKey: clientName ?? "")
            }

            _ = try? await QueueAPI.fetchQueue().first(where: {
                $0.client.name.lowercased() == rescue.client?.lowercased()
            })?.setInProgress()
        }

        let recentlyClosed = Array(self.recentlyClosed)

        if let (_, recentRescue) = recentlyClosed.first(where: {
            let currentClient = $0.value.client
            let updatedAt = $0.value.updatedAt

            return currentClient == clientName && Date().timeIntervalSince(updatedAt) < 900
        }), configuration.general.drillMode == false, initiated != .insertion {
            if recentRescue.quotes.contains(where: { $0.message.lowercased().contains("fuel+") })
                == false {
                if let caseId = await restoreRecentlyClosed(id: recentRescue.id) {
                    message.reply(
                        message: lingo.localize(
                            "rescue.reopen.opened", locale: "en-GB",
                            interpolations: [
                                "id": recentRescue.id.ircRepresentation,
                                "caseId": caseId
                            ]
                        )
                    )
                    return
                }
            }
        }

        var even: Bool?
        if initiated == .insertion {
            if message.user.nickname.lowercased().contains("even") {
                even = true
            } else if message.user.nickname.lowercased().contains("odd") {
                even = false
            }
        }

        let identifier = await self.insert(rescue: rescue, preferringEvenness: even)
        self.recentIdentifiers.removeAll(where: { $0 == identifier })
        self.recentIdentifiers.append(identifier)

        if rescue.codeRed == false && configuration.general.drillMode == false
            && initiated != .insertion {
            schedulePrepTimer(rescue: rescue)
        }

        if configuration.general.drillMode == false {
            Task {
                try? await self.checkClientFrequentFlier(rescue: rescue)
            }
        }

        var systemChangedByXboxLive = false
        if rescue.platform == .Xbox {
            systemChangedByXboxLive = await performXboxProfileCheck(rescue: rescue)
        }
        if rescue.platform == .PS, let name = rescue.client {
            rescue.psnProfile = await PSN.performLookup(name: name)
        }
        
        if rescue.system != nil {
            try? await rescue.validateSystem()
        }

        try? rescue.save(nil)
        let signal = try generateSignal(caseId: identifier, rescue: rescue, initiated: initiated)
        message.reply(message: signal)

        await rescue.prep(message: message, initiated: initiated)

        checkSystemBodyInClientMessage(caseId: identifier, rescue: rescue)

        if systemChangedByXboxLive {
            notifyXboxSystemCorrection(caseId: identifier, rescue: rescue)
        }
        
        checkThargoidSystemState(caseId: identifier, rescue: rescue)
        checkUnobtainablePermitSystem(caseId: identifier, rescue: rescue)
        checkXboxPrivacy(caseId: identifier, rescue: rescue)
        checkPSPlusMissing(caseId: identifier, rescue: rescue)
        try? rescue.save(nil)
    }
    
    func generateSignal (caseId: Int, rescue: Rescue, initiated: RescueInitiationType) throws -> String {
        let language = (rescue.clientLanguage ?? Locale(identifier: "en")).englishDescription
        let languageCode = (rescue.clientLanguage ?? Locale(identifier: "en")).identifier
        guard rescue.system != nil else {
            return try stencil.renderLine(
                name: "ratsignal.stencil",
                context: [
                    "caseId": caseId,
                    "signal": configuration.general.signal.uppercased(),
                    "platform": rescue.platform.ircRepresentable,
                    "expansion": rescue.platform == .PC
                        ? rescue.expansion.shortIRCRepresentable : "",
                    "rescue": rescue,
                    "system": rescue.system as Any,
                    "landmark": rescue.system?.landmark as Any,
                    "language": language,
                    "platformSignal": rescue.signal,
                    "initiated": initiated,
                    "langCode": languageCode
                ]
            )
        }

        return try stencil.renderLine(
            name: "ratsignal.stencil",
            context: [
                "caseId": caseId,
                "signal": configuration.general.signal.uppercased(),
                "platform": rescue.platform.ircRepresentable,
                "expansion": rescue.platform == .PC ? rescue.expansion.shortIRCRepresentable : "",
                "rescue": rescue,
                "system": rescue.system as Any,
                "landmark": rescue.system?.landmark as Any,
                "language": language,
                "platformSignal": rescue.signal,
                "initiated": initiated,
                "langCode": languageCode,
                "invalid": rescue.system?.isInvalid ?? false
            ]
        )
    }
    
    func reopenRecentlyClosed(recentRescue: Rescue) async throws -> Int? {
        guard let result = try await FuelRatsAPI.getRescue(id: recentRescue.id) else {
            return nil
        }

        let apiRescue = result.body.data!.primary.value
        let rats = result.assignedRats()
        let (lastEditUser, _) = result.lastEditUser()
        let firstLimpet = result.firstLimpet()

        let rescue = Rescue(
            fromAPIRescue: apiRescue,
            withRats: rats,
            firstLimpet: firstLimpet,
            lastEditUser: lastEditUser,
            onBoard: board
        )
        rescue.outcome = nil
        rescue.status = .Open

        let caseId = await board.insert(
            rescue: rescue, preferringIdentifier: apiRescue.commandIdentifier
        )
        try rescue.save(nil)
        return caseId
    }

    @discardableResult
    func remove(id: Int) async -> Bool {
        if let rescue = self.rescues.removeValue(forKey: id) {
            await self.cancelPrepTimer(forRescue: rescue)
            self.recentlyClosed[id] = rescue
            return true
        }
        return false
    }
    
    func schedulePrepTimer (rescue: Rescue) {
        let rescueId = rescue.id
        self.prepTimers[rescue.id] = loop.next().scheduleTask(
            in: .seconds(180), { @Sendable in
                Task {
                    guard let (caseId, rescue) = await self.rescues.first(where: { $0.value.id == rescueId }) else {
                        return
                    }
                    if rescue.codeRed == false || rescue.status == .Inactive {
                        rescue.channel?.send(key: "board.notprepped", map: [
                            "caseId": caseId
                        ])
                    }
                }
            }
        )
    }

    func setLastSignalReceived(platform: GamePlatform, expansion: GameMode, date: Date) {
        self.lastSignalsReceived[PlatformExpansion(platform: platform, expansion: expansion)] = date
    }

    func getNewIdentifier(even: Bool? = nil) -> Int {
        /* Get the first 10 identifiers not currently being used by a case, this method lets us generally stay between
         0 and 15 re-using a recent number if we need to without the case ID becoming something ridicolous like #32 */
        let fetchCount = self.rescues.count > 9 ? 1 : Swift.max(10 - self.rescues.count, 4)
        let generatedIdentifiers = generateAvailableIdentifiers(count: fetchCount)

        // Create a map of identifiers to the identifier's index in the the recently used list
        let identifierMap = generatedIdentifiers.reduce(
            [:],
            { (identifiers: [Int: Int], identifier: Int) -> [Int: Int] in
                var identifiers = identifiers
                var index = 0

                if let firstIndex = recentIdentifiers.firstIndex(of: identifier) {
                    index =
                        recentIdentifiers.distance(
                            from: recentIdentifiers.startIndex, to: firstIndex) + 1
                }

                identifiers[identifier] = index
                return identifiers
            }
        )

        /* Sort identifiers by their position in the recently used list, the longer ago one was used, the more likely
         it is to be picked. If two identifiers have the same score, we will prefer the one that is the lowest number */
        let sortedIdentifiers = generatedIdentifiers.sorted(by: {
            return identifierMap[$0]! < identifierMap[$1]!
        })

        let evenCases = self.rescues.filter({
            $0.1.status != .Inactive && $0.0.isEven && $0.value.codeRed == false
        }).count
        let evenCRCases = self.rescues.filter({
            $0.1.status != .Inactive && $0.0.isEven && $0.value.codeRed == true
        }).count
        let oddCases = self.rescues.filter({
            $0.1.status != .Inactive && $0.0.isEven == false && $0.value.codeRed == false
        }).count
        let oddCRCases = self.rescues.filter({
            $0.1.status != .Inactive && $0.0.isEven == false && $0.value.codeRed == true
        }).count
        var expectedEvenness = even
        if expectedEvenness == nil {
            let evenWeight = (evenCases + (evenCRCases * 3))
            let oddWeight = oddCases + (oddCRCases * 3)
            if evenWeight == oddWeight {
                expectedEvenness = Bool.random()
            }
            expectedEvenness = evenWeight < oddWeight
        }

        // Return the best scoring identifier that is the opposite evenness of the last case identifier
        return sortedIdentifiers.first(where: { identifier in
            return identifier.isEven == expectedEvenness
        }) ?? sortedIdentifiers[0]
    }

    func generateAvailableIdentifiers(count: Int) -> [Int] {
        var identifiers = [Int]()
        var currentIdentifier = 0
        while identifiers.count < count {
            if rescues.first(where: { $0.0 == currentIdentifier }) == nil {
                identifiers.append(currentIdentifier)
            }
            currentIdentifier += 1
        }

        return identifiers
    }

    var firstAvailableIdentifier: Int {
        var identifier = 0
        while rescues.first(where: { $0.0 == identifier }) != nil {
            identifier += 1
        }

        return identifier
    }

    func setLastSignalReceived(platform: GamePlatform, expansion: GameMode, _ lastReceived: Date)
        async {
        self.lastSignalsReceived[PlatformExpansion(platform: platform, expansion: expansion)] =
            lastReceived
    }

    func setLastPaperworkReminder(forUser userId: UUID, toDate date: Date) async {
        self.lastPaperworkReminder[userId] = Date()
    }

    nonisolated func checkElapsedPaperwork(task: RepeatedTask) {
        Task {
            let results = try await FuelRatsAPI.getUnfiledRescues()

            let cases =
                results.body.data?.primary.values.filter({
                    $0.attributes.status.value == .Closed
                        && Date().timeIntervalSince($0.attributes.updatedAt.value) > 7200.0
                }) ?? []

            let casesPerUser = cases.reduce(
                [UUID: [RemoteRescue]](),
                { caseMap, rescue -> [UUID: [RemoteRescue]] in
                    var caseMap = caseMap
                    var firstLimpet = results.body.includes![Rat.self].first(where: {
                        $0.id.rawValue == rescue.relationships.firstLimpet?.id.rawValue
                    })
                    if firstLimpet == nil {
                        firstLimpet = results.assignedRatsFor(rescue: rescue).first
                    }

                    if let userId = firstLimpet?.relationships.user?.id.rawValue {
                        if caseMap[userId] == nil {
                            caseMap[userId] = []
                        }
                        caseMap[userId]?.append(rescue)
                    }
                    return caseMap
                })

            for (userId, rescues) in casesPerUser {
                if let lastReminder = await self.lastPaperworkReminder[userId],
                    Date().timeIntervalSince(lastReminder) < 21600 {
                    continue
                }

                var presentNicks =
                    mecha.reportingChannel?.members.filter({
                        return $0.associatedAPIData?.user?.id.rawValue == userId
                            && $0.lastMessage != nil
                    }) ?? []

                presentNicks.sort(by: { $0.lastMessage!.raw.time > $1.lastMessage!.raw.time })
                guard let latestNick = presentNicks.first else {
                    continue
                }
                if await latestNick.getAssignedRescue() != nil {
                    continue
                }
                await self.setLastPaperworkReminder(forUser: userId, toDate: Date())

                var rescueLinks: [UUID: URL] = [:]
                try await withThrowingTaskGroup(of: (UUID, URL).self) { group in
                    for rescue in rescues {
                        group.addTask {
                            return (
                                rescue.id.rawValue,
                                await URLShortener.attemptShorten(url: rescue.editLink)
                            )
                        }
                    }

                    for try await (id, url) in group {
                        rescueLinks[id] = url
                    }
                }

                let rescueStrings = rescues.map({ rescue -> String in
                    return lingo.localize(
                        "rescue.pwreminder.rescue", locale: "en-GB",
                        interpolations: [
                            "client": rescue.attributes.client.value ?? "unknown client",
                            "timeAgo": rescue.attributes.updatedAt.value.timeAgo(maximumUnits: 1),
                            "link": rescueLinks[rescue.id.rawValue] ?? "Link Unavailable"
                        ])
                })

                let key = "rescue.pwreminder.meme"

                mecha.reportingChannel?.client.sendMessage(
                    toTarget: latestNick.nickname,
                    contents: lingo.localize(
                        key, locale: "en-GB",
                        interpolations: [
                            "nick": latestNick.nickname,
                            "rescues": rescueStrings.joined(separator: ", ")
                        ]))
                if rescues.count > 0 {
                    let snickersCalculation = ceil(
                        rescues.reduce(
                            0,
                            { acc, rescue in
                                return
                                    (acc + (abs(Date().timeIntervalSince(rescue.createdAt)) / 3600))
                            }) * 10)
                    mecha.reportingChannel?.send(
                        key: "rescue.pwreminder.special",
                        map: [
                            "nick": latestNick.nickname,
                            "snickers": Swift.max(Int(snickersCalculation), 1)
                        ])
                    return
                }
            }
        }
    }

    func awaitClientJoin(
        name clientName: String, forRescue rescue: Rescue, initiated: RescueInitiationType
    ) async -> EventLoopFuture<Void> {
        let future = loop.next().makePromise(of: Void.self)
        guard rescue.channel != nil else {
            future.fail(ClientJoinError.joinFailed)
            return future.futureResult
        }

        // Immedately resolve if client is already in the channel
        if rescue.channel?.member(named: clientName) != nil || configuration.general.drillMode
            || initiated == .insertion {
            future.succeed(())
        }

        // Add a reference of pending client joins
        await board.addPendingClientJoin(key: clientName.lowercased(), promise: future, rescue: rescue)

        // Make a 5 second timeout where mecha will give up on the client joining
        loop.next().scheduleTask(
            in: .seconds(5),
            {
                Task {
                    if let (promise, _) = await board.getPendingClientJoins()[clientName.lowercased()] {
                        promise.fail(ClientJoinError.joinFailed)
                        await board.removePendingJoin(key: clientName.lowercased())
                    }
                }
            })

        return future.futureResult
    }

    func anticipateClientJoin(
        name clientName: String, forRescue rescue: Rescue, initiated: RescueInitiationType
    ) async throws {
        return try await withCheckedThrowingContinuation({ continuation in
            Task {
                await awaitClientJoin(name: clientName, forRescue: rescue, initiated: initiated).whenComplete(
                    { result in
                        switch result {
                            case .failure(let error):
                                continuation.resume(throwing: error)

                            case .success:
                                continuation.resume(returning: ())
                    }
                })
            }
        })
    }

    func announceExistingRescue(
        _ existingRescue: Rescue, conflictingWith rescue: Rescue, initiated: RescueInitiationType,
        inMessage message: IRCPrivateMessage
    ) async throws {
        let caseId = await board.getId(forRescue: existingRescue) ?? 0
        let crStatus = existingRescue.codeRed ? "(\(IRCFormat.color(.LightRed, "CR")))" : ""
        if initiated == .signal {
            message.reply(
                message: lingo.localize(
                    "board.signal.helpyou", locale: "en",
                    interpolations: [
                        "client": rescue.clientNick ?? rescue.client ?? ""
                    ]
                )
            )
        } else if initiated == .insertion {
            message.reply(
                message: lingo.localize(
                    "board.signal.exists", locale: "en",
                    interpolations: [
                        "client": existingRescue.clientDescription,
                        "system": existingRescue.system.description,
                        "caseId": caseId,
                        "platform": existingRescue.platform.ircRepresentable,
                        "cr": crStatus
                    ]
                )
            )
        }

        var changes: [String] = []
        if rescue.clientNick?.lowercased() != existingRescue.clientNick?.lowercased() {
            changes.append(
                "\(IRCFormat.bold("IRC Nick:")) \(existingRescue.clientNick ?? "?") -> \(rescue.clientNick ?? "?")"
            )
            existingRescue.clientNick = rescue.clientNick
            try? existingRescue.save(nil)
        }

        let platform = rescue.platform
        if platform != existingRescue.platform && platform != nil, platform != .PC {
            let oldPlatform = existingRescue.platform.ircRepresentable
            let newPlatform = rescue.platform.ircRepresentable
            changes.append(
                "\(IRCFormat.bold("Platform:")) \(oldPlatform) -> \(newPlatform)"
            )
        }

        if rescue.expansion != existingRescue.expansion && initiated == .announcer {
            let oldExpansion = existingRescue.expansion.englishDescription
            let newExpansion = rescue.expansion.englishDescription
            changes.append(
                "\(IRCFormat.bold("Expansion:")) \(oldExpansion) -> \(newExpansion)"
            )
        }
        if rescue.system != nil && rescue.system?.name != existingRescue.system?.name {
            changes.append(
                "\(IRCFormat.bold("System:")) \(existingRescue.system.name) -> \(rescue.system.name)"
            )
            if let system = rescue.system, rescue.system?.isConfirmed == false {
                let result = try await SystemsAPI.performSystemCheck(forSystem: system.name)
                guard result.isConfirmed else {
                    return
                }

                existingRescue.system = result
                try? existingRescue.save(nil)

                message.reply(
                    message: lingo.localize(
                        "board.syschange", locale: "en-GB",
                        interpolations: [
                            "caseId": caseId,
                            "client": rescue.client!,
                            "systemInfo": existingRescue.system.description
                        ]))

                checkThargoidSystemState(caseId: caseId, rescue: rescue)
                checkUnobtainablePermitSystem(caseId: caseId, rescue: rescue)

            }
        }
        if rescue.codeRed != existingRescue.codeRed && rescue.codeRed == true {
            changes.append(
                "\(IRCFormat.bold("O2:")) \(existingRescue.ircOxygenStatus) -> \(rescue.ircOxygenStatus)"
            )
            await rescue.prep(message: message, initiated: initiated)
        }
        if changes.count > 0 {
            message.reply(
                message: lingo.localize(
                    "board.signal.changes", locale: "en-GB",
                    interpolations: [
                        "caseId": caseId,
                        "changes": changes.joined(separator: ", ")
                    ]))
        }
    }

    func checkClientFrequentFlier(rescue: Rescue) async throws {
        guard let clientName = rescue.client else {
            return
        }
        let result = try await FuelRatsAPI.getRescues(forClient: clientName)
        let recencyDate = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
        let recentRescues =
            result.body.data?.primary.values.filter({
                $0.attributes.createdAt.value > recencyDate && $0.attributes.outcome.value != .Purge
            }) ?? []
        if recentRescues.count >= 3 {
            let caseId = self.getId(forRescue: rescue) ?? 0
            mecha.reportingChannel?.client.sendMessage(
                toChannelName: "#operations",
                withKey: "board.frequentclient",
                mapping: [
                    "client": clientName,
                    "caseId": caseId,
                    "count": recentRescues.count
                ]
            )
        }
    }

    @discardableResult
    func cancelPrepTimer(forRescue rescue: Rescue) async -> Bool {
        if let prepTimer = self.prepTimers[rescue.id] {
            prepTimer?.cancel()
            self.prepTimers.removeValue(forKey: rescue.id)
            return true
        } else {
            return false
        }
    }

    func performSyncUntilSuccess(reported: Bool = false) async {
        do {
            try await self.sync()
        } catch {
            debug(String(describing: error))
            if reported == false {
                mecha.reportingChannel?.send(key: "board.syncfailed")
            }
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            await performSyncUntilSuccess(reported: true)
        }
    }

    @EventListener<IRCUserJoinedChannelNotification>
    var onJoinChannel = { joinEvent in
        // Check if joining user is a client of a pending announcement
        Task {
            if let (promise, rescue) = await board.getPendingClientJoins()[joinEvent.user.nickname.lowercased()],
                joinEvent.channel == rescue.channel {
                rescue.clientLastHostName = joinEvent.user.hostmask
                promise.succeed(())
                await board.removePendingJoin(key: joinEvent.user.nickname.lowercased())
            }
        }
    }

    @EventListener<RatSocketRescueCreatedNotification>
    var onRemoteRescueCreated = { rescueCreation in
        guard
            configuration.general.drillMode == false,
            rescueCreation.sender.uuidString != configuration.api.userId.uuidString,
            let remoteRescue = rescueCreation.body?.body.data?.primary.value
        else {
            return
        }
        mecha.reportingChannel?.send(
            key: "board.remotecreation",
            map: [
                "caseId": remoteRescue.attributes.commandIdentifier.value,
                "client": remoteRescue.attributes.client.value ?? "?"
            ])
    }

    @AsyncEventListener<RatSocketRescueUpdatedNotification>
    var onRemoteRescueUpdated = { rescueUpdate in
        guard
            configuration.general.drillMode == false,
            rescueUpdate.sender.uuidString != configuration.api.userId.uuidString,
            let remoteRescue = rescueUpdate.body?.body.data?.primary.value
        else {
            return
        }

        if remoteRescue.attributes.status.value == .Closed {
            if let (caseId, rescue) = await board.getRescues().first(where: {
                $0.1.id == remoteRescue.id.rawValue
            }) {
                await board.remove(id: caseId)
                mecha.reportingChannel?.send(
                    key: "board.remoteclose",
                    map: [
                        "caseId": caseId,
                        "client": rescue.clientDescription
                    ])
            }
            return
        }
        mecha.reportingChannel?.send(
            key: "board.remoteupdate",
            map: [
                "caseId": remoteRescue.attributes.commandIdentifier.value,
                "client": remoteRescue.attributes.client.value ?? "?"
            ])
    }

    @AsyncEventListener<RatSocketRescueDeletedNotification>
    var onRemoteRescueDeleted = { rescueDeletion in
        guard
            configuration.general.drillMode == false,
            rescueDeletion.sender.uuidString != configuration.api.userId.uuidString,
            let rescueIdString = rescueDeletion.resourceIdentifier,
            let rescueId = UUID(uuidString: rescueIdString)
        else {
            return
        }

        if let (caseId, rescue) = await board.getRescues().first(where: { $0.1.id == rescueId }) {
            await board.remove(id: caseId)
            mecha.reportingChannel?.send(
                key: "board.remotedeletion",
                map: [
                    "caseId": caseId,
                    "client": rescue.clientDescription
                ])
        }
    }
}

enum RescueInitiationType {
    case announcer
    case signal
    case insertion
}

enum ClientJoinError: Error {
    case joinFailed
}

extension RescueBoard: AsyncSequence {
    typealias Element = (key: Int, value: Rescue)

    nonisolated func makeAsyncIterator() -> AsyncIterator {
        return AsyncIterator(board: self)
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        var board: RescueBoard
        var index = 0
        var iterator: EnumeratedSequence<[Int: Rescue]>.Iterator?

        mutating func next() async -> (key: Int, value: Rescue)? {
            if iterator == nil {
                iterator = await board.rescues.enumerated().makeIterator()
            }
            return iterator!.next()?.element
        }
    }
}

extension AsyncSequence {
    func getAllResults() async throws -> [Element] {
        var results: [Element] = []
        for try await element in self {
            results.append(element)
        }
        return results
    }
}

func performXboxProfileCheck (rescue: Rescue) async -> Bool {
    rescue.xboxProfile = await XboxLive.performLookup(forRescue: rescue)
    if let systemName = rescue.xboxProfile?.systemName,
        systemName.lowercased() != rescue.system.name.lowercased() {
        rescue.system = StarSystem(name: systemName)
        return true
    }
    return false
}

func notifyXboxSystemCorrection (caseId: Int, rescue: Rescue) {
    rescue.channel?.send(key:
        "board.xboxsyschange",
        map: [
            "caseId": caseId,
            "client": rescue.clientDescription
        ]
    )
    
    let xboxCorrected = lingo.localize("board.xboxcorrected", locale: "en")

    rescue.appendQuote(
        RescueQuote(
            author: mecha.rescueChannel?.client.currentNick ?? "Unknown",
            message: xboxCorrected,
            createdAt: Date(),
            updatedAt: Date(),
            lastAuthor: mecha.rescueChannel?.client.currentNick ?? "Unknown"
        )
    )
}

func checkSystemBodyInClientMessage (caseId: Int, rescue: Rescue) {
    if let system = rescue.system, let systemBody = rescue.system?.clientProvidedBody {
        let bodyDescription = system.systemBodyDescription(forBody: systemBody)
        rescue.channel?.send(key:
            "board.systembody",
            map: [
                "bodyDescription": bodyDescription
            ]
        )
        rescue.appendQuote(
            RescueQuote(
                author: mecha.rescueChannel?.client.currentNick ?? "Unknown",
                message: "Client indicated location in system near body \(bodyDescription)",
                createdAt: Date(),
                updatedAt: Date(),
                lastAuthor: mecha.rescueChannel?.client.currentNick ?? "Unknown"
            )
        )
    }
}

func checkThargoidSystemState (caseId: Int, rescue: Rescue) {
    if let system = rescue.system, system.isUnderAttack && rescue.expansion != .legacy {
        rescue.channel?.send(key:
            "board.systemattack",
            map: [
                "system": system.name
            ]
        )
        rescue.appendQuote(
            RescueQuote(
                author: mecha.rescueChannel?.client.currentNick ?? "Unknown",
                message: "CAUTION: \(system.name) is currently under attack by Thargoids",
                createdAt: Date(),
                updatedAt: Date(),
                lastAuthor: mecha.rescueChannel?.client.currentNick ?? "Unknown"
            )
        )
    }
}

func checkUnobtainablePermitSystem (caseId: Int, rescue: Rescue) {
    if let system = rescue.system, system.isUnobtainablePermitSystem {
        rescue.channel?.send(key:
            "board.unobtainablepermit",
            map: [
                "system": system.name
            ]
        )
        rescue.appendQuote(
            RescueQuote(
                author: mecha.rescueChannel?.client.currentNick ?? "Unknown",
                message: "CAUTION: \(system.name) has an unobtainable permit - no player can access this system",
                createdAt: Date(),
                updatedAt: Date(),
                lastAuthor: mecha.rescueChannel?.client.currentNick ?? "Unknown"
            )
        )
    }
}

func checkXboxPrivacy (caseId: Int, rescue: Rescue) {
    if case let .found(xboxProfile) = rescue.xboxProfile {
        if xboxProfile.privacy.isAllowed == false {
            
            rescue.channel?.send(key:
                "board.xboxprivacy",
                map: [
                    "caseId": caseId,
                    "client": rescue.clientDescription
                ]
            )

            rescue.appendQuote(
                RescueQuote(
                    author: mecha.rescueChannel?.client.currentNick ?? "Unknown",
                    message:
                        "WARNING: This client's Xbox Live privacy settings may prevent them from joining a team",
                    createdAt: Date(),
                    updatedAt: Date(),
                    lastAuthor: mecha.rescueChannel?.client.currentNick ?? "Unknown"
                )
            )
        }
    }
}

func checkPSPlusMissing (caseId: Int, rescue: Rescue) {
    if case .found = rescue.psnProfile?.0, rescue.psnProfile?.1 == nil {
        if case let .found(profile) = rescue.psnProfile?.0, profile.plus == 0 {
            rescue.channel?.send(key: "board.psplusmissing", map: [
                "caseId": caseId,
                "client": rescue.clientDescription
            ])
            
            rescue.appendQuote(
                RescueQuote(
                    author: mecha.rescueChannel?.client.currentNick ?? "Unknown",
                    message:
                        "WARNING: This client may be missing a PS Plus subscription",
                    createdAt: Date(),
                    updatedAt: Date(),
                    lastAuthor: mecha.rescueChannel?.client.currentNick ?? "Unknown"
                )
            )
        }
    }
}
