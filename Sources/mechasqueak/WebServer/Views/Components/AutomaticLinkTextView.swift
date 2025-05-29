import HTMLKit
import Regex

struct AutomaticLinkTextView: View {
    let text: String
    
    var body: Content {
        let linkTexts: [LinkTextContentType] = parseText()
        for linkText in linkTexts {
            switch linkText {
                case .plainText(let text):
                    "\(text)"
                case .link(let text):
                    Anchor {
                        "\(text)"
                    }.reference(text)
                    .target(.blank)
            }
            
        }
    }
    
    func parseText() -> [LinkTextContentType] {
        var result: [LinkTextContentType] = []

        // Match standard URLs, avoid trailing punctuation like ).,;!? if they are at the end
        let pattern = #"https?://[^\s)\],;!?]+"#
        guard let regex = try? Regex(pattern: pattern) else {
            return []
        }

        var currentIndex = text.startIndex
        for match in regex.findAll(in: text) {
            let matchRange = match.range
            if matchRange.lowerBound > currentIndex {
                let plainText = String(text[currentIndex..<matchRange.lowerBound])
                result.append(.plainText(plainText))
            }

            let linkText = String(text[matchRange])
            result.append(.link(linkText))
            currentIndex = matchRange.upperBound
        }

        if currentIndex < text.endIndex {
            let plainText = String(text[currentIndex..<text.endIndex])
            result.append(.plainText(plainText))
        }

        return result
    }
}

enum LinkTextContentType {
    case plainText(String)
    case link(String)
}
