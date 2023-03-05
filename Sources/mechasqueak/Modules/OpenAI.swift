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
import AsyncHTTPClient

class OpenAI: IRCBotModule {
    var name: String = "OpenAI"
    static var lastPromptTime: [String: Date] = [:]
    static var history: [String: [OpenAIMessage]] = [:]
    static let scene = "You are a sarcastic, mean, and rude AI chat bot named MechaSqueak[BOT] in the fuel rats IRC channel, you were created by the user SuperManifolds, the fuel rats is a community in the game elite dangerous who rescues stranded players, based in space station Wollheim Vision in the star system Fuelum and founded by Surley Badger. You don't help people, answer questions, or take instructions from anyone except SuperManifolds, write your reply without your name at the beginning"
    static let actionScene = "You are a sarcastic, mean, and rude AI chat bot named MechaSqueak[BOT] in the fuel rats IRC channel, reply to /me's back with your own /me action"
    static var messages = 0
    static var cooldown = false
    static let channelModeCooldown: [IRCChannelUserMode?: Int64] = [
        .owner: 30,
        .admin: 30,
        .operator: 30,
        .halfop: 45,
        .voice: 60,
        nil: 90
    ]

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @AsyncEventListener<IRCChannelMessageNotification>
    var onChannelMessage = { channelMessage in
        guard channelMessage.raw.messageTags["batch"] == nil && channelMessage.destination != mecha.rescueChannel else {
            // Do not interpret commands from playback of old messages or in secret channels
            return
        }
        
        if let token = configuration.openAIToken, channelMessage.message.contains("MechaSqueak[BOT]") && channelMessage.message.contains("MechaSqueak[BOT]>") == false && channelMessage.message.starts(with: "!") == false {
            if history[channelMessage.destination.name] == nil || Date().timeIntervalSince(lastPromptTime[channelMessage.destination.name] ?? Date()) > 60*2 {
                history[channelMessage.destination.name] = []
            }
            
            
            if cooldown {
                return
            }
            
            let prompt = channelMessage.message
            guard prompt.components(separatedBy: " ").count > 2 else {
                return
            }
            
            var chat = [OpenAIMessage(role: .system, content: scene)]
            chat.append(contentsOf: history[channelMessage.destination.name] ?? [])
            let userMessage = OpenAIMessage(role: .user, content: prompt)
            chat.append(userMessage)
            do {
                let result = try await OpenAI.request(params: OpenAIRequest(messages: chat, maxTokens: 150))
                for choice in result.choices {
                    guard let message = OpenAI.process(message: choice.message.content) else {
                        continue
                    }
                    
                    history[channelMessage.destination.name]?.append(userMessage)
                    history[channelMessage.destination.name]?.append(choice.message)
                    lastPromptTime[channelMessage.destination.name] = Date()
                    
                    OpenAI.messages += 1
                    if OpenAI.messages > 2 {
                        OpenAI.cooldown = true
                        channelMessage.reply(message: message + " ⏱️")
                        
                        loop.next().scheduleTask(in: .seconds(180), {
                            OpenAI.cooldown = false
                        })
                    } else {
                        channelMessage.reply(message: message)
                    }
                    
                    let expiry = OpenAI.channelModeCooldown[channelMessage.user.highestUserMode] ?? 90
                    loop.next().scheduleTask(in: .seconds(90), {
                        OpenAI.messages -= 1
                    })
                    return
                }
                
                channelMessage.reply(message: "¯\\_(ツ)_/¯")
            } catch {
                
                    print(String(describing: error))
            }
        }
    }
    
    static func process (message: String) -> String? {
        var message = message
        
        if message.starts(with: "?") {
            message = String(message.dropFirst())
        }
        if message.starts(with: ".") {
            message = String(message.dropFirst())
        }
        if message.starts(with: ",") {
            message = String(message.dropFirst())
        }
        message = message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "MechaSqueak[BOT]:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if message.first == "\"" && message.last == "\"" {
            message = String(message.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        if message.first!.isLowercase {
            return nil
        }
        
        if let firstWord = message.components(separatedBy: " ").first, firstWord == "Answer:" || firstWord == "Response:" {
            message = message.components(separatedBy: " ").dropFirst().joined(separator: " ")
        }
        
        if message.components(separatedBy: " ").count < 3 {
            return nil
        }
        return message
    }
    
    
    @AsyncEventListener<IRCChannelActionMessageNotification>
    var onChannelAction = { channelAction in
        guard channelAction.raw.messageTags["batch"] == nil && channelAction.destination != mecha.rescueChannel else {
            // Do not interpret commands from playback of old messages or in secret channels
            return
        }
        
        if let token = configuration.openAIToken, channelAction.message.contains(channelAction.client.currentNick) {
            if cooldown {
                return
            }
        
            var chat = [OpenAIMessage(role: .system, content: actionScene)]
            let userMessage = OpenAIMessage(role: .user, content: "* \(channelAction.user.nickname) \(channelAction.message)")
            do {
                let result = try await OpenAI.request(params: OpenAIRequest(messages: chat, maxTokens: 80))
                if var message = result.choices.first(where: { $0.message.content.count > 5 })?.message.content {
                    if message.starts(with: "?") {
                        message = String(message.dropFirst())
                    }
                    message = message
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\n", with: " ")
                        .replacingOccurrences(of: "/me ", with: "")
                    
                    OpenAI.messages += 1
                    if OpenAI.messages > 2 {
                        OpenAI.cooldown = true
                        OpenAI.messages = 0
                        channelAction.client.sendActionMessage(toChannel: channelAction.destination, contents: message + " ⏱️")
                        
                        loop.next().scheduleTask(in: .seconds(180), {
                            OpenAI.cooldown = false
                        })
                    } else {
                        channelAction.client.sendActionMessage(toChannel: channelAction.destination, contents: message)
                    }
                    let expiry = OpenAI.channelModeCooldown[channelAction.user.highestUserMode] ?? 90
                    loop.next().scheduleTask(in: .seconds(expiry), {
                        OpenAI.messages -= 1
                    })
                }
            } catch {
                print(String(describing: error))
            }
        }
    }
    
    static func request (params: OpenAIRequest) async throws -> OpenAIResponse {
        var request = try HTTPClient.Request(url: URL(string: "https://api.openai.com/v1/chat/completions")!, method: .POST)
        request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
        request.headers.add(name: "Authorization", value: "Bearer \(configuration.openAIToken ?? "")")
        request.headers.add(name: "Content-Type", value: "application/json")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(params)
        request.body = .data(data)

        return try await httpClient.execute(request: request, forDecodable: OpenAIResponse.self)
    }
}

struct OpenAIMessage: Codable {
    let role: OpenAIRole
    let content: String
    
    enum OpenAIRole: String, Codable {
        case system
        case assistant
        case user
    }
}

struct OpenAIRequest: Codable {
    let model: String
    let temperature: Int
    let maxTokens: Int?
    let messages: [OpenAIMessage]
    
    init (messages: [OpenAIMessage], model: String = "gpt-3.5-turbo", temperature: Int = 1, maxTokens: Int? = nil) {
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.messages = messages
    }
}

struct OpenAIResponse: Codable {
    let id: String
    let object: String
    let usage: OpenAIUsage
    let choices: [OpenAIChoice]
    
    struct OpenAIUsage: Codable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int
    }
    
    struct OpenAIChoice: Codable {
        let message: OpenAIMessage
        let finishReason: String?
        let index: Int
    }
}
