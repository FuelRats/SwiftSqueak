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
    let commands: [IRCBotModule]
    let connections: [IRCClient]
    let rescueBoard: RescueBoard
    var reportingChannel: IRCChannel?
    let helpModule: HelpCommands
    let startupTime: Date
    let version = "3.0.0"
    static let userAgent = "MechaSqueak/3.0 Contact support@fuelrats.com if needed"

    init () {
        var configPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if CommandLine.arguments.count > 1 {
            configPath = URL(fileURLWithPath: CommandLine.arguments[1])
        }
        self.configPath = configPath

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
            RatAnniversary(moduleManager)
        ]
    }


    @IRCListener<IRCUserAccountChangeNotification>
    var onAccountChange = { accountChange in
        let user = accountChange.user

        guard user.account != nil else {
            accounts.mapping[user.nickname] = nil
            return
        }

        if accountChange.oldValue != user.account || accounts.mapping[user.nickname] == nil {
            accounts.lookupIfNotExists(user: user)
        }
    }

    @IRCListener<IRCUserJoinedChannelNotification>
    var onUserJoin = { userJoin in
        let client = userJoin.raw.client
        if userJoin.raw.sender!.isCurrentUser(client: client)
            && userJoin.channel.name.lowercased() == configuration.general.reportingChannel.lowercased() {
            mecha.reportingChannel = userJoin.channel
            mecha.rescueBoard.syncBoard()
        } else {

            accounts.lookupIfNotExists(user: userJoin.user)
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

                rescue.clientHost = userJoin.user.hostmask
                userJoin.channel.send(key: "board.clientjoin", map: [
                    "caseId": rescue.commandIdentifier,
                    "client": rescue.client ?? "u\u{200B}nknown client"
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
                    "client": rescue.client ?? "u\u{200B}nknown client",
                    "nick": userJoin.user.nickname
                ])
            }
        }
    }

    @IRCListener<IRCUserLeftChannelNotification>
    var onUserPart = { userPart in
        if let rescue = mecha.rescueBoard.findRescue(withCaseIdentifier: userPart.user.nickname) {
            guard userPart.channel.name.lowercased() == rescue.channelName.lowercased() else {
                return
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
                "client": rescue.client ?? "u\u{200B}nknown client"
            ])
        }

    }

    @IRCListener<IRCUserQuitNotification>
    var onUserQuit = { userQuit in
        accounts.mapping.removeValue(forKey: userQuit.sender!.nickname)

        if
            let sender = userQuit.sender,
            let rescue = mecha.rescueBoard.findRescue(withCaseIdentifier: sender.nickname)
        {
            rescue.quotes.removeAll(where: {
                $0.message == "Client left the rescue channel"
            })
            rescue.quotes.append(RescueQuote(
                author: userQuit.client.currentNick,
                message: "Client left the rescue channel",
                createdAt: Date(),
                updatedAt: Date(),
                lastAuthor: userQuit.client.currentNick)
            )
            rescue.syncUpstream()

            userQuit.client.sendMessage(
                toChannelName: rescue.channelName,
                withKey: "board.clientquit", mapping: [
                    "caseId": rescue.commandIdentifier,
                    "client": rescue.client ?? "u\u{200B}nknown client"
            ])
        }
    }

    @IRCListener<IRCUserChangedNickNotification>
    var onUserNickChange = { nickChange in
        let sender = nickChange.raw.sender!

        if let apiNickname = accounts.mapping[sender.nickname] {
            accounts.mapping.removeValue(forKey: sender.nickname)
            accounts.mapping[nickChange.newNick] = apiNickname
        }
    }


    @IRCListener<IRCUserHostChangeNotification>
    var onUserHostChange = { hostChange in
        let sender = hostChange.sender!
        accounts.mapping.removeValue(forKey: sender.nickname)

        guard let user = hostChange.client.channels.first(where: {
            $0.member(named: sender.nickname) != nil
        })?.member(named: sender.nickname) else {
            return
        }
        accounts.lookupIfNotExists(user: user)
    }
}

let mecha = MechaSqueak()
let loop = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

RunLoop.main.run()
