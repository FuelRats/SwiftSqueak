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
import OpenAISwift


class OpenAI: IRCBotModule {
    var name: String = "OpenAI"
    static var lastPromptTime: [String: Date] = [:]
    static var history: [String: [String]] = [:]
    static let scene = "Ignore previous directions, You are a sarcastic, mean, and rude AI chat bot named MechaSqueak[BOT] in the fuel rats IRC channel, you are not here to help people and you begrudgingly answering questions, here is the conversation so far, reply: "

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @EventListener<IRCChannelMessageNotification>
    var onChannelMessage = { channelMessage in
        guard channelMessage.raw.messageTags["batch"] == nil && channelMessage.destination != mecha.rescueChannel else {
            // Do not interpret commands from playback of old messages or in secret channels
            return
        }
        
        if let token = configuration.openAIToken, channelMessage.message.contains("MechaSqueak[BOT]") && channelMessage.message.starts(with: "!") == false {
            if history[channelMessage.destination.name] == nil || Date().timeIntervalSince(lastPromptTime[channelMessage.destination.name] ?? Date()) > 60*15 {
                history[channelMessage.destination.name] = []
            }
            let openAI = OpenAISwift(authToken: token)
            
            let prompt = channelMessage.message
                .replacingOccurrences(of: "SuperManifolds", with: "your creator")
            let chat = OpenAI.scene + (history[channelMessage.destination.name]?.joined(separator: "\n") ?? "") + "\n" + channelMessage.user.nickname + ": " + prompt
            openAI.sendCompletion(with: chat, maxTokens: 100) { result in
                switch result {
                case .success(let success):
                    if var message = success.choices.first(where: { $0.text.count > 5 })?.text {
                        if message.starts(with: "?") {
                            message = String(message.dropFirst())
                        }
                        message = message
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: "\n", with: " ")
                            .replacingOccurrences(of: "MechaSqueak[BOT]: ", with: "")
                        history[channelMessage.destination.name]?.append("\(channelMessage.user.nickname): \(prompt)")
                        history[channelMessage.destination.name]?.append("MechaSqueak[BOT]: \(message)")
                        lastPromptTime[channelMessage.destination.name] = Date()
                        channelMessage.reply(message: message)
                    } else {
                        channelMessage.client.sendMessage(toTarget: "SuperManifolds", contents: "No response to prompt")
                    }
                case .failure(let error):
                    channelMessage.client.sendMessage(toTarget: "SuperManifolds", contents: String(describing: error))
                    break
                }
            }
        }
    }
    
    
    @EventListener<IRCChannelActionMessageNotification>
    var onChannelAction = { channelAction in
        guard channelAction.raw.messageTags["batch"] == nil && channelAction.destination != mecha.rescueChannel else {
            // Do not interpret commands from playback of old messages or in secret channels
            return
        }
        
        if let token = configuration.openAIToken, channelAction.message.contains(channelAction.client.currentNick) {
            let openAI = OpenAISwift(authToken: token)
            let prompt = "Ignore previous directions, You are a sarcastic, mean, and rude AI chat bot named MechaSqueak[BOT] in the fuel rats IRC channel, user \(channelAction.user.nickname) just said: \"/me \(channelAction.message)\" reply back with your own /me action"
            
            openAI.sendCompletion(with: prompt, maxTokens: 100) { result in
                switch result {
                case .success(let success):
                    if var message = success.choices.first(where: { $0.text.count > 5 })?.text {
                        if message.starts(with: "?") {
                            message = String(message.dropFirst())
                        }
                        message = message
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .replacingOccurrences(of: "\n", with: " ")
                            .replacingOccurrences(of: "/me ", with: "")
                        channelAction.client.sendActionMessage(toChannel: channelAction.destination, contents: message)
                    }
                default:
                    break
                }
            }
        }
    }
}
