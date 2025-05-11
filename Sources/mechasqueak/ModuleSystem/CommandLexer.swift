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
import Regex

private let ircFormattingExpression = "(\\x03([0-9]{1,2})?(,[0-9]{1,2})?|\\x02|\\x1F|\\x1E|\\x11)"
    .r!

extension String {
    var strippingIRCFormatting: String {
        return ircFormattingExpression.replaceAll(in: self, with: "")
    }
}

struct IRCBotCommand {
    var id: UUID
    var command: String
    var parameters: [String]
    var parameterQuoted: [Bool]
    var options: OrderedSet<Character>
    var arguments: [String: String?]
    var locale: Locale
    let message: IRCPrivateMessage

    init?(from text: String, inMessage privateMessage: IRCPrivateMessage) {
        self.id = UUID()
        let message = text.strippingIRCFormatting.trimmingCharacters(in: .whitespacesAndNewlines)

        var lexer = Lexer(body: message)
        do {
            var tokens = try lexer.lex()
            tokens = tokens.filter({
                if case .Delimiter = $0 {
                    return false
                }
                return true
            })

            guard tokens.count > 0, case let .Command(commandToken) = tokens[0] else {
                return nil
            }

            self.message = privateMessage
            self.command = commandToken.identifier
            self.locale = Locale(identifier: commandToken.languageCode ?? "en")

            let commandDefinition = MechaSqueak.commands.first(where: {
                $0.commands.contains(commandToken.identifier)
            })

            var arguments = [String: String?]()
            var options = OrderedSet<Character>()
            var parameters = [String]()
            var parameterQuoted = [Bool]()

            var tokenIndex = 0
            while tokenIndex < tokens.count {
                let currentToken = tokens[tokenIndex]

                switch currentToken {
                case .Argument(let argumentName):
                    guard let argumentDefinition = commandDefinition?.arguments[argumentName],
                        argumentDefinition != nil
                    else {
                        arguments.updateValue(nil, forKey: argumentName)
                        break
                    }
                    var params: [String] = []
                    while tokenIndex + 1 < tokens.count,
                        case .Parameter(let param, _) = tokens[tokenIndex + 1]
                    {
                        params.append(param)
                        tokenIndex += 1
                    }
                    arguments.updateValue(params.joined(separator: " "), forKey: argumentName)
                case .Option(let optionName):
                    options.append(optionName)

                case .Parameter(let param, let quoted):
                    parameters.append(param)
                    parameterQuoted.append(quoted)

                default:
                    break
                }
                tokenIndex += 1
            }

            self.arguments = arguments

            self.options = options
            self.parameters = parameters
            self.parameterQuoted = parameterQuoted
        } catch LexerError.noCommand {
            return nil
        } catch LexerError.invalidOption {
            return nil
        } catch {
            return nil
        }
    }

    init?(from channelMessage: IRCPrivateMessage) {
        let message = channelMessage.message
        self.init(from: message, inMessage: channelMessage)
    }

    init?(
        from channelMessage: IRCPrivateMessage,
        withIdentifier identifier: String,
        usage usageMessage: String,
        minParameters: Int = 0,
        maxParameters: Int? = nil
    ) {
        self.init(from: channelMessage)

        guard self.command == identifier.lowercased() else {
            return nil
        }

        if let maxParameters = maxParameters, self.parameters.count > maxParameters {
            channelMessage.reply(
                message: "Command was given too many parameters, usage: \(usageMessage)")
            return nil
        }

        if self.parameters.count < minParameters {
            channelMessage.reply(
                message: "Command was given too few parameters, usage: \(usageMessage)")
            return nil
        }
    }

    func has(argument: String) -> Bool {
        return self.arguments.keys.contains(argument.lowercased())
    }

    func argumentValue(for arg: String) -> String? {
        return self.arguments[arg] ?? nil
    }

    var isRepeatInvocation: Bool {
        let previousIncoation = IRCBotModuleManager.commandHistory.elements.reversed().first(
            where: {
                $0.id != self.id && $0.command == self.command && $0.parameters == self.parameters
                    && $0.message.user.nickname == self.message.user.nickname
            })
        return previousIncoation != nil
            && Date().timeIntervalSince(previousIncoation!.message.raw.time) < 30
    }

    var forceOverride: Bool {
        return self.options.contains("f") || self.arguments.keys.contains("force")
            || self.isRepeatInvocation
    }

    var param1: String? {
        self.parameters[safe: 0]
    }

    var param2: (String?, String?) {
        return (self.parameters[safe: 0], self.parameters[safe: 1])
    }

    var param3: (String?, String?, String?) {
        return (self.parameters[safe: 0], self.parameters[safe: 1], self.parameters[safe: 2])
    }

    var param4: (String?, String?, String?, String?) {
        return (
            self.parameters[safe: 0], self.parameters[safe: 1], self.parameters[safe: 2],
            self.parameters[safe: 3]
        )
    }

    var param5: (String?, String?, String?, String?, String?) {
        return (
            self.parameters[safe: 0], self.parameters[safe: 1], self.parameters[safe: 2],
            self.parameters[safe: 3], self.parameters[safe: 4]
        )
    }

    func error(_ error: Error) {
        debug(String(describing: error))
        self.message.error(key: "genericerror", fromCommand: self)
    }
}

