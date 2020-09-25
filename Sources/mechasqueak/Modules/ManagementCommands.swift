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
import IRCKit

class ManagementCommands: IRCBotModule {
    var name: String = "ManagementCommands"

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @BotCommand(
        ["flushnames", "clearnames", "flushall", "invalidateall"],
        parameters: 0...0,
        category: .management,
        description: "Invalidate the bots cache of API user data and fetch it again for all users.",
        permission: .UserWrite
    )
    var didReceiveFlushAllCommand = { command in
        mecha.accounts.queue.cancelAllOperations()
        mecha.accounts.mapping.removeAll()

        let signedInUsers = mecha.connections.flatMap({
            return $0.channels.flatMap({
                return $0.members.filter({
                    $0.account != nil
                })
            })
        })

        for user in signedInUsers {
            mecha.accounts.lookupIfNotExists(user: user)
        }

        command.message.replyPrivate(key: "flushall.response", fromCommand: command)
    }

    @BotCommand(
        ["flush", "clearname", "invalidate"],
        parameters: 1...1,
        category: .management,
        description: "Invalidate a single name in the cache and fetch it again.",
        permission: .UserWrite
    )
    var didReceiveFlushCommand = { command in
        guard let mapping = mecha.accounts.mapping.first(where: {
            $0.key.lowercased() == command.parameters[0].lowercased()
        }) else {
            command.message.replyPrivate(key: "flush.notfound", fromCommand: command, map: [
                "name": command.parameters[0]
            ])
            return
        }

        mecha.accounts.mapping.removeValue(forKey: mapping.key)
        guard let user = command.message.client.channels.first(where: {
            $0.member(named: command.parameters[0]) != nil
        })?.member(named: command.parameters[0]) else {
            command.message.replyPrivate(key: "flush.nouser", fromCommand: command, map: [
                "name": command.parameters[0]
            ])
            return
        }
        mecha.accounts.lookupIfNotExists(user: user)
        command.message.replyPrivate(key: "flush.response", fromCommand: command, map: [
            "name": command.parameters[0]
        ])
    }
}
