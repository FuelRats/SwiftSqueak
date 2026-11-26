import XCTest

@testable import mechasqueak

final class URLShortenerTests: XCTestCase {
    // Bodies shaped on the live YOURLS 1.10.6 API at t.fuelr.at, which sends statusCode as a string.
    private let created = Data("""
        {"url":{"keyword":"k3x9q","url":"https://fuelrats.com/paperwork/4f1d2c3e-8a7b-4c6d-9e0f-1a2b3c4d5e6f/edit",
        "title":"Paperwork - Fuel Rats","date":"2026-11-26 14:50:12","ip":"34.224.237.196"},
        "status":"success","message":"https://fuelrats.com/paperwork/4f1d2c3e... added to database",
        "title":"Paperwork - Fuel Rats","shorturl":"https://t.fuelr.at/k3x9q","statusCode":"200"}
        """.utf8)

    private let alreadyStored = Data("""
        {"status":"fail","code":"error:url","url":{"keyword":"1cz5","url":"https://fuelrats.com/",
        "title":"The Fuel Rats","date":"2019-03-02 18:21:40","ip":"10.0.0.12","clicks":"412"},
        "message":"https://fuelrats.com/ already exists in database (short URL: t.fuelr.at/1cz5)",
        "title":"The Fuel Rats","shorturl":"https://t.fuelr.at/1cz5","statusCode":"409","errorCode":"409"}
        """.utf8)

    func testNewLinkDecodes() throws {
        let response = try URLShortener.decode(status: 200, body: created)
        XCTAssertEqual(response.shorturl.absoluteString, "https://t.fuelr.at/k3x9q")
        XCTAssertEqual(response.title, "Paperwork - Fuel Rats")
    }

    func testAlreadyStoredLinkReturnsExistingShortURL() throws {
        let response = try URLShortener.decode(status: 409, body: alreadyStored)
        XCTAssertEqual(response.shorturl.absoluteString, "https://t.fuelr.at/1cz5")
    }

    func testTakenKeywordIsAnError() {
        let body = Data("""
            {"status":"fail","code":"error:keyword","message":"Short URL importantinfo already exists in database or is reserved",
            "errorCode":"400","statusCode":"400"}
            """.utf8)
        XCTAssertThrowsError(try URLShortener.decode(status: 400, body: body))
    }

    func testRejectedSignatureIsAnError() {
        let body = Data(#"{"message":"Please log in","errorCode":"403","callback":""}"#.utf8)
        XCTAssertThrowsError(try URLShortener.decode(status: 403, body: body))
    }
}
