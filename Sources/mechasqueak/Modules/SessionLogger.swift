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

class SessionLogger: IRCBotModule {
    var name: String = "Session Logger"
    
    static var sessions: [String: LoggingSession] = [:]

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }
    
    @BotCommand(
        ["startlogs"],
        category: .utility,
        description: "Start a new logging session in this channel",
        permission: .AnnouncementWrite,
        allowedDestinations: .Channel
    )
    var didReceiveStartLoggingCommand = { command in
        guard configuration.general.drillChannels.contains(command.message.destination.name.lowercased()) else {
            return
        }
        
        sessions[command.message.destination.name] = LoggingSession(message: command.message, include: false)
        command.message.reply(key: "savelogs.started", fromCommand: command)
    }
    
    @AsyncBotCommand(
        ["savelogs", "stoplogs"],
        category: .utility,
        description: "Save logs from a drill or training session, use after the session has completed",
        permission: .AnnouncementWrite,
        allowedDestinations: .Channel
    )
    var didReceiveSaveLogsCommand = { command in
        guard let session = sessions[command.message.destination.name], session.messages.count > 2 else {
            command.message.error(key: "savelogs.notfound", fromCommand: command)
            return
        }
        
        do {
            let result = try await Rodentbin.upload(contents: session.logs)
            
            sessions.removeValue(forKey: command.message.destination.name)
            command.message.reply(key: "savelogs.saved", fromCommand: command, map: [
                "url": "https://paste.fuelrats.com/\(result.key).md"
            ])
        } catch {
            command.error(error)
        }
    }

    @EventListener<IRCChannelMessageNotification>
    var onChannelMessage = { channelMessage in
        guard channelMessage.raw.messageTags["batch"] == nil, configuration.general.drillChannels.contains(channelMessage.destination.name.lowercased()) else {
            // Do not interpret commands from playback of old messages
            return
        }

        addSessionMessage(channelMessage)
    }
    
    @EventListener<IRCChannelActionMessageNotification>
    var onChannelAction = { channelMessage in
        guard channelMessage.raw.messageTags["batch"] == nil, configuration.general.drillChannels.contains(channelMessage.destination.name.lowercased()) else {
            // Do not interpret commands from playback of old messages
            return
        }

        addSessionMessage(channelMessage)
    }
    
    @EventListener<IRCEchoMessageNotification>
    var onEchoMessage = { echoMessage in
        guard echoMessage.raw.messageTags["batch"] == nil, configuration.general.drillChannels.contains(echoMessage.destination.name.lowercased()) else {
            // Do not interpret commands from playback of old messages
            return
        }
        
        addSessionMessage(echoMessage)
    }
    
    static func addSessionMessage (_ message: IRCPrivateMessage) {
        if let session = sessions[message.destination.name] {
            if message.message.lowercased().starts(with: "!savelogs") || message.message.lowercased().starts(with: "!startlogs") || message.raw.time.timeIntervalSince(session.initiated) < 0.5 {
                return
            }
            if let time = session.messages.last?.raw.time, Date().timeIntervalSince(time) > 1200 {
                sessions[message.destination.name] = LoggingSession(message: message)
            } else {
                session.messages.append(message)
            }
        } else {
            sessions[message.destination.name] = LoggingSession(message: message)
        }
    }
}

class LoggingSession {
    let channel: IRCChannel
    let initiated: Date
    var messages: [IRCPrivateMessage]
    
    init (message: IRCPrivateMessage, include: Bool = true) {
        self.channel = message.destination
        self.initiated = Date()
        if include {
            self.messages = [message]
        } else {
            self.messages = []
        }
    }
    
    var logs: String {
        return self.messages.reduce("", { logs, line in
            return logs + line.ircLogMessage + "\n"
        })
    }
}


extension IRCPrivateMessage {
    var ircLogMessage: String {
        let messageContents = self.message.strippingIRCFormatting
        let userMode = self.user.highestUserMode != nil ? String(self.user.highestUserMode!.toPrefix(onClient: self.client) ?? "") : ""
        
        let timestampFormatter = DateFormatter()
        timestampFormatter.timeZone = TimeZone(abbreviation: "UTC")
        timestampFormatter.dateFormat = "HH:mm:ss 'UTC'"
        
        let time = timestampFormatter.string(from: self.raw.time)
        
        if self.raw.isActionMessage {
            return "[\(time)] * \(userMode)\(self.user.nickname) \(messageContents)"
        }
        return "[\(time)] <\(userMode)\(self.user.nickname)> \(messageContents)"
    }
}
