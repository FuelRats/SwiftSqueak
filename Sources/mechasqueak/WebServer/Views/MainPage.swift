import HTMLKit

struct MainPage: View {
    let currentPage: Page
    var factCategories: [FactCategory]? = nil
    var platformFacts: [String : [GroupedFact]]? = nil
    
    var body: Content {
        HTMLKit.Document(.html5)
        Html {
            Head {
                Meta().charset(.utf8)
                Meta().name(.viewport).content("width=device-width, initial-scale=1.0")
                
                Link()
                    .relationship(.stylesheet)
                    .reference("/css/styles.css")
                
                Link()
                    .relationship(.stylesheet)
                    .reference("https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.7.2/css/all.min.css")
                
                Script {}.source("https://unpkg.com/htmx.org@1.9.2")
                Script {}.source("https://unpkg.com/htmx.org@1.9.12/dist/ext/class-tools.js")
                Script {}.source("/js/main.js")
                Title { "MechaSqueak" }
            }
            
            Body {
                NavbarComponent()
                
                Main {
                    switch currentPage {
                    case .home:
                        HomePage().body
                    case .commands:
                        CommandsPage().body
                    case .facts:
                        FactsPage(factCategories: factCategories ?? [], platformFacts: platformFacts ?? [:]).body
                    }
                }
                .id("main-content")
                .class("main")
            }
        }
    }
}

enum Page {
    case home
    case commands
    case facts
}
