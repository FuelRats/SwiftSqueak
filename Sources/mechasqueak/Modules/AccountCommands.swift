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

class AccountCommands: IRCBotModule {
    var name: String = "AccountCommands"

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @BotCommand(
        ["whoami"],
        category: .account,
        description: "Check the Fuel Rats account information the bot is currently associating with your nick",
        cooldown: .seconds(300)
    )
    var didReceiveWhoAmICommand = { command in
        let message = command.message
        let user = message.user
        guard let account = user.account else {
            command.message.reply(key: "whoami.notloggedin", fromCommand: command)
            return
        }

        guard let associatedNickname = user.associatedAPIData else {
            command.message.reply(key: "whoami.nodata", fromCommand: command, map: [
                "account": account
            ])
            return
        }

        guard let apiUser = associatedNickname.body.includes![User.self].first(where: {
            return $0.id.rawValue == associatedNickname.body.data?.primary.values[0].relationships.user?.id.rawValue
        }) else {
            command.message.reply(key: "whoami.noaccount", fromCommand: command, map: [
                "account": account
            ])
            return
        }

        let rats = associatedNickname.ratsBelongingTo(user: apiUser).map({ (rat: Rat) -> String in
            if rat.odyssey {
                return "\(rat.attributes.name.value) (\(rat.attributes.platform.value.ircRepresentable)) (\(IRCFormat.color(.Orange, "Odyssey")))"
            }
            return "\(rat.attributes.name.value) (\(rat.attributes.platform.value.ircRepresentable))"
        }).joined(separator: ", ")

        let joinedDate = associatedNickname.ratsBelongingTo(user: apiUser).reduce(nil, { (acc: Date?, rat: Rat) -> Date? in
            if acc == nil || rat.attributes.createdAt.value < acc! {
                return rat.attributes.createdAt.value
            }
            return acc
        })

        let verifiedStatus = associatedNickname.permissions.contains(.UserVerified) ?
            IRCFormat.color(.LightGreen, "Verified") :
            IRCFormat.color(.Orange, "Unverified")

        command.message.reply(key: "whoami.response", fromCommand: command, map: [
            "account": account,
            "userId": apiUser.id.rawValue.ircRepresentation,
            "rats": rats,
            "joined": joinedDate?.eliteFormattedString ?? "u\u{200B}nknown",
            "verified": verifiedStatus
        ])
    }

    @BotCommand(
        ["whois", "ratid", "who", "id"],
        [.param("nickname", "SpaceDawg")],
        category: .account,
        description: "Check the Fuel Rats account information the bot is associating with someone's nick.",
        permission: .RatReadOwn,
        cooldown: .seconds(300)
    )
    var didReceiveWhoIsCommand = { command in
        let message = command.message
        let nick = command.parameters[0]

        guard let user = message.client.channels.compactMap({ channel in
            return channel.member(named: nick)
        }).first else {
            command.message.error(key: "whois.notfound", fromCommand: command, map: [
                "nick": nick
            ])
            return
        }

        guard let account = user.account else {
            command.message.reply(key: "whois.notloggedin", fromCommand: command, map: [
                "nick": nick
            ])
            return
        }

        guard let associatedNickname = user.associatedAPIData else {
            command.message.reply(key: "whois.nodata", fromCommand: command, map: [
                "nick": nick,
                "account": account
            ])
            return
        }

        guard let apiUser = associatedNickname.body.includes![User.self].first(where: {
            return $0.id.rawValue == associatedNickname.body.data?.primary.values[0].relationships.user?.id.rawValue
        }) else {
            command.message.reply(key: "whois.noaccount", fromCommand: command, map: [
                "nick": nick,
                "account": account
            ])
            return
        }

        let rats = associatedNickname.ratsBelongingTo(user: apiUser).map({ (rat: Rat) -> String in
            if rat.odyssey {
                return "\(rat.attributes.name.value) (\(rat.attributes.platform.value.ircRepresentable)) (\(IRCFormat.color(.Orange, "Odyssey")))"
            }
            return "\(rat.attributes.name.value) (\(rat.attributes.platform.value.ircRepresentable))"
        }).joined(separator: ", ")

        let joinedDate = associatedNickname.ratsBelongingTo(user: apiUser).reduce(nil, { (acc: Date?, rat: Rat) -> Date? in
            if acc == nil || rat.attributes.createdAt.value < acc! {
                return rat.attributes.createdAt.value
            }
            return acc
        })

        let verifiedStatus = associatedNickname.permissions.contains(.UserVerified) ?
            IRCFormat.color(.LightGreen, "Verified") :
            IRCFormat.color(.Orange, "Unverified")

        command.message.reply(key: "whois.response", fromCommand: command, map: [
            "nick": nick,
            "account": account,
            "userId": apiUser.id.rawValue.ircRepresentation,
            "rats": rats,
            "joined": joinedDate?.eliteFormattedString ?? "u\u{200B}nknown",
            "verified": verifiedStatus
        ])
    }

