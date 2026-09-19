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

import AsyncHTTPClient
import Foundation
import NIO

/// The origin collection of a retrieved document. Drives attribution and the grounding contract
/// (SOP answers must cite; ED-Knowledge is game-knowledge, not procedure).
enum OutlineSource: String, Sendable, Equatable {
    case sop
    case edKnowledge
}

/// A single retrieved Outline document (search hit or full body).
struct OutlineDoc: Sendable, Equatable {
    let id: String
    let title: String
    let url: String
    let snippet: String
    let source: OutlineSource
    let collectionId: String
}

/// Read-only retriever over the Outline `documents.search` API, scoped to an allowlist of
/// collections (public FRKB + the private ED-Knowledge collection). Results outside the
/// allowlist are dropped as defense-in-depth even though the query already filters by collection.
struct OutlineAPI: Sendable {
    /// Performs one POST to an Outline API path with the given JSON body, returning the 2xx body.
    typealias Transport = @Sendable (_ path: String, _ body: Data) async throws -> Data

    let baseURL: URL
    let frkbCollectionId: String
    let edKbCollectionId: String?
    private let transport: Transport

    static let defaultLimit = 8

    /// Production initializer using the shared `httpClient`.
    init(token: String, baseURL: URL, frkbCollectionId: String, edKbCollectionId: String?) {
        self.baseURL = baseURL
        self.frkbCollectionId = frkbCollectionId
        self.edKbCollectionId = edKbCollectionId
        self.transport = { path, body in
            var request = try HTTPClient.Request(
                url: baseURL.appendingPathComponent(path), method: .POST)
            request.headers.add(name: "Authorization", value: "Bearer \(token)")
            request.headers.add(name: "Content-Type", value: "application/json")
            request.headers.add(name: "Accept", value: "application/json")
            request.headers.add(name: "User-Agent", value: MechaSqueak.userAgent)
            request.body = .data(body)
            let response = try await httpClient.execute(
                request: request, deadline: .now() + .seconds(15)).get()
            guard (200...202).contains(response.status.code) else {
                let text = response.body.map { String(buffer: $0) } ?? ""
                aiLogger.error("[Outline] \(path) failed \(response.status.code): \(text)")
                throw LLMError.badRequest(status: response.status.code, body: text)
            }
            return response.body.map { Data(buffer: $0) } ?? Data()
        }
    }

    /// Testing initializer: inject a fake transport.
    init(
        baseURL: URL,
        frkbCollectionId: String,
        edKbCollectionId: String?,
        transport: @escaping Transport
    ) {
        self.baseURL = baseURL
        self.frkbCollectionId = frkbCollectionId
        self.edKbCollectionId = edKbCollectionId
        self.transport = transport
    }

    /// Collections the bot is allowed to read from.
    var allowedCollectionIds: [String] {
        [frkbCollectionId] + (edKbCollectionId.map { [$0] } ?? [])
    }

    // MARK: - Search

    /// Searches every allowed collection and merges the hits by ranking. Outline's `documents.search`
    /// only honours the singular `collectionId` param for scoping (the `filters` array is ignored on
    /// this instance), so multi-collection retrieval means one query per collection.
    func search(_ query: String, limit: Int = OutlineAPI.defaultLimit) async throws -> [OutlineDoc] {
        var ranked: [(ranking: Double, order: Int, doc: OutlineDoc)] = []
        var order = 0
        for collectionId in allowedCollectionIds {
            let request = buildSearchRequest(query: query, limit: limit, collectionId: collectionId)
            let data = try await transport("documents.search", try OutlineAPI.encoder.encode(request))
            for result in rankedResults(data) {
                ranked.append((ranking: result.ranking, order: order, doc: result.doc))
                order += 1
            }
        }
        // Drop the weak tail relative to the best hit for this query (a ranking floor), so marginally
        // relevant documents don't get injected as grounding and spuriously cited, then take the
        // strongest few. Merge by raw ranking (Outline scores the same query comparably across
        // collections), with insertion order breaking ties so the result is deterministic.
        guard let top = ranked.map(\.ranking).max(), top > 0 else {
            return ranked.prefix(limit).map { $0.doc }
        }
        let floor = top * OutlineAPI.rankingFloor
        return ranked
            .filter { $0.ranking >= floor }
            .sorted { $0.ranking != $1.ranking ? $0.ranking > $1.ranking : $0.order < $1.order }
            .prefix(limit)
            .map { $0.doc }
    }

