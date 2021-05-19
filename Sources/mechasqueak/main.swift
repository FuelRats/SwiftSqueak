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
import Lingo
import IRCKit
import AsyncHTTPClient
import NIO

let processId = ProcessInfo.processInfo.processIdentifier
try "\(processId)".write(toFile: "\(FileManager.default.currentDirectoryPath)/mechasqueak.pid", atomically: true, encoding: .utf8)

let lingo = try! Lingo(rootPath: "\(FileManager.default.currentDirectoryPath)/localisation", defaultLocale: "en")
let httpClient = HTTPClient(eventLoopGroupProvider: .createNew, configuration: .init(
    redirectConfiguration: .none,
    timeout: .init(connect: .seconds(5), read: .seconds(60))
))

func loadConfiguration () -> MechaConfiguration {
    var configPath = URL(
        fileURLWithPath: FileManager.default.currentDirectoryPath
    ).appendingPathComponent("config.json")
    if CommandLine.arguments.count > 1 {
        configPath = URL(fileURLWithPath: CommandLine.arguments[1])
    }

    guard let configData = try? Data(contentsOf: configPath) else {
        fatalError("Could not locate configuration file in \(configPath.absoluteString)")
    }

    let configDecoder = JSONDecoder()
    return try! configDecoder.decode(MechaConfiguration.self, from: configData)
}

func debug (_ output: String) {
    if configuration.general.debug == true {
        print(output)
    }
}

let configuration = loadConfiguration()

class MechaSqueak {
    let configPath: URL
    static var commands: [IRCBotCommandDeclaration] = []
    let moduleManager: IRCBotModuleManager
    static let accounts = NicknameLookupManager()
    var commands: [IRCBotModule]
    let connections: [IRCClient]
    let rescueBoard: RescueBoard
    var reportingChannel: IRCChannel?
    let helpModule: HelpCommands
    let startupTime: Date
    let version = "3.0.0"
    var landmarks: [SystemsAPI.LandmarkListDocument.LandmarkListEntry] = []
    var sectors: [StarSector] = []
    static let userAgent = "MechaSqueak/3.0 Contact support@fuelrats.com if needed"
    static var lastDeltaMessageTime: Date? = nil
    let ratSocket: RatSocket?

    init () {
        var configPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if CommandLine.arguments.count > 1 {
            configPath = URL(fileURLWithPath: CommandLine.arguments[1])
        }
        self.configPath = configPath

        if configuration.api.websocket != nil {
            ratSocket = RatSocket()
        } else {
            ratSocket = nil
        }

        self.startupTime = Date()
        self.rescueBoard = RescueBoard()

        self.connections = configuration.connections.map({
            let client = IRCClient(configuration: $0)
            if let operLogin = configuration.general.operLogin {
                client.connectCommands = [ { client in
                    client.send(command: .OPER, parameters: operLogin)
                }]
            }
            return client
        })
        

        self.moduleManager = IRCBotModuleManager()
        self.helpModule = HelpCommands(moduleManager)
        self.commands = [
            MessageScanner(moduleManager),
            GeneralCommands(moduleManager),
            SystemSearch(moduleManager),
            BoardCommands(moduleManager),
            BoardAssignCommands(moduleManager),
            BoardAttributeCommands(moduleManager),
            BoardPlatformCommands(moduleManager),
            BoardQuoteCommands(moduleManager),
            RemoteRescueCommands(moduleManager),
            FactCommands(moduleManager),
            ShortenURLCommands(moduleManager),
            TweetCommands(moduleManager),
            ManagementCommands(moduleManager),
            RatAnniversary(moduleManager),
            AccountCommands(moduleManager),
            SessionLogger(moduleManager)
        ]
        
        if configuration.queue != nil {
            commands.append(QueueCommands(moduleManager))
        }
        
        if let documentationPath = configuration.documentationPath {
            ReferenceGenerator.generate(inPath: documentationPath)
        }
        
        SystemsAPI.fetchLandmarkList().whenSuccess({ landmarks in
            self.landmarks = landmarks
        })
        
        SystemsAPI.fetchSectorList().whenSuccess({ sectors in
            self.sectors = sectors
        })
    }


    @EventListener<IRCUserAccountChangeNotification>
    var onAccountChange = { accountChange in
        let user = accountChange.user

        guard let account = user.account else {
            if let oldValue = accountChange.oldValue {
                accounts.mapping[oldValue] = nil
            }
            return
        }

        accounts.lookupIfNotExists(user: user)
    }

