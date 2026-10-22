import HTMLKit
import XCTest

@testable import mechasqueak

final class MarkdownViewTests: XCTestCase {
    private func render(_ markdown: String) throws -> String {
        try Renderer().render(view: MarkdownView(text: markdown))
    }

    func testWebLinksAreRendered() throws {
        let html = try render("See [the docs](https://docs.fuelrats.com/sop).")
        XCTAssertTrue(html.contains("href=\"https://docs.fuelrats.com/sop\""))
    }

    func testRelativeLinksAreKeptButSchemeRelativeAreNot() throws {
        XCTAssertTrue(try render("[facts](/facts)").contains("href=\"/facts\""))
        XCTAssertTrue(try render("[top](#top)").contains("href=\"#top\""))
        XCTAssertFalse(try render("[x](//evil.example/x)").contains("evil.example"))
    }

    func testScriptLinksAreRenderedAsPlainText() throws {
        let html = try render("[click me](javascript:alert(document.cookie))")
        XCTAssertFalse(html.lowercased().contains("javascript:"))
        XCTAssertTrue(html.contains("click me"))
    }

    func testImagesWithDataURLsAreDropped() throws {
        let html = try render("![logo](data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=)")
        XCTAssertFalse(html.contains("data:image"))
        XCTAssertFalse(html.contains("<img"))
    }

    func testTextContentIsEscaped() throws {
        let html = try render("Release &lt;script&gt;alert(1)&lt;/script&gt; notes")
        XCTAssertFalse(html.contains("<script>"))
    }
}
