/*
 Copyright 2025 The Fuel Rats Mischief

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
import HTMLKit

class Translate: IRCBotModule {
    var name: String = "Translation Commands"
    static var clientTranslationSubscribers: [String: ClientTranslateSubscription] = [:]

    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @BotCommand(
        ["translate", "t"],
        [.param("message", "Help is on the way!", .continuous)],
        category: .utility,
        description: "Translate a message to another language",
        tags: ["google", "deepl"],
        helpLocale: "fr",
        cooldown: .seconds(30),
        helpExtra: {
            return "Consult https://llm-translate.com/Supported%20languages/gpt-4o/ for a list of valid language codes"
        },
        helpView: {
            HTMLKit.Div {
                "Consult "
                Anchor("this page")
                    .reference("https://llm-translate.com/Supported%20languages/gpt-4o/")
                    .target(.blank)
                " for a list of valid language codes"
            }
        }
    )
    var didReceiveTranslateCommand = { command in
        if command.locale.englishDescription == "unknown locale" {
            command.message.error(key: "translate.locale", fromCommand: command, map: [
                "locale": command.locale.identifier
            ])
            return
        }
        do {
            if let translation = try await Translate.translate(
                command.parameters[0], locale: command.locale) {
                command.message.reply(message: translation)
            }
        } catch {
            command.error(error)
        }
    }

    @BotCommand(
        ["tcase", "tc"],
        [.param("case id/client", "4"), .param("message", "Help is on the way!", .continuous)],
        category: .utility,
        description: "Translates a message to the client's language and replies in the rescue channel as you",
        tags: ["google", "deepl", "client", "rescue"],
        allowedDestinations: .PrivateMessage
    )
    var didReceiveTranslateCaseCommand = { command in
        guard let (caseId, rescue) = await board.findRescue(
            withCaseIdentifier: command.parameters[0], includingRecentlyClosed: true) else {
            command.message.error(
                key: "board.casenotfound", fromCommand: command,
                map: [
                    "caseIdentifier": command.parameters[0]
            ])
            return
        }
        var locale = rescue.clientLanguage ?? command.locale
        if command.locale.languageCode != "en" {
            locale = command.locale
        }
        if locale.englishDescription == "unknown locale" {
            command.message.error(key: "translate.locale", fromCommand: command, map: [
                "locale": locale.identifier
            ])
            return
        }
        let target = rescue.clientNick ?? rescue.client ?? ""

        do {
            if let translation = try await Translate.translate(
                command.parameters[1], locale: locale) {
                let destination = rescue.channel ?? mecha.rescueChannel
                command.message.client.send("MSGAS", parameters: [
                    command.message.raw.sender?.nickname ?? "",
                    destination?.name ?? "",
                    "\(target): \(translation)"
                ])
                let contents = "<\(command.message.user.nickname)> \(command.parameters[1])"
                for (subscriber, subType) in Translate.clientTranslationSubscribers {
                    switch subType {
                        case .Notice:
                            command.message.client.send("CNOTICE", parameters: [
                                subscriber,
                                destination?.name ?? "",
                                contents
                            ])

                        case .PrivateMessage:
                        command.message.client.sendMessage(toTarget: subscriber, contents: contents)
                    }
                }
            }
        } catch {
            command.error(error)
        }
    }
    
    @BotCommand(
        ["translateme", "tme"],
        [
            .param("channel", "#fuelrats"),
            .param("language code", "fr"),
            .param("message", "Help is on the way!", .continuous)
        ],
        category: .utility,
        description: "Translate a message to another language and sends the message to a channel as you",
        tags: ["google", "deepl"],
        allowedDestinations: .PrivateMessage,
        cooldown: .seconds(30),
        helpExtra: {
            return "Consult https://llm-translate.com/Supported%20languages/gpt-4o/ for a list of valid language codes"
        },
        helpView: {
            HTMLKit.Div {
                "Consult "
                Anchor("this page")
                    .reference("https://llm-translate.com/Supported%20languages/gpt-4o/")
                    .target(.blank)
                " for a list of valid language codes"
            }
        }
    )
    var didReceiveTranslateMeCommand = { command in
        var channelName = command.parameters[0]
        var locale = Locale(identifier: command.parameters[1])
        var message = command.parameters[2]
        
        guard let channel = command.message.client.channels.first(where: {
            return $0.name.lowercased() == channelName.lowercased()
        }) else {
            command.message.error(key: "translate.destination", fromCommand: command, map: [
                "channel": channelName
            ])
            return
        }
        guard channel.member(fromSender: command.message.raw.sender!) != nil else {
            command.message.error(key: "translate.destination", fromCommand: command, map: [
                "channel": channelName
            ])
            return
        }
        
        if locale.englishDescription == "unknown locale" {
            command.message.error(key: "translate.locale", fromCommand: command, map: [
                "locale": locale.identifier
            ])
            return
        }
        
        do {
            if let translation = try await Translate.translate(
                message, locale: locale) {
                command.message.client.send("MSGAS", parameters: [
                    command.message.raw.sender?.nickname ?? "",
                    channel.name,
                    translation
                ])
                let contents = "<\(command.message.user.nickname)> \(message)"
                notifyTranslateSubscribers(client: command.message.client, channel: channelName, contents: contents)
            }
        } catch {
            command.error(error)
        }
    }

    @BotCommand(
        ["transsub", "tsub"],
        [.param("message type", "notice", .standard, .optional)],
        category: .utility,
        description:
            "Subscribe to automatic translations of client messages by either private message, or notice",
        tags: ["google", "deepl", "notice", "subscription", "sub"],
        permission: .UserWriteOwn,
        allowedDestinations: .PrivateMessage
    )
    var didReceiveTranslateSubscribeCommand = { command in
        guard let subscriptionType = ClientTranslateSubscription(rawValue: command.param1 ?? "notice")
        else {
            command.message.error(
                key: "transsub.subtype", fromCommand: command, map: ["type": command.parameters[0]])
            return
        }

        guard let user = command.message.user.associatedAPIData?.user else {
            command.message.error(key: "transsub.nouser", fromCommand: command)
            return
        }

        do {
            var data = user.attributes.data.value
            data.clientTranslateSubscription = subscriptionType
            _ = try await user.updateUserData(dataObject: data)
            Translate.clientTranslationSubscribers[command.message.user.nickname] = subscriptionType
            command.message.reply(key: "transsub.subbed", fromCommand: command)
        } catch {
            debug(String(describing: error))
        }
    }

    @BotCommand(
        ["transunsub", "tunsub"],
        category: .utility,
        description:
            "Subscribe to automatic translations of client messages by either private message, or notice",
        tags: ["google", "deepl", "notice", "subscription", "sub"],
        permission: .UserWriteOwn,
        allowedDestinations: .PrivateMessage
    )
    var didReceiveTranslateUnsubscribeCommand = { command in
        guard let user = command.message.user.associatedAPIData?.user else {
            command.message.error(key: "transsub.nouser", fromCommand: command)
            return
        }

        var data = user.attributes.data.value
        data.clientTranslateSubscription = nil
        _ = try? await user.updateUserData(dataObject: data)
        Translate.clientTranslationSubscribers[command.message.user.nickname] = nil
        command.message.reply(key: "transsub.unsubbed", fromCommand: command)
    }

    static func translate(_ text: String, locale: Foundation.Locale? = nil) async throws -> String? {
        var prompt = OpenAIMessage(
            role: .system,
            content:
                """
                Translate to English only, no extra text or quotes,
                if it's already in english output 'no translation'.
                Context: Fuel Rats bot helping stranded Elite Dangerous players.
                """
        )
        if let locale = locale {
            let languageText = locale.englishDescription
            prompt = OpenAIMessage(
                role: .system,
                content:
                    """
                    Translate to \(languageText) only, no extra text or quotes,
                    if it's already in english output 'no translation'.
                    Context: Fuel Rats bot helping stranded Elite Dangerous players.
                    """
            )
        }
        let message = OpenAIMessage(role: .user, content: text)

        let request = OpenAIRequest(
            messages: [prompt, message], model: "gpt-4o", temperature: 0.2, maxTokens: nil)
        let result = try await OpenAI.request(params: request)
        let translation = result.choices.first?.message.content
        let translationStripped = translation?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
            .lowercased()
        if translationStripped?.count == 0
            || translationStripped == "no translation" {
            return nil
        }
        return result.choices.first?.message.content
    }

    @AsyncEventListener<IRCChannelMessageNotification>
    var onChannelMessage = { channelMessage in
        guard channelMessage.raw.messageTags["batch"] == nil else {
            // Do not interpret commands from playback of old messages
            return
        }
        guard let (caseId, rescue) = await board.findRescue(
            withCaseIdentifier: channelMessage.user.nickname, includingRecentlyClosed: true) else {
            return
        }
        guard rescue.clientLanguage?.languageCode != "en" else {
            return
        }

        if let translation = try? await Translate.translate(channelMessage.message) {
            let contents = "<\(channelMessage.user.nickname)> \(translation)"
            notifyTranslateSubscribers(client: channelMessage.client, channel: channelMessage.destination.name, contents: contents)
        }
    }
}

func notifyTranslateSubscribers (client: IRCClient, channel: String, contents: String) {
    for (subscriber, subType) in Translate.clientTranslationSubscribers {
        switch subType {
            case .Notice:
                client.send("CNOTICE", parameters: [
                    subscriber,
                    channel,
                    contents
                ])

            case .PrivateMessage:
                client.sendMessage(toTarget: subscriber, contents: contents)
        }
    }
}

enum ClientTranslateSubscription: String, Codable {
    case PrivateMessage = "pm"
    case Notice = "notice"
}
