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

class ManagementCommands: IRCBotModule {
    var name: String = "ManagementCommands"

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @BotCommand(
        ["flushnames", "clearnames", "flushall", "invalidateall"],
        parameters: 0...0,
        category: .management,
        description: "Invalidate the bots cache of API user data and fetch it again for all users.",
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

        command.message.replyPrivate(key: "flushall.response", fromCommand: command)
    }

    @BotCommand(
        ["flush", "clearname", "invalidate"],
        parameters: 1...1,
        category: .management,
        description: "Invalidate a single name in the cache and fetch it again.",
        permission: .UserWrite
    )
    var didReceiveFlushCommand = { command in
        if let mapping = MechaSqueak.accounts.mapping.first(where: {
            $0.key.lowercased() == command.parameters[0].lowercased()
        }) {
            MechaSqueak.accounts.mapping.removeValue(forKey: mapping.key)
        }

        guard let user = command.message.client.channels.first(where: {
            $0.member(named: command.parameters[0]) != nil
        })?.member(named: command.parameters[0]) else {
            command.message.replyPrivate(key: "flush.nouser", fromCommand: command, map: [
                "name": command.parameters[0]
            ])
            return
        }
        MechaSqueak.accounts.lookupIfNotExists(user: user)
        command.message.replyPrivate(key: "flush.response", fromCommand: command, map: [
            "name": command.parameters[0]
        ])
    }

    @BotCommand(
        ["groups", "permissions"],
        parameters: 1...1,
        category: .management,
        description: "Lists the permissions of a specific person",
        permission: .UserRead
    )
    var didReceivePermissionsCommand = { command in
        guard let mapping = MechaSqueak.accounts.mapping.first(where: {
            $0.key.lowercased() == command.parameters[0].lowercased()
        }) else {
            command.message.replyPrivate(key: "groups.nouser", fromCommand: command, map: [
                "nick": command.parameters[0]
            ])
            return
        }

        let groupIds = mapping.value.user?.relationships.groups?.ids ?? []

        let groups = mapping.value.body.includes![Group.self].filter({
            groupIds.contains($0.id)
        }).map({
            $0.attributes.name.value
        })

        command.message.reply(key: "groups.response", fromCommand: command, map: [
            "nick": command.parameters[0],
            "groups": groups.joined(separator: ", ")
        ])
    }

    @BotCommand(
        ["addgroup"],
        parameters: 2...2,
        category: .management,
        description: "Add a permission to a person",
        paramText: "<nick/user id> <group name>",
        example: "SpaceDawg dispatch",
        permission: .UserWrite
    )
    var didReceiveAddGroupCommand = { command in
        var getUserId = UUID(uuidString: command.parameters[0])
        if getUserId == nil {
            getUserId = command.message.client.user(withName: command.parameters[0])?.associatedAPIData?.user?.id.rawValue
        }

        guard let userId = getUserId else {
            command.message.reply(key: "addgroup.noid", fromCommand: command, map: [
                "param": command.parameters[0]
            ])
            return
        }

        Group.list().whenSuccess({ groupSearch in
            guard let group = groupSearch.body.data?.primary.values.first(where: {
                $0.attributes.name.value.lowercased() == command.parameters[1].lowercased()
            }) else {
                command.message.reply(key: "addgroup.nogroup", fromCommand: command, map: [
                    "param": command.parameters[1]
                ])
                return
            }

            group.addUser(id: userId).whenComplete({ result in
                switch result {
                    case .success(_):
                        command.message.reply(key: "addgroup.success", fromCommand: command, map: [
                            "group": group.attributes.name.value,
                            "groupId": group.id.rawValue.ircRepresentation,
                            "userId": userId.ircRepresentation
                        ])

                    case .failure(let error):
                        debug(String(describing: error))
                        command.message.error(key: "addgroup.error", fromCommand: command)
                }
            })
        })
    }

    @BotCommand(
        ["suspend"],
        parameters: 2...2,
        category: .management,
        description: "Suspend a user account, accepts IRC style timespans (0 for indefinite).",
        paramText: "<nick/user id> <timespan>",
        example: "SpaceDawg 7d",
        permission: .UserWrite
    )
    var didReceiveSuspendCommand = { command in
        var getUserId = UUID(uuidString: command.parameters[0])
        if getUserId == nil {
            getUserId = command.message.client.user(withName: command.parameters[0])?.associatedAPIData?.user?.id.rawValue
        }

        guard let userId = getUserId else {
            command.message.error(key: "suspend.noid", fromCommand: command, map: [
                "param": command.parameters[0]
            ])
            return
        }

        guard let timespan = TimeInterval.from(string: command.parameters[1]) else {
            command.message.error(key: "suspend.invalidspan", fromCommand: command, map: [
                "param": command.parameters[1]
            ])
            return
        }

        let date = Date().addingTimeInterval(timespan)

        User.get(id: userId).whenComplete({ result in
            switch result {
                case .failure(_):
                    command.message.error(key: "suspend.nouser", fromCommand: command)

                case .success(let userDocument):
                    userDocument.body.primaryResource?.value.suspend(date: date).whenComplete({ result in
                        switch result {
                            case .failure(let error):
                                debug(String(describing: error))
                                command.message.error(key: "suspend.error", fromCommand: command)

                            case .success(_):
                                command.message.reply(key: "suspend.success", fromCommand: command, map: [
                                    "userId": userId.ircRepresentation,
                                    "date": date.ircRepresentable
                                ])
                        }
                    })

            }
        })
    }

    @BotCommand(
        ["msg", "say"],
        parameters: 2...2,
        lastParameterIsContinous: true,
        category: .utility,
        description: "Make the bot send an IRC message somewhere.",
        paramText: "<destination> <message>",
        example: "#ratchat Squeak!",
        permission: .UserWrite
    )
    var didReceiveSayCommand = { command in
        command.message.reply(key: "say.sending", fromCommand: command, map: [
            "target": command.parameters[0],
            "contents": command.parameters[1]
        ])
        command.message.client.sendMessage(toTarget: command.parameters[0], contents: command.parameters[1])
    }

    @BotCommand(
        ["me", "action", "emote"],
        parameters: 2...2,
        lastParameterIsContinous: true,
        category: .utility,
        description: "Make the bot send an IRC action (/me) somewhere.",
        paramText: "<destination> <action message>",
        example: "#ratchat noms popcorn.",
        permission: .UserWrite
    )
    var didReceiveMeCommand = { command in
        command.message.reply(key: "me.sending", fromCommand: command, map: [
            "target": command.parameters[0],
            "contents": command.parameters[1]
        ])
        command.message.client.sendActionMessage(toChannelName: command.parameters[0], contents: command.parameters[1])
    }
}
