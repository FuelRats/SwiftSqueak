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
import SwiftyRequest

class FuelRatsAPI {
    static func getNicknameFor (
        ircAccount: String,
        complete: @escaping (NicknameSearchDocument?) -> Void,
        error: @escaping (RestError) -> Void
    ) throws {

        let request = RestRequest(
            method: .get,
            url: "\(configuration.api.url)/nicknames?nick=\(ircAccount)",
            insecure: false,
            clientCertificate: nil,
            timeout: .init(connect: .seconds(3), read: .seconds(5)),
            eventLoopGroup: nil
        )
        request.credentials = .bearerAuthentication(token: configuration.api.token)

        request.responseData { result in
            switch result {
                case .success(let response):
                    let document = try! NicknameSearchDocument.from(data: response.body)
                    guard (document.body.data?.primary.values.count)! > 0 else {
                        complete(nil)
                        return
                    }

                    complete(document)
                case .failure(let restError):
                    error(restError)
            }
        }
    }

    static func rescueSearch (
        query: [URLQueryItem],
        complete: @escaping (RescueSearchDocument) -> Void,
        error: @escaping (Error) -> Void
    ) {
        let request = RestRequest(
            method: .get,
            url: "\(configuration.api.url)/rescues",
            insecure: false,
            clientCertificate: nil,
            timeout: .init(connect: .seconds(3), read: .seconds(5)),
            eventLoopGroup: nil
        )
        request.credentials = .bearerAuthentication(token: configuration.api.token)

        request.queryItems = query

        request.responseData { result in
            switch result {
                case .success(let response):
                    let document = try! RescueSearchDocument.from(data: response.body)
                    guard document.body.data != nil else {
                        return
                    }
                    complete(document)
                case .failure(let restError):
                    error(restError)
            }
        }
    }

    static func getRescue (
        id: UUID,
        complete: @escaping (RescueGetDocument) -> Void,
        error: @escaping (Error) -> Void
    ) {
        let request = RestRequest(
            method: .get,
            url: "\(configuration.api.url)/rescues/\(id)",
            insecure: false,
            clientCertificate: nil,
            timeout: .init(connect: .seconds(3), read: .seconds(5)),
            eventLoopGroup: nil
        )
        request.credentials = .bearerAuthentication(token: configuration.api.token)

        request.responseData { result in
            switch result {
                case .success(let response):
                    let document = try! RescueGetDocument.from(data: response.body)
                    guard document.body.data != nil else {
                        return
                    }

                    complete(document)
                case .failure(let restError):
                    error(restError)
            }
        }
    }

    static func getOpenRescues (
        complete: @escaping (RescueSearchDocument) -> Void,
        error: @escaping (Error) -> Void
    ) {
        let query = [URLQueryItem(name: "filter", value: [
            "status": ["ne": "closed"]
        ].jsonString)]

        FuelRatsAPI.rescueSearch(query: query, complete: complete, error: error)
    }

    static func getRecentlyClosedRescues (
        count: Int,
        complete: @escaping (RescueSearchDocument) -> Void,
        error: @escaping (Error) -> Void
    ) {
        let query = [
            URLQueryItem(name: "filter", value: [
                "status": ["eq": "closed"]
            ].jsonString),
            URLQueryItem(name: "sort", value: "-createdAt"),
            URLQueryItem(name: "page[limit]", value: String(count))
        ]

        FuelRatsAPI.rescueSearch(query: query, complete: complete, error: error)
    }

    static func getRescuesInTrash (
        complete: @escaping (RescueSearchDocument) -> Void,
        error: @escaping (Error) -> Void
    ) {
        let query = [
            URLQueryItem(name: "filter", value: [
                "status": ["eq": "closed"],
                "outcome": "purge"
            ].jsonString)
        ]

        FuelRatsAPI.rescueSearch(query: query, complete: complete, error: error)
    }

    static func getUnfiledRescues (
        complete: @escaping (RescueSearchDocument) -> Void,
        error: @escaping (Error) -> Void
    ) {
        let query = [
            URLQueryItem(name: "filter", value: [
                "status": ["eq": "closed"],
                "outcome": ["is": nil]
            ].jsonString)
        ]

        FuelRatsAPI.rescueSearch(query: query, complete: complete, error: error)
    }

    static func deleteRescue (id: UUID, complete: @escaping () -> Void, error: @escaping (RestError) -> Void) {
        let request = RestRequest(
            method: .delete,
            url: "\(configuration.api.url)/rescues/\(id)",
            insecure: false,
            clientCertificate: nil,
            timeout: .init(connect: .seconds(3), read: .seconds(5)),
            eventLoopGroup: nil
        )
        request.credentials = .bearerAuthentication(token: configuration.api.token)

        request.responseData { result in
            switch result {
                case .success:
                    complete()
                case .failure(let restError):
                    error(restError)
            }
        }
    }
}

extension Dictionary {
    var jsonString: String? {
        guard let json = try? JSONSerialization.data(withJSONObject: self, options: []) else {
            return nil
        }
        return String(data: json, encoding: .utf8)
    }
}
