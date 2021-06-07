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
import NIO

class FuelRatsAPI {
    static internal var deadline: NIODeadline {
        return .now() + .seconds(30)
    }

    @available(*, deprecated, message: "Use getNickname(forIRCAccount account) async instead")
    static func getNicknameFor (
        ircAccount: String,
        complete: @escaping (NicknameSearchDocument?) -> Void,
        error: @escaping (Error?) -> Void
    ) throws {
        var url = URLComponents(string: "\(configuration.api.url)/nicknames")!
        url.queryItems = [URLQueryItem(name: "nick", value: ircAccount)]

        var request = try! HTTPClient.Request(url: url.url!, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.api.token)")

        httpClient.execute(request: request, deadline: FuelRatsAPI.deadline).whenCompleteExpecting(status: 200) { result in
            switch result {
                case .success(let response):
                    guard let document = try? NicknameSearchDocument.from(data: Data(buffer: response.body!)) else {
                        error(nil)
                        return
                    }
                    guard (document.body.data?.primary.values.count)! > 0 else {
                        debug("No results found in fetch for \(ircAccount)")
                        complete(nil)
                        return
                    }

                    complete(document)
                case .failure(let restError):
                    error(restError)
            }
        }
    }
    
    static func getNickname (forIRCAccount account: String) async throws -> NicknameSearchDocument? {
        var url = URLComponents(string: "\(configuration.api.url)/nicknames")!
        url.queryItems = [URLQueryItem(name: "nick", value: account)]

        var request = try! HTTPClient.Request(url: url.url!, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.api.token)")
        
        let response = try await httpClient.execute(request: request, deadline: FuelRatsAPI.deadline, expecting: 200)
        guard let document = try? NicknameSearchDocument.from(data: Data(buffer: response.body!)) else {
            throw response
        }
        
        guard (document.body.data?.primary.values.count)! > 0 else {
            debug("No results found in fetch for \(account)")
            return nil
        }
        
        return document
    }

    @available(*, deprecated, message: "Use rescueSearch(query) async instead")
    static func rescueSearch (
        query: [URLQueryItem],
        complete: @escaping (RescueSearchDocument) -> Void,
        error: ((Error?) -> Void)?
    ) {
        var url = URLComponents(string: "\(configuration.api.url)/rescues")!
        url.queryItems = query
        var request = try! HTTPClient.Request(url: url.url!, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.api.token)")

        httpClient.execute(request: request, deadline: FuelRatsAPI.deadline).whenCompleteExpecting(status: 200) { result in
            switch result {
                case .success(let response):
                    guard
                        let document = try? RescueSearchDocument.from(data: Data(buffer: response.body!)),
                        document.body.data != nil
                    else {
                        error?(nil)
                        return
                    }

                    complete(document)
                case .failure(let restError):
                    error?(restError)
            }
        }
    }
    
    static func rescueSearch (query: [URLQueryItem]) async throws -> RescueSearchDocument {
        var url = URLComponents(string: "\(configuration.api.url)/rescues")!
        url.queryItems = query
        var request = try! HTTPClient.Request(url: url.url!, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.api.token)")
        
        let response = try await httpClient.execute(request: request, deadline: FuelRatsAPI.deadline, expecting: 200)
        guard
            let document = try? RescueSearchDocument.from(data: Data(buffer: response.body!)),
            document.body.data != nil
        else {
            throw response
        }
        
        return document
    }

    @available(*, deprecated, message: "Use getRescue(id) async instead")
    static func getRescue (
        id: UUID,
        complete: @escaping (RescueGetDocument) -> Void,
        error: @escaping (Error?) -> Void
    ) {
        let url = URLComponents(string: "\(configuration.api.url)/rescues/\(id)")!
        var request = try! HTTPClient.Request(url: url.url!, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.api.token)")

        httpClient.execute(request: request, deadline: FuelRatsAPI.deadline).whenCompleteExpecting(status: 200) { result in
            switch result {
                case .success(let response):
                    guard
                        let document = try? RescueGetDocument.from(data: Data(buffer: response.body!)),
                        document.body.data != nil
                    else {
                        error(nil)
                        return
                    }

                    complete(document)
                case .failure(let restError):
                    error(restError)
            }
        }
    }
    
    static func getRescue (id: UUID) async throws -> RescueGetDocument? {
        let url = URLComponents(string: "\(configuration.api.url)/rescues/\(id)")!
        var request = try! HTTPClient.Request(url: url.url!, method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.api.token)")
        
        let response = try await httpClient.execute(request: request, deadline: FuelRatsAPI.deadline, expecting: 200)
        return try? RescueGetDocument.from(data: Data(buffer: response.body!))
    }

    @available(*, deprecated, message: "Use getOpenRescues() async instead")
    static func getOpenRescues (
        complete: @escaping (RescueSearchDocument) -> Void,
        error: @escaping (Error?) -> Void
    ) {
        let query = [URLQueryItem(name: "filter", value: [
            "status": ["ne": "closed"]
        ].jsonString)]

        FuelRatsAPI.rescueSearch(query: query, complete: complete, error: error)
    }
    
    static func getOpenRescues () async throws -> RescueSearchDocument {
        let query = [URLQueryItem(name: "filter", value: [
            "status": ["ne": "closed"]
        ].jsonString)]
        
        return try await FuelRatsAPI.rescueSearch(query: query)
    }

