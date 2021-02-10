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
import SwiftKueryORM
import SwiftKueryPostgreSQL
import NIO

struct Fact: Codable {
    static var dateEncodingFormat: DateEncodingFormat = .timestamp
    var id: Int?

    var name: String
    var language: String
    var message: String
    var author: String
    var createdAt: Date
    var updatedAt: Date

    static var idKeypath: IDKeyPath = \Fact.id
}

struct FactQuery: QueryParams {
    let name: String
    let language: String
}

struct FactListQuery: QueryParams {
    let language: String
}

extension Fact: Model {
    public static func get (name: String, forLocale locale: Locale) -> EventLoopFuture<Fact?> {
        let promise = loop.next().makePromise(of: Fact?.self)

        let query = FactQuery(name: name.lowercased(), language: String(locale.identifier.prefix(2)))
        Fact.findAll(using: Database.default, matching: query, { (facts, error) in
            if let error = error {
                promise.fail(error)
                return
            }

            guard let facts = facts, facts.count > 0 else {
                promise.succeed(nil)
                return
            }

            promise.succeed(facts[0])
        })
        return promise.futureResult
    }

    public static func getWithFallback (name: String, forLcoale locale: Locale) -> EventLoopFuture<Fact?> {
        return Fact.get(name: name, forLocale: locale).flatMap({ (fact) -> EventLoopFuture<Fact?> in
            guard let fact = fact else {
                return Fact.get(name: name, forLocale: Locale(identifier: "en"))
            }

            return loop.next().makeSucceededFuture(fact)
        })
    }

    public static func get (
        name: String,
        forLocale locale: Locale,
        onComplete: @escaping (Fact?) -> Void,
        onError: ((Error) -> Void)? = nil
    ) {
        let query = FactQuery(name: name.lowercased(), language: String(locale.identifier.prefix(2)))
        Fact.findAll(using: Database.default, matching: query, { (facts, error) in
            if let error = error {
                onError?(error)
                return
            }

            guard let facts = facts, facts.count > 0 else {
                onComplete(nil)
                return
            }

            onComplete(facts[0])
        })
    }
}
