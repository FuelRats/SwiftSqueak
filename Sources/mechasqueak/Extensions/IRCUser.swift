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
@preconcurrency import IRCKit

extension IRCUser {
    var associatedAPIData: NicknameSearchDocument? {
        // A private message forwarded by a server-side alias (e.g. the /ody, /hor and /leg
        // aliases, which send "!mymode ..." to us) arrives without the IRCv3 account tag, so
        // self.account is nil even when the sender is identified. Fall back to the account we
        // already track for this nick via channel membership (WHOX / account-notify) so
        // identity-dependent commands can still resolve the sender.
        guard
            let account = self.account
                ?? self.client.channels.lazy
                    .compactMap({ $0.member(named: self.nickname)?.account })
                    .first
        else {
            return nil
        }
        return MechaSqueak.accounts.apiData(forAccount: account)
    }

    var settings: UserDataObject? {
        return self.associatedAPIData?.user?.attributes.data.value
    }

    func getAssignedRescue() async -> (Int, Rescue)? {
        guard let userId = self.associatedAPIData?.user?.id.rawValue else {
            return nil
        }
        return await board.first(where: {
            return $0.value.rats.contains(where: {
                return $0.relationships.user?.id?.rawValue == userId
            }) || $0.value.unidentifiedRats.contains(self.nickname)
        })
    }

    var platform: GamePlatform? {
        let nickname = self.nickname.lowercased()

        if nickname.hasSuffix("[pc]") {
            return .PC
        }

        if nickname.hasSuffix("[xb]") || nickname.hasSuffix("[xb1]") {
            return .Xbox
        }

        if nickname.contains("[ps]") || nickname.contains("[ps4]]") || nickname.contains("[ps5]") {
            return .PS
        }

        return nil
    }

    var currentRat: Rat? {
        guard let apiData = self.associatedAPIData, let user = apiData.user else {
            return nil
        }

        var rats = apiData.ratsBelongingTo(user: user)
        if let platform = self.platform {
            rats = rats.filter({
                $0.attributes.platform.value == platform
            })
        }

        var nickname = self.nickname.lowercased()
        nickname = nickname.replacingOccurrences(
            of: "(\\[[A-Za-z0-9]+\\])", with: "", options: .regularExpression)

        rats.sort(by: {
            nickname.levenshtein($0.attributes.name.value.lowercased())
                < nickname.levenshtein($1.attributes.name.value.lowercased())
        })

        return rats.first
    }

    func flush() {
        if let account = self.account {
            MechaSqueak.accounts.setAPIData(nil, forAccount: account)
        }
        MechaSqueak.accounts.lookupIfNotExists(user: self)
    }

    func hasPermission(permission: AccountPermission) -> Bool {
        guard let permissions = self.associatedAPIData?.permissions else {
            return self.hostPermissions().contains(permission)
        }

        return permissions.contains(permission)
    }

    func getRatRepresenting(platform: GamePlatform?) -> Rat? {
        guard let apiData = self.associatedAPIData, let user = apiData.user else {
            return nil
        }

        var rats = apiData.ratsBelongingTo(user: user)
        rats = rats.filter({
            $0.attributes.platform.value == platform
        })

        var nickname = self.nickname.lowercased()
        nickname = nickname.replacingOccurrences(
            of: "(\\[[A-Za-z0-9]+\\])", with: "", options: .regularExpression)

        rats.sort(by: {
            nickname.levenshtein($0.attributes.name.value.lowercased())
                < nickname.levenshtein($1.attributes.name.value.lowercased())
        })

        return rats.first
    }

    func isAssignedTo(rescue: Rescue) async -> Bool {
        guard let user = self.associatedAPIData?.user,
            let rats = self.associatedAPIData?.ratsBelongingTo(user: user)
        else {
            return false
        }
        let rescueRats = rescue.rats
        return rescueRats.contains(where: { assigned in
            return rats.contains(where: { $0.id.rawValue == assigned.id.rawValue })
        })
    }

    func isAssociatedWith(rescue: Rescue) async -> Bool {
        let clientNick = rescue.clientNick
        return await isAssignedTo(rescue: rescue) || clientNick == self.nickname
    }

    /// Whether the hostmask is `domain` itself or a host under it, so "pirat.fuelrats.com" is not a rat vhost.
    func hasVirtualHost(under domain: String) -> Bool {
        let host = self.hostmask.lowercased()
        return host == domain || host.hasSuffix(".\(domain)")
    }

    func hostPermissions() -> [AccountPermission] {
        if self.hasVirtualHost(under: "i.see.all")
            || self.hasVirtualHost(under: "netadmin.fuelrats.com")
            || self.hasVirtualHost(under: "admin.fuelrats.com") {
            return [
                .UserRead,
                .UserReadOwn,
                .UserWriteOwn,
                .UserWrite,
                .RatRead,
                .RatReadOwn,
                .RatWrite,
                .RatWriteOwn,
                .RescueRead,
                .RescueReadOwn,
                .RescueWrite,
                .RescueWriteOwn,
                .TwitterWrite,
                .DispatchRead,
                .DispatchWrite,
                .AnnouncementWrite
            ]
        }

        if self.hasVirtualHost(under: "overseer.fuelrats.com")
            || self.hasVirtualHost(under: "techrat.fuelrats.com") {
            return [
                .UserReadOwn,
                .UserWriteOwn,
                .RatRead,
                .RatReadOwn,
                .RatWrite,
                .RatWriteOwn,
                .RescueRead,
                .RescueReadOwn,
                .RescueWrite,
                .RescueWriteOwn,
                .TwitterWrite,
                .DispatchRead,
                .DispatchWrite,
                .AnnouncementWrite
            ]
        }

        if self.hasVirtualHost(under: "trainer.fuelrats.com") {
            return [
                .UserReadOwn,
                .UserWriteOwn,
                .RatReadOwn,
                .RatWriteOwn,
                .RescueRead,
                .RescueReadOwn,
                .RescueWriteOwn,
                .DispatchRead,
                .DispatchWrite,
                .TwitterWrite,
                .AnnouncementWrite
            ]
        }

        if self.hasVirtualHost(under: "rat.fuelrats.com") {
            return [
                .UserReadOwn,
                .UserWriteOwn,
                .RatReadOwn,
                .RatWriteOwn,
                .RescueRead,
                .RescueReadOwn,
                .RescueWriteOwn,
                .DispatchRead,
                .DispatchWrite,
                .TwitterWrite
            ]
        }

        if self.hasVirtualHost(under: "recruit.fuelrats.com") {
            return [
                .UserReadOwn,
                .UserWriteOwn,
                .RatReadOwn,
                .RatWriteOwn,
                .RescueReadOwn
            ]
        }

        return []
    }
}
