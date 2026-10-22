import XCTest

@testable import mechasqueak

final class URLShortenerFormTests: XCTestCase {
    func testFormEncodingEscapesReservedCharacters() {
        let body = URLShortener.formEncoded([
            ("url", "https://example.com/a+b?x=1&y=2"),
            ("keyword", "rat signal")
        ])
        XCTAssertEqual(body, "url=https%3A%2F%2Fexample.com%2Fa%2Bb%3Fx%3D1%26y%3D2&keyword=rat%20signal")
    }
}
