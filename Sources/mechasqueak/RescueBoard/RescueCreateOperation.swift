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
import AsyncHTTPClient

class RescueCreateOperation: Operation {
    let rescue: LocalRescue
    let representing: IRCUser?

    var onCompletion: (() -> Void)?
    var onError: ((Error) -> Void)?
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

    init (rescue: LocalRescue, representing: IRCUser? = nil) {
        self.rescue = rescue
        self.representing = representing
        super.init()
    }

    override func start () {
        debug("Starting update operation for \(rescue.id)")
        guard isCancelled == false else {
            debug("Update operation was cancelled")
            self.isFinished = true
            return
        }
        if configuration.general.drillMode {
            self.isFinished = true
            self.onCompletion?()
            return
        }

        self.isExecuting = true

        let postDocument = SingleDocument(
            apiDescription: .none,
            body: .init(resourceObject: rescue.toApiRescue),
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
        do {
            try HTTPClient.Body.encodable(postDocument)
        } catch {
            debug(String(describing: error))
        }

        httpClient.execute(request: request).whenComplete{ result in
            switch result {
                case .success(let response):
                    if response.status == .created || response.status == .conflict {
                        self.rescue.synced = true
                        self.onCompletion?()
                    } else {
                        self.rescue.synced = false
                        mecha.rescueBoard.synced = false
                        self.onError?(response)
                        self.onError?(response)
                        debug(String(response.status.code))
                    }

                    self.isFinished = true
                    self.isExecuting = false
                case .failure(let error):
                    debug(String(describing: error))
                    self.rescue.synced = false
                    mecha.rescueBoard.synced = false
                    self.onError?(error)
                    self.isFinished = true
                    self.isExecuting = false
            }
        }
    }
}
