import HTMLKit

struct TableOfContentsView: View {
    let items: [TOCItem]
    
    var body: Content {
        Nav {
            Details {
                Summary{ "Table of Contents" }
                UnorderedList {
                    for item in items {
                        ListItem {
                            Anchor("\(item.title)").reference("#\(item.reference)").class("toc-header")
                            UnorderedList {
                                for child in item.children {
                                    ListItem {
                                        Anchor("\(child.title)").reference("#\(child.reference)")
                                    }
                                }
                            }
                            .class("toc-subitem")
                        }
                    }
                }.class("toc-content")
            }.class("toc-collapsible")
            UnorderedList {
                for item in items {
                    ListItem {
                        Anchor("\(item.title)").reference("#\(item.reference)").class("toc-header")
                        UnorderedList {
                            for child in item.children {
                                ListItem {
                                    Anchor("\(child.title)").reference("#\(child.reference)")
                                }
                            }
                        }
                        .class("toc-subitem")
                    }
                }
            }.class("toc-content toc-sidebar")
        }
        .class("toc-container")
        .id("toc")
    }
}

protocol TOCItem {
    var title: String { get }
    var reference : String { get }
    var children: [TOCSubItem] { get }
}

protocol TOCSubItem {
    var title: String { get }
    var reference : String { get }
}
