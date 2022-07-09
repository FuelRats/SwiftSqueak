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
import Lingo
import IRCKit
import AsyncHTTPClient
import NIO
import Backtrace

Backtrace.install()

let processId = ProcessInfo.processInfo.processIdentifier
try "\(processId)".write(toFile: "\(FileManager.default.currentDirectoryPath)/mechasqueak.pid", atomically: true, encoding: .utf8)

let httpClient = HTTPClient(eventLoopGroupProvider: .createNew, configuration: .init(
    redirectConfiguration: .none,
    timeout: .init(connect: .seconds(5), read: .seconds(180))
))

var configPath = URL(
    fileURLWithPath: FileManager.default.currentDirectoryPath
).appendingPathComponent("config.json")
if CommandLine.arguments.count > 1 {
    configPath = URL(fileURLWithPath: CommandLine.arguments[1])
}

func loadConfiguration () -> MechaConfiguration {
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

var configuration = loadConfiguration()
let lingo = try! Lingo(rootPath: "\(configuration.sourcePath.path)/localisation", defaultLocale: "en")

class MechaSqueak {
    let configPath: URL
    static var commands: [IRCBotCommandDeclaration] = []
    let moduleManager: IRCBotModuleManager
    static let accounts = NicknameLookupManager()
    var commands: [IRCBotModule]
    let connections: [IRCClient]
    var rescueChannel: IRCChannel?
    var reportingChannel: IRCChannel?
    let helpModule: HelpCommands
    let startupTime: Date
    let version = "3.0.0"
    var landmarks: [SystemsAPI.LandmarkListDocument.LandmarkListEntry] = []
    var sectors: [StarSector] = []
    var groups: [Group] = []
    static let userAgent = "MechaSqueak/3.0 Contact support@fuelrats.com if needed"
    static var lastDeltaMessageTime: Date? = nil
    let ratSocket: RatSocket?

    init () {
        var configPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if CommandLine.arguments.count > 1 {
            configPath = URL(fileURLWithPath: CommandLine.arguments[1])
        }
        self.configPath = configPath


        self.startupTime = Date()

        self.connections = configuration.connections.map({
            let client = IRCClient(configuration: $0)
            if let operLogin = configuration.general.operLogin {
                client.connectCommands = [ { client in
                    client.send(command: .OPER, parameters: operLogin)
                    client.send(command: .MODE, parameters: [client.currentNick, "+B"])
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
        
        ratSocket = RatSocket()
        
        if configuration.general.drillMode == false {
            loop.next().scheduleRepeatedTask(initialDelay: .seconds(15), delay: .minutes(5), self.checkEliteStatus)
        }
        
        Task {
            self.landmarks = try await SystemsAPI.fetchLandmarkList()
            self.sectors = try await SystemsAPI.fetchSectorList()
            self.groups = try await Group.getList().body.data?.primary.values ?? []
            
            ReferenceGenerator.generate(inPath: configuration.sourcePath)
        }
    }
    
    func checkEliteStatus (task: RepeatedTask) {
        Task {
            let serverStatus = try? await EliteServerStatus.fetch()
            let statusString = serverStatus?.text ?? "Unreachable"
            var statusStringFormatted = statusString
            if statusStringFormatted == "OK" {
                statusStringFormatted = IRCFormat.color(.Green, statusString)
            } else if statusString == "Unreachable" {
                statusStringFormatted = IRCFormat.color(.LightRed, statusString)
            } else {
                statusStringFormatted = IRCFormat.color(.Orange, statusString)
            }
            if let topic = reportingChannel?.topic {
                var topicSections = topic.contents.components(separatedBy: " | ")
                if topicSections.last?.starts(with: "ED Server Status: ") == true {
                    let serverStatusSection = topicSections.last!.components(separatedBy: " ").dropFirst(2).joined(separator: " ")
                    guard serverStatusSection.contains(statusString) == false else {
                        return
                    }
                    topicSections.removeLast()
                }
                
                topicSections.append("ED Server Status: \(statusStringFormatted)")
                
                while topicSections.joined(separator: " | ").bytes.count > 360 {
                    topicSections.remove(at: topicSections.endIndex - 2)
                }
                print(topicSections.joined(separator: " | ").bytes.count)
                reportingChannel?.client.send(command: .TOPIC, parameters: [
                    reportingChannel!.name,
                    topicSections.joined(separator: " | ")
                ])
            }
        }
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

        accounts.lookup(user: user)
    }

    @AsyncEventListener<IRCUserJoinedChannelNotification>
    var onUserJoin = { userJoin in
        let client = userJoin.raw.client
        if userJoin.raw.sender!.isCurrentUser(client: client)
            && userJoin.channel.name.lowercased() == configuration.general.rescueChannel.lowercased() {
            mecha.rescueChannel = userJoin.channel
        }
        if userJoin.raw.sender!.isCurrentUser(client: client)
            && userJoin.channel.name.lowercased() == configuration.general.reportingChannel.lowercased() {
            mecha.reportingChannel = userJoin.channel
            try? await board.sync()
            
            let gitDir = configuration.sourcePath
            let release = shell("/usr/bin/git", ["tag", "--points-at", "HEAD"], currentDirectory: gitDir)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let releaseName = release, releaseName.count > 0 {
                mecha.reportingChannel?.send(message: "Update complete. Go here to read the latest changes: https://github.com/FuelRats/SwiftSqueak/releases/tag/\(releaseName)")
            }
        } else {
            accounts.lookup(user: userJoin.user)
            if let (caseId, rescue) = await board.findRescue(withCaseIdentifier: userJoin.user.nickname) {
                var quotes = rescue.quotes
                    quotes.removeAll(where: {
                        $0.message.starts(with: "Client rejoined the rescue channel")
                    })
                    quotes.append(RescueQuote(
                        author: userJoin.raw.client.currentNick,
                        message: "Client rejoined the rescue channel",
                        createdAt: Date(),
                        updatedAt: Date(),
                        lastAuthor: userJoin.raw.client.currentNick)
                    )
                
                rescue.setQuotes(quotes)
                try? rescue.save()

                var key = rescue.rats.count == 0 ? "board.clientjoin.needsrats" : "board.clientjoin"
                userJoin.channel.send(key: key, map: [
                    "caseId": caseId,
                    "client": rescue.clientDescription,
                    "platform": rescue.platform.ircRepresentable,
                    "system": rescue.system.description
                ])
            }
        }
    }

    @AsyncEventListener<IRCUserLeftChannelNotification>
    var onUserPart = { userPart in
        if let (caseId, rescue) = await board.findRescue(withCaseIdentifier: userPart.user.nickname) {
            guard rescue.channel == userPart.channel else {
                return
            }
            await board.cancelPrepTimer(forRescue: rescue)

            var quotes = rescue.quotes
            quotes.removeAll(where: {
                $0.message == "Client left the rescue channel"
            })
            quotes.append(RescueQuote(
                author: userPart.raw.client.currentNick,
                message: "Client left the rescue channel",
                createdAt: Date(),
                updatedAt: Date(),
                lastAuthor: userPart.raw.client.currentNick)
            )
            rescue.setQuotes(quotes)
            try? rescue.save()

            userPart.channel.send(key: "board.clientquit", map: [
                "caseId": caseId,
                "client": rescue.clientDescription
            ])
        }

    }

    @AsyncEventListener<IRCUserQuitNotification>
    var onUserQuit = { userQuit in
        if
            let sender = userQuit.raw.sender,
            let (caseId, rescue) = await board.findRescue(withCaseIdentifier: sender.nickname)
        {
            await board.cancelPrepTimer(forRescue: rescue)
            var quotes = rescue.quotes
            quotes.removeAll(where: {
                $0.message == "Client left the rescue channel"
            })
            
            if let quitMessage = userQuit.raw.parameters.first, quitMessage.starts(with: "Banned ") || quitMessage.starts(with: "Killed ") {
                if rescue.rats.count > 0 {
                    rescue.notes = "Client was banned"
                    let url = "https://fuelrats.com/paperwork/\(rescue.id.uuidString.lowercased())/edit"
                    
                    do {
                        try await rescue.close()
                        
                        mecha.reportingChannel?.send(key: "board.bannedclose", map: [
                            "caseId": caseId,
                            "link": url,
                            "client": rescue.clientDescription
                        ])
                        await board.remove(id: caseId)
                    } catch {
                        
                    }
                } else {
                    do {
                        var banDueToVpn = quitMessage.contains("banned VPN network")
                        try await rescue.trash(reason: "Client was banned")
                        
                        mecha.reportingChannel?.send(key: banDueToVpn ? "board.bannedvpn" : "board.bannedmd", map: [
                            "caseId": caseId,
                            "client": rescue.clientDescription
                        ])
                        await board.remove(id: caseId)
                    } catch {
                        
                    }
                }
                return
            }
            
            rescue.appendQuote(RescueQuote(
                author: userQuit.raw.client.currentNick,
                message: "Client left the rescue channel",
                createdAt: Date(),
                updatedAt: Date(),
                lastAuthor: userQuit.raw.client.currentNick)
            )
            
            try? rescue.save()

            let quitChannels = userQuit.previousChannels
            for channel in quitChannels {
                channel.send(key: "board.clientquit", map: [
                    "caseId": caseId,
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
            } else if channelMessage.message.count > 405 {
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

    @AsyncEventListener<IRCUserChangedNickNotification>
    var onUserNickChange = { nickChange in
        let sender = nickChange.raw.sender!

        if let (caseId, rescue) = await board.findRescue(withCaseIdentifier: sender.nickname) {
            rescue.clientNick = nickChange.newNick

            rescue.channel?.send(key: "board.clientnick", map: [
                "caseId": caseId,
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
        accounts.lookup(user: user)
    }
}

signal(SIGTERM, SIG_IGN)

let sigtermSrc = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigtermSrc.setEventHandler {
    mecha.reportingChannel?.send(message: IRCFormat.bold("Performing a planned restart, I will be back in a jiffy"))
    mecha.reportingChannel?.client.sendQuit(message: "Restarting..")
    exit(0)
}
sigtermSrc.resume()

let loop = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount * 2)

func makePromise<T>(of type: T.Type = T.self) -> EventLoopPromise<T> {
    return loop.next().makePromise(of: type)
}
let mecha = MechaSqueak()
let board = RescueBoard()
board.startUpRoutines()

RunLoop.main.run()
