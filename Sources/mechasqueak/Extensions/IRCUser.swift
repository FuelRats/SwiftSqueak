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
            self.nickname.levenshtein($0.attributes.name.value) < self.nickname.levenshtein($1.attributes.name.value)
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
                .RescueWriteOwn,
                .TwitterWrite,
                .DispatchRead
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
                .RescueWriteOwn,
                .TwitterWrite,
                .DispatchRead
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
                .RescueWriteOwn,
                .DispatchRead
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
