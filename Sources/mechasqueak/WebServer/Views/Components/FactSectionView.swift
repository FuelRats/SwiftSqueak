import HTMLKit

struct FactSectionView: View {
    let category: FactCategory

    var body: Content {
        let categoryName = FactCommands.factCategoryNames[category.key] ?? category.key.firstCapitalized
        
        Div {
            H2 {
                categoryName
                
                ShareAnchorView(value: category.key)
            }.class("section-heading")

            Div {
                for fact in category.facts {
                    FactView(fact: fact)
                }
            }
            .class("fact-list")
        }
        .id(category.key)
        .class("section fact-section")
    }
}

struct PlatformFactSectionView: View {
    let facts: [String: [GroupedFact]]

    var body: Content {
        Div {
            H2 {
                "Platform facts"
                
                ShareAnchorView(value: "platform")
            }.class("section-heading")

            Div {
                for (identifier, platforms) in facts {
                    PlatformFactView(identifier: identifier, platformFacts: platforms)
                }
            }
            .class("fact-list")
        }
        .id("platform")
        .class("section fact-section")
    }
}
