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

struct Bulletin: Codable {
    static var dateEncodingFormat: DateEncodingFormat = .timestamp
    var id: Int?

    var message: String
    var author: String
    var createdAt: Date
    var updatedAt: Date

    static var idKeypath: IDKeyPath = \Bulletin.id
}

struct BulletinQuery: QueryParams {
    let id: Int
}

extension Bulletin: Model {
    public static func get (id: Int) -> EventLoopFuture<Bulletin?> {
        let promise = loop.next().makePromise(of: Bulletin?.self)

        let query = BulletinQuery(id: id)
        Bulletin.findAll(using: Database.default, matching: query, { (bulletins, error) in
            if let error = error {
                promise.fail(error)
                return
            }

            guard let bulletins = bulletins, bulletins.count > 0 else {
                promise.succeed(nil)
                return
            }

            promise.succeed(bulletins[0])
        })
        return promise.futureResult
    }
}
