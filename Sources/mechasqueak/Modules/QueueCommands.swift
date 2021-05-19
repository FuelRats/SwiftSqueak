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
    static var maxClientsCount: Int = 15
    var name: String = "QueueCommands"

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
        QueueAPI.getConfig().whenSuccess({
            QueueCommands.maxClientsCount = $0.maxActiveClients
        })
    }
    
    @BotCommand(
        ["queue"],
        category: .queue,
        description: "Get current information on the queue",
        permission: .DispatchRead,
        allowedDestinations: .Channel,
        cooldown: .seconds(90)
    )
    var didReceiveQueueCommand = { command in
        QueueAPI.fetchQueue().whenSuccess({ queue in
            let queueItems = queue.filter({ $0.inProgress == false && $0.pending == false })
            guard queueItems.count > 0 else {
                command.message.reply(key: "queue.none", fromCommand: command)
                return
            }
            
            let queueCount = queueItems.count
            let waitTimes = queueItems.map({ Date().timeIntervalSince($0.arrivalTime) }).sorted()
            let longestWait = waitTimes.last!
            let averageWait = waitTimes.reduce(0.0, { $0 + $1 }) / Double(waitTimes.count)
            
            command.message.reply(key: "queue.info", fromCommand: command, map: [
                "count": queueCount,
                "longest": longestWait.timeSpan,
                "average": averageWait.timeSpan
            ])
        })
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
        QueueAPI.dequeue().whenComplete({ result in
            switch result {
            case .failure(_):
                command.message.error(key: "dequeue.error", fromCommand: command)
                
            case .success(_):
                command.message.reply(key: "dequeue.success", fromCommand: command)
            }
        })
    }
    
    @BotCommand(
        ["maxclients", "maxload", "maxcases"],
        [.param("number of clients", "10", .standard, .optional)],
        category: .queue,
        description: "See how many rescues are allowed at once before clients get put into a queue, provide a number as an argument to change the value",
        permission: .DispatchWrite,
        allowedDestinations: .Channel,
        cooldown: .seconds(60)
    )
    var didReceiveMaxClientsCommand = { command in
        if let queueSizeString = command.param1 {
            guard let queueSize = Int(queueSizeString), (5...20).contains(queueSize) else {
                command.message.error(key: "maxclients.invalid", fromCommand: command)
                return
            }
            
            QueueAPI.setMaxActiveClients(queueSize).whenSuccess({ _ in
                QueueCommands.maxClientsCount = queueSize
                command.message.reply(key: "maxclients.set", fromCommand: command, map: [
                    "count": queueSize
                ])
            })
        } else {
            QueueAPI.getConfig().whenSuccess({ config in
                QueueCommands.maxClientsCount = config.maxActiveClients
                command.message.reply(key: "maxclients.get", fromCommand: command, map: [
                    "count": config.maxActiveClients
                ])
            })
        }
    }
}
