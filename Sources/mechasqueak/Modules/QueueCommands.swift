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
        
        Task {
            guard let queueConfig = try? await QueueAPI.getConfig() else {
                return
            }
            
            QueueCommands.maxClientsCount = queueConfig.maxActiveClients
        }
    }
    
    @AsyncBotCommand(
        ["queue"],
        category: .queue,
        description: "Get current information on the queue",
        permission: .DispatchRead,
        cooldown: .seconds(90)
    )
    var didReceiveQueueCommand = { command in
        guard let queue = try? await QueueAPI.fetchQueue() else {
            return
        }
        
        let queueItems = queue.filter({ $0.inProgress == false && $0.pending == false })
        guard queueItems.count > 0 else {
            command.message.reply(key: "queue.none", fromCommand: command)
            return
        }
        
        let queueCount = queueItems.count
        
        command.message.reply(key: "queue.info", fromCommand: command, map: [
            "count": queueCount
        ])
    }
    
    @AsyncBotCommand(
        ["queuestats"],
        [.param("start date", "2021-04-01", .standard, .optional)],
        category: .queue,
        description: "Get statistics from the queueing system",
        permission: .DispatchRead,
        cooldown: .seconds(90)
    )
    var didReceiveQueueStatsCommand = { command in
        var date = Date()
        if command.parameters.count > 0 {
            let formatter = DateFormatter()
            formatter.dateFormat = "YYYY-MM-dd"

            if let userSuppliedDate = formatter.date(from: command.parameters[0]) {
                date = userSuppliedDate
            } else {
                command.message.error(key: "queuestats.date", fromCommand: command)
            }
        }
        guard let stats = try? await QueueAPI.fetchStatistics(fromDate: date) else {
            return
        }
        command.message.reply(key: "queuestats.stats", fromCommand: command, map: [
            "totalClients": stats.totalClients ?? 0,
            "instantJoin": stats.instantJoin ?? 0,
            "queuedJoin": stats.queuedJoin ?? 0,
            "averageQueuetime": stats.averageQueuetimeSpan,
            "averageRescuetime": stats.averageRescuetimeSpan,
            "longestQueuetime": stats.longestQueuetimeSpan,
            "lostQueues": stats.lostQueues ?? 0,
            "successfulQueues": stats.successfulQueues ?? 0,
        ])
    }
    
    @AsyncBotCommand(
        ["dequeue", "next"],
        category: .queue,
        description: "Manually move the next client from the queue into the rescue channel",
        permission: .DispatchWrite,
        allowedDestinations: .Channel,
        cooldown: .seconds(5)
    )
    var didReceiveDeQueueCommand = { command in
        do {
            try await QueueAPI.dequeue()
            command.message.reply(key: "dequeue.success", fromCommand: command)
        } catch {
            command.message.error(key: "dequeue.error", fromCommand: command)
        }
    }
    
    @AsyncBotCommand(
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
            
            do {
                try await QueueAPI.setMaxActiveClients(queueSize)
                QueueCommands.maxClientsCount = queueSize
                command.message.reply(key: "maxclients.set", fromCommand: command, map: [
                    "count": queueSize
                ])
            } catch {
                command.error(error)
            }
        } else {
            do {
                let config = try await QueueAPI.getConfig()
                QueueCommands.maxClientsCount = config.maxActiveClients
                command.message.reply(key: "maxclients.get", fromCommand: command, map: [
                    "count": config.maxActiveClients
                ])
            } catch {
                command.error(error)
            }
        }
    }
}
