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
import NIO

class BoardAssignCommands: IRCBotModule {
    var name: String = "Assign Commands"
    required init(_ moduleManager: IRCBotModuleManager) {
        moduleManager.register(module: self)
    }

    @AsyncBotCommand(
        ["go", "assign", "add"],
        [.options(["a", "f"]), .argument("carrier"), .param("case id/client", "4"), .param("rats", "SpaceDawg StuffedRat", .multiple, .optional)],
        category: .board,
        description: "Add rats to the rescue and instruct the client to add them as friends.",
        permission: .DispatchWrite,
        allowedDestinations: .Channel
    )
    var didReceiveAssignCommand = { command in
        let message = command.message
        
        let force = command.forceOverride
        let carrier = command.has(argument: "carrier")

        // Find case by rescue ID or client name
        guard let (_, rescue) = await BoardCommands.assertGetRescueId(command: command) else {
            return
        }
        var command = command
        if command.locale.identifier == "auto" {
            command.locale = rescue.clientLanguage ?? Locale(identifier: "en-GB")
        }

        // Disallow assigns on rescues without a platform set
        guard let platform = rescue.platform else {
            command.message.error(key: "board.assign.noplatform", fromCommand: command)
            return
        }
        
        var params = command.parameters.count > 0 ? Array(command.parameters[1...]) : []

        var assigns: [Result<AssignmentResult, RescueAssignError>] = []
        for param in params {
            assigns.append(await rescue.assign(param, fromChannel: command.message.destination, force: force, carrier: carrier))
        }
        try? rescue.save(command)
        
        _ = sendAssignMessages(assigns: assigns, forRescue: rescue, fromCommand: command)

    }

    @AsyncBotCommand(
        ["gofr", "assignfr", "frgo"],
        [.options(["a", "f"]),  .argument("carrier"), .param("case id/client", "4"), .param("rats", "SpaceDawg StuffedRat", .multiple, .optional)],
        category: .board,
        description: "Add rats to the rescue and instruct the client to add them as friends, also inform the client how to add friends.",
        permission: .DispatchWrite,
        allowedDestinations: .Channel
    )
    var didReceiveAssignWithInstructionsCommand = { command in
        let message = command.message
        if command.command == "f" {
          command.message.replyPrivate(message: "Warning: !f was added by accident and will be removed in a future update. It is recommended that you start using !gofr.")
        }
        
        let force = command.forceOverride
        let carrier = command.has(argument: "carrier")

        // Find case by rescue ID or client name
        guard let (_, rescue) = await BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        var command = command
        if command.locale.identifier == "auto" {
            command.locale = rescue.clientLanguage ?? Locale(identifier: "en-GB")
        }

        // Disallow assigns on rescues without a platform set
        guard let platform = rescue.platform else {
            command.message.error(key: "board.assign.noplatform", fromCommand: command)
            return
        }
        
        var params = command.parameters.count > 0 ? Array(command.parameters[1...]) : []
        
        var assigns: [Result<AssignmentResult, RescueAssignError>] = []
        for param in params {
            assigns.append(await rescue.assign(param, fromChannel: command.message.destination, force: force, carrier: carrier))
        }
        try? rescue.save(command)

        let didSend = sendAssignMessages(assigns: assigns, forRescue: rescue, fromCommand: command)
        
        if didSend {
            var factName = rescue.codeRed && rescue.platform == .PC ? "\(platform.factPrefix)frcr" : "\(platform.factPrefix)fr"
            guard let fact = try? await Fact.getWithFallback(name: factName, forLocale: command.locale) else {
                return
            }
            
            let client = rescue.clientNick ?? rescue.client ?? ""
            message.reply(message: "\(client) \(fact.message)")
        }
    }

    @AsyncBotCommand(
        ["unassign", "deassign", "rm", "remove", "standdown"],
        [.param("case id/client", "4"), .param("rats", "SpaceDawg StuffedRat", .multiple)],
        category: .board,
        description: "Remove rats from the rescue",
        permission: .DispatchWrite,
        allowedDestinations: .Channel
    )
    var didReceiveUnassignCommand = { command in
        let message = command.message

        guard let (caseId, rescue) = await BoardCommands.assertGetRescueId(command: command) else {
            return
        }

        let unassigns = command.parameters[1...]

        var removed: [String] = []

        for unassign in unassigns {
            if let assignIndex = rescue.unidentifiedRats.firstIndex(where: {
                $0.lowercased() == unassign.lowercased()
            }) {
                rescue.unidentifiedRats.remove(at: assignIndex)
                removed.append(unassign)
                continue
            } else if
                let nick = message.destination.member(named: unassign),
                let apiData = nick.associatedAPIData,
                let user = apiData.user {
                var rats = apiData.ratsBelongingTo(user: user).filter({ rat in
                    return rescue.rats.contains(where: {
                        $0.id.rawValue == rat.id.rawValue
                    })
                })

                if rats.count == 0 {
                    continue
                }

                let nickname = unassign.lowercased()
                rats.sort(by: { nickname.levenshtein($0.attributes.name.value.lowercased()) < nickname.levenshtein($1.attributes.name.value.lowercased()) })
                let rat = rats[0]

                if let ratIndex = rescue.rats.firstIndex(of: rat) {
                    rescue.rats.remove(at: ratIndex)
                    removed.append(rat.attributes.name.value)
                    continue
                }
            } else if
                let ratIndex = rescue.rats.firstIndex(where: { $0.attributes.name.value.lowercased() == unassign.lowercased() })
            {
                removed.append(rescue.rats[ratIndex].attributes.name.value)
                rescue.rats.remove(at: ratIndex)
                continue
            }
            
            command.message.reply(key: "board.unassign.notassigned", fromCommand: command, map: [
                "rats": unassign,
                "caseId": caseId
            ])
        }

        guard removed.count > 0 else {
            return
        }
        
        try? rescue.save(command)
        let unassignedRats = removed.joined(separator: ", ")
        command.message.reply(key: "board.unassign.removed", fromCommand: command, map: [
            "caseId": caseId,
            "rats": unassignedRats
        ])
    }
    
