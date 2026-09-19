import XCTest

@testable import mechasqueak

final class OutlineAPITests: XCTestCase {
    private let base = URL(string: "https://docs.fuelrats.com/api")!
    private let frkb = "collection-frkb"
    private let edKb = "collection-edkb"

    private func makeAPI(edKb: String?) -> OutlineAPI {
        OutlineAPI(
            baseURL: base,
            frkbCollectionId: frkb,
            edKbCollectionId: edKb,
            transport: { _, _ in Data() })
    }

    func testSearchRequestScopesToASingleCollection() throws {
        // Only the singular collectionId param restricts server-side; each request targets one.
        let api = makeAPI(edKb: edKb)
        let request = api.buildSearchRequest(query: "how to file a case", limit: 8, collectionId: frkb)

        XCTAssertEqual(request.query, "how to file a case")
        XCTAssertEqual(request.limit, 8)
        XCTAssertEqual(request.collectionId, frkb)

        let json = String(data: try OutlineAPI.encoder.encode(request), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"collectionId\":\"collection-frkb\""))
    }

    func testAllowedCollectionsOmitsEdKbWhenUnset() {
        XCTAssertEqual(makeAPI(edKb: nil).allowedCollectionIds, [frkb])
        XCTAssertEqual(makeAPI(edKb: edKb).allowedCollectionIds, [frkb, edKb])
    }

    func testSearchQueriesEachCollectionAndMergesByRanking() async throws {
        // One transport response per collection; merged output should be ranked across both.
        let frkbBody = """
        {"data":[{"context":"sop hi","ranking":0.7,
          "document":{"id":"f1","title":"SOP","url":"/doc/sop","collectionId":"collection-frkb"}}]}
        """
        let edBody = """
        {"data":[{"context":"ed hi","ranking":0.95,
          "document":{"id":"e1","title":"ED","url":"/doc/ed","collectionId":"collection-edkb"}}]}
        """
        let edId = edKb
        let api = OutlineAPI(
            baseURL: base, frkbCollectionId: frkb, edKbCollectionId: edKb,
            transport: { _, body in
                let request = try? JSONDecoder().decode(OutlineAPI.SearchRequest.self, from: body)
                return Data((request?.collectionId == edId ? edBody : frkbBody).utf8)
            })

        let docs = try await api.search("q", limit: 10)
        XCTAssertEqual(docs.map(\.id), ["e1", "f1"], "higher-ranked ED hit sorts before the SOP hit")
        XCTAssertEqual(docs.first?.source, .edKnowledge)
    }

    func testSearchAppliesRankingFloorDroppingWeakTail() async throws {
        let body = """
        {"data":[
          {"context":"strong","ranking":0.9,
           "document":{"id":"s","title":"S","url":"/doc/s","collectionId":"collection-frkb"}},
          {"context":"weak","ranking":0.2,
           "document":{"id":"w","title":"W","url":"/doc/w","collectionId":"collection-frkb"}}
        ]}
        """
        let api = OutlineAPI(
            baseURL: base, frkbCollectionId: frkb, edKbCollectionId: nil,
            transport: { _, _ in Data(body.utf8) })
        let docs = try await api.search("q", limit: 10)
        XCTAssertEqual(docs.map(\.id), ["s"], "a hit far below the top score is dropped as grounding")
    }

    func testParseTagsSourcesAndDropsNonAllowlisted() {
        let api = makeAPI(edKb: edKb)
        let payload = """
        {"data":[
          {"context":"file a case with !signal","ranking":0.9,
           "document":{"id":"d1","title":"Dispatch SOP","url":"/doc/dispatch-abc",
                       "collectionId":"collection-frkb","text":"full body"}},
          {"context":"supercruise time scales with distance","ranking":0.8,
           "document":{"id":"d2","title":"Supercruise","url":"/doc/sc-xyz",
                       "collectionId":"collection-edkb","text":"full body"}},
          {"context":"secret operator note","ranking":0.7,
           "document":{"id":"d3","title":"Operators","url":"/doc/ops-secret",
                       "collectionId":"collection-operators","text":"full body"}}
        ]}
        """
        let docs = api.parseSearchResults(Data(payload.utf8))

        XCTAssertEqual(docs.count, 2, "The non-allowlisted Operators result must be dropped")
        XCTAssertEqual(docs.map(\.id), ["d1", "d2"])
        XCTAssertEqual(docs[0].source, .sop)
        XCTAssertEqual(docs[1].source, .edKnowledge)
        XCTAssertEqual(docs[0].snippet, "file a case with !signal")
        XCTAssertEqual(docs[0].url, "https://docs.fuelrats.com/doc/dispatch-abc")
        XCTAssertFalse(docs.contains { $0.title == "Operators" })
    }

    func testParseHandlesEmptyAndMalformed() {
        let api = makeAPI(edKb: edKb)
        XCTAssertEqual(api.parseSearchResults(Data("{}".utf8)).count, 0)
        XCTAssertEqual(api.parseSearchResults(Data("not json".utf8)).count, 0)
    }

    private func hit(id: String) -> OutlineDoc {
        OutlineDoc(
            id: id, title: "Doc", url: "https://docs.fuelrats.com/doc/\(id)", snippet: "snippet",
            source: .sop, collectionId: frkb)
    }

    func testFullTextReturnsBodyWhenInfoOmitsCollectionId() async throws {
        // documents.info responses sometimes omit collectionId; the already-allowlisted hit's body
        // must still be returned rather than silently degrading to the search snippet.
        let body = """
        {"data":{"id":"d1","title":"Dispatch SOP","url":"/doc/d1","text":"the full document body"}}
        """
        let api = OutlineAPI(
            baseURL: base, frkbCollectionId: frkb, edKbCollectionId: edKb,
            transport: { _, _ in Data(body.utf8) })
        let text = try await api.fullText(for: hit(id: "d1"))
        XCTAssertEqual(text, "the full document body")
    }

    func testFullTextRejectsDisallowedCollectionId() async throws {
        // If info explicitly reports a non-allowlisted collection, refuse the body (defense-in-depth).
        let body = """
        {"data":{"id":"d3","title":"Operators","url":"/doc/d3",
                 "collectionId":"collection-operators","text":"secret operator note"}}
        """
        let api = OutlineAPI(
            baseURL: base, frkbCollectionId: frkb, edKbCollectionId: edKb,
            transport: { _, _ in Data(body.utf8) })
        let text = try await api.fullText(for: hit(id: "d3"))
        XCTAssertNil(text, "an explicitly disallowed collection must not leak a body")
    }
}
