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
    try await db.raw("""
        CREATE VIRTUAL TABLE IF NOT EXISTS commands USING fts5(
            name,
            aliases,
            description,
            tags,
            arguments,
            options,
            tokenize = 'unicode61'
        )
    """).run()
}

func insertCommand(_ command: IRCBotCommandDeclaration, on db: SQLDatabase) async throws {
    try await db.insert(into: "commands")
        .columns("name", "aliases", "description", "tags")
        .values([
            SQLBind(command.commands[0]),
            SQLBind(command.commands.joined(separator: ", ")),
            SQLBind(command.description),
            SQLBind(command.tags.joined(separator: ", "))
        ]).run()
}

func searchCommands(query: String, on db: SQLDatabase) async throws -> [Command] {
    let wildcardQuery = query
        .split(separator: " ")
        .map { "\($0)*" }
        .joined(separator: " ")

    let rows = try await db.raw("""
        SELECT rowid, name, aliases, description, tags, bm25(commands) AS rank
        FROM commands
        WHERE commands MATCH \(bind: wildcardQuery)
        ORDER BY rank
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
