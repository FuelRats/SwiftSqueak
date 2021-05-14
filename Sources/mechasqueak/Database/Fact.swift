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
    static let platformFacts = ["wing", "beacon", "fr", "quit", "frcr", "modules", "trouble", "relog", "restart", "team"]
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
        let localeString = locale.short
        
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
    
    public static func create (name: String, author: String, message: String, forLocale locale: Locale = Locale(identifier: "en")) -> EventLoopFuture<Fact> {
        let createDate = Date()
        let localeString = locale.short
        
        return pools.withConnection({ conn -> EventLoopFuture<Fact> in
            let sql = conn.sql()
            let queries = conn.simpleQuery("BEGIN").flatMap({ _ in
                return sql.insert(into: "facts")
                    .columns("id", "alias", "createdAt", "updatedAt")
                    .values(SQLBind(name), SQLBind(name), SQLBind(createDate), SQLBind(createDate))
                    .run()
            }).flatMap({
                return sql.insert(into: "factmessages")
                    .columns("fact", "language", "message", "author", "createdAt", "updatedAt")
                    .values(SQLBind(name), SQLBind(localeString), SQLBind(message), SQLBind(author), SQLBind(createDate), SQLBind(createDate))
                    .run()
            }).flatMap({
                return conn.simpleQuery("COMMIT")
            }).map({ _ in
                return Fact(
                    id: name,
                    fact: name,
                    createdAt: createDate,
                    updatedAt: createDate,
                    language: localeString,
                    message: message,
                    author: author
                )
            })
            
            queries.whenFailure({ _ in
                _ = conn.simpleQuery("ROLLBACK")
            })
            
            return queries
        })
        
    }
    
    public static func create (alias: String, forName name: String) -> EventLoopFuture<Void> {
        let createDate = Date()
        return sql.insert(into: "facts")
            .columns("id", "alias", "createdAt", "updatedAt")
            .values(SQLBind(name), SQLBind(alias), SQLBind(createDate), SQLBind(createDate))
            .run()
    }
    
    public static func create (message: String, forName name: String, inLocale locale: Locale, withAuthor author: String) -> EventLoopFuture<Void> {
        let createDate = Date()
        let localeString = locale.short
        
        return sql.insert(into: "factmessages")
            .columns("fact", "language", "message", "author", "createdAt", "updatedAt")
            .values(SQLBind(name), SQLBind(localeString), SQLBind(message), SQLBind(author), SQLBind(createDate), SQLBind(createDate))
            .run()
    }
    
    public static func update (locale: Locale, forFact fact: String, withMessage message: String, fromAuthor author: String) -> EventLoopFuture<Void> {
        let updateDate = Date()
        cache.removeValue(forKey: "\(fact)-\(locale.short)")
        return sql.update("factmessages")
            .set("message", to: message)
            .set("author", to: author)
            .set("updatedAt", to: updateDate)
            .where("fact", .equal, SQLBind(fact))
            .where("locale", .equal, SQLBind(locale.short))
            .run()
    }
    
    public static func delete (locale: Locale, forFact fact: String) -> EventLoopFuture<Void> {
        cache.removeValue(forKey: "\(fact)-\(locale.short)")
        return sql.delete(from: "factmessages")
            .where("fact", .equal, SQLBind(fact))
            .where("language", .equal, SQLBind(locale.short))
            .run()
    }
    
    public static func drop (name: String) -> EventLoopFuture<Void> {
        for item in cache.filter({ $0.key.starts(with: "\(name)-") }) {
            cache.removeValue(forKey: item.key)
        }
        return sql.delete(from: "facts")
            .where("id", .equal, SQLBind(name))
            .run()
    }
    
    public static func delete (alias: String) -> EventLoopFuture<Void> {
        for item in cache.filter({ $0.key.starts(with: "\(alias)-") }) {
            cache.removeValue(forKey: item.key)
        }
        return sql.delete(from: "facts")
            .where("alias", .equal, SQLBind(alias))
            .run()
    }
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
        sql.select().columns([
                SQLColumn("id", table: "aliases"),
                SQLAlias(SQLColumn("alias", table: "aliases"), as: SQLIdentifier("fact")),
                SQLColumn("createdAt", table: "factmessages"),
                SQLColumn("updatedAt", table: "factmessages"),
                SQLColumn("language", table: "factmessages"),
                SQLColumn("author", table: "factmessages"),
                SQLColumn("message", table: "factmessages")
            ])
            .from("facts")
            .join(
                SQLAlias(SQLIdentifier("facts"), as: SQLIdentifier("aliases")),
                method: SQLJoinMethod.left,
                on: SQLColumn("id", table: "facts"), .equal, SQLColumn("id", table: "aliases")
            )
            .join("factmessages", method: .left, on: "facts.id=factmessages.fact")
            .where(SQLColumn("alias", table: "facts"), .equal, SQLBind(name))
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
        return self.reduce([String: GroupedFact](), { facts, fact in
            var facts = facts
            if var entry = facts[fact.id] {
                if entry.aliases.contains(fact.fact) == false {
                    entry.aliases.append(fact.fact)
                }
                entry.messages[fact.language] = fact
                facts[fact.id] = entry
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
