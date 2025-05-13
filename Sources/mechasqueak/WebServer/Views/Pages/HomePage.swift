import HTMLKit

struct HomePage: View {

    struct Context {}

    var body: Content {
        Div {
            H1 { "MechaSqueak" }
            Paragraph {
                "MechaSqueak intro"
            }
        }.class("content")
    }
}