    static func sendAssignMessages (assigns: [Result<AssignmentResult, RescueAssignError>], forRescue rescue: Rescue, fromCommand command: IRCBotCommand) -> Bool {
        let includeExistingAssigns = command.options.contains("a")
        let carrier = command.has(argument: "carrier")
        
        let failedAssigns = assigns.compactMap({ assign -> RescueAssignError? in
            if case let .failure(result) = assign {
                return result
            }
            return nil
        })
        
        if failedAssigns.count > 0 {
            var errorMessage = "\(failedAssigns.count) rats failed to assign: "
            let notFound = failedAssigns.compactMap({ assign -> String? in
                if case let .notFound(rat) = assign {
                    return rat
                }
                return nil
            })
            if notFound.count > 0 {
                errorMessage += "\(notFound.joined(separator: ", ")) was not found in the channel. "
            }
            
            let invalid = failedAssigns.compactMap({ assign -> String? in
                if case let .invalid(rat) = assign {
                    return rat
                }
                return nil
            })
            if invalid.count > 0 {
                errorMessage += "\(invalid.joined(separator: ", ")) as they are not a fuel rat. "
            }
            
            let unidentified = failedAssigns.compactMap({ assign -> String? in
                if case let .unidentified(rat) = assign {
                    return rat
                }
                return nil
            })
            if unidentified.count > 0 {
                if rescue.platform == .PC {
                    if rescue.odyssey {
                        errorMessage += "\(unidentified.joined(separator: ", ")) does not have a valid CMDR for \(rescue.platform.ircRepresentable) (\(IRCFormat.color(.Orange, "Odyssey")))"
                    } else {
                        errorMessage += "\(unidentified.joined(separator: ", ")) does not have a valid CMDR for \(rescue.platform.ircRepresentable) (\(IRCFormat.color(.LightGrey, "Horizons")))"
                    }
                } else {
                    errorMessage += "\(unidentified.joined(separator: ", ")) does not have a valid CMDR for \(rescue.platform.ircRepresentable)"
                }
            }
            
            let jumpCallConflicts = failedAssigns.compactMap({ assign -> String? in
                if case let .jumpCallConflict(rat) = assign {
                    return rat.name
                }
                return nil
            })
            if jumpCallConflicts.count > 0 {
                errorMessage += "\(jumpCallConflicts.joined(separator: ", ")) called for a different case and not this one. "
            }
            command.message.reply(message: errorMessage)
            
            let blacklisted = failedAssigns.compactMap({ assign -> String? in
                if case let .blacklisted(rat) = assign {
                    return rat
                }
                return nil
            })
            if blacklisted.count > 0 {
                command.message.error(key: "board.assign.banned", fromCommand: command, map: [
                                "rats": blacklisted.joined(separator: ", ")
                ])
            }
        }
            
        
        let successfulAssigns = assigns.compactMap({ assign -> AssignmentResult? in
            if case let .success(result) = assign {
                return result
            }
            return nil
        })
        
        if successfulAssigns.count > 0 || includeExistingAssigns || assigns.count == 0 {
            let duplicates = successfulAssigns.compactMap({ assign -> AssignmentResult? in
                switch assign {
                case .duplicate(_), .unidentifiedDuplicate(_):
                    return assign
                    
                default:
                    return nil
                }
            })
            
            var names = successfulAssigns.compactMap({ assign -> String? in
                switch assign {
                case .assigned(let rat):
                    return rat.name
                case .unidentified(let unidentifiedRat):
                    return unidentifiedRat
                case .duplicate(let rat):
                    return rat.name
                case .unidentifiedDuplicate(let unidentifiedRat):
                    return unidentifiedRat
                }
            })
            
            if assigns.count == 0 || includeExistingAssigns {
                names = rescue.rats.map({
                    $0.name
                }) + rescue.unidentifiedRats
            }
            guard names.count > 0 else {
                return false
            }
            
            var format = rescue.codeRed ? "board.assign.gocr" : "board.assign.go"
            if carrier {
                format = "board.assign.carrier"
            }
            
            if duplicates.count > 0 {
                command.message.reply(key: "board.assign.duplicates", fromCommand: command)
            }
            command.message.reply(key: format, fromCommand: command, map: [
                            "client": rescue.clientNick!,
                            "rats": names.map({
                                "\"\($0)\""
                            }).joined(separator: ", "),
                            "count": names.count
                        ])
            return true
        }
        return false
    }
}
