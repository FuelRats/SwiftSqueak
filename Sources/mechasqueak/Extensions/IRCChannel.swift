//
//  IRCChannel.swift
//  mechasqueak
//
//  Created by Alex Sørlie Glomsaas on 2020-05-27.
//

import Foundation
import IRCKit

extension IRCChannel {
    func send (key: String, map: [String: Any] = [:]) {
        self.send(message: lingo.localize(key, locale: "en-GB", interpolations: map))
    }
}
