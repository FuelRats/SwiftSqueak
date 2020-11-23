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
import SwiftKueryORM
import SwiftKueryPostgreSQL
import IRCKit

class BulletinCommands: IRCBotModule {
    var name: String = "Bulletin Commands"
    private var channelMessageObserver: NotificationToken?
    private var privateMessageObserver: NotificationToken?

    @BotCommand(
        ["bulletins", "bulletin"],
        parameters: 0...3,
        lastParameterIsContinous: true,
        category: .other,
        description: "View the list of bulletins, modify, or delete them.",
        paramText: "add <message> / info/del <bulletin number>",
        example: "set hello world, !bulletins info 1, !bulletins del 5"
    )
    var didReceiveFactCommand = { command in
        if command.parameters.count == 0 {
            didReceiveBulletinListCommand(command: command)
            return
        }

        let modifier = command.parameters[0].lowercased()

        switch modifier {
            case "add":
                didReceiveBulletinAddCommand(command: command)

            case "info":
                didReceiveBulletinInfoCommand(command: command)

            case "del", "delete":
                didReceiveBulletinDeleteCommand(command: command)

            default:
                command.message.error(key: "bulletin.invalidargument", fromCommand: command, map: [
                    "argument": modifier
                ])
        }
    }

    static func didReceiveBulletinListCommand (command: IRCBotCommand) {

    }

    static func didReceiveBulletinAddCommand (command: IRCBotCommand) {
        guard command.parameters.count == 3 else {
            command.message.error(key: "bulletin.add.syntax", fromCommand: command)
            return
        }

        guard command.message.user.hasPermission(permission: .UserWrite) else {
            command.message.error(key: "bulletin.add.nopermission", fromCommand: command)
            return
        }
        let contents = command.parameters[2]

        let bulletin = Bulletin(
            message: contents,
            author: command.message.user.nickname,
            createdAt: Date(),
            updatedAt: Date()
        )

        bulletin.save({ (_, error) in
            guard error == nil else {
                command.message.error(key: "bulletin.add.error", fromCommand: command)
                return
            }

            command.message.error(key: "bulletin.add.created", fromCommand: command, map: [
                "message": contents.excerpt(maxLength: 100)
            ])
        })
    }

    static func didReceiveBulletinInfoCommand (command: IRCBotCommand) {
        guard command.parameters.count == 2 else {
            command.message.error(key: "bulletin.info.syntax", fromCommand: command)
            return
        }

        guard let bulletinId = Int(command.parameters[2]) else {
            return
        }

        Bulletin.get(id: bulletinId).whenComplete { result in
            switch result {
                case .success(let bulletin):
                    guard let bulletin = bulletin else {
                        return
                    }

                case .failure(let error):
                    break
            }
        }
    }

    static func didReceiveBulletinDeleteCommand (command: IRCBotCommand) {

    }

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)

        let pool = PostgreSQLConnection.createPool(
            host: configuration.database.host,
            port: configuration.database.port,
            options: [
                .databaseName(configuration.database.database),
                .userName(configuration.database.username)
            ],
            poolOptions: ConnectionPoolOptions(initialCapacity: 1, maxCapacity: 3)
        )
        Database.default = Database(pool)
        do {
            try Fact.createTableSync()
        } catch let error {
            debug(String(describing: error))
        }
    }
}