    /// A hit must score at least this fraction of the query's best hit to be used as grounding — keeps
    /// the strong matches and drops the long weak tail.
    static let rankingFloor = 0.4

    /// Fetches the full body for an already-allowlisted search hit. The hit passed the collection
    /// allowlist at search time, so its body is trusted; we only re-reject if `documents.info`
    /// reports a `collectionId` that is present AND disallowed. Crucially we do NOT drop the body
    /// when Outline omits `collectionId` from the info response — doing so silently degraded
    /// grounding to the search snippet. Returns nil only on an explicit allowlist violation.
    func fullText(for hit: OutlineDoc) async throws -> String? {
        let body = try OutlineAPI.encoder.encode(InfoRequest(id: hit.id))
        let data = try await transport("documents.info", body)
        let decoded = try OutlineAPI.decoder.decode(InfoResponse.self, from: data)
        if let collectionId = decoded.data.collectionId,
            allowedCollectionIds.contains(collectionId) == false {
            return nil
        }
        return decoded.data.text
    }

    // MARK: - Payload construction / parsing (unit-testable, network-free)

    func buildSearchRequest(query: String, limit: Int, collectionId: String) -> SearchRequest {
        SearchRequest(query: query, limit: limit, collectionId: collectionId)
    }

    /// Parsed hits paired with their ranking (for cross-collection merge).
    func rankedResults(_ data: Data) -> [(ranking: Double, doc: OutlineDoc)] {
        guard let decoded = try? OutlineAPI.decoder.decode(SearchResponse.self, from: data) else {
            return []
        }
        return decoded.data.compactMap { result in
            guard let doc = document(
                from: result.document, snippet: result.context ?? result.document.text ?? "") else {
                return nil
            }
            return (result.ranking ?? 0, doc)
        }
    }

    /// Allowlist-filtered docs from one search response (defense-in-depth; also used in tests).
    func parseSearchResults(_ data: Data) -> [OutlineDoc] {
        rankedResults(data).map { $0.doc }
    }

    /// Maps a wire document to an `OutlineDoc`, tagging its source and dropping anything
    /// outside the allowlist.
    private func document(from wire: WireDocument, snippet: String) -> OutlineDoc? {
        guard let collectionId = wire.collectionId else { return nil }
        let source: OutlineSource
        if collectionId == frkbCollectionId {
            source = .sop
        } else if let edId = edKbCollectionId, collectionId == edId {
            source = .edKnowledge
        } else {
            return nil
        }
        return OutlineDoc(
            id: wire.id,
            title: wire.title,
            url: absoluteURL(wire.url),
            snippet: snippet,
            source: source,
            collectionId: collectionId)
    }

    /// Outline returns document URLs as site-relative paths; resolve them against the site origin.
    private func absoluteURL(_ path: String?) -> String {
        guard let path else { return "" }
        if path.hasPrefix("http") { return path }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return path
        }
        components.path = path
        components.queryItems = nil
        return components.url?.absoluteString ?? path
    }

    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    // MARK: - Wire types

    struct SearchRequest: Codable {
        let query: String
        let limit: Int
        let collectionId: String
    }

    struct InfoRequest: Encodable {
        let id: String
    }

    struct WireDocument: Decodable {
        let id: String
        let title: String
        let url: String?
        let collectionId: String?
        let text: String?
    }

    struct SearchResponse: Decodable {
        let data: [Result]

        struct Result: Decodable {
            let context: String?
            let ranking: Double?
            let document: WireDocument
        }
    }

    struct InfoResponse: Decodable {
        let data: WireDocument
    }
}
