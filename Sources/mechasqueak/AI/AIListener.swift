/*
 Copyright 2026 The Fuel Rats Mischief

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

/// Registers the always-listening AI surface: a name-trigger listener on all channels the bot is
/// in, plus a private-message listener. Both defer to the global `aiService`; if it is nil (tokens
/// unset) the handlers are inert. The bot's own messages arrive as echo notifications, not channel
/// messages, so they never re-enter here.
class AIListener: IRCBotModule {
    var name = "AI Assistant"

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @AsyncEventListener<IRCChannelMessageNotification>
    var onChannelMessage = { channelMessage in
        guard let service = aiService else { return }
        // Skip playback of old messages (batch) and secret channels.
        guard channelMessage.raw.messageTags["batch"] == nil,
            channelMessage.destination.channelModes.keys.contains(.isSecret) == false else {
            return
        }
        // Record every message for scrollback context, then act only on name-triggers.
        await service.scrollback.record(channelMessage)
        await service.handleChannelMessage(channelMessage)
    }

    @AsyncEventListener<IRCPrivateMessageNotification>
    var onPrivateMessage = { privateMessage in
        guard let service = aiService else { return }
        guard privateMessage.raw.messageTags["batch"] == nil else { return }
        await service.handlePrivateMessage(privateMessage)
    }
}
