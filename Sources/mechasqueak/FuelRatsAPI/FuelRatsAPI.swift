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
import NIOHTTP1

class FuelRatsAPI {
    static internal var deadline: NIODeadline {
        return .now() + .seconds(30)
    }
    
    static func getNickname (forIRCAccount account: String) async throws -> NicknameSearchDocument? {
        let request = try! HTTPClient.Request(apiPath: "/nicknames", method: .GET, query: ["nick": account])
        
        let response = try await httpClient.execute(request: request, deadline: .now() + .seconds(5), expecting: 200)
        do {
            let document = try NicknameSearchDocument.from(data: Data(buffer: response.body!))
            
            guard (document.body.data?.primary.values.count)! > 0 else {
                debug("No results found in fetch for \(account)")
                return nil
            }
            
            return document
        } catch {
            debug(String(describing: error))
            throw error
        }
    }
    
    static func rescueSearch (query: [String: String?]) async throws -> RescueSearchDocument {
        let request = try! HTTPClient.Request(apiPath: "/rescues", method: .GET, query: query)
        
        let response = try await httpClient.execute(request: request, deadline: FuelRatsAPI.deadline, expecting: 200)
        print(String(data: Data(buffer: response.body!), encoding: .utf8)!)
        let document = try! RescueSearchDocument.from(data: Data(buffer: response.body!))
        
        return document
    }
    
    static func getRescue (id: UUID) async throws -> RescueGetDocument? {
        let request = try! HTTPClient.Request(apiPath: "/rescues/\(id)", method: .GET)
        
        let response = try await httpClient.execute(request: request, deadline: FuelRatsAPI.deadline, expecting: 200)
        return try? RescueGetDocument.from(data: Data(buffer: response.body!))
    }
    
    static func getOpenRescues () async throws -> RescueSearchDocument {
        return try await FuelRatsAPI.rescueSearch(query: ["filter": [
            "status": ["ne": "closed"]
        ].jsonString])
    }
    
    static func getLastRescues () async throws -> RescueSearchDocument {
        return try await FuelRatsAPI.rescueSearch(query: ["page[limit]": "200", "sort": "-createdAt"])
    }
    
    static func getRecentlyClosedRescues (count: Int) async throws -> RescueSearchDocument {
        let query = [
            "filter": [
                "status": ["eq": "closed"]
            ].jsonString,
            "sort": "-createdAt",
            "page[limit]": String(count)
        ]
        
        return try await FuelRatsAPI.rescueSearch(query: query)
    }
    
    static func getRescues (forClient client: String) async throws -> RescueSearchDocument {
        let query = [
            "filter": [
                "client": ["ilike": client]
            ].jsonString,
            "sort": "-createdAt"
        ]
        
        return try await FuelRatsAPI.rescueSearch(query: query)
    }
    
    static func getRescuesInTrash () async throws -> RescueSearchDocument {
        let query = [
            "filter": [
                "status": ["eq": "closed"],
                "outcome": "purge"
            ].jsonString
        ]

        return try await FuelRatsAPI.rescueSearch(query: query)
    }
    
    static func getUnfiledRescues () async throws -> RescueSearchDocument {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let twoHoursAgo = Calendar.current.date(byAdding: .hour, value: -2, to: Date())!

        let query = [
            "filter": [
                "status": ["eq": "closed"],
                "outcome": ["is": nil],
                "createdAt": [
                    "gte": DateFormatter.iso8601Full.string(from: thirtyDaysAgo),
                    "lt": DateFormatter.iso8601Full.string(from: twoHoursAgo)
                ]
            ].jsonString
        ]

        return try await FuelRatsAPI.rescueSearch(query: query)
    }
    
    static func deleteRescue (id: UUID) async throws -> Void {
        let request = try! HTTPClient.Request(apiPath: "/rescues/\(id)", method: .DELETE)
        
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
