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
@preconcurrency import IRCKit

extension IRCBotCommand {
    /// Builds a command for programmatic (AI) dispatch. Parameters are bound positionally with no
    /// options or arguments, so model-supplied text can never be re-lexed into an option like
    /// `-f`/`--force` — the lexer injection path (B3) is closed by construction.
    init(toolInvocation command: String, parameters: [String], message: IRCPrivateMessage, locale: Locale) {
        self.id = UUID()
        self.command = command
        self.parameters = parameters
        self.parameterQuoted = parameters.map { _ in false }
        self.options = []
        self.arguments = [:]
        self.locale = locale
        self.message = message
    }
}

/// Tier-2 tool: lets the model invoke a read-only IRC command on the user's behalf. The command
/// replies through its normal path, as the invoking user, so cooldowns/destinations are enforced
/// natively by `handleIncomingCommand`. Permission is gated up front here too (parity with the
/// command's own `permission`) so the model can't do anything the user couldn't, and a lack of
/// permission is refused cleanly to the model instead of surfacing in-channel. Only commands the
/// author opted in with `allowTool` (and which are not rescue-writing dispatch commands) are permitted.
enum CommandDispatchTool {
    /// Built fresh on access so the allow-list in the description reflects the live command registry:
    /// every command flagged `allowTool` becomes discoverable to the model automatically, with no
    /// second place to update when a command is added or its flag flipped.
    static var tool: AITool {
        AITool(
            name: "run_command",
            description: """
            Invoke a read-only MechaSqueak IRC command on the user's behalf; it replies in the \
            channel as usual, as if the user had typed it. Use this for live data or calculations a \
            command already provides. Pass arguments as plain positional values with no leading \
            dashes. The only commands you may run (name: what it does) are: \
            \(dispatchableCommandList()). Anything else is refused.
            """,
            inputSchema: .objectSchema(
                properties: [
                    ("command", .stringSchema("The command name without the ! prefix, e.g. \"unfiled\"")),
                    ("args", .arraySchema("Positional string arguments, no option flags"))
                ],
                required: ["command"])
        ) { input, context in
            guard let message = context.message else {
                return ToolOutput.error("no invocation context available")
            }
            guard let name = input["command"]?.stringValue?
                .trimmingCharacters(in: .whitespaces).lowercased(), name.isEmpty == false else {
                return ToolOutput.error("missing 'command'")
            }
            let args = (input["args"]?.arrayValue ?? []).compactMap { $0.stringValue }

            // Positional values only: reject anything that looks like an option flag or carries quote /
            // shell sigils, so an argument can never be re-interpreted as a flag (M5/B3).
            if args.contains(where: CommandDispatchTool.looksUnsafe) {
                return ToolOutput.error("arguments may not contain option flags or quotes")
            }

            guard let declaration = MechaSqueak.commands.first(where: { $0.commands.contains(name) }) else {
                return ToolOutput.error("unknown command '\(name)'")
            }
            guard CommandDispatchTool.isDispatchable(declaration) else {
                return ToolOutput.error("command '\(name)' is not available to the assistant")
            }
            // Gate the AI path by the command's own permission, so run_command never lets the model do
            // something the user couldn't do by typing it — and refuse cleanly to the model here rather
            // than letting the command emit an in-channel "no permission" reply in the user's name.
            guard CommandDispatchTool.isPermitted(
                declaration, hasPermission: { message.user.hasPermission(permission: $0) }) else {
                return ToolOutput.error("you do not have permission to use '\(name)'")
            }

            let botCommand = IRCBotCommand(
                toolInvocation: name, parameters: args, message: message, locale: context.locale)
            await IRCBotModuleManager.handleIncomingCommand(ircBotCommand: botCommand)
            return deliveredResult
        }
    }

    /// Success sentinel returned when a command was dispatched. The pipeline treats this as terminal:
    /// the command has already replied to the user with the complete answer, so the assistant ends
    /// its turn silently rather than restating or (worse) fabricating a parallel answer it can't see.
    static let deliveredResult =
        "The command has replied to the user directly with the complete answer. Do not restate, "
        + "summarize, or add to it, and never state figures you did not receive."

    /// The allow-list rendered for the tool description so the model can discover exactly which
    /// commands it may dispatch, each with its authored description and a concrete example of its
    /// arguments — never just a bare name whose meaning or argument format it would have to guess.
    static func dispatchableCommandList() -> String {
        dispatchableList(from: MechaSqueak.commands)
    }

    /// Pure formatter for `dispatchableCommandList` (registry injected for testability). Emits
    /// `name <example-args>: description` entries sorted by name, using the command's own concrete
    /// positional example (e.g. `sctime 2500ls`) so the model gets the argument format, not just an
    /// abstract placeholder. The example is omitted for commands that take no parameters.
    static func dispatchableList(from commands: [IRCBotCommandDeclaration]) -> String {
        let entries = commands
            .filter(isDispatchable)
            .compactMap { declaration -> String? in
                guard let name = declaration.commands.first else { return nil }
                let example = declaration.parameters.example
                let signature = example.isEmpty ? "" : " \(example)"
                return "\(name)\(signature): \(declaration.description)"
            }
            .sorted()
        return entries.isEmpty ? "(none currently available)" : entries.joined(separator: "; ")
    }

    /// A command may be AI-dispatched only if the author opted it in (`allowTool`) and it is not a
    /// rescue-writing dispatch command — the second check is a backstop against a mis-tag.
    static func isDispatchable(_ declaration: IRCBotCommandDeclaration) -> Bool {
        declaration.allowTool && declaration.isDispatchingCommand == false
    }

    /// Convenience overload for resolving + gating by name against a command set (used in tests).
    static func isDispatchable(_ name: String, in commands: [IRCBotCommandDeclaration]) -> Bool {
        guard let declaration = commands.first(where: { $0.commands.contains(name.lowercased()) }) else {
            return false
        }
        return isDispatchable(declaration)
    }

    /// Whether the invoking user may AI-dispatch this command: permission parity with the interactive
    /// command. A command with no `permission` is open to anyone (matching its interactive behavior);
    /// otherwise the user must hold that permission. `hasPermission` is injected for testability.
    static func isPermitted(
        _ declaration: IRCBotCommandDeclaration, hasPermission: (AccountPermission) -> Bool
    ) -> Bool {
        guard let permission = declaration.permission else { return true }
        return hasPermission(permission)
    }

    static func looksUnsafe(_ argument: String) -> Bool {
        if argument.hasPrefix("-") { return true }
        return argument.contains { "\"'`$;|&<>".contains($0) }
    }
}