    @EventListener<IRCUserJoinedChannelNotification>
    var onUserJoin = { userJoin in
        let client = userJoin.raw.client
        if userJoin.raw.sender!.isCurrentUser(client: client)
            && userJoin.channel.name.lowercased() == configuration.general.reportingChannel.lowercased() {
            mecha.reportingChannel = userJoin.channel
            mecha.rescueBoard.syncBoard()
            
            if let gitDir = configuration.documentationPath {
                let release = shell("/usr/bin/git", ["tag", "--points-at", "HEAD"], currentDirectory: gitDir)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let releaseName = release, releaseName.count > 0 {
                    mecha.reportingChannel?.send(message: "Update complete. Go here to read the latest changes: https://github.com/FuelRats/SwiftSqueak/releases/tag/\(releaseName)")
                }
            }
        } else {
            accounts.lookup(user: userJoin.user)
            if let rescue = mecha.rescueBoard.findRescue(withCaseIdentifier: userJoin.user.nickname) {
                    rescue.quotes.removeAll(where: {
                        $0.message.starts(with: "Client rejoined the rescue channel")
                    })
                    rescue.quotes.append(RescueQuote(
                        author: userJoin.raw.client.currentNick,
                        message: "Client rejoined the rescue channel",
                        createdAt: Date(),
                        updatedAt: Date(),
                        lastAuthor: userJoin.raw.client.currentNick)
                    )
                    rescue.syncUpstream()

                var key = rescue.rats.count == 0 ? "board.clientjoin.needsrats" : "board.clientjoin"
                rescue.clientHost = userJoin.user.hostmask
                userJoin.channel.send(key: key, map: [
                    "caseId": rescue.commandIdentifier,
                    "client": rescue.clientDescription,
                    "platform": rescue.platform.ircRepresentable,
                    "system": rescue.system.shortDescription
                ])
            } else if let rescue = mecha.rescueBoard.rescues.first(where: {
                $0.clientHost == userJoin.user.hostmask
            }) {
                rescue.quotes.removeAll(where: {
                    $0.message.starts(with: "Client rejoined the rescue channel")
                })
                rescue.quotes.append(RescueQuote(
                    author: userJoin.raw.client.currentNick,
                    message: "Client rejoined the rescue channel as \(userJoin.user.nickname)",
                    createdAt: Date(),
                    updatedAt: Date(),
                    lastAuthor: userJoin.raw.client.currentNick)
                )
                rescue.syncUpstream()

                rescue.clientNick = userJoin.user.nickname
                userJoin.channel.send(key: "board.clientjoinhost", map: [
                    "caseId": rescue.commandIdentifier,
                    "client": rescue.clientDescription,
                    "nick": userJoin.user.nickname
                ])
            }
        }
    }

    @EventListener<IRCUserLeftChannelNotification>
    var onUserPart = { userPart in
        if let rescue = mecha.rescueBoard.findRescue(withCaseIdentifier: userPart.user.nickname) {
            guard userPart.channel.name.lowercased() == rescue.channelName.lowercased() else {
                return
            }
            if let prepTimer = mecha.rescueBoard.prepTimers[rescue.id] {
                prepTimer?.cancel()
                mecha.rescueBoard.prepTimers.removeValue(forKey: rescue.id)
            }

            rescue.quotes.removeAll(where: {
                $0.message == "Client left the rescue channel"
            })
            rescue.quotes.append(RescueQuote(
                author: userPart.raw.client.currentNick,
                message: "Client left the rescue channel",
                createdAt: Date(),
                updatedAt: Date(),
                lastAuthor: userPart.raw.client.currentNick)
            )
            rescue.syncUpstream()

            userPart.channel.send(key: "board.clientquit", map: [
                "caseId": rescue.commandIdentifier,
                "client": rescue.clientDescription
            ])
        }

    }

