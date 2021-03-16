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


enum AllowedCommandDestination {
    case Channel
    case PrivateMessage
    case All
}

typealias BotCommandFunction = (IRCBotCommand) -> Void
@propertyWrapper struct BotCommand {
    var wrappedValue: BotCommandFunction
    
    init (
        wrappedValue value: @escaping BotCommandFunction,
        _ commands: [String],
        _ body: [CommandBody] = [],
        category: HelpCategory?,
        description: String,
        permission: AccountPermission? = nil,
        allowedDestinations: AllowedCommandDestination = .All
    ) {
        self.wrappedValue = value
        
        var maxParameters: Int? = body.parameters.count
        var lastIsContinious = false
        if case .param(_, _, let type, _) = body.last {
            if type == .continuous {
                lastIsContinious = true
            } else if type == .multiple {
                maxParameters = nil
            }
        }
        

        let declaration = IRCBotCommandDeclaration(
            commands: commands,
            minParameters: body.requiredParameters.count,
            onCommand: self.wrappedValue,
            maxParameters: maxParameters,
            lastParameterIsContinous: lastIsContinious,
            options: body.options,
            namedOptions: body.namedOptions,
            category: category,
            description: description,
            paramText: body.paramText,
            example: body.example,
            permission: permission,
            allowedDestinations: allowedDestinations
        )

        MechaSqueak.commands.append(declaration)
    }
}

struct IRCBotCommandDeclaration {
    let commands: [String]
    let minimumParameters: Int
    let maximumParameters: Int?
    let options: OrderedSet<Character>
    let namedOptions: OrderedSet<String>
    let permission: AccountPermission?
    let lastParameterIsContinous: Bool
    let allowedDestinations: AllowedCommandDestination
    let category: HelpCategory?
    let description: String
    var paramText: String?
    var example: String?

    var onCommand: BotCommandFunction?

    init (
        commands: [String],
        minParameters: Int,
        onCommand: BotCommandFunction?,
        maxParameters: Int? = nil,
        lastParameterIsContinous: Bool = false,
        options: OrderedSet<Character> = [],
        namedOptions: OrderedSet<String> = [],
        category: HelpCategory?,
        description: String,
        paramText: String? = nil,
        example: String? = nil,
        permission: AccountPermission? = nil,
        allowedDestinations: AllowedCommandDestination = .All
    ) {
        self.commands = commands
        self.minimumParameters = minParameters
        self.maximumParameters = maxParameters
        self.options = options
        self.namedOptions = namedOptions
        self.lastParameterIsContinous = lastParameterIsContinous
        self.permission = permission
        self.onCommand = onCommand
        self.allowedDestinations = allowedDestinations
        self.category = category
        self.description = description
        self.paramText = paramText
        self.example = example
    }

    func usageDescription (command: IRCBotCommand?) -> String {
        var usage = "!" + (command?.command ?? self.commands[0])

        if self.options.count > 0 {
            usage += " [-\(String(self.options))]"
        }

        if self.namedOptions.count > 0 {
            usage += " " + Array(self.namedOptions).map({ "[--\($0)]" }).joined(separator: " ")
        }

        if let paramText = self.paramText {
            usage += " \(paramText)"
        }
        return usage
    }

    func exampleDescription (command: IRCBotCommand?) -> String {
        return "!\(command?.command ?? self.commands[0]) \(self.example ?? "")"
    }

    var isDispatchingCommand: Bool {
        return self.category == .board && (self.permission == .RescueWrite || self.permission == .RescueWriteOwn)
    }
}



@propertyWrapper struct EventListener<T: NotificationDescriptor> {
    var wrappedValue: (T.Payload) -> Void
    let token: NotificationToken

    init (wrappedValue value: @escaping (T.Payload) -> Void) {
        self.wrappedValue = value
        self.token = NotificationCenter.default.addObserver(descriptor: T(), using: self.wrappedValue)
    }
}
