import HTMLKit
import Foundation

struct FactView: View {
    let fact: GroupedFact
    var defaultLocale: Foundation.Locale = Foundation.Locale(identifier: "en")
   

    var body: Content {
        let defaultFact = fact.messages["en"] ?? fact.messages.first?.1
        
        Article {
            H3 {
                Div {
                    "!" + fact.cannonicalName
                    ShareAnchorView(value: fact.cannonicalName.lowercased())
                    for (localeString, _) in fact.messages.sorted(by: { $0.key < $1.key }) {
                        let locale = Locale(identifier: localeString)
                        let isActive = localeString == defaultLocale.identifier
                        FactLanguageView(identifier: fact.cannonicalName, locale: locale, isActive: isActive)
                    }
                }
                .class("fact-header")
            }
            
            if !fact.aliases.dropFirst().isEmpty {
                Div {
                    "Aliases: " + fact.aliases.dropFirst().map { "!\($0)" }.joined(separator: ", ")
                }
                .class("fact-aliases-inline")
            }

            if let defaultFact = defaultFact {
                FactMessageView(fact: defaultFact)
            }
        }
        .id(fact.cannonicalName.lowercased())
        .class("fact")
    }
}

struct PlatformFactView: View {
    let identifier: String
    let platformFacts: [GroupedFact]
    var defaultLocale: Foundation.Locale = Foundation.Locale(identifier: "en")
   

    var body: Content {
        let defaultPlatform = platformFacts.first!
        
        Article {
            H3 {
                Div {
                    "!" + identifier
                    ShareAnchorView(value: identifier)
                    for (localeString, _) in defaultPlatform.messages.sorted(by: { $0.key < $1.key }) {
                        let locale = Locale(identifier: localeString)
                        let isActive = localeString == defaultLocale.identifier
                        FactLanguageView(identifier: identifier, locale: locale, isActive: isActive, isPlatformFact: true)
                    }
                }
                .class("fact-header")
            }
            
            if !defaultPlatform.aliases.dropFirst().isEmpty {
                Div {
                    "Aliases: " + defaultPlatform.aliases.dropFirst().map { "!\($0)" }.joined(separator: ", ")
                }
                .class("fact-aliases-inline")
            }

            Div {
                PlatformFactMessageGroupView(platformFacts: platformFacts, defaultLocale: defaultLocale)
            }.class("platform-facts")
            .id("platform-fact-\(identifier)")
        }
        .id(identifier)
        .class("fact")
    }
}

struct PlatformFactMessageGroupView: View {
    let platformFacts: [GroupedFact]
    var defaultLocale: Foundation.Locale = Foundation.Locale(identifier: "en")
    
    var body: Content {
        for platformFact in platformFacts {
            if let defaultFact = platformFact.messages[defaultLocale.identifier] {
                FactMessageView(fact: defaultFact, platform: platformFact.platform)
            }
        }
    }
}

let webFormatter: DateFormatter = {
  let formatter = DateFormatter()
  formatter.dateFormat = "yyyy-MM-dd"
  formatter.calendar = Calendar(identifier: .iso8601)
  formatter.timeZone = TimeZone(secondsFromGMT: 0)
  formatter.locale = Locale(identifier: "en_US_POSIX")
  return formatter
}()

struct FactMessageView: View {
    let fact: Fact
    var platform: GamePlatform? = nil
    
    var body: Content {
        let date = webFormatter.string(from: fact.updatedAt)
        
        Div {
            Div {
                if let platform = platform {
                    Div {}
                        .class("platform-icon fa-brands \(platform.fontAwesomeClass)")
                        .aria(label: "\(platform)")
                }
                Paragraph {
                    AutomaticLinkTextView(text: fact.message)
                }
            }.class("fact-contents")
            Div {
                "Last modified "
                Time {
                    date
                }.dateTime(date)
                " by \(fact.author)"
            }.class("byline")
            
        }.class("fact-message")
        .id("fact-message-\(fact.id)")
    }
}
