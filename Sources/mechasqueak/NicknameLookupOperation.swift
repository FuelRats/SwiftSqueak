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
@preconcurrency import IRCKit
@preconcurrency import JSONAPI
import Logging

class NicknameLookupManager {
    let queue = OperationQueue()
    // Written by lookup completions on the operation queue and read by every permission check.
    private let mapping = Locked([String: NicknameSearchDocument]())

    func apiData(forAccount account: String) -> NicknameSearchDocument? {
        return self.mapping.withValue({ $0[account] })
    }

    func setAPIData(_ data: NicknameSearchDocument?, forAccount account: String) {
        self.mapping.withValue({ $0[account] = data })
    }

    func removeAllAPIData() {
        self.mapping.withValue({ $0.removeAll() })
    }

    init() {
        self.queue.maxConcurrentOperationCount = 5
    }

    var lookupServiceAvailable = true {
        didSet {
            self.queue.isSuspended = !self.lookupServiceAvailable
        }
    }

    func lookup(user: IRCUser, completed: ((NicknameSearchDocument) -> Void)? = nil) {
        guard let account = user.account else {
            return
        }

        guard hasExistingFetchOperation(user: user) == false else {
            logger.debug("Ignoring fetch for \(user.nickname) due to existing fetch operation")
            return
        }

        let operation = NicknameLookupOperation(user: user)

        // Stored under the account that was looked up, not whatever account the user holds when the lookup ends.
        operation.onCompletion = { apiNick in
            guard let result = apiNick else {
                // The API no longer has this account, so permissions cached from an earlier lookup must go.
                // A failed lookup (onError) keeps them, so an API outage doesn't lock every rat out.
                self.setAPIData(nil, forAccount: account)
                return
            }
            self.setAPIData(result, forAccount: account)
            if let subscription = result.user?.data.clientTranslateSubscription {
                Translate.setTranslationSubscription(subscription, forNick: user.nickname)
            }
            completed?(result)
        }

        operation.onError = { _ in
        }

        self.queue.addOperation(operation)
        logger.debug("Added fetch for \(user.nickname) to queue (\(self.queue.operationCount))")
    }

    func lookupIfNotExists(user: IRCUser, completed: ((NicknameSearchDocument) -> Void)? = nil) {
        guard let account = user.account, self.apiData(forAccount: account) == nil else {
            return
        }

        lookup(user: user)
    }

    func hasExistingFetchOperation(user: IRCUser) -> Bool {
        return self.queue.operations.contains(where: {
            $0.name == user.account
        })
    }

    @EventListener<RatSocketUserUpdatedNotification>
    var onRemoteUserUpdate = { userUpdateEvent in
        guard let userId = UUID(uuidString: userUpdateEvent.resourceIdentifier ?? "") else {
            return
        }

        let users = mecha.reportingChannel?.members ?? []
        for user in users.filter({ $0.associatedAPIData?.user?.id.rawValue == userId }) {
            MechaSqueak.accounts.lookup(user: user)
        }

        // A user update also fires when one of the user's rats is deleted. Proactively drop
        // any now-missing rats from that user's active rescues so the board self-heals
        // without waiting for a save to fail with a 422.
        Task {
            let affected =
                (try? await board.filter({ (_, rescue) in
                    rescue.rats.contains(where: {
                        $0.relationships.user?.id?.rawValue == userId
                    })
                }).getAllResults()) ?? []

            for (caseId, rescue) in affected {
                let removed = await rescue.pruneDeletedRats()
                guard removed.isEmpty == false else {
                    continue
                }
                let ratNames = removed.map({ $0.attributes.name.value }).joined(separator: ", ")
                logger.warning(
                    "Removed \(removed.count) deleted rat(s) from case #\(caseId): \(ratNames)")
                try? await rescue.saveAndWait(nil)
                mecha.reportingChannel?.send(
                    key: "board.sync.removedDeletedRat",
                    map: [
                        "caseId": caseId,
                        "rats": ratNames
                    ])
            }
        }
    }

    @EventListener<IRCChannelUserModeChangeNotification>
    var onUserModeChange = { userModeChange in
        guard userModeChange.channel == mecha.rescueChannel else {
            return
        }
        MechaSqueak.accounts.lookup(user: userModeChange.target)
    }
}

class NicknameLookupOperation: Operation, @unchecked Sendable {
    let user: IRCUser
    var onCompletion: ((NicknameSearchDocument?) -> Void)?
    var onError: ((Error?) -> Void)?
    private var _executing: Bool = false
    private var _finished: Bool = false

    override var isAsynchronous: Bool {
        return true
    }

    override var isExecuting: Bool {
        get {
            return _executing
        }
        set {
            willChangeValue(forKey: "isExecuting")
            _executing = newValue
            didChangeValue(forKey: "isExecuting")
        }
    }

    override var isFinished: Bool {
        get {
            return _finished
        }
        set {
            willChangeValue(forKey: "isFinished")
            _finished = newValue
            didChangeValue(forKey: "isFinished")
        }
    }

    init(user: IRCUser) {
        self.user = user
        super.init()
        self.name = user.account
    }

    override func start() {
        logger.debug("Starting fetch operation for \(user.nickname)")
        guard isCancelled == false else {
            logger.debug("Fetch operation was cancelled")
            self.isFinished = true
            return
        }

        self.isExecuting = true

        guard let account = user.account else {
            logger.debug("Ignoring fetch for \(user.nickname) as they are not logged in")
            self.isFinished = true
            return
        }

        Task {
            do {
                let apiNickname = try await FuelRatsAPI.getNickname(forIRCAccount: account)
                if apiNickname != nil {
                    logger.debug("Synced account data for \(account)")
                } else {
                    logger.debug("Did not find account data for \(account)")
                }
                self.isFinished = true
                self.isExecuting = false
                self.onCompletion?(apiNickname)
            } catch {
                logger.error("Failed to lookup account data for \(account)")
                logger.error("\(error)")
                self.isFinished = true
                self.isExecuting = false
                self.onError?(error)
            }
        }
    }
}
