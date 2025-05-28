import HTMLKit

struct MainPage: View {
    let currentPage: Page
    var factCategories: [FactCategory]?
    var platformFacts: [String: [GroupedFact]]?
    var releases: [GithubRelease]?

    var body: Content {
        HTMLKit.Document(.html5)
        Html {
            Head {
                Meta().charset(.utf8)
                Meta().name(.viewport).content("width=device-width, initial-scale=1.0")
                Meta().name(.applicationName).content("MechaSqueak")
                Meta().name(.themeColor).content("#d65050")
                Meta()
                    .custom(key: "name", value: "apple-mobile-web-app-title")
                    .content("MechaSqueak")
                
                Title { currentTitle }
                
                Meta().name(.description).content("Documentation for the Fuel Rats MechaSqueak IRC Bot")
                
                Link()
                    .relationship(.icon)
                    .reference("/favicon.ico")

                Link()
                    .relationship(.stylesheet)
                    .reference("/css/styles.css")

                Link()
                    .relationship(.stylesheet)
                    .reference("https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.7.2/css/all.min.css")

                Script {}.source("https://unpkg.com/htmx.org@1.9.2")
                Script {}.source("https://unpkg.com/htmx.org@1.9.12/dist/ext/class-tools.js")
                Script {}.source("/js/main.js")
            }

            Body {
                NavbarComponent()

                Main {
                    switch currentPage {
                        case .home:
                        HomePage(releases: releases ?? []).body
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
    
    var currentTitle: String {
        switch currentPage {
            case .home:
                HomePage.title
            case .commands:
                CommandsPage.title
            case .facts:
                FactsPage.title
        }
    }
}

enum Page {
    case home
    case commands
    case facts
}
