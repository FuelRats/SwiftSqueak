//
//  NOP.swift
//  mechasqueak
//
//  Created by Alex Sørlie Glomsaas on 2021-01-26.
//

import Foundation
import NIO

extension EventLoopFuture {
    func and<SecondValue, ThirdValue>(_ future2: EventLoopFuture<SecondValue>, _ future3: EventLoopFuture<ThirdValue>) -> EventLoopFuture<(Value, SecondValue, ThirdValue)> {
        let combinedFuture = self.eventLoop.next().makePromise(of: (Value, SecondValue, ThirdValue).self)
        self.and(future2).and(future3).whenComplete({ result in
            switch result {
                case .success(let value):
                    combinedFuture.succeed((value.0.0, value.0.1, value.1))

                case .failure(let error):
                    combinedFuture.fail(error)
            }
        })

        return combinedFuture.futureResult
    }
}