    @BotCommand(
        ["activerat", "assigncheck", "assigntest"],
        [.param("platform", "PC")],
        category: .account,
        description: "Check what CMDR name mecha would currently assign to a case based on your nickname",
        permission: .RatReadOwn,
        cooldown: .seconds(300)
    )
    var didReceiveAssignCheckCommand = { command in
        let message = command.message
        let user = message.user

        guard let platform = GamePlatform(rawValue: command.parameters[0].lowercased()) else {
            command.message.reply(key: "activerat.invalidplatform", fromCommand: command)
            return
        }

        guard let rat = user.getRatRepresenting(platform: platform) else {
            command.message.reply(key: "activerat.none", fromCommand: command, map: [
                "platform": platform.ircRepresentable
            ])
            return
        }

        command.message.reply(key: "activerat.response", fromCommand: command, map: [
            "platform": platform.ircRepresentable,
            "id": rat.id.rawValue.ircRepresentation,
            "name": rat.attributes.name.value
        ])
    }

    @BotCommand(
        ["changeemail", "changemail"],
        [.param("email", "spacedawg@fuelrats.com")],
        category: .account,
        description: "Change your Fuel Rats account email address",
        permission: .UserWriteOwn,
        allowedDestinations: .PrivateMessage
    )
    var didReceiveChangeEmailCommand = { command in
        guard let user = command.message.user.associatedAPIData?.user else {
            command.message.error(key: "changemail.notloggedin", fromCommand: command)
            return
        }

        user.changeEmail(to: command.parameters[0]).whenComplete({ result in
            switch result {
                case .failure(let error):
                    print(String(describing: error))
                    command.message.error(key: "changemail.error", fromCommand: command)

                case .success(_):
                    command.message.reply(key: "changemail.success", fromCommand: command, map: [
                        "email": command.parameters[0]
                    ])
            }
        })
    }
    
    @BotCommand(
        ["permits"],
        category: .account,
        description: "Add the permit belonging to this system to your account",
        permission: .UserWriteOwn
    )
    var didReceiveListPermitCommand = { command in
        guard let currentRat = command.message.user.currentRat else {
            command.message.replyPrivate(key: "permits.norat", fromCommand: command)
            return
        }
        
        let permits = currentRat.attributes.data.value.permits ?? []
        
        guard permits.count > 0 else {
            command.message.replyPrivate(key: "permits.nopermits", fromCommand: command)
            return
        }
        
        let heading = lingo.localize("permits.list", locale: "en-GB", interpolations: [
            "name": currentRat.attributes.name.value
        ])
        
        command.message.replyPrivate(list: permits, separator: ", ", heading: "\(heading) ")
    }
    
