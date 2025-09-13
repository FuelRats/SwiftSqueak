import HTMLKit

struct CommandSectionView: View {
    let category: HelpCategory

    var body: Content {
        let categoryTitle = category.rawValue.firstCapitalized
        let categoryDescription = lingo.localize(
            "help.category.\(category)", locale: "en-GB")
        let commands = MechaSqueak.commands.filter({
            $0.category == category
        }).sorted(by: {
            $0.commands[0] < $1.commands[0]
        })
        
        Details {
            Summary {
                H2 {
                    categoryTitle
                    
                    ShareAnchorView(value: categoryTitle.lowercased())
                }.class("section-heading")
                Paragraph { categoryDescription }.class("description")
            }

            Div {
                for command in commands {
                    CommandView(command: command)
                }
            }
            .class("command-list")
        }
        .isOpen(true)
        .id(categoryTitle.lowercased())
        .class("section command-section")
    }
}
