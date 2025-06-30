import HTMLKit

struct GithubReleaseView: View {
    let release: GithubRelease

    var body: Content {
        Article {
            H3 {
                release.name
            }
            Div {
                MarkdownView(text: release.body)
            }
        }
        .class("gh-release")
        .id("release-" + String(release.id))
    }
}
