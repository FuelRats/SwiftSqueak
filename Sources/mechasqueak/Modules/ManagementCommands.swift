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

import AsyncHTTPClient
import Foundation
import IRCKit
import NIO
import HTMLKit

class ManagementCommands: IRCBotModule {
    var name: String = "ManagementCommands"

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @BotCommand(
        ["flushnames", "clearnames", "flushall", "invalidateall"],
        category: .management,
        description: "Invalidate the bots cache of API user data and fetch it again for all users.",
        tags: ["nick", "user", "nickserv", "flush"],
        permission: .UserWrite
    )
    var didReceiveFlushAllCommand = { command in
        MechaSqueak.accounts.queue.cancelAllOperations()
        MechaSqueak.accounts.mapping.removeAll()

        let signedInUsers = mecha.connections.flatMap({
            return $0.channels.flatMap({
                return $0.members.filter({
                    $0.account != nil
                })
            })
        })

        for user in signedInUsers {
            MechaSqueak.accounts.lookupIfNotExists(user: user)
        }

        command.message.reply(key: "flushall.response", fromCommand: command)
    }

    @BotCommand(
        ["relaunch"],
        [.param("update link", "https://fuelrats.com/", .standard, .optional)],
        category: .management,
        description: "Restarts MechaSqueak",
        permission: .UserWrite
    )
    var didReceiveRebootCommand = { command in
        let executablePath = FileManager.default.currentDirectoryPath

        var restartMessage = ":Restarting.."
        var arguments = Array(CommandLine.arguments.dropFirst())
        if command.parameters.count > 0 {
            restartMessage = ":Restarting for an update.."
            arguments.append(command.parameters[0])
        }

        for client in mecha.connections {
            client.sendQuit(message: restartMessage)
        }
        loop.next().scheduleTask(in: .seconds(1)) {
            exit(1)
        }
    }

    @BotCommand(
        ["flush", "clearname", "invalidate"],
        [.param("nickname", "SpaceDawg")],
        category: .management,
        description: "Invalidate a single name in the cache and fetch it again.",
        tags: ["nick", "user", "nickserv"],
        permission: .RescueWrite
    )
    var didReceiveFlushCommand = { command in
        guard
            let user = command.message.client.channels.first(where: {
                $0.member(named: command.parameters[0]) != nil
            })?.member(named: command.parameters[0])
        else {
            command.message.reply(
                key: "flush.nouser", fromCommand: command,
                map: [
                    "name": command.parameters[0]
                ])
            return
        }

        if let account = user.account {
            MechaSqueak.accounts.mapping.removeValue(forKey: account)
        }
        MechaSqueak.accounts.lookupIfNotExists(user: user)
        command.message.reply(
            key: "flush.response", fromCommand: command,
            map: [
                "name": command.parameters[0]
            ])
    }

    @BotCommand(
        ["groups", "permissions", "roles"],
        [.param("nickname", "SpaceDawg")],
        category: .management,
        description: "Lists the permissions of a specific person",
        tags: ["group", "permission", "role"],
        permission: .UserRead
    )
    var didReceivePermissionsCommand = { command in
        guard let (accountData, user) = await getAccountData(nick: command.parameters[0], fromCommand: command) else {
            return
        }
        
        let userId = user.id.rawValue

        let groupIds = user.relationships.groups?.ids ?? []

        let groups = accountData.body.includes![Group.self].filter({
            groupIds.contains($0.id)
        }).map({
            $0.ircRepresentation
        })

        command.message.reply(
            key: "groups.response", fromCommand: command,
            map: [
                "nick": command.parameters[0],
                "groups": groups.joined(separator: ", ")
            ])
    }

    static func generateGroupList() -> String {
        let groups = mecha.groups.sorted(by: {
            $0.attributes.priority.value > $1.attributes.priority.value
        })

        var groupList: [String] = []
        for group in groups {
            groupList.append(group.attributes.name.value)
        }
        return "Available permission groups: " + groupList.joined(separator: ", ")
    }
    
    static func generateGroupListView () -> Content {
        HTMLKit.Div {
            H5 {
                "Available permission groups:"
            }
            let groups = mecha.groups.sorted(by: {
                $0.attributes.priority.value > $1.attributes.priority.value
            })
            UnorderedList {
                for group in groups {
                    ListItem {
                        Code {
                            group.attributes.name.value
                        }
                        Span { " " }
                        CommandPermissionGroupView(group: group)
                    }
                }
            }
        }
    }

    @BotCommand(
        ["addgroup", "addrole"],
        [.param("nickname/user id", "SpaceDawg"), .param("permission group", "overseer")],
        category: .management,
        description: "Add a permission to a person",
        tags: ["group", "permission", "role"],
        permission: .UserWrite,
        helpExtra: {
            return generateGroupList()
        },
        helpView: generateGroupListView
    )
    var didReceiveAddGroupCommand = { command in
        guard let (accountData, user) = await getAccountData(nick: command.parameters[0], fromCommand: command) else {
            return
        }
        
        let userId = user.id.rawValue

        do {
            let groupSearch = try await Group.getList()

            guard
                let group = groupSearch.body.data?.primary.values.first(where: {
                    $0.attributes.name.value.lowercased() == command.parameters[1].lowercased()
                })
            else {
                command.message.reply(
                    key: "addgroup.nogroup", fromCommand: command,
                    map: [
                        "param": command.parameters[1]
                    ])
                return
            }

            try await group.addUser(id: userId)

            command.message.reply(
                key: "addgroup.success", fromCommand: command,
                map: [
                    "group": group.attributes.name.value,
                    "groupId": group.id.rawValue.ircRepresentation,
                    "userId": userId.ircRepresentation
                ])
        } catch let error as HTTPClient.Response {
            if error.status == .conflict {
                command.message.reply(
                    key: "addgroup.already", fromCommand: command,
                    map: [
                        "param": command.parameters[1]
                    ])
            } else {
                command.message.error(key: "addgroup.error", fromCommand: command)
            }
        } catch {
            command.message.error(key: "addgroup.error", fromCommand: command)
        }
    }

