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
import SwiftKuery
import NIO
import SQLKit
import PostgresKit
import IRCKit

let sqlConfiguration = PostgresConfiguration(
    hostname: configuration.database.host,
    username: configuration.database.username,
    password: configuration.database.password,
    database: configuration.database.database
)

let pools = EventLoopGroupConnectionPool(
    source: PostgresConnectionSource(configuration: sqlConfiguration),
    on: loop
)
let sql = pools.database(logger: Logger(label: "SQL")).sql()


struct Fact: Codable, Hashable {
    static let platformFacts = ["wing", "beacon", "fr", "quit", "frcr", "modules", "trouble", "relog"]
    private static var cache = [String: Fact]()
    
    var id: String
    var fact: String
    var createdAt: Date
    var updatedAt: Date
    var language: String
    var message: String
    var author: String
    
    var cacheIdentifier: String {
        return "\(self.fact.lowercased())-\(self.language)"
    }
    
    public static func get (name: String, forLocale locale: Locale) -> EventLoopFuture<Fact?> {
        let factName = name.lowercased()
        let localeString = locale.identifier.prefix(2)
        
        let future = loop.next().makePromise(of: Fact?.self)
        if let cachedFact = cache["\(factName)-\(localeString)"] {
            future.succeed(cachedFact)
        } else {
            sql.select().column("*")
                .from("facts")
                .join("factmessages", method: .inner, on: "facts.id=factmessages.fact and factmessages.language='\(localeString)'")
                .where("alias", .equal, factName)
                .first().whenComplete({ result in
                    switch result {
                        case .failure(let error):
                            future.fail(error)
                            
                        case .success(let row):
                            guard let row = row else {
                                future.succeed(nil)
                                return
                            }
                            
                            let fact = try? row.decode(model: Fact.self)
                            if let cacheFact = fact {
                                cache["\(factName)-\(localeString)"] = cacheFact
                            }
                            future.succeed(fact)
                    }
                })
        }
        
        return future.futureResult
    }

    public static func getWithFallback (name: String, forLcoale locale: Locale) -> EventLoopFuture<Fact?> {
        return Fact.get(name: name, forLocale: locale).flatMap({ (fact) -> EventLoopFuture<Fact?> in
            guard let fact = fact else {
                return Fact.get(name: name, forLocale: Locale(identifier: "en"))
            }

            return loop.next().makeSucceededFuture(fact)
        })
    }
    
    public static var all: EventLoopFuture<[Fact]> {
        let future = loop.next().makePromise(of: [Fact].self)
        sql.select().column("*")
            .from("facts")
            .join("factmessages", method: .inner, on: "facts.id=factmessages.fact")
            .all().whenComplete({ result in
                switch result {
                case .failure(let error):
                    future.fail(error)
                
                case .success(let rows):
                    let facts = rows.compactMap({ try? $0.decode(model: Fact.self) })
                    for fact in facts {
                        cache[fact.cacheIdentifier] = fact
                    }
                    future.succeed(facts)
                }
            })
        return future.futureResult
    }
    
//    public static func create (name: String, message: String, forLocale: Locale = Locale(identifier: "en")) -> EventLoopFuture<Fact> {
//        sql.insertif
//    }
}

struct GroupedFact: Codable {
    let cannonicalName: String
    var messages: [String: Fact]
    var aliases: [String]
    
    var isPlatformFact: Bool {
        return Fact.platformFacts.contains(where: { cannonicalName.hasSuffix($0) })
    }
    
    var platform: GamePlatform? {
        guard self.isPlatformFact else {
            return nil
        }
        
        switch self.cannonicalName {
            case let str where str.starts(with: "pc"):
                return .PC
                
            case let str where str.starts(with: "x"):
                return .Xbox
                
            case let str where str.starts(with: "ps"):
                return .PS
                
            default:
                return nil
        }
    }
    
    var platformLessIdentifier: String? {
        guard let platform = self.platform else {
            return nil
        }
        
        switch platform {
            case .PC, .PS:
                return String(self.cannonicalName.dropFirst(2))
                
            case .Xbox:
                return String(self.cannonicalName.dropFirst(1))
        }
    }
    
    static func get (name: String) -> EventLoopFuture<GroupedFact?> {
        let future = loop.next().makePromise(of: GroupedFact?.self)
        sql.select().column("*")
            .from("facts")
            .join("factmessages", method: .inner, on: "facts.id=factmessages.fact")
            .where("alias", .equal, SQLBind(name))
            .all(decoding: Fact.self)
            .whenComplete({ result in
                switch result {
                    case .failure(let error):
                        future.fail(error)
                        
                    case .success(let facts):
                        future.succeed(facts.grouped.values.first)
                }
            })
        return future.futureResult
    }
}

extension Array where Element == GroupedFact {
    var platformGrouped: [String: [GroupedFact]] {
        return self.reduce([String: [GroupedFact]](), { groups, group in
            var groups = groups
            guard let platformLessIdentifier = group.platformLessIdentifier else {
                return groups
            }
            if groups[platformLessIdentifier] == nil {
                groups[platformLessIdentifier] = []
            }
            groups[platformLessIdentifier]?.append(group)
            return groups
        })
    }
    
    var platformFactDescription: String {
        let platforms = self.compactMap({ $0.platform?.factPrefix })
        let platformPrefix = IRCFormat.color(.Grey, "(\(platforms.joined(separator: "|")))")
        return "\(platformPrefix)\(self.first?.platformLessIdentifier ?? "")"
    }
}

extension Array where Element == Fact {
    var grouped: [String: GroupedFact] {
        self.reduce([String: GroupedFact](), { facts, fact in
            var facts = facts
            if var entry = facts[fact.id] {
                if entry.aliases.contains(fact.fact) == false {
                    entry.aliases.append(fact.fact)
                }
                entry.messages[fact.language] = fact
            } else {
                facts[fact.id] = GroupedFact(
                    cannonicalName: fact.id,
                    messages: [fact.language: fact],
                    aliases: [fact.fact]
                )
            }
            return facts
        })
    }
}
