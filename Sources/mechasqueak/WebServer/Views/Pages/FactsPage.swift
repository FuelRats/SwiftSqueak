import HTMLKit

struct FactsPage: View {

    struct Context {}
    
    let factCategories: [FactCategory]
    let platformFacts: [String: [GroupedFact]]

    var body: Content {
        Div {
            TableOfContentsView(items: factCategories)
            Anchor("↑ TOC").reference("#toc").class("toc-jump")
            Div {
                Div {
                    H1 { "Facts" }
                    Div {
                        Input()
                            .type(.search)
                            .name("query")
                            .placeholder("Search facts…")
                            .custom(key: "autocomplete", value: "off")
                            .custom(key: "hx-get", value: "/fact-search")
                            .custom(key: "hx-target", value: "#facts-list")
                            .custom(key: "hx-trigger", value: "input changed delay:300ms")
                    }
                    .class("search fact-search")
                }
                .class("facts-header")
                Div {
                    for category in factCategories {
                        FactSectionView(category: category)
                    }
                    if !platformFacts.isEmpty {
                        PlatformFactSectionView(facts: platformFacts)
                    }
                }.id("fact-list")
            }.class("content")
        }.class("layout")
    }
}

extension FactCategory: TOCItem {
    var title: String {
        return FactCommands.factCategoryNames[key] ?? key.firstCapitalized
    }
    
    var reference: String {
        return key
    }
    
    var children: [any TOCSubItem] {
        return self.facts
    }
}

extension GroupedFact: TOCSubItem {
    var title: String {
        return "!\(self.cannonicalName)"
    }
    
    var reference: String {
        return self.cannonicalName
    }
}
