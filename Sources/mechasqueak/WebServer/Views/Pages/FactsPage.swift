import HTMLKit

struct FactsPage: View {
    static let title = "Facts | MechaSqueak Docs"

    struct Context {}
    
    let factCategories: [FactCategory]
    let platformFacts: [String: [GroupedFact]]

    var body: Content {
        var tocItems: [TOCItem] = factCategories
        if !platformFacts.isEmpty {
            tocItems.append(PlatformFactTOCItem(facts: platformFacts))
        }

        return Div {
            Title {
                FactsPage.title
            }
            TableOfContentsView(items: tocItems)
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
                            .custom(key: "hx-target", value: "#fact-list")
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
        return "!\(self.canonicalName)"
    }

    var reference: String {
        return self.canonicalName
    }
}

struct PlatformFactTOCItem: TOCItem {
    let facts: [String: [GroupedFact]]

    var title: String { "Platform facts" }
    var reference: String { "platform" }

    var children: [any TOCSubItem] {
        facts.keys.sorted().map { PlatformFactTOCSubItem(name: $0) }
    }
}

struct PlatformFactTOCSubItem: TOCSubItem {
    let name: String
    var title: String { "!\(name)" }
    var reference: String { name }
}
