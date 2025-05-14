import HTMLKit

struct HomePage: View {

    struct Context {}

    var body: Content {
        Div {
            H1 { "MechaSqueak" }
            Paragraph {
                "Welcome to the MechaSqueak help site. " +
                "MechaSqueak is the IRC bot the Fuel Rats use to log rescues, run training drills, " +
                "and provide quick utilities in chat."
            }
            
            Paragraph {
                "See the Commands page for a plain‑language list of every programmed command. " +
                "Each entry shows the exact syntax, parameters, and a short example."
            }
            
            Paragraph {
                "See the Facts page for one‑line information snippets that dispatchers can post in‑channel. " +
                "Facts can be added or translated live by Ops and Overseers."
            }
        }.class("content section")
    }
}
