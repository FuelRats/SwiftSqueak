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
import IRCKit
import JSONAPI
import AsyncHTTPClient

class RescueUpdateOperation: Operation {
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
    
    init (rescue: Rescue, withCaseId caseId: Int, representing: IRCUser? = nil) {
        self.caseId = caseId
        self.rescue = rescue
        self.representing = representing
        super.init()
    }
    
    func attemptUpload () async throws -> RemoteRescue {
        return try await withCheckedThrowingContinuation { continuation in
            let patchDocument = SingleDocument(
                apiDescription: .none,
                body: .init(resourceObject: rescue.toApiRescue(withIdentifier: caseId)),
                includes: .none,
                meta: .none,
                links: .none
            )
            
            let url = URLComponents(string: "\(configuration.api.url)/rescues/\(rescue.id.uuidString.lowercased())")!
            
            do {
                var request = try HTTPClient.Request(url: url.url!, method: .PATCH)
                request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
                request.headers.add(name: "Authorization", value: "Bearer \(configuration.api.token)")
                request.headers.add(name: "Content-Type", value: "application/vnd.api+json")
                if let user = self.representing?.associatedAPIData?.user {
                    //request.headers.add(name: "x-representing", value: user.id.rawValue.uuidString)
                }
                
                request.body = try? .encodable(patchDocument)
                
                httpClient.execute(request: request).whenComplete { result in
                    switch result {
                    case .success(let response):
                        if response.status == .ok {
                            self.rescue.synced = true
                            
                            do {
                                let rescue = try RescueGetDocument.from(data: Data(buffer: response.body!))
                                continuation.resume(returning: rescue.body.data!.primary.value)
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        } else {
                            self.rescue.synced = false
                            
                            continuation.resume(throwing: response)
                            debug(String(response.status.code))
                            debug(String(data: Data(buffer: response.body!), encoding: .utf8)!)
                        }
                        
                    case .failure(let error):
                        debug(String(describing: error))
                        self.rescue.synced = false
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func performUploadUntilSuccess () async throws -> RemoteRescue {
        guard isCancelled == false else {
            self.isFinished = true
            throw CancellationError()
        }
        let previousSyncState = self.rescue.synced
        do {
            let rescue = try await attemptUpload()
            if errorReported && previousSyncState == false {
                mecha.reportingChannel?.send(key: "board.sync.errorsolved", map: [
                    "caseId": caseId
                ])
            }
            let allSuccess = await board.rescues.allSatisfy({ $0.value.synced && $0.value.uploaded })
            if allSuccess {
                await board.setIsSynced(true)
            }
            return rescue
        } catch {
            if errorReported == false && previousSyncState == true {
                mecha.reportingChannel?.send(key: "board.sync.error", map: [
                    "caseId": caseId
                ])
                errorReported = true
            }
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            return try await performUploadUntilSuccess()
        }
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
        
        Task {
            do {
                let updatedRescue = try await performUploadUntilSuccess()
                
                rescue.updatedAt = updatedRescue.updatedAt
                self.rescue.synced = true
                self.onCompletion?()
            } catch {
                self.onError?(error)
            }
        }
    }
}
