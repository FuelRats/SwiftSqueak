import XCTest

@testable import mechasqueak

final class JSONValueTests: XCTestCase {
    private func decode(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    func testIntValueReadsIntegersAndTruncatesFractions() throws {
        XCTAssertEqual(try decode("25").intValue, 25)
        XCTAssertEqual(try decode("12.9").intValue, 12)
        XCTAssertEqual(try decode("-3.5").intValue, -3)
    }

    func testIntValueIsNilForNumbersOutsideIntRange() throws {
        // A model-supplied tool argument like this used to trap the whole process in Int(_:).
        XCTAssertNil(try decode("100000000000000000000000").intValue)
        XCTAssertNil(try decode("1e300").intValue)
        XCTAssertNil(try decode("-1e300").intValue)
    }

    func testIntValueIsNilForNonNumbers() throws {
        XCTAssertNil(try decode("\"25\"").intValue)
        XCTAssertNil(try decode("true").intValue)
    }
}
