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
import NIO
import IRCKit

class RescueBoard {
    var rescues: [LocalRescue] = []
    private var isSynced = true
    var syncTimer: RepeatedTask?
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private let distanceFormatter: NumberFormatter
    var lastSignalReceived: Date?
    var prepTimers: [UUID: Scheduled<()>?] = [:]
    var recentIdentifiers: [Int] = []

    init () {
        self.distanceFormatter = NumberFormatter()
        self.distanceFormatter.numberStyle = .decimal
        self.distanceFormatter.groupingSize = 3
        self.distanceFormatter.maximumFractionDigits = 1
        self.distanceFormatter.roundingMode = .halfUp

        FuelRatsAPI.getLastRescue(complete: { result in
            guard let rescues = result.body.primaryResource, rescues.values.count > 0 else {
                return
            }

            let createdAt = rescues.values[0].attributes.createdAt.value
            if self.lastSignalReceived == nil || createdAt > self.lastSignalReceived! {
                print(createdAt)
                self.lastSignalReceived = createdAt
            }
        }, error: { error in
            print(error)
        })
    }

    var synced: Bool {
        get {
            return self.isSynced
        }

        set {
            if newValue == false {
                guard self.isSynced == true && self.syncTimer == nil else {
                    return
                }
                mecha.accounts.lookupServiceAvailable = false

                if let channel = mecha.reportingChannel {
                    channel.send(key: "board.syncfailed")
                }

                self.syncTimer = group.next().scheduleRepeatedTask(
                    initialDelay: .seconds(30),
                    delay: .seconds(30), { _ in
                    self.syncBoard()
                })
                self.isSynced = false

            } else {
                guard self.isSynced == false else {
                    return
                }

                mecha.accounts.lookupServiceAvailable = true
                self.isSynced = true
                if let timer = self.syncTimer {
                    timer.cancel()
                }
                self.syncTimer = nil
            }
        }
    }

    func findRescue (withCaseIdentifier caseIdentifier: String) -> LocalRescue? {
        var caseIdentifier = caseIdentifier
        if caseIdentifier.starts(with: "#") {
            caseIdentifier = String(caseIdentifier.suffix(
                from: caseIdentifier.index(caseIdentifier.startIndex, offsetBy: 1)
            ))
        }

        if let caseIdNumber = Int(caseIdentifier) {
            return self.rescues.first(where: {
                $0.commandIdentifier == caseIdNumber
            })
        }

        return self.rescues.first(where: {
            $0.client?.lowercased() == caseIdentifier.lowercased()
                || $0.clientNick?.lowercased() == caseIdentifier.lowercased()
        })
    }

