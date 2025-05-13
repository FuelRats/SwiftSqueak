import HTMLKit

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
    
    func parseText () -> [LinkTextContentType] {
        var result: [LinkTextContentType] = []
        var currentText = ""
        for word in text.components(separatedBy: .whitespacesAndNewlines) {
            if word.hasPrefix("http://") || word.hasPrefix("https://") {
                if !currentText.isEmpty {
                    result.append(.plainText(currentText))
                    currentText = " "
                }
                result.append(.link(word))
            } else {
                currentText += "\(word) "
            }
        }
        if !currentText.isEmpty {
            result.append(.plainText(currentText))
        }
        print(result)
        return result
    }
}

enum LinkTextContentType {
    case plainText(String)
    case link(String)
}