    @available(*, deprecated, message: "Use getLastRescue() async instead")
    static func getLastRescue (
        complete: @escaping (RescueSearchDocument) -> Void,
        error: @escaping (Error?) -> Void
    ) {
        let query = [
            URLQueryItem(name: "page[limit]", value: "1"),
            URLQueryItem(name: "sort", value: "-createdAt")
        ]

        FuelRatsAPI.rescueSearch(query: query, complete: complete, error: error)
    }
    
    static func getLastRescue () async throws -> RescueSearchDocument {
        let query = [
            URLQueryItem(name: "page[limit]", value: "1"),
            URLQueryItem(name: "sort", value: "-createdAt")
        ]
        
        return try await FuelRatsAPI.rescueSearch(query: query)
    }
    
    @available(*, deprecated, message: "Use getRecentlyClosedRescues(count) async instead")
    static func getRecentlyClosedRescues (
        count: Int,
        complete: @escaping (RescueSearchDocument) -> Void,
        error: @escaping (Error?) -> Void
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
    
    static func getRecentlyClosedRescues (count: Int) async throws -> RescueSearchDocument {
        let query = [
            URLQueryItem(name: "filter", value: [
                "status": ["eq": "closed"]
            ].jsonString),
            URLQueryItem(name: "sort", value: "-createdAt"),
            URLQueryItem(name: "page[limit]", value: String(count))
        ]
        
        return try await FuelRatsAPI.rescueSearch(query: query)
    }

    @available(*, deprecated, message: "Use getRescues(forClient client) async instead")
    static func getRescuesForClient (
        client: String,
        complete: @escaping (RescueSearchDocument) -> Void,
        error: ((Error?) -> Void)? = nil
    ) {
        let query = [
            URLQueryItem(name: "filter", value: [
                "client": ["ilike": client]
            ].jsonString),
            URLQueryItem(name: "sort", value: "-createdAt"),
        ]

        FuelRatsAPI.rescueSearch(query: query, complete: complete, error: error)
    }
    
    static func getRescues (forClient client: String) async throws -> RescueSearchDocument {
        let query = [
            URLQueryItem(name: "filter", value: [
                "client": ["ilike": client]
            ].jsonString),
            URLQueryItem(name: "sort", value: "-createdAt"),
        ]
        
        return try await FuelRatsAPI.rescueSearch(query: query)
    }

    @available(*, deprecated, message: "Use getRescuesInTrash() async instead")
    static func getRescuesInTrash (
        complete: @escaping (RescueSearchDocument) -> Void,
        error: @escaping (Error?) -> Void
    ) {
        let query = [
            URLQueryItem(name: "filter", value: [
                "status": ["eq": "closed"],
                "outcome": "purge"
            ].jsonString)
        ]

        FuelRatsAPI.rescueSearch(query: query, complete: complete, error: error)
    }
    
    static func getRescuesInTrash () async throws -> RescueSearchDocument {
        let query = [
            URLQueryItem(name: "filter", value: [
                "status": ["eq": "closed"],
                "outcome": "purge"
            ].jsonString)
        ]

        return try await FuelRatsAPI.rescueSearch(query: query)
    }

    @available(*, deprecated, message: "Use getUnfiledRescues) async instead")
    static func getUnfiledRescues (
        complete: @escaping (RescueSearchDocument) -> Void,
        error: @escaping (Error?) -> Void
    ) {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let twoHoursAgo = Calendar.current.date(byAdding: .hour, value: -2, to: Date())!

        let query = [
            URLQueryItem(name: "filter", value: [
                "status": ["eq": "closed"],
                "outcome": ["is": nil],
                "createdAt": [
                    "gte": DateFormatter.iso8601Full.string(from: thirtyDaysAgo),
                    "lt": DateFormatter.iso8601Full.string(from: twoHoursAgo)
                ]
            ].jsonString)
        ]

        FuelRatsAPI.rescueSearch(query: query, complete: complete, error: error)
    }
    
    static func getUnfiledRescues () async throws -> RescueSearchDocument {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let twoHoursAgo = Calendar.current.date(byAdding: .hour, value: -2, to: Date())!

        let query = [
            URLQueryItem(name: "filter", value: [
                "status": ["eq": "closed"],
                "outcome": ["is": nil],
                "createdAt": [
                    "gte": DateFormatter.iso8601Full.string(from: thirtyDaysAgo),
                    "lt": DateFormatter.iso8601Full.string(from: twoHoursAgo)
                ]
            ].jsonString)
        ]

        return try await FuelRatsAPI.rescueSearch(query: query)
    }

    @available(*, deprecated, message: "Use deleteRescue(id) async instead")
    static func deleteRescue (id: UUID, complete: @escaping () -> Void, error: @escaping (Error?) -> Void) {
        let url = URLComponents(string: "\(configuration.api.url)/rescues/\(id)")!
        var request = try! HTTPClient.Request(url: url.url!, method: .DELETE)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.api.token)")

        httpClient.execute(request: request, deadline: FuelRatsAPI.deadline).whenCompleteExpecting(status: 204) { result in
            switch result {
                case .success:
                    complete()
                case .failure(let restError):
                    error(restError)
            }
        }
    }
    
    static func deleteRescue (id: UUID) async throws -> Void {
        let url = URLComponents(string: "\(configuration.api.url)/rescues/\(id)")!
        var request = try! HTTPClient.Request(url: url.url!, method: .DELETE)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.api.token)")
        
       _ = try await httpClient.execute(request: request, deadline: FuelRatsAPI.deadline, expecting: 204)
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
