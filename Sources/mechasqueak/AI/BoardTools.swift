/*
 Copyright 2026 The Fuel Rats Mischief

 Redistribution and use in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice,
 this list of conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following
 disclaimer in the documentation and/or other materials provided with the distribution.

 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote
 products derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
 INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

import Foundation

/// Read-only tools over MechaSqueak's own operational state: the live rescue board, Fuel Rats
/// member records, and the command catalogue. Each returns compact JSON and never mutates
/// anything. Board/case text is operational, not personal data, and is already visible in-channel.
enum BoardTools {
    static let quoteLimit = 6

    static func all() -> [AITool] {
        [activeCases, caseDetail, ratLookup, findCommand]
    }

    // MARK: - active_cases

    static let activeCases = AITool(
        name: "active_cases",
        description: """
        List the rescue cases currently on the board: case number, client, system, platform, \
        code-red status, and assigned rats. Use for "how many cases are open", "what is case N", \
        or "is anyone on <client>" style questions about the live board.
        """,
        inputSchema: .objectSchema(properties: [], required: [])
    ) { _, _ in
        let rescues = await board.getRescues()
        let cases = rescues
            .sorted { $0.key < $1.key }
            .map { caseSummary(id: $0.key, rescue: $0.value) }
        return ToolOutput.json(BoardSummary(openCases: cases.count, cases: cases))
    }

    // MARK: - case_detail

    static let caseDetail = AITool(
        name: "case_detail",
        description: """
        Show full detail for a single rescue case, including notes and recent quotes, by case \
        number or client name. Use to summarise or catch up on a specific case.
        """,
        inputSchema: .objectSchema(
            properties: [("case", .stringSchema("The case number or client name"))],
            required: ["case"])
    ) { input, _ in
        guard let query = input["case"]?.stringValue, query.isEmpty == false else {
            return ToolOutput.error("missing 'case'")
        }
        let rescues = await board.getRescues()
        guard let (id, rescue) = resolveCase(query, in: rescues) else {
            return ToolOutput.error("no case found for '\(query)'")
        }
        return ToolOutput.json(caseDetailSummary(id: id, rescue: rescue))
    }

    // MARK: - rat_lookup

    static let ratLookup = AITool(
        name: "rat_lookup",
        description: """
        Look up a Fuel Rats member by their IRC nickname or account: their registered CMDR \
        (rat) names and platforms, when they joined, and their permission groups/roles. Use for \
        "who is <name>", "what platform is <name>", or "how long has <name> been a rat".
        """,
        inputSchema: .objectSchema(
            properties: [("name", .stringSchema("The IRC nickname or account name"))],
            required: ["name"])
    ) { input, _ in
        guard let name = input["name"]?.stringValue, name.isEmpty == false else {
            return ToolOutput.error("missing 'name'")
        }
        do {
            guard let document = try await FuelRatsAPI.getNickname(forIRCAccount: name) else {
                return ToolOutput.error("no Fuel Rats account found for '\(name)'")
            }
            return ToolOutput.json(ratSummary(name: name, document: document))
        } catch {
            aiLogger.error("[tool:rat_lookup] \(error)")
            return ToolOutput.error("rat lookup failed")
        }
    }

    // MARK: - find_command

    static let findCommand = AITool(
        name: "find_command",
        description: """
        Search MechaSqueak's command catalogue by capability to find which bot command does \
        something (e.g. "file paperwork", "change platform", "travel time"). Returns matching \
        command names, aliases, and descriptions. Use this to answer "what command do I use to …".
        """,
        inputSchema: .objectSchema(
            properties: [("query", .stringSchema("What the user is trying to do"))],
            required: ["query"])
    ) { input, _ in
        guard let query = input["query"]?.stringValue, query.isEmpty == false else {
            return ToolOutput.error("missing 'query'")
        }
        guard let database = mecha.sqliteDatabase else {
            return ToolOutput.error("command search unavailable")
        }
        do {
            let results = try await searchCommands(query: query, on: database)
            let matches = commandMatches(results)
            if matches.isEmpty {
                return ToolOutput.error("no commands found for '\(query)'")
            }
            return ToolOutput.json(CommandMatchList(query: query, commands: matches))
        } catch {
            aiLogger.error("[tool:find_command] \(error)")
            return ToolOutput.error("command search failed")
        }
    }

    // MARK: - Pure shaping (unit-testable)

    /// Resolves a case by its board number (if the query is an integer) or by a case-insensitive
    /// match on the client name (exact first, then prefix).
    static func resolveCase(
        _ query: String, in rescues: [Int: Rescue]
    ) -> (id: Int, rescue: Rescue)? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if let id = Int(trimmed), let rescue = rescues[id] {
            return (id, rescue)
        }
        let needle = trimmed.lowercased()
        let exact = rescues.first { $0.value.client?.lowercased() == needle }
        let match = exact ?? rescues.first { $0.value.client?.lowercased().hasPrefix(needle) == true }
        return match.map { ($0.key, $0.value) }
    }

    static func caseSummary(id: Int, rescue: Rescue) -> CaseSummary {
        CaseSummary(
            caseNumber: id,
            client: rescue.clientDescription,
            system: rescue.system?.name,
            platform: rescue.platform?.rawValue,
            expansion: rescue.platform == .PC ? rescue.expansion.englishDescription : nil,
            codeRed: rescue.codeRed,
            status: rescue.status.rawValue,
            assignedRats: assignedNames(rescue))
    }

    static func caseDetailSummary(id: Int, rescue: Rescue) -> CaseDetail {
        let quotes = rescue.quotes.suffix(quoteLimit).map {
            QuoteSummary(author: $0.author, message: ToolOutput.truncate($0.message, limit: 300))
        }
        return CaseDetail(
            caseNumber: id,
            client: rescue.clientDescription,
            clientNick: rescue.clientNick,
            system: rescue.system?.name,
            platform: rescue.platform?.rawValue,
            expansion: rescue.platform == .PC ? rescue.expansion.englishDescription : nil,
            codeRed: rescue.codeRed,
            status: rescue.status.rawValue,
            title: rescue.title,
            assignedRats: assignedNames(rescue),
            jumpCalls: rescue.jumpCalls.count,
            createdAt: rescue.createdAt,
            notes: rescue.notes.isEmpty ? nil : ToolOutput.truncate(rescue.notes),
            quotes: Array(quotes))
    }

    static func assignedNames(_ rescue: Rescue) -> [String] {
        rescue.rats.map { $0.attributes.name.value } + rescue.unidentifiedRats
    }

    static func ratSummary(name: String, document: NicknameSearchDocument) -> RatSummary {
        let rats = document.user.map { document.ratsBelongingTo(user: $0) } ?? []
        return RatSummary(
            name: name,
            joinDate: document.joinDate,
            rats: rats.map {
                RatEntry(
                    name: $0.attributes.name.value,
                    platform: $0.attributes.platform.value.rawValue,
                    expansion: $0.attributes.expansion.value.englishDescription)
            },
            roles: document.groups.map { $0.attributes.name.value }.sorted())
    }

    static func commandMatches(_ commands: [Command]) -> [CommandMatch] {
        commands.prefix(DataTools.searchResultLimit).map {
            CommandMatch(
                name: $0.name,
                aliases: $0.aliases.isEmpty ? nil : $0.aliases,
                description: $0.description)
        }
    }

    // MARK: - Result summaries

    struct BoardSummary: Encodable {
        let openCases: Int
        let cases: [CaseSummary]
    }

    struct CaseSummary: Encodable {
        let caseNumber: Int
        let client: String
        let system: String?
        let platform: String?
        let expansion: String?
        let codeRed: Bool
        let status: String
        let assignedRats: [String]
    }

    struct CaseDetail: Encodable {
        let caseNumber: Int
        let client: String
        let clientNick: String?
        let system: String?
        let platform: String?
        let expansion: String?
        let codeRed: Bool
        let status: String
        let title: String?
        let assignedRats: [String]
        let jumpCalls: Int
        let createdAt: Date
        let notes: String?
        let quotes: [QuoteSummary]
    }

    struct QuoteSummary: Encodable {
        let author: String
        let message: String
    }

    struct RatSummary: Encodable {
        let name: String
        let joinDate: Date?
        let rats: [RatEntry]
        let roles: [String]
    }

    struct RatEntry: Encodable {
        let name: String
        let platform: String
        let expansion: String
    }

    struct CommandMatchList: Encodable {
        let query: String
        let commands: [CommandMatch]
    }

    struct CommandMatch: Encodable {
        let name: String
        let aliases: String?
        let description: String
    }
}
