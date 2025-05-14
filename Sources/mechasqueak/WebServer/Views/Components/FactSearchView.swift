import HTMLKit

struct FactSearchView: View {
    let facts: [GroupedFact]

    var body: Content {
        Div {
            H2 {
                "\(facts.count) search results"
                
            }.class("section-heading")
            Div {
                for fact in facts {
                    FactView(fact: fact)
                }
            }
            .class("fact-list")
        }
        .class("section fact-section")
    }
}

struct FactListView: View {
    let factCategories: [FactCategory]
    let platformFacts: [String: [GroupedFact]]
    
    var body: Content {
        for category in factCategories {
            FactSectionView(category: category)
        }
        if !platformFacts.isEmpty {
            PlatformFactSectionView(facts: platformFacts)
        }
    }
}
