//
//  IRCUser.swift
//  mechasqueak
//
//  Created by Alex Sørlie Glomsaas on 2020-05-27.
//

import Foundation
import IRCKit

extension IRCUser {
    var associatedAPIData: NicknameSearchDocument? {
        return mecha.accounts.mapping[self.nickname]
    }

    func hasPermission (permission: AccountPermission) -> Bool {
        guard let permissions = self.associatedAPIData?.permissions else {
            return self.hostPermissions().contains(permission)
        }

        return permissions.contains(permission)
    }

    func getRatRepresenting (rescue: LocalRescue) -> Rat? {
        guard let apiData = self.associatedAPIData, let user = apiData.user else {
            return nil
        }

        var rats = apiData.ratsBelongingTo(user: user)
        rats = rats.filter({
            $0.attributes.platform.value == rescue.platform
        })

        rats.sort(by: {
            self.nickname.levenshtein($0.attributes.name.value) > self.nickname.levenshtein($1.attributes.name.value)
        })

        return rats.first
    }

    func hostPermissions () -> [AccountPermission] {
        if self.hostmask.hasSuffix("i.see.all")
            || self.hostmask.hasSuffix("netadmin.fuelrats.com")
            || self.hostmask.hasSuffix("admin.fuelrats.com") {
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
                .RescueWriteOwn
            ]
        }

        if self.hostmask.hasSuffix("overseer.fuelrats.com") || self.hostmask.hasSuffix("techrat.fuelrats.com") {
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
                .RescueWriteOwn
            ]
        }

        if self.hostmask.hasSuffix("rat.fuelrats.com") {
            return [
                .UserReadOwn,
                .UserWriteOwn,
                .RatReadOwn,
                .RatWriteOwn,
                .RescueRead,
                .RescueReadOwn,
                .RescueWriteOwn
            ]
        }

        if self.hostmask.hasSuffix("recruit.fuelrats.com") {
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
