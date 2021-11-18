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

class ShortenURLCommands: IRCBotModule {
    var name: String = "Shorten URL Commands"
    static var ongoingShortenUrls: [String: String] = [:]

    @AsyncBotCommand(
        ["shorten", "short", "shortener"],
        [.param("url", "https://www.youtube.com/watch?v=dQw4w9WgXcQ"), .param("custom link", "importantinfo", .standard, .optional)],
        category: .utility,
        description: "Create a t.fuelr.at short url to another url, optionally set a custom url rather than a random.",
        permission: .RescueWriteOwn,
        allowedDestinations: .PrivateMessage
    )
    var didReceiveShortenURLCommand = { (command: IRCBotCommand) in
        var keyword: String?
        if command.parameters.count > 1 {
            keyword = command.parameters[1].lowercased()
        }
        
        var longUrl = command.parameters[0]
        
        if command.message.destination.isPrivateMessage {
            ongoingShortenUrls[command.message.user.nickname] = longUrl
            
            print("starting wait")
            await Task.sleep(1_000_000_000)
            print("ending wait")
            longUrl = ongoingShortenUrls[command.message.user.nickname] ?? longUrl
            ongoingShortenUrls.removeValue(forKey: command.message.user.nickname)
        }
        
        print(longUrl)
        guard let url = URL(string: longUrl.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed)!) else {
            command.message.error(key: "shorten.invalidurl", fromCommand: command)
            return
        }
        
        do {
            let response = try await URLShortener.shorten(url: url, keyword: keyword)
            
            command.message.reply(key: "shorten.shortened", fromCommand: command, map: [
                "url": response.shorturl,
                "title": response.title.prefix(160)
            ])
        } catch {
            command.message.error(key: "shorten.error", fromCommand: command)
        }
    }
    
    @EventListener<IRCPrivateMessageNotification>
    var onPrivateMessage = { privateMessage in
        if var url = ongoingShortenUrls[privateMessage.user.nickname] {
            print("appending url")
            url += privateMessage.message
            ongoingShortenUrls[privateMessage.user.nickname] = url
        }
    }

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }
}
