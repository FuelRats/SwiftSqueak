import Logging
import NIO
import SQLKit
import SQLiteKit
import XCTest

@testable import mechasqueak

/// Covers `searchCommands` command lookup: a verbose natural-language question must still surface the
/// right command (OR semantics + Porter stemming), where the previous implicit-AND search returned nothing.
final class SearchTests: XCTestCase {
    private static let seed: [(String, String, String, String)] = [
        ("rename", "rename, renameid", "Change the client name of a closed case", "rename, change"),
        ("system", "system, sys", "Change the star system of a rescue", "location"),
        ("grab", "grab", "Add the last message a client said to their case as a quote", "quote"),
        ("reopen", "reopen", "Reopen a closed rescue and put it back on the board", "closed, restore"),
        ("cmdr", "cmdr, client, commander", "Change the CMDR name of the client of this rescue.", ""),
        ("title", "title, operation", "Set the operation title of a rescue", "operation")
    ]

    /// Opens an in-memory FTS database, seeds the commands, runs `body`, and always closes the connection
    /// (SQLiteNIO asserts if a connection deinitializes unclosed).
    private func withSeededDatabase(_ body: (SQLDatabase) async throws -> Void) async throws {
        let connection = try await SQLiteConnectionSource(configuration: .init(storage: .memory))
            .makeConnection(logger: Logger(label: "SearchTests"), on: MultiThreadedEventLoopGroup.singleton.next())
            .get()
        do {
            let db = connection.sql()
            try await configureSearchDatabase(db: db)
            for (name, aliases, description, tags) in Self.seed {
                try await db.insert(into: "commands")
                    .columns("name", "aliases", "description", "tags")
                    .values([
                        SQLBind(name), SQLBind(aliases), SQLBind(description),
                        SQLBind(searchTags(forCommand: name, baseTags: tags))
                    ])
                    .run()
            }
            try await body(db)
        } catch {
            try? await connection.close().get()
            throw error
        }
        try await connection.close().get()
    }

    func testVerboseNaturalLanguageQuerySurfacesCommand() async throws {
        try await withSeededDatabase { db in
            let results = try await searchCommands(
                query: "what is the command for changing the client name of a rescue after it has been closed",
                on: db)
            // The query is genuinely ambiguous — `cmdr` (aliased `!client`, "Change the CMDR name of the
            // client") is a legitimate sibling of `rename`. The fix's job is that `rename` now *surfaces*
            // in the ranked candidates at all (it returned nothing under implicit-AND); the model then
            // disambiguates on "closed" from the returned descriptions.
            XCTAssertTrue(
                results.prefix(3).contains { $0.name == "rename" },
                "rename must surface in the top results (was absent under implicit-AND search)")
        }
    }

    func testStemmedInflectionsMatch() async throws {
        try await withSeededDatabase { db in
            // "changing"/"closed" must stem to "change"/"close" to match the command description.
            let results = try await searchCommands(query: "how do I rename a closed case", on: db)
            XCTAssertEqual(results.first?.name, "rename")
        }
    }

    func testConciseQueryStillWorks() async throws {
        try await withSeededDatabase { db in
            let results = try await searchCommands(query: "change star system of rescue", on: db)
            XCTAssertEqual(results.first?.name, "system")
        }
    }

    func testNoMatchReturnsEmpty() async throws {
        try await withSeededDatabase { db in
            let results = try await searchCommands(query: "brew a pot of coffee", on: db)
            XCTAssertTrue(results.isEmpty)
        }
    }

    func testSynonymSurfacesCommandWithNoLexicalOverlap() async throws {
        try await withSeededDatabase { db in
            // "handle"/"wrong" appear in rename's curated synonyms, not its name or description.
            let results = try await searchCommands(query: "fix the wrong client handle", on: db)
            XCTAssertEqual(results.first?.name, "rename")
        }
    }

    func testSearchTagsMergesSynonyms() {
        let merged = searchTags(forCommand: "rename", baseTags: "rename, change")
        XCTAssertTrue(merged.contains("rename, change"), "keeps the command's own tags")
        XCTAssertTrue(merged.contains("handle"), "appends curated synonyms")
    }

    func testSearchTagsPassesThroughWhenNoSynonyms() {
        XCTAssertEqual(searchTags(forCommand: "meow", baseTags: "cat"), "cat")
    }
}
