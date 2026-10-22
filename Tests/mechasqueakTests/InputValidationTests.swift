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

final class GroupPathSegmentTests: XCTestCase {
    func testChannelSegmentsRejectPathCharacters() throws {
        XCTAssertEqual(try Group.pathSegment("fuelrats"), "fuelrats")
        for bad in ["", ".", "..", "../../rescues/1", "a/b", "a?x=1", "a#b", "a%2Fb", "a\\b"] {
            XCTAssertThrowsError(try Group.pathSegment(bad), bad)
        }
    }

    func testPermissionSegmentsMustLookLikeScopes() throws {
        XCTAssertEqual(try Group.permissionSegment("rescues.write.me"), "rescues.write.me")
        for bad in ["rescues..write", "../users", "rescues.write/", "", "Rescues.write"] {
            XCTAssertThrowsError(try Group.permissionSegment(bad), bad)
        }
    }

    func testRawParametersRebuildTheTrailingParameter() {
        XCTAssertEqual(ManagementCommands.rawParameters(["#chan", ":hello", "there"]), ["#chan", "hello there"])
        XCTAssertEqual(ManagementCommands.rawParameters(["#channel", "+v", ":SpaceDawg"]), ["#channel", "+v", "SpaceDawg"])
        XCTAssertEqual(ManagementCommands.rawParameters(["#channel", "+v", "SpaceDawg"]), ["#channel", "+v", "SpaceDawg"])
    }

    func testServicesTargetsAreRecognised() {
        XCTAssertTrue(ManagementCommands.isServicesTarget("NickServ"))
        XCTAssertTrue(ManagementCommands.isServicesTarget("someone@services.fuelrats.com"))
        XCTAssertFalse(ManagementCommands.isServicesTarget("#ratchat"))
        XCTAssertFalse(ManagementCommands.isServicesTarget("SpaceDawg"))
    }
}