    func add (
        rescue: LocalRescue,
        fromMessage message: IRCPrivateMessage,
        initiated: RescueInitiationType
    ) {
        if let existingRescue = self.rescues.first(where: {
            $0.client?.lowercased() == rescue.client?.lowercased() || ($0.clientNick != nil && $0.clientNick?.lowercased() == rescue.clientNick?.lowercased())
        }) {

            let crStatus = existingRescue.codeRed ? "(\(IRCFormat.color(.LightRed, "CR")))" : ""
            if initiated == .signal {
                message.reply(message: lingo.localize("board.signal.helpyou", locale: "en", interpolations: [
                    "client": rescue.clientNick ?? rescue.client ?? ""
                ]))
            } else {
                message.reply(message: lingo.localize("board.signal.exists", locale: "en", interpolations: [
                    "client": existingRescue.client!,
                    "system": existingRescue.system!,
                    "caseId": existingRescue.commandIdentifier!,
                    "platform": existingRescue.platform.ircRepresentable,
                    "cr": crStatus
                ]))
            }

            var changes: [String] = []
            if rescue.platform != existingRescue.platform {
                changes.append("\(IRCFormat.bold("Platform:")) \(existingRescue.platform.ircRepresentable) -> \(rescue.platform.ircRepresentable)")
            }
            if rescue.system != existingRescue.system {
                changes.append("\(IRCFormat.bold("System:")) \(existingRescue.system ?? "u\u{200B}nknown") -> \(rescue.system ?? "u\u{200B}nknown")")
            }
            if rescue.codeRed != existingRescue.codeRed {
                changes.append("\(IRCFormat.bold("O2:")) \(existingRescue.ircOxygenStatus) -> \(rescue.ircOxygenStatus)")
            }
            if changes.count > 0 {
                message.reply(message: lingo.localize("board.signal.changes", locale: "en-GB", interpolations: [
                    "caseId": existingRescue.commandIdentifier!,
                    "changes": changes.joined(separator: ", ")
                ]))
            }

            return
        }

        let crStatus = rescue.codeRed ? "(\(IRCFormat.color(.LightRed, "CR")))" : ""
        let identifier = self.getNewIdentifier()
        rescue.commandIdentifier = identifier
        self.recentIdentifiers.removeAll(where: { $0 == identifier })
        self.recentIdentifiers.append(identifier)
        self.lastSignalReceived = Date()

        if rescue.codeRed == false && configuration.general.drillMode == false {
            prepTimers[rescue.id] = group.next().scheduleTask(in: .seconds(180), {
                if rescue.codeRed == false || rescue.status == .Inactive {
                    message.reply(message: lingo.localize("board.notprepped", locale: "en-GB", interpolations: [
                        "caseId": rescue.commandIdentifier!
                    ]))
                }
            })
        }

        self.rescues.append(rescue)
        rescue.createUpstream(fromBoard: self)

        let caseId = String(rescue.commandIdentifier!)

        let announceType = initiated == .announcer ? "announce" : "signal"

        let language = (rescue.clientLanguage ?? Locale(identifier: "en")).englishDescription
        let languageCode = (rescue.clientLanguage ?? Locale(identifier: "en")).identifier

        guard let system = rescue.system else {
            message.reply(message: lingo.localize("board.\(announceType).nosystem", locale: "en", interpolations: [
                "signal": configuration.general.signal.uppercased(),
                "client": rescue.client ?? "u\u{200B}nknown",
                "platform": rescue.platform?.ircRepresentable ?? "u\u{200B}nknown",
                "oxygen": rescue.ircOxygenStatus,
                "caseId": caseId,
                "platformSignal": rescue.platform?.signal ?? "",
                "cr": crStatus,
                "language": language,
                "langCode": languageCode
            ]))
            return
        }

        SystemsAPI.performCaseLookup(
            forSystem: system,
            inRescue: rescue,
            onComplete: { searchResult, landmarkResult, correction in
            guard let searchResult = searchResult, let landmarkResult = landmarkResult else {
                message.reply(message: lingo.localize("board.\(announceType).notindb", locale: "en", interpolations: [
                    "signal": configuration.general.signal.uppercased(),
                    "client": rescue.client ?? "u\u{200B}nknown",
                    "platform": rescue.platform?.ircRepresentable ?? "u\u{200B}nknown",
                    "oxygen": rescue.ircOxygenStatus,
                    "caseId": caseId,
                    "system": rescue.system ?? "none",
                    "platformSignal": rescue.platform?.signal ?? "",
                    "cr": crStatus,
                    "language": language,
                    "langCode": languageCode
                ]))

                if let correction = correction {
                    message.reply(message: lingo.localize("autocorrect.correction", locale: "en-GB", interpolations: [
                        "system": system,
                        "correction": correction
                    ]))
                }

                self.prepClient(rescue: rescue, message: message, initiated: initiated)
                return
            }

            let distance = self.distanceFormatter.string(from: NSNumber(value: landmarkResult.distance))!

            let format = searchResult.permitRequired ? "board.\(announceType).permit" : "board.\(announceType).landmark"

            message.reply(message: lingo.localize(format, locale: "en", interpolations: [
                "signal": configuration.general.signal.uppercased(),
                "client": rescue.client ?? "u\u{200B}nknown",
                "platform": rescue.platform.ircRepresentable,
                "oxygen": rescue.ircOxygenStatus,
                "caseId": caseId,
                "system": rescue.system ?? "none",
                "distance": distance,
                "landmark": landmarkResult.name,
                "permit": searchResult.permitText ?? "",
                "platformSignal": rescue.platform?.signal ?? "",
                "cr": crStatus,
                "language": language,
                "langCode": languageCode
            ]))

            self.prepClient(rescue: rescue, message: message, initiated: initiated)
        })
    }

    func prepClient (rescue: LocalRescue, message: IRCPrivateMessage, initiated: RescueInitiationType) {
        if initiated == .signal && rescue.codeRed == false {
            message.reply(message: lingo.localize("board.signal.oxygen", locale: "en-GB", interpolations: [
                "client": rescue.clientNick ?? rescue.client ?? ""
            ]))
        } else if initiated != .insertion && rescue.codeRed == true {
            let factKey = rescue.platform != nil ? rescue.platform!.quitFact : "prepcr"
            let locale = rescue.clientLanguage ?? Locale(identifier: "en")

            Fact.get(name: factKey, forLocale: locale).flatMap({ (fact) -> EventLoopFuture<Fact?> in
                guard let fact = fact else {
                    return Fact.get(name: factKey, forLocale: rescue.clientLanguage ?? Locale(identifier: "en"))
                }

                return loop.next().makeSucceededFuture(fact)
            }).flatMap { (fact) -> EventLoopFuture<Fact?> in
                if let fact = fact {
                    return loop.next().makeSucceededFuture(fact)
                } else if rescue.clientLanguage != nil && rescue.platform != nil {
                    // If platform specific quit is not available in this language, try !prepcr in this language
                    return Fact.get(name: "prepcr", forLocale: rescue.clientLanguage!)
                } else {
                    return loop.next().makeSucceededFuture(nil)
                }
            }.flatMap { (fact) -> EventLoopFuture<Fact?> in
                if let fact = fact {
                    return loop.next().makeSucceededFuture(fact)
                } else if rescue.clientLanguage != nil && rescue.platform != nil {
                    // If neiher quit or prepcr is available in this language, fall back to English.
                    return Fact.get(name: factKey, forLocale: Locale(identifier: "en"))
                } else {
                    return loop.next().makeSucceededFuture(nil)
                }
            }.whenSuccess { fact in
                guard fact != nil else {
                    return
                }

                let client = rescue.clientNick ?? rescue.client ?? ""
                message.reply(message: "\(client) \(fact!.message)")
            }
        }
    }

