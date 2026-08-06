import XCTest

@testable import mechasqueak

final class UpdateAnnouncerTests: XCTestCase {
    private var directory: URL!

    private var sourcePath: String { directory.path }
    private var stateFile: String { directory.appendingPathComponent("announced-version.txt").path }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("update-announcer-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func writeVersion(_ value: String) throws {
        try value.write(
            toFile: directory.appendingPathComponent("version.txt").path, atomically: true,
            encoding: .utf8)
    }

    private func announce() -> String? {
        UpdateAnnouncer.versionToAnnounce(sourcePath: sourcePath, stateFile: stateFile)
    }

    func testAnnouncesANewVersionExactlyOnce() throws {
        try writeVersion("3.1.0")
        XCTAssertEqual(announce(), "3.1.0", "A newly-seen version should be announced")
        // A restart or reconnect with the same version must not re-announce.
        XCTAssertNil(announce(), "The same version should not be announced twice")
        XCTAssertNil(announce())
    }

    func testAnnouncesAgainOnlyWhenTheVersionChanges() throws {
        try writeVersion("3.1.0")
        XCTAssertEqual(announce(), "3.1.0")

        try writeVersion("3.2.0")
        XCTAssertEqual(announce(), "3.2.0", "A genuine version change should be announced")
        XCTAssertNil(announce(), "...but only once")
    }

    func testIgnoresUnknownOrEmptyVersions() throws {
        try writeVersion("unknown")
        XCTAssertNil(announce())

        try writeVersion("")
        XCTAssertNil(announce())
    }

    func testReturnsNilWhenTheVersionFileIsMissing() {
        XCTAssertNil(announce())
    }
}
