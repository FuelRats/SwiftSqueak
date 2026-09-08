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

    func testSearchRequestFiltersByAllowedCollections() throws {
        let api = makeAPI(edKb: edKb)
        let request = api.buildSearchRequest(query: "how to file a case", limit: 8)

        XCTAssertEqual(request.query, "how to file a case")
        XCTAssertEqual(request.limit, 8)
        XCTAssertEqual(request.filters.count, 1)
        let filter = try XCTUnwrap(request.filters.first)
        XCTAssertEqual(filter.field, "collectionId")
        XCTAssertEqual(filter.operator, "in")
        XCTAssertEqual(filter.value, [frkb, edKb])

        // The encoded body must carry the deprecated-free `filters` array verbatim.
        let json = String(data: try OutlineAPI.encoder.encode(request), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"collectionId\""))
        XCTAssertTrue(json.contains("\"operator\":\"in\""))
    }

    func testSearchOmitsEdKbWhenUnset() throws {
        let api = makeAPI(edKb: nil)
        let filter = try XCTUnwrap(api.buildSearchRequest(query: "q", limit: 5).filters.first)
        XCTAssertEqual(filter.value, [frkb], "ED-Knowledge id must be absent until the collection is seeded")
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
}