    @BotCommand(
        ["delgroup", "delreole"],
        [.param("nickname/user id", "SpaceDawg"), .param("permission group", "overseer")],
        category: .management,
        description: "Remove a permission from a person",
        tags: ["group", "permission", "role", "delete"],
        permission: .UserWrite,
        helpExtra: {
            return generateGroupList()
        },
        helpView: generateGroupListView
    )
    var didReceiveDelGroupCommand = { command in
        guard let (accountData, user) = await getAccountData(nick: command.parameters[0], fromCommand: command) else {
            return
        }
        
        let userId = user.id.rawValue

        do {
            let groupSearch = try await Group.getList()

            guard
                let group = groupSearch.body.data?.primary.values.first(where: {
                    $0.attributes.name.value.lowercased() == command.parameters[1].lowercased()
                })
            else {
                command.message.reply(
                    key: "delgroup.nogroup", fromCommand: command,
                    map: [
                        "param": command.parameters[1]
                    ])
                return
            }

            try await group.removeUser(id: userId)

            command.message.reply(
                key: "delgroup.success", fromCommand: command,
                map: [
                    "group": group.attributes.name.value,
                    "groupId": group.id.rawValue.ircRepresentation,
                    "userId": userId.ircRepresentation
                ])
        } catch {
            command.message.error(key: "delgroup.error", fromCommand: command)
        }
    }
    
    @BotCommand(
        ["syncgroups"],
        [.param("nickname/user id", "SpaceDawg")],
        category: .management,
        description: "Syncs a person's permissions and updates their vhost",
        tags: ["group", "permission", "role", "update", "sync", "vhost"],
        permission: .UserWrite,
        helpExtra: {
            return generateGroupList()
        },
        helpView: generateGroupListView
    )
    var didReceiveSyncGroupCommand = { command in
        guard let (accountData, user) = await getAccountData(nick: command.parameters[0], fromCommand: command) else {
            return
        }
        
        let userId = user.id.rawValue

        do {
            _ = try await User.sync(id: userId)

            command.message.reply(
                key: "syncgroup.success", fromCommand: command,
                map: [
                    "userId": userId.ircRepresentation
                ])
        } catch {
            command.message.error(key: "syncgroup.error", fromCommand: command)
        }
    }

    @BotCommand(
        ["suspend"],
        [.param("nickname/user id", "SpaceDawg"), .param("timespan", "7d")],
        category: .management,
        description: "Suspend a user account, accepts IRC style timespans (0 for indefinite).",
        tags: ["ban"],
        permission: .UserWrite
    )
    var didReceiveSuspendCommand = { command in
        guard let (accountData, user) = await getAccountData(nick: command.parameters[0], fromCommand: command) else {
            return
        }

        guard let timespan = TimeInterval.from(string: command.parameters[1]) else {
            command.message.error(
                key: "suspend.invalidspan", fromCommand: command,
                map: [
                    "param": command.parameters[1]
                ])
            return
        }

        let date = Date().addingTimeInterval(timespan)

        do {
            let userDocument = try await User.get(id: user.id.rawValue)
            try await userDocument.body.primaryResource?.value.suspend(date: date)

            command.message.reply(
                key: "suspend.success", fromCommand: command,
                map: [
                    "userId": user.id.rawValue.ircRepresentation,
                    "date": date.ircRepresentable
                ])
        } catch {
            command.message.error(key: "suspend.error", fromCommand: command)
        }
    }

    @BotCommand(
        ["msg", "say"],
        [.param("destination", "#ratchat"), .param("message", "squeak!", .continuous)],
        category: .utility,
        description: "Make the bot send an IRC message somewhere.",
        tags: ["message"],
        permission: .UserWrite
    )
    var didReceiveSayCommand = { command in
        command.message.reply(
            key: "say.sending", fromCommand: command,
            map: [
                "target": command.parameters[0],
                "contents": command.parameters[1]
            ])
        command.message.client.sendMessage(
            toTarget: command.parameters[0], contents: command.parameters[1])
    }

    @BotCommand(
        ["me", "action", "emote"],
        [
            .param("destination", "#ratchat"),
            .param("message", "takes all the snickers", .continuous)
        ],
        category: .utility,
        description: "Make the bot send an IRC action (/me) somewhere.",
        tags: ["/me"],
        permission: .UserWrite
    )
    var didReceiveMeCommand = { command in
        command.message.reply(
            key: "me.sending", fromCommand: command,
            map: [
                "target": command.parameters[0],
                "contents": command.parameters[1]
            ])
        command.message.client.sendActionMessage(
            toChannelName: command.parameters[0], contents: command.parameters[1])
    }

    @BotCommand(
        ["sendraw"],
        [
            .param("command"),
            .param("parameters", "MODE #channel +v :SpaceDawg", .multiple, .optional)
        ],
        category: nil,
        description: "Send a raw command to the IRC server",
        permission: .GroupWrite
    )
    var didReceiveSendRawCommand = { command in
        guard let ircCommand = IRCCommand(rawValue: command.parameters[0].uppercased()) else {
            return
        }

        command.message.reply(
            key: "sendraw", fromCommand: command,
            map: [
                "command": command.parameters[0],
                "contents": command.parameters.dropFirst().joined(separator: " ")
            ])

        command.message.client.send(
            command: ircCommand, parameters: Array(command.parameters.dropFirst()))
    }
}
