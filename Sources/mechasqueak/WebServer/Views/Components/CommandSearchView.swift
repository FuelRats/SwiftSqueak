import HTMLKit

struct CommandSearchView: View {
    let commands: [IRCBotCommandDeclaration]

    var body: Content {
        Div {
            H2 {
                "\(commands.count) search results"
                
            }.class("section-heading")
            Div {
                for command in commands {
                    CommandView(command: command)
                }
            }
            .class("command-list")
        }
        .class("section command-section")
    }
}

struct CommandsListView: View {
    var body: Content {
        for category in HelpCategory.allCases {
            CommandSectionView(category: category)
        }
    }
}
