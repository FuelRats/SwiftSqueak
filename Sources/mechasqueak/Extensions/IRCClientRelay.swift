/*
 Copyright 2026 The Fuel Rats Mischief

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

import IRCKit

/// MSGAS and CNOTICE are delivered by the server under a different source and command than the line MechaSqueak
/// sends, so their text is split for the line clients receive rather than by `sendMessage`.
extension IRCClient {
    /// Length of the longest `nick!user@host` source (30 + 1 + 10 + 1 + 63), used when the real source is unknown.
    static let worstCaseSourceLength = 105

    /**
     Splits `text` into lines for a relay command such as MSGAS or CNOTICE.

     - Parameter command: The command MechaSqueak sends, `MSGAS` or `CNOTICE`
     - Parameter nick: The nickname parameter of that command
     - Parameter channel: The channel the server delivers the line to
     - Parameter source: The `nick!user@host` source clients will see on the delivered line, nil when unknown
     - Parameter relayedCommand: The command clients will see, `PRIVMSG` or `NOTICE`
     - Parameter linePrefix: Text repeated at the start of every line, such as the client's nickname
     - Returns: Lines that fit both the line MechaSqueak sends and the line the server delivers
     */
    static func relayLines(
        _ text: String,
        command: String,
        nick: String,
        channel: String,
        source: String?,
        relayedCommand: String,
        linePrefix: String = ""
    ) -> [String] {
        let deliveredBudget = IRCClient.messageByteBudget(
            source: source ?? String(repeating: "x", count: worstCaseSourceLength),
            command: relayedCommand, target: channel)
        let sentBudget = IRCClient.messageByteBudget(source: "", command: command, target: "\(nick) \(channel)")
        let budget = min(deliveredBudget, sentBudget) - linePrefix.utf8.count
        return IRCClient.splitMessage(text, maxBytes: budget).map({ linePrefix + $0 })
    }

    /// The full `nick!user@host` of `sender`, or nil when the server did not provide the user and host.
    static func fullSource(of sender: IRCSender?) -> String? {
        guard let sender, sender.username != nil, sender.hostmask != nil else {
            return nil
        }
        return sender.description
    }

    /// Sends `contents` to `channel` as `nick` with MSGAS, one line per chunk.
    func sendMessage(
        as nick: String, source: IRCSender?, toChannel channel: String, contents: String, linePrefix: String = ""
    ) {
        let lines = IRCClient.relayLines(
            contents, command: "MSGAS", nick: nick, channel: channel, source: IRCClient.fullSource(of: source),
            relayedCommand: "PRIVMSG", linePrefix: linePrefix)
        for line in lines {
            self.send("MSGAS", parameters: [nick, channel, line])
        }
    }

    /// Sends `contents` to `nick` as a notice in the context of `channel` with CNOTICE, one line per chunk.
    func sendChannelNotice(
        to nick: String, inChannel channel: String, contents: String, linePrefix: String = "",
        tags: [String: String?] = [:]
    ) {
        let lines = IRCClient.relayLines(
            contents, command: "CNOTICE", nick: nick, channel: channel,
            source: IRCClient.fullSource(of: self.currentSender), relayedCommand: "NOTICE", linePrefix: linePrefix)
        for line in lines {
            self.send("CNOTICE", parameters: [nick, channel, line], tags: tags)
        }
    }
}
