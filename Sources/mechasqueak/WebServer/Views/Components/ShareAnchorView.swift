import HTMLKit

struct ShareAnchorView: View {
    let value: String
    let title: String = "Copy link"

    var body: Content {
        Button {}
        .class("share-anchor")
        .custom(key: "data-anchor", value: value)
        .aria(label: title)
        .title(title)
    }
}
