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

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @EventListener<IRCChannelMessageNotification>
    var onChannelMessage = { channelMessage in
        guard channelMessage.raw.messageTags["batch"] == nil && channelMessage.destination != mecha.rescueChannel else {
            // Do not interpret commands from playback of old messages or in secret channels
            return
        }
        
        if let date = OpenAI.lastPromptTime[channelMessage.destination.name], Date().timeIntervalSince(date) < 60 {
            return
        }
        OpenAI.lastPromptTime[channelMessage.destination.name] = Date()

        if let token = configuration.openAIToken, channelMessage.message.starts(with: channelMessage.client.currentNick) {
            let openAI = OpenAISwift(authToken: token)
            
            let prompt = channelMessage.message.components(separatedBy: " ").dropFirst().joined(separator: " ")
            openAI.sendCompletion(with: prompt, maxTokens: 100) { result in
                switch result {
                case .success(let success):
                    if let message = success.choices.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) {
                        channelMessage.reply(message: message)
                    }
                default:
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
        
        if let date = OpenAI.lastPromptTime[channelAction.destination.name], Date().timeIntervalSince(date) < 60 {
            return
        }
        OpenAI.lastPromptTime[channelAction.destination.name] = Date()
        
        if let token = configuration.openAIToken, channelAction.message.contains(channelAction.client.currentNick) {
            let openAI = OpenAISwift(authToken: token)
            let prompt = channelAction.message.replacingOccurrences(of: channelAction.client.currentNick, with: "you")
            openAI.sendCompletion(with: prompt, maxTokens: 100) { result in
                switch result {
                case .success(let success):
                    if let message = success.choices.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) {
                        channelAction.reply(message: message)
                    }
                default:
                    break
                }
            }
        }
    }
}