enum Token {
    case Command(CommandToken)
    case Delimiter
    case Option(Character)
    case Argument(String)
    case Parameter(String, quoted: Bool)
}

enum LexerError: Error {
    case noCommand
    case invalidOption
    case invalidArgument
    case unknown(String)
}

struct Lexer {
    private static let identifierSet = CharacterSet.alphanumerics.union(["@"])
    private enum State {
        case Command
        case Parameters
        case ParsingOptions
    }

    private var state: State = .Command
    private var offset = 0
    private var tokens: [Token] = []
    private var current: String.Index
    var body: String

    init(body: String) {
        self.body = body
        self.current = body.startIndex
    }

    private mutating func nextToken() throws -> Token? {
        guard let current = self.peek() else { return nil }

        let next = self.peek(aheadBy: 1)
        let isIdentifier = current.unicodeScalars.allSatisfy({ Lexer.identifierSet.contains($0) })
        let nextIsIdentifier = next?.unicodeScalars.allSatisfy({ Lexer.identifierSet.contains($0) })

        switch (state, current, isIdentifier, next, nextIsIdentifier) {
        case (.Command, "!", _, _, true): return try lexCommand()
        case (.Parameters, " ", _, _, _): return delimit()
        case (.Parameters, "-", _, "-", _): return try lexArgument()
        case (.Parameters, "-", _, _, true):
            do {
                state = .ParsingOptions
                return delimit()
            }
        case (.ParsingOptions, _, true, _, _): return lexOption()
        case (.ParsingOptions, _, false, _, _):
            do {
                state = .Parameters
                return delimit()
            }
        case (.Parameters, _, _, _, _): return try lexParameter()
        case (.Command, _, _, _, _): throw LexerError.noCommand
        }
    }

    mutating func lex() throws -> [Token] {
        while let next = try self.nextToken() {
            tokens.append(next)
            offset += 1
        }
        return tokens
    }
    private mutating func delimit() -> Token {
        pop()
        return .Delimiter
    }

    private mutating func lexCommand() throws -> Token {
        let commandString = readWhile({ $0.isWhitespace == false })
        guard let command = CommandToken(fromString: commandString) else {
            throw LexerError.noCommand
        }
        state = .Parameters
        return Token.Command(command)
    }

    private mutating func lexArgument() throws -> Token {
        _ = readWhile({ $0 == "-" })
        if peek()?.isWhitespace != false {
            throw LexerError.invalidOption
        }
        return Token.Argument(readWhile({ $0.isWhitespace == false }).lowercased())
    }

    private mutating func lexOption() -> Token {
        let option = peek()
        pop()
        return Token.Option(option!)
    }

    private mutating func lexParameter() throws -> Token {
        if peek() == "`" {
            pop()
            let arg = readWhile({ $0 != "`" })
            guard arg.count > 0 else {
                throw LexerError.invalidArgument
            }
            pop()

            return Token.Parameter(arg, quoted: true)
        }
        if peek() == "\"" {
            pop()
            let arg = readWhile({ $0 != "\"" })
            guard arg.count > 0 else {
                throw LexerError.invalidArgument
            }
            pop()

            return Token.Parameter(arg, quoted: true)
        }
        return Token.Parameter(readWhile({ $0.isWhitespace == false }), quoted: false)
    }

    @discardableResult
    mutating func pop() -> Character? {
        guard current < body.endIndex else { return nil }
        defer { current = body.index(after: current) }
        return body[current]
    }

    mutating func readWhile(_ check: (Character) -> Bool) -> String {
        return String(readSliceWhile(pop: true, check))
    }

    mutating func peekWhile(_ check: (Character) -> Bool) -> String {
        return String(peekSliceWhile(check))
    }

    @discardableResult
    mutating func popWhile(_ check: (Character) -> Bool) -> Int {
        return readSliceWhile(pop: true, check).count
    }

    func peek(aheadBy idx: Int = 0) -> Character? {
        let peekIndex = body.index(current, offsetBy: idx)
        guard peekIndex < body.endIndex else { return nil }
        return body[peekIndex]
    }

    mutating private func readSliceWhile(pop: Bool, _ check: (Character) -> Bool) -> [Character] {
        var str = [Character]()
        str.reserveCapacity(512)
        while let next = peek() {
            guard check(next) else { return str }
            if pop { self.pop() }
            str.append(next)
        }
        return str
    }

    mutating private func peekSliceWhile(_ check: (Character) -> Bool) -> [Character] {
        var str = [Character]()
        str.reserveCapacity(512)
        var index = 0
        while let next = peek(aheadBy: index) {
            guard check(next) else { return str }
            str.append(next)
            index += 1
        }
        return str
    }
}

struct CommandToken {
    static let regex = "^(!)([A-Za-z0-9_]*)(?:-([A-Za-z]{2,}))?".r!

    let declaration: String
    let identifier: String
    let languageCode: String?

    init?(fromString token: String) {
        let match = CommandToken.regex.findFirst(in: token)!
        guard
            let declaration = match.group(at: 1),
            let identifier = match.group(at: 2)?.lowercased()
        else {
            return nil
        }

        self.declaration = declaration
        self.identifier = identifier
        self.languageCode = match.group(at: 3)?.lowercased()
    }
}
