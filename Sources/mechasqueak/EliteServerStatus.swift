//
//  File.swift
//  
//
//  Created by Alex Sørlie Glomsaas on 16/11/2021.
//

import Foundation
import AsyncHTTPClient

struct EliteServerStatus: Codable {
    let text: String
    let status: Int
    
    static func fetch () async throws -> EliteServerStatus {
        var request = try! HTTPClient.Request(url: "http://hosting.zaonce.net/launcher-status/status.json", method: .GET)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Content-Type", value: "application/json")

        return try await httpClient.execute(request: request, forDecodable: EliteServerStatus.self)
    }
}
