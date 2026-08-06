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
import Logging

class RescueCreateOperation: Operation, @unchecked Sendable {
    private static let baseBackoffSeconds: UInt64 = 2
    private static let maxBackoffSeconds: UInt64 = 300
    private static let maxPermanentAttempts = 5

    let caseId: Int
    let rescue: Rescue
    let representing: IRCUser?
    var attempt = 0

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
        await board.markOutgoingUpdate(rescueId: rescue.id)
        return try await withCheckedThrowingContinuation { continuation in
            let postDocument = SingleDocument(
                apiDescription: .none,
                body: .init(resourceObject: rescue.toApiRescue(withIdentifier: caseId)),
                includes: .none,
                meta: .none,
                links: .none
            )

            var url = URLComponents(string: "\(configuration.api.url)/rescues")!
            url.queryItems = [URLQueryItem(name: "include", value: "rats,firstLimpet,lastEditUser")]
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
                                if let body = response.body,
                                   let doc = try? RescueGetDocument.from(data: Data(buffer: body)),
                                   let remoteRescue = doc.body.data?.primary.value {
                                    self.rescue.updatedAt = remoteRescue.attributes.updatedAt.value
                                }
                                continuation.resume(returning: ())
                            } else {
                                self.rescue.synced = false
                                continuation.resume(throwing: response)
                            }

                            self.isFinished = true
                            self.isExecuting = false
                        case .failure(let error):
                            continuation.resume(throwing: error)
                            logger.error("\(error)")
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
            if await board.clearSyncErrorReported(rescueId: rescue.id) {
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
            // Alert once per degraded period (tracked on the board so a fresh operation
            // per change doesn't re-spam the channel).
            if await board.markSyncErrorReported(rescueId: rescue.id) {
                logger.error("Create error on case #\(caseId): \(error)")
                mecha.reportingChannel?.send(
                    key: "board.sync.error",
                    map: [
                        "caseId": caseId
                    ])
            }

            attempt += 1

            // A 4xx (other than request-timeout/rate-limit) is a client error that blind
            // retries won't fix — give up after a few attempts instead of hammering the
            // server and channel forever.
            if let response = error as? HTTPClient.Response {
                let code = Int(response.status.code)
                let isPermanent = (400...499).contains(code) && code != 408 && code != 429
                if isPermanent && attempt >= Self.maxPermanentAttempts {
                    logger.error(
                        "Giving up on case #\(caseId) after \(attempt) attempts on a permanent error (\(code))")
                    mecha.reportingChannel?.send(
                        key: "board.sync.givingup",
                        map: [
                            "caseId": caseId
                        ])
                    throw error
                }
            }

            // Exponential backoff, capped, instead of a fixed 30s retry.
            let backoffSeconds = min(
                Self.baseBackoffSeconds << min(attempt - 1, 8), Self.maxBackoffSeconds)
            try? await Task.sleep(nanoseconds: backoffSeconds * 1_000_000_000)
            try await performUploadUntilSuccess()
        }
    }

    override func start() {
        logger.debug("Starting create operation for \(rescue.id)")
        guard isCancelled == false else {
            logger.debug("Create operation was cancelled")
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
