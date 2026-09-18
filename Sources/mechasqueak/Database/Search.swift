//
//  Search.swift
//  mechasqueak
//
//  Created by Alex Sørlie on 11/05/2025.
//

import Vapor
import SQLKit
import NIO
import SQLiteKit
struct Command: Content {
    let id: Int?
    let name: String
    let aliases: String
    let description: String
    let tags: String
}

func createFTS5TableIfNeeded(db: SQLDatabase) async throws {
    // Porter stemming so a question phrased with inflected words ("changing", "closed") still
    // matches a command described with the root forms ("change", "close").
    try await db.raw("""
        CREATE VIRTUAL TABLE IF NOT EXISTS commands USING fts5(
            name,
            aliases,
            description,
            tags,
            arguments,
            options,
            tokenize = 'porter unicode61'
        )
    """).run()
}

/// Common English function words dropped from a command search so a verbose, natural-language question
/// ("what is the command for changing the client name of a rescue after it has been closed") is reduced
/// to its meaningful terms and doesn't drown out the ranking. Deliberately excludes command verbs like
/// "change"/"set"/"show"/"close" — those are the discriminating words.
private let commandSearchStopwords: Set<String> = [
    "the", "of", "a", "an", "to", "for", "on", "in", "is", "it", "its", "has", "have", "had", "been",
    "be", "with", "your", "you", "their", "they", "i", "we", "my", "me", "at", "as", "by", "from",
    "into", "about", "and", "or", "after", "before", "when", "how", "do", "does", "did", "what",
    "which", "that", "this", "these", "those", "can", "will", "would", "should", "if", "there", "s"
]

/// Extra search keywords per command (keyed by primary name) merged into the FTS `tags` column, so a
/// natural-language capability query reaches a command whose name and description share no words with it
/// — e.g. "fix the wrong client handle" → `rename`, "undo closing a rescue" → `reopen`. Only the commands
/// people tend to ask about in plain language need an entry; the rest rank fine on their own text.
let commandSearchSynonyms: [String: String] = [
    "rename": "handle typo wrong misspelled correct fix",
    "system": "starsystem location where stranded jump wrong",
    "sysc": "correct fix wrong autocorrect",
    "cmdr": "ingame open board reassign",
    "nick": "ircnick username reassign rename",
    "lang": "language locale speaks foreign",
    "pc": "platform steam computer",
    "xb": "platform xbox console",
    "ps": "platform playstation ps4 ps5 console",
    "cr": "code red emergency oxygen o2 dying life support",
    "grab": "quote capture last message said",
    "inject": "add note information update quote",
    "sub": "edit quote replace fix typo text entry",
    "title": "operation name mission opname label",
    "active": "toggle inactive standby afk",
    "clear": "close finish complete done paperwork md",
    "paperwork": "link report md close pwl",
    "clientpw": "paperwork link previous closed by name",
    "trash": "delete remove bin junk invalid duplicate",
    "restore": "untrash recover undelete",
    "reopen": "restore back on board undo close",
    "unclose": "reopen back on board previous case number undo",
    "closed": "recently history recent",
    "quote": "show info details view case",
    "go": "assign rats friend dispatch",
    "unassign": "remove rats",
    "station": "nearest dock repair refuel",
    "distance": "how far between ly light years",
    "sctime": "supercruise travel time how long",
    "landmark": "proximity near sol colonia sagittarius",
    "search": "find system galaxy lookup",
    "searchfacts": "find fact",
    "queue": "waiting list backlog",
    "list": "board open cases show all",
    "gametime": "game time utc current",
    "timezone": "convert time tz",
    "shorten": "url short link",
    "suspend": "ban block account"
]

/// The `tags` value indexed for a command: its own tags plus any curated search synonyms.
func searchTags(forCommand name: String, baseTags: String) -> String {
    guard let synonyms = commandSearchSynonyms[name] else { return baseTags }
    return baseTags.isEmpty ? synonyms : baseTags + ", " + synonyms
}

func insertCommand(_ command: IRCBotCommandDeclaration, on db: SQLDatabase) async throws {
    let name = command.commands[0]
    try await db.insert(into: "commands")
        .columns("name", "aliases", "description", "tags")
        .values([
            SQLBind(name),
            SQLBind(command.commands.joined(separator: ", ")),
            SQLBind(command.description),
            SQLBind(searchTags(forCommand: name, baseTags: command.tags.joined(separator: ", ")))
        ]).run()
}

func searchCommands(query: String, on db: SQLDatabase) async throws -> [Command] {
    let tokens = query.lowercased()
        .split(whereSeparator: { $0.isLetter == false && $0.isNumber == false })
        .map(String.init)
        .filter { $0.count > 1 }
    var meaningful = tokens.filter { commandSearchStopwords.contains($0) == false }
    if meaningful.isEmpty { meaningful = tokens }  // an all-stopword query: keep the originals
    guard meaningful.isEmpty == false else { return [] }
    // OR the prefix terms so a verbose natural-language question still matches a command whose
    // description shares only some of its words; bm25 ranks the best overlap first, LIMIT trims the tail.
    let wildcardQuery = meaningful.map { "\($0)*" }.joined(separator: " OR ")

    // Weight a match by the column it lands in (name > description > aliases > tags/synonyms); a hit on
    // the command's own name outranks one in another command's body, and the authoritative description
    // outranks curated synonyms so synonym padding can't override the real capability text. Column
    // order: name, aliases, description, tags, arguments, options.
    let rows = try await db.raw("""
        SELECT rowid, name, aliases, description, tags,
            bm25(commands, 8.0, 5.0, 6.0, 4.0, 1.0, 1.0) AS rank
        FROM commands
        WHERE commands MATCH \(bind: wildcardQuery)
        ORDER BY rank
        LIMIT 10
    """).all()

    return rows.compactMap { row in
        try? Command(
            id: row.decode(column: "rowid", as: Int.self),
            name: row.decode(column: "name", as: String.self),
            aliases: row.decode(column: "aliases", as: String.self),
            description: row.decode(column: "description", as: String.self),
            tags: row.decode(column: "tags", as: String.self)
        )
    }
}

func configureSearchDatabase(db: SQLDatabase) async throws {
    try await createFTS5TableIfNeeded(db: db)
}

func makeSQLiteDatabase(eventLoopGroup: EventLoopGroup) async throws -> SQLDatabase {
    let configuration = SQLiteConfiguration(storage: .memory)
    let source = SQLiteConnectionSource(configuration: configuration)
    let connection = try await source.makeConnection(
        logger: Logger(label: "SQLite"),
        on: eventLoopGroup.next()
    ).get()
    
    let db = connection.sql()
    try await configureSearchDatabase(db: db)
    return db
}
