import HTMLKit
import Foundation

struct FactLanguageView: View {
    let identifier: String
    let locale: Foundation.Locale
    var isActive = false
    var isPlatformFact = false
    
    var body: Content {
        Anchor {
            Pre {
                locale.identifier
            }
            locale.englishDescription
        }.class("fact-language \(isActive ? "active" : "")")
            .custom(key: "hx-get", value: fetchUrl)
            .custom(key: "hx-target", value: replaceTarget)
            .custom(key: "hx-swap", value: "innerHTML")
            .custom(key: "hx-on", value: "click: this.closest('.fact').querySelectorAll('.fact-language').forEach(el => el.classList.remove('active')); this.classList.add('active')")
    }
    
    var fetchUrl: String {
        if isPlatformFact {
            return "/platform-fact?name=\(identifier)&locale=\(locale.identifier)"
        }
        return "/fact-message?name=\(identifier)&locale=\(locale.identifier)"
    }
    
    var replaceTarget: String {
        if isPlatformFact {
            return "#platform-fact-\(identifier)"
        }
        return "#fact-message-\(identifier)"
    }
}
