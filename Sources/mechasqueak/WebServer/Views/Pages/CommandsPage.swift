import HTMLKit

struct CommandsPage: View {
    static let title = "Commands | MechaSqueak Docs"

    struct Context {}

    var body: Content {
        Div {
            Title {
                CommandsPage.title
            }
            TableOfContentsView(items: HelpCategory.allCases)
            Anchor("↑ TOC").reference("#toc").class("toc-jump")
            Div {
                Div {
                    H1 { "Commands" }
                    Div {
                        Input()
                            .type(.search)
                            .name("query")
                            .placeholder("Search commands…")
                            .custom(key: "autocomplete", value: "off")
                            .custom(key: "hx-get", value: "/command-search")
                            .custom(key: "hx-target", value: "#commands-list")
                            .custom(key: "hx-trigger", value: "input changed delay:300ms")
                    }
                    .class("search command-search")
                }
                .class("commands-header")
                Div {
                    for category in HelpCategory.allCases {
                        CommandSectionView(category: category)
                    }
                }.id("commands-list")
            }.class("content")
        }.class("layout")
    }
}

extension HelpCategory: TOCItem {
    var title: String {
        return self.rawValue.firstCapitalized
    }
    
    var reference: String {
        return self.rawValue
    }
    
    var children: [any TOCSubItem] {
        return MechaSqueak.commands.filter({
            $0.category == self
        }).sorted(by: {
            $0.commands[0] < $1.commands[0]
        })
    }
}

extension IRCBotCommandDeclaration: TOCSubItem {
    var title: String {
        return "!\(self.commands[0])"
    }
    var reference: String {
        return self.commands[0]
    }
}
