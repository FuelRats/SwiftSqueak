//
//  Markdown.swift
//  mechasqueak
//
//  Created by Alex Sørlie on 25/05/2025.
//
import HTMLKit
import Markdown

struct MarkdownView: View {
    let text: String
    
    var body: Content {
        var visitor = HTMLVisitor()
        let document = Markdown.Document(parsing: text)
        
        HTMLKit.Group {
            visitor.visit(document)
        }
    }
}

struct HTMLVisitor: MarkupVisitor {
    mutating func defaultVisit(_ markup: Markup) -> any Content {
        switch markup {
            case let doc as Markdown.Document:
                return HTMLKit.Group {
                    for child in doc.children {
                        defaultVisit(child)
                    }
                }
            
            case let text as Markdown.Text:
                return AutomaticLinkTextView(text: text.string)
                
            case let quote as Markdown.BlockQuote:
                return HTMLKit.Blockquote {
                    for child in quote.children {
                        defaultVisit(child)
                    }
                }
                
            case let listItem as Markdown.ListItem:
                return HTMLKit.ListItem {
                    for child in listItem.children {
                        defaultVisit(child)
                    }
                }
                
            case let orderedList as Markdown.OrderedList:
                return HTMLKit.OrderedList {
                    for child in orderedList.children {
                        if let listItem = child as? Markdown.ListItem {
                            visitListItem(listItem)
                        }
                    }
                }
                
            case let unorderedList as Markdown.UnorderedList:
                return HTMLKit.UnorderedList {
                    for child in unorderedList.children {
                        if let listItem = child as? Markdown.ListItem {
                            visitListItem(listItem)
                        }
                    }
                }
                
            case let paragraph as Markdown.Paragraph:
                return HTMLKit.Paragraph {
                    for child in paragraph.children {
                        defaultVisit(child)
                    }
                }
                
            case _ as Markdown.ThematicBreak:
                return HTMLKit.HorizontalRule()
                
            case let codeBlock as Markdown.CodeBlock:
                return HTMLKit.Code {
                    codeBlock.code
                }.class("lang-\(codeBlock.language ?? "")")
                
            case let emphasis as Markdown.Emphasis:
                return HTMLKit.Italic {
                    for child in emphasis.children {
                        defaultVisit(child)
                    }
                }
                
            case let image as Markdown.Image:
                return HTMLKit.Image()
                    .source(image.source ?? "")
                    .alternate(image.title ?? "")
                
            case let link as Markdown.Link:
                return HTMLKit.Anchor {
                    for child in link.children {
                        defaultVisit(child)
                    }
                }.target(.blank).reference(link.destination ?? "")
                
            case let strikethrough as Markdown.Strikethrough:
                return HTMLKit.Span {
                    for child in strikethrough.children {
                        defaultVisit(child)
                    }
                }.class("strikethrough")
                
            case let strong as Markdown.Strong:
                return HTMLKit.Bold {
                    for child in strong.children {
                        defaultVisit(child)
                    }
                }
                
            case let inlineCode as Markdown.InlineCode:
                return HTMLKit.Pre {
                    inlineCode.code
                }
                
            case _ as Markdown.SoftBreak:
                return HTMLKit.LineBreak()
            
            case _ as Markdown.LineBreak:
                return HTMLKit.LineBreak()
            
            case let heading as Markdown.Heading:
                switch heading.level {
                    case 1:
                        return HTMLKit.H1 {
                            for child in heading.children {
                                defaultVisit(child)
                            }
                        }
                        
                    case 2:
                        return HTMLKit.H2 {
                            for child in heading.children {
                                defaultVisit(child)
                            }
                        }
                        
                    case 3:
                        return HTMLKit.H3 {
                            for child in heading.children {
                                defaultVisit(child)
                            }
                        }
                        
                    case 4:
                        return HTMLKit.H4 {
                            for child in heading.children {
                                defaultVisit(child)
                            }
                        }
                        
                    default:
                        return HTMLKit.H5 {
                            for child in heading.children {
                                defaultVisit(child)
                            }
                        }
                }
                
            default:
                return "Unknown type \(String(describing: type(of: markup)))"
        }
    }
    
    mutating func visitListItem(_ listItem: Markdown.ListItem) -> HTMLKit.ListElement {
        return HTMLKit.ListItem {
            for child in listItem.children {
                defaultVisit(child)
            }
        }
    }
}