    func syncBoard () {
        FuelRatsAPI.getOpenRescues(complete: { rescueDocument in
            self.merge(rescueDocument: rescueDocument)
        }, error: { error in
            debug(String(describing: error))
            self.synced = false
        })
    }

    func getNewIdentifier () -> Int {
        /* Get the first 10 identifiers not currently being used by a case, this method lets us generally stay between
         0 and 15 re-using a recent number if we need to without the case ID becoming something ridicolous like #32 */
        let fetchCount = self.rescues.count > 9 ? 1 : 10 - self.rescues.count
        let generatedIdentifiers = generateAvailableIdentifiers(count: fetchCount)

        // Create a map of identifiers to the identifier's index in the the recently used list
        let identifierMap = generatedIdentifiers.reduce(
            [:], { (identifiers: [Int: Int], identifier: Int) -> [Int: Int] in
                var identifiers = identifiers
                var index = 0

                if let firstIndex = recentIdentifiers.firstIndex(of: identifier) {
                    index = recentIdentifiers.distance(from: recentIdentifiers.startIndex, to: firstIndex) + 1
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

        // Return the best scoring identifier
        return sortedIdentifiers[0]
    }

    func generateAvailableIdentifiers (count: Int) -> [Int] {
        var identifiers = [Int]()
        var currentIdentifier = 0
        while identifiers.count < count {
            if (rescues.first(where: { $0.commandIdentifier == currentIdentifier }) == nil) {
                identifiers.append(currentIdentifier)
            }
            currentIdentifier += 1
        }

        return identifiers
    }

    var firstAvailableIdentifier: Int {
        var identifier = 0
        while (rescues.first(where: { $0.commandIdentifier == identifier }) != nil) {
            identifier += 1
        }

        return identifier
    }

    func checkSynced () {
        self.synced = self.rescues.contains(where: {
            $0.synced == false
        }) == false
    }

    func merge (rescueDocument: RescueSearchDocument) {
        let apiRescues = rescueDocument.convertToLocalRescues(onBoard: self)

        var pendingUpstreamUpdate: [LocalRescue] = []
        var pendingDownstream: [LocalRescue] = []

        let pendingUpstreamNew = self.rescues.filter({ localRescue in
            return apiRescues.contains(where: { apiRescue in
                apiRescue.id == localRescue.id
            }) == false
        })

        let novelRescues = apiRescues.filter({ apiRescue in
            return self.rescues.contains(where: { localRescue in
                localRescue.id == apiRescue.id
            }) == false
        })

        pendingDownstream.append(contentsOf: novelRescues)

//        let updatedDownstreamRescues = apiRescues.filter({ apiRescue in
//            let matchingLocal = self.rescues.first(where: { localRescue in
//                localRescue.id == apiRescue.id
//            })
//
//            return matchingLocal != nil && matchingLocal!.updatedAt < apiRescue.updatedAt
//        })
//
//        pendingDownstream.append(contentsOf: updatedDownstreamRescues)

        var requiredIdChange = 0

        for novelRescue in pendingDownstream {
            if novelRescue.hasConflictingId(inBoard: self) {
                novelRescue.commandIdentifier = self.getNewIdentifier()
                requiredIdChange += 1
                pendingUpstreamUpdate.append(novelRescue)
            }

            self.rescues.removeAll(where: {
                $0.id == novelRescue.id
            })

            if self.lastSignalReceived == nil || novelRescue.createdAt > self.lastSignalReceived! {
                self.lastSignalReceived = novelRescue.createdAt
            }

            if let identifier = novelRescue.commandIdentifier {
                self.recentIdentifiers.removeAll(where: { $0 == identifier })
                self.recentIdentifiers.append(identifier)
            }

            self.rescues.append(novelRescue)
        }

        for rescue in pendingUpstreamNew {
            rescue.createUpstream(fromBoard: self)
        }

        for rescue in pendingUpstreamUpdate {
            rescue.syncUpstream(fromBoard: self)
        }

        if let rescueChannel = mecha.reportingChannel {
            rescueChannel.send(key: "board.synced", map: [
                "api": configuration.api.url,
                "downstreamNew": novelRescues.count,
                "downstreamChange": 0,
                "upstreamNew": pendingUpstreamNew.count,
                "upstreamChange": pendingUpstreamUpdate.count,
                "conflicts": requiredIdChange
            ])
        }

        if pendingUpstreamUpdate.count == 0 {
            self.synced = true
        }
    }
}

enum RescueInitiationType {
    case announcer
    case signal
    case insertion
}
