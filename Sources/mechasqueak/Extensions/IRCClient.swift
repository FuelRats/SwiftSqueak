//
//  IRCClient.swift
//  mechasqueak
//
//  Created by Alex Sørlie Glomsaas on 2020-05-27.
//

import Foundation
import IRCKit

extension IRCClient {
    func sendMessage (toChannelName channelName: String, withKey key: String, mapping map: [String: Any]? = [:]) {
        self.sendMessage(
            toChannelName: channelName,
            contents: lingo.localize(key, locale: "en-GB", interpolations: map)
        )
    }
}
