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

class RatAnniversary: IRCBotModule {
    var name: String = "Rat Anniversary"
    static var birthdayAnnounced = Set<UUID>()

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @EventListener<IRCChannelMessageNotification>
    var onChannelMessage = { channelMessage in
        guard channelMessage.raw.messageTags["batch"] == nil && channelMessage.destination == mecha.reportingChannel else {
            // Do not interpret commands from playback of old messages or in secret channels
            return
        }

        if
            let apiData = channelMessage.user.associatedAPIData,
            let apiUser = apiData.user,
            let joinDate = apiData.joinDate
        {
            guard birthdayAnnounced.contains(apiUser.id.rawValue) == false else {
                return
            }
            let joinComponents = Calendar.current.dateComponents([.day, .month, .year], from: joinDate)
            let todayComponents = Calendar.current.dateComponents([.day, .month, .year, .hour], from: Date())
            guard todayComponents.hour! > 6 else {
                return
            }
            let years = todayComponents.year! - joinComponents.year!

            if joinComponents.day! == todayComponents.day! && joinComponents.month! == todayComponents.month!, years > 0 {
                mecha.reportingChannel?.send(key: "birthday", map: [
                    "name": channelMessage.user.nickname,
                    "years": years
                ])
                birthdayAnnounced.insert(apiUser.id.rawValue)
            }
        }
    }
}
