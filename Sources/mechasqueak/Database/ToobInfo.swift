//
//  ToobInfo.swift
//  mechasqueak
//
//  Created by Alex Sørlie Glomsaas on 19/07/2022.
//

import Foundation
import SQLKit
import PostgresKit

struct ToobInfo: Codable, Hashable {
    
    var count: Int
    var lastCalomrielBribe: Date
    
    public static func get () async throws -> ToobInfo? {
            return try await withCheckedThrowingContinuation({ continuation in
                sql.select().column("*")
                    .from("toobs")
                    .all().whenComplete({ result in
                        switch result {
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        
                        case .success(let rows):
                            let res = rows.compactMap({ try? $0.decode(model: ToobInfo.self) })
                            continuation.resume(returning: res.first)
                        }
                    })
            })
        }
    
    public static func update (count: Int, lastCalomrielBribe: Date? = nil) async throws {
        if let date = lastCalomrielBribe {
            return try await sql.update("toobs")
                            .set("count", to: count)
                            .set("lastCalomrielBribe", to: date)
                            .run().asContinuation()
        }
        return try await sql.update("toobs")
            .set("count", to: count)
            .run().asContinuation()
    }
    
}
