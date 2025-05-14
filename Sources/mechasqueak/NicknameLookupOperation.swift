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
import IRCKit
import JSONAPI

class NicknameLookupManager {
    let queue = OperationQueue()
    var mapping: [String: NicknameSearchDocument] = [:]

    init() {
        self.queue.maxConcurrentOperationCount = 5
    }

    var lookupServiceAvailable = true {
        didSet {
            self.queue.isSuspended = !self.lookupServiceAvailable
        }
    }

    func lookup(user: IRCUser, completed: ((NicknameSearchDocument) -> Void)? = nil) {
        guard user.account != nil else {
            return
        }

        guard hasExistingFetchOperation(user: user) == false else {
            debug("Ignoring fetch for \(user.nickname) due to existing fetch operation")
            return
        }

        let operation = NicknameLookupOperation(user: user)

        operation.onCompletion = { apiNick in
            if let result = apiNick, let account = user.account {
                self.mapping[account] = result
                if let subscription = result.user?.data.clientTranslateSubscription {
                    Translate.clientTranslationSubscribers[user.nickname] = subscription
                }
                completed?(result)
            }
        }

        operation.onError = { _ in
        }

        self.queue.addOperation(operation)
        debug("Added fetch for \(user.nickname) to queue (\(self.queue.operationCount))")
    }

    func lookupIfNotExists(user: IRCUser, completed: ((NicknameSearchDocument) -> Void)? = nil) {
        guard let account = user.account, self.mapping[account] == nil else {
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
        debug("Starting fetch operation for \(user.nickname)")
        guard isCancelled == false else {
            debug("Fetch operation was cancelled")
            self.isFinished = true
            return
        }

        self.isExecuting = true

        guard let account = user.account else {
            debug("Ignoring fetch for \(user.nickname) as they are not logged in")
            self.isFinished = true
            return
        }

        Task {
            do {
                let apiNickname = try await FuelRatsAPI.getNickname(forIRCAccount: account)
                if apiNickname != nil {
                    debug("Synced account data for \(account)")
                } else {
                    debug("Did not find account data for \(account)")
                }
                self.isFinished = true
                self.isExecuting = false
                self.onCompletion?(apiNickname)
            } catch {
                debug("Failed to lookup account data for \(account)")
                print(String(describing: error))
                self.isFinished = true
                self.isExecuting = false
                self.onError?(error)
            }
        }
    }
}
