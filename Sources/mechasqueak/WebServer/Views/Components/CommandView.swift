import HTMLKit

struct CommandView: View {
    let command: IRCBotCommandDeclaration

    var body: Content {
        Article {
            H3 {
                Div {
                    "!" + command.commands[0]
                    for token in command.parameters {
                        CommandParameterComponent(token: token)
                    }
                    ShareAnchorView(value: command.commands[0].lowercased())
                    
                    if let groups = command.permission?.groups.sorted(by: {
                        $0.priority < $1.priority
                    }), !groups.isEmpty {
                        Div {
                            for group in groups {
                                CommandPermissionGroupView(group: group)
                            }
                        }.class("command-permission-groups")
                    }
                }
                .class("command-header")
            }
            
            if command.allowedDestinations == .PrivateMessage {
                Span {
                    "Private Message Only"
                }.class("destination-tag destination-tag-pm")
            } else if command.allowedDestinations == .Channel {
                Span {
                    "In Channel Only"
                }.class("destination-tag destination-tag-channel")
            }
            
            if !command.commands.dropFirst().isEmpty {
                Div {
                    "Aliases: " + command.commands.dropFirst().map { "!\($0)" }.joined(separator: ", ")
                }
                .class("command-aliases-inline")
            }

            Paragraph {
                command.description
            }
            
            if let helpView = command.helpView {
                helpView()
            } else {
                let commandIdentifier = "help.command.\(command.commands[0])"
                let fullDescription = lingo.localize(commandIdentifier, locale: "en-GB")
                if fullDescription != commandIdentifier {
                    Paragraph {
                        fullDescription
                    }
                }
                
                if let helpExtra = command.helpExtra {
                    Paragraph {
                        helpExtra()
                    }
                }
            }

            if !command.options.isEmpty {
                Div {
                    H4 { "Options:" }
                    UnorderedList {
                        for option in command.options {
                            let optionDescription = lingo.localize(
                                "help.command.\(command.commands[0]).\(option)", locale: "en-GB")
                            ListItem {
                                Div {
                                    " -\(option) "
                                }.class("command-options-option")
                                Div {
                                    optionDescription
                                }.class("command-options-description")
                            }
                        }
                    }
                }.class("command-options")
            }

            if !command.helpArguments.isEmpty {
                Div {
                    H4 { "Arguments:" }
                    UnorderedList {
                        for (name, valueDesc, _) in command.helpArguments {
                            
                            ListItem {
                                let optionDescription = lingo.localize(
                                    "help.command.\(command.commands[0]).\(name)", locale: "en-GB")
                                Span {
                                    " --\(name)"
                                }.class("command-arguments-argument")
                                if let value = valueDesc {
                                    Span {
                                        value
                                    }.class("command-parameter")
                                }
                                Span {
                                    optionDescription
                                }.class("command-arguments-description")
                            }
                        }
                    }
                }.class("command-arguments")
            }

            if !command.example.isEmpty {
                Div {
                    H4 { "Example:" }
                    Code {
                        "!\(command.commands[0]) \(command.example)"
                    }.class("command-example")
                }
            }
        }
        .id(command.commands[0].lowercased())
        .class("command")
    }
}