    @EventListener<IRCUserQuitNotification>
    var onUserQuit = { userQuit in
        if
            let sender = userQuit.raw.sender,
            let rescue = mecha.rescueBoard.findRescue(withCaseIdentifier: sender.nickname)
        {
            if let prepTimer = mecha.rescueBoard.prepTimers[rescue.id] {
                prepTimer?.cancel()
                mecha.rescueBoard.prepTimers.removeValue(forKey: rescue.id)
            }
            rescue.quotes.removeAll(where: {
                $0.message == "Client left the rescue channel"
            })
            
            if let quitMessage = userQuit.raw.parameters.first, quitMessage.starts(with: "Banned ") || quitMessage.starts(with: "Killed ") {
                if let timer = mecha.rescueBoard.prepTimers[rescue.id] {
                    timer?.cancel()
                    mecha.rescueBoard.prepTimers.removeValue(forKey: rescue.id)
                }
                
                if rescue.rats.count > 0 {
                    rescue.notes = "Client was banned"
                    let url = "https://fuelrats.com/paperwork/\(rescue.id.uuidString.lowercased())/edit"
                    rescue.close(fromBoard: mecha.rescueBoard, onComplete: {
                        mecha.reportingChannel?.send(key: "board.bannedclose", map: [
                            "caseId": rescue.commandIdentifier,
                            "link": url,
                            "client": rescue.clientDescription
                        ])
                        mecha.rescueBoard.rescues.removeAll(where: { $0.id == rescue.id })
                    }, onError: { _ in
                        
                    })
                } else {
                    rescue.trash(fromBoard: mecha.rescueBoard, reason: "Client was banned", onComplete: {
                        mecha.reportingChannel?.send(key: "board.bannedmd", map: [
                            "caseId": rescue.commandIdentifier,
                            "client": rescue.clientDescription
                        ])
                        mecha.rescueBoard.rescues.removeAll(where: { $0.id == rescue.id })
                    }, onError: { _ in
                        
                    })
                }
                return
            }
            
            rescue.quotes.append(RescueQuote(
                author: userQuit.raw.client.currentNick,
                message: "Client left the rescue channel",
                createdAt: Date(),
                updatedAt: Date(),
                lastAuthor: userQuit.raw.client.currentNick)
            )
            rescue.syncUpstream()

            let quitChannels = userQuit.previousChannels
            for channel in quitChannels {
                channel.send(key: "board.clientquit", map: [
                    "caseId": rescue.commandIdentifier,
                    "client": rescue.clientDescription
                ])
            }
        }
    }

    @EventListener<IRCChannelMessageNotification>
    var onChannelMessage = { channelMessage in
        guard channelMessage.raw.messageTags["batch"] == nil else {
            return
        }

        if channelMessage.destination.name.lowercased() == configuration.general.rescueChannel.lowercased() {
            mecha.ratSocket?.broadcast(event: .channelMessage, payload: ChannelMessageEventPayload(channelMessage: channelMessage))
        }

        if channelMessage.user.nickname.starts(with: "Delta_RC_2526")
            && channelMessage.destination.name.lowercased() != configuration.general.rescueChannel.lowercased() {
            if let deltaInterval = lastDeltaMessageTime, Date().timeIntervalSince(deltaInterval) < 0.5 {
                lastDeltaMessageTime = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1), execute: {
                    channelMessage.client.sendActionMessage(toChannel: channelMessage.destination, contents: "drinks")
                })
            } else if channelMessage.message.count > 410 {
                lastDeltaMessageTime = Date()
            }
        }
    }
    
    @EventListener<IRCEchoMessageNotification>
    var onEchoMessage = { echoMessage in
        guard echoMessage.raw.messageTags["batch"] == nil else {
            return
        }

        if echoMessage.destination.name.lowercased() == configuration.general.rescueChannel.lowercased() {
            mecha.ratSocket?.broadcast(event: .channelMessage, payload: ChannelMessageEventPayload(channelMessage: echoMessage))
        }
    }

    @EventListener<IRCUserChangedNickNotification>
    var onUserNickChange = { nickChange in
        let sender = nickChange.raw.sender!

        if let rescue = mecha.rescueBoard.findRescue(withCaseIdentifier: sender.nickname) {
            rescue.clientNick = nickChange.newNick
            rescue.syncUpstream()

            nickChange.raw.client.sendMessage(
                toChannelName: rescue.channelName,
                withKey: "board.clientnick", mapping: [
                    "caseId": rescue.commandIdentifier,
                    "client": rescue.clientDescription,
                    "newNick": nickChange.newNick
            ])
        }
    }


    @EventListener<IRCUserHostChangeNotification>
    var onUserHostChange = { hostChange in
        let sender = hostChange.sender!
        
        guard let user = hostChange.client.channels.first(where: {
            $0.member(named: sender.nickname) != nil
        })?.member(named: sender.nickname) else {
            return
        }
        accounts.lookupIfNotExists(user: user)
    }
}

let loop = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount * 2)

func makePromise<T>(of type: T.Type = T.self) -> EventLoopPromise<T> {
    return loop.next().makePromise(of: type)
}
let mecha = MechaSqueak()

RunLoop.main.run()