    @BotCommand(
        ["addpermit", "permitadd"],
        [.param("system name", "NLTT 48288", .continuous)],
        category: .account,
        description: "Add the permit belonging to this system to your current CMDR",
        permission: .UserWriteOwn,
        allowedDestinations: .PrivateMessage
    )
    var didReceiveAddPermitCommand = { command in
        let systemName = command.parameters[0]
        guard var currentRat = command.message.user.currentRat else {
            command.message.reply(key: "addpermit.norat", fromCommand: command)
            return
        }
        
        SystemsAPI.performSearch(forSystem: systemName).whenComplete({ result in
            switch result {
                case .failure(_):
                    command.message.error(key: "addpermit.searcherror", fromCommand: command, map: [
                        "system": systemName
                    ])
                    
                case .success(let searchResult):
                    guard
                        searchResult.data?.count ?? 0 > 0,
                        let system = searchResult.data?[0],
                        system.similarity == 1,
                        system.permitRequired
                    else {
                        command.message.error(key: "addpermit.nosystem", fromCommand: command, map: [
                            "system": systemName
                        ])
                        return
                    }
                    
                    var ratData = currentRat.attributes.data.value
                    var permits = ratData.permits ?? []
                    let permitName = system.permitName ?? system.name
                    if permits.contains(permitName) == false {
                        permits.append(permitName)
                    }
                    ratData.permits = permits
                    currentRat = currentRat.tappingAttributes({ $0.data = .init(value: ratData)})
                    
                    currentRat.update().whenSuccess({
                        command.message.user.flush()
                        command.message.reply(key: "addpermit.added", fromCommand: command, map: [
                            "name": currentRat.attributes.name.value,
                            "permit": permitName
                        ])
                    })
            }
            
        })
        

    }
    
    @BotCommand(
        ["delpermit", "permitdel"],
        [.param("permit name", "Pilot's Federation District", .continuous)],
        category: .account,
        description: "Delete this permit from your current CMDR",
        permission: .UserWriteOwn,
        allowedDestinations: .PrivateMessage
    )
    var didReceiveRemovePermitCommand = { command in
        let permitName = command.parameters[0]
        guard var currentRat = command.message.user.currentRat else {
            command.message.reply(key: "delpermit.norat", fromCommand: command)
            return
        }
        
        var ratData = currentRat.attributes.data.value
        var permits = ratData.permits ?? []
        
        guard let permitIndex = permits.firstIndex(where: { $0.lowercased() == permitName.lowercased() }) else {
            command.message.error(key: "delpermit.nopermit", fromCommand: command)
            return
        }
        permits.remove(at: permitIndex)
        
        ratData.permits = permits
        currentRat = currentRat.tappingAttributes({ $0.data = .init(value: ratData)})
        
        currentRat.update().whenSuccess({
            command.message.user.flush()
            command.message.reply(key: "delpermit.removed", fromCommand: command, map: [
                "name": currentRat.attributes.name.value,
                "permit": permitName
            ])
        })
    }
    
    @BotCommand(
        ["useodyssey"],
        category: .account,
        description: "Informs Mecha that you are currently using Odyssey on your active commander (Determined by your nickname)",
        permission: .UserWriteOwn,
        allowedDestinations: .PrivateMessage
    )
    var didReceiveUseOdysseyCommand = { command in
        guard let currentRat = command.message.user.getRatRepresenting(platform: .PC) else {
            command.message.replyPrivate(key: "useodyssey.norat", fromCommand: command)
            return
        }
        
        let isUsingOdyssey = !currentRat.attributes.odyssey.value
        currentRat.setIsUsingOdyssey(true).whenSuccess({
            command.message.reply(key: "useodyssey.odyssey", fromCommand: command, map: [
                "name": currentRat.attributes.name.value
            ])
            command.message.user.flush()
        })
    }
    
    @BotCommand(
        ["usehorizons"],
        category: .account,
        description: "Informs Mecha that you are currently using Horizons on your active commander (Determined by your nickname)",
        permission: .UserWriteOwn,
        allowedDestinations: .PrivateMessage
    )
    var didReceiveUseHorizonsCommand = { command in
        guard let currentRat = command.message.user.getRatRepresenting(platform: .PC) else {
            command.message.replyPrivate(key: "useodyssey.norat", fromCommand: command)
            return
        }
        
        currentRat.setIsUsingOdyssey(false).whenSuccess({
            command.message.reply(key: "useodyssey.horizons", fromCommand: command, map: [
                "name": currentRat.attributes.name.value
            ])
            command.message.user.flush()
        })
    }
}
