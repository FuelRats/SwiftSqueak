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
import IRCKit
import NIO

class QueueCommands: IRCBotModule {
    var name: String = "QueueCommands"

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }
    
    @BotCommand(
        ["dequeue"],
        category: .queue,
        description: "Manually move the next client from the queue into the rescue channel",
        permission: .DispatchWrite,
        allowedDestinations: .Channel,
        cooldown: .seconds(5)
    )
    var didReceiveDeQueueCommand = { command in
        // TODO: Dequeue logic 
    }
    
    @BotCommand(
        ["maxqueue", "maxclients", "maxload"],
        [.param("number of clients", "10", .standard, .optional)],
        category: .queue,
        description: "See how many rescues are allowed at once before clients get put into a queue, provide a number as an argument to change the value",
        permission: .DispatchWrite,
        allowedDestinations: .Channel
    )
    var didReceiveMaxClientsCommand = { command in
        if let queueSizeString = command.param1 {
            guard let queueSize = Int(queueSizeString) else {
                command.message.error(key: "maxclients.invalid", fromCommand: command)
                return
            }
            
            guard (5...25).contains(queueSize) else {
                command.message.error(key: "maxclients.range", fromCommand: command)
                return
            }
            
            // TODO: Set queue size
        }
        
        // TODO: Get queue size
    }
}
