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

import AsyncHTTPClient
import Foundation
import IRCKit
import JSONAPI

class RescueCreateOperation: Operation, @unchecked Sendable {
    let caseId: Int
    let rescue: Rescue
    let representing: IRCUser?
    var errorReported = false

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

    init(rescue: Rescue, withCaseId caseId: Int, representing: IRCUser? = nil) {
        self.caseId = caseId
        self.rescue = rescue
        self.representing = representing
        super.init()
    }

    private func attemptUpload() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let postDocument = SingleDocument(
                apiDescription: .none,
                body: .init(resourceObject: rescue.toApiRescue(withIdentifier: caseId)),
                includes: .none,
                meta: .none,
                links: .none
            )

            let url = URLComponents(string: "\(configuration.api.url)/rescues")!
            do {
                var request = try HTTPClient.Request(url: url.url!, method: .POST)
                request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
                request.headers.add(
                    name: "Authorization", value: "Bearer \(configuration.api.token)")
                request.headers.add(name: "Content-Type", value: "application/vnd.api+json")
                if let user = self.representing?.associatedAPIData?.user {
                    request.headers.add(name: "x-representing", value: user.id.rawValue.uuidString)
                }

                request.body = try? .encodable(postDocument)

                httpClient.execute(request: request).whenComplete { result in
                    switch result {
                        case .success(let response):
                            if response.status == .created || response.status == .conflict {
                                self.rescue.synced = true
                                continuation.resume(returning: ())
                            } else {
                                self.rescue.synced = false
                                continuation.resume(throwing: response)
                            }

                            self.isFinished = true
                            self.isExecuting = false
                        case .failure(let error):
                            continuation.resume(throwing: error)
                            debug(String(describing: error))
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func performUploadUntilSuccess() async throws {
        guard isCancelled == false else {
            self.isFinished = true
            throw CancellationError()
        }
        do {
            try await attemptUpload()
            if errorReported {
                mecha.reportingChannel?.send(
                    key: "board.sync.errorsolved",
                    map: [
                        "caseId": caseId
                    ])
            }
            let allSuccess = await board.getRescues().allSatisfy({ $0.value.synced && $0.value.uploaded })
            if allSuccess {
                await board.setIsSynced(true)
            }
        } catch {
            if errorReported == false {
                mecha.reportingChannel?.send(
                    key: "board.sync.error",
                    map: [
                        "caseId": caseId
                    ])
                errorReported = true
            }
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            try await performUploadUntilSuccess()
        }
    }

    override func start() {
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

        Task {
            do {
                try await performUploadUntilSuccess()
                self.rescue.synced = true
                self.rescue.uploaded = true
                self.onCompletion?()
            } catch {
                self.rescue.synced = false
                self.onError?(error)
                self.isFinished = true
                self.isExecuting = false
            }
        }
    }
}
