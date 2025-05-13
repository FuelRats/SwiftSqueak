import HTMLKit

struct NavbarComponent: View {
    var body: Content {
        HTMLKit.Group {
            Nav {
                Anchor("Home")
                    .custom(key: "hx-get", value: "/home")
                    .custom(key: "hx-target", value: "#main-content")
                    .custom(key: "hx-swap", value: "innerHTML")
                    .custom(key: "hx-push-url", value: "true")

                Anchor("Commands")
                    .custom(key: "hx-get", value: "/commands")
                    .custom(key: "hx-target", value: "#main-content")
                    .custom(key: "hx-swap", value: "innerHTML")
                    .custom(key: "hx-push-url", value: "true")

                Anchor("Facts")
                    .custom(key: "hx-get", value: "/facts")
                    .custom(key: "hx-target", value: "#main-content")
                    .custom(key: "hx-swap", value: "innerHTML")
                    .custom(key: "hx-push-url", value: "true")
                
                Anchor("Help")
                    .reference("http://t.fuelr.at/help")
                    .target(.blank)
                    .class("nav-right")
            }
            .class("navbar")
        }
    }
}
