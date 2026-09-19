import XCTest

@testable import mechasqueak

final class AskPipelineTests: XCTestCase {
    // MARK: - Test doubles

    private actor Script {
        private var responses: [Result<LLMResponse, Error>]
        private(set) var requests: [LLMRequest] = []

        init(_ responses: [Result<LLMResponse, Error>]) {
            self.responses = responses
        }

        func next(_ request: LLMRequest) throws -> LLMResponse {
            requests.append(request)
            let result = responses.count > 1 ? responses.removeFirst() : responses.first!
            return try result.get()
        }

        var callCount: Int { requests.count }
        func request(_ index: Int) -> LLMRequest { requests[index] }
    }

    private struct ScriptedProvider: LLMProvider {
        let script: Script
        func complete(_ request: LLMRequest) async throws -> LLMResponse {
            try await script.next(request)
        }
    }

    private func outline() -> OutlineAPI {
        // Each per-collection query returns only that collection's doc. The SOP hit ranks highest,
        // so the merged order is [SOP (index 0), ED-Knowledge (index 1)].
        let sopBody = """
        {"data":[{"context":"snippet a","ranking":0.9,
          "document":{"id":"d-sop","title":"Dispatch SOP","url":"/doc/dispatch",
                      "collectionId":"c-frkb","text":"sop body"}}]}
        """
        let edBody = """
        {"data":[{"context":"snippet b","ranking":0.8,
          "document":{"id":"d-ed","title":"Supercruise","url":"/doc/sc",
                      "collectionId":"c-edkb","text":"ed body"}}]}
        """
        let info = #"{"data":{"id":"d","title":"t","url":"/doc/d","collectionId":"c-frkb","text":"full body"}}"#
        return OutlineAPI(
            baseURL: URL(string: "https://docs.fuelrats.com/api")!,
            frkbCollectionId: "c-frkb",
            edKbCollectionId: "c-edkb",
            transport: { path, body in
                guard path == "documents.search" else { return Data(info.utf8) }
                let request = try? JSONDecoder().decode(OutlineAPI.SearchRequest.self, from: body)
                return Data((request?.collectionId == "c-edkb" ? edBody : sopBody).utf8)
            })
    }

    private func pipeline(_ script: Script, tools: [AITool] = []) -> AskPipeline {
        AskPipeline(
            provider: ScriptedProvider(script: script),
            outline: outline(),
            tools: tools,
            maxToolRounds: 5)
    }

    private func textResponse(
        _ text: String, citeDocIndex: Int? = nil, stop: LLMStopReason = .endTurn
    ) -> LLMResponse {
        var citations: [LLMCitation] = []
        if let index = citeDocIndex {
            citations = [LLMCitation(
                citedText: "cited", documentIndex: index, documentTitle: "t",
                startCharIndex: 0, endCharIndex: 5)]
        }
        return LLMResponse(
            content: [.text(text, citations: citations)], stopReason: stop, usage: LLMUsage())
    }

    private func toolUseResponse(name: String, input: JSONValue, id: String) -> LLMResponse {
        LLMResponse(
            content: [.toolUse(id: id, name: name, input: input)],
            stopReason: .toolUse, usage: LLMUsage())
    }

    private func stubTool(_ name: String, returns output: String) -> AITool {
        AITool(
            name: name, description: "test",
            inputSchema: .objectSchema(
                properties: [("system", .stringSchema("s"))], required: ["system"]),
            run: { _, _ in output })
    }

    // MARK: - Tests

    func testDirectAnswerMapsSOPCitation() async throws {
        let script = Script([.success(textResponse("!clear closes a rescue.", citeDocIndex: 0))])
        let reply = try await pipeline(script).answer(question: "what does !clear do?")

        XCTAssertFalse(reply.refused)
        XCTAssertEqual(reply.text, "!clear closes a rescue.")
        XCTAssertEqual(reply.toolRounds, 0)
        XCTAssertEqual(reply.citations.count, 1)
        XCTAssertEqual(reply.citations.first?.url, "https://docs.fuelrats.com/doc/dispatch")
        XCTAssertEqual(reply.citations.first?.source, .sop)
    }

    func testToolLoopExecutesToolThenAnswersWithEDCitation() async throws {
        let script = Script([
            .success(toolUseResponse(name: "system_info", input: .object([("system", .string("Sol"))]), id: "t1")),
            .success(textResponse("Scoopable.", citeDocIndex: 1))
        ])
        let tools = [stubTool("system_info", returns: #"{"scoopable":true}"#)]
        let reply = try await pipeline(script, tools: tools).answer(question: "is Sol scoopable?")

        XCTAssertEqual(reply.text, "Scoopable.")
        XCTAssertEqual(reply.toolRounds, 1)
        XCTAssertEqual(reply.citations.first?.source, .edKnowledge)
        XCTAssertEqual(reply.citations.first?.url, "https://docs.fuelrats.com/doc/sc")

        // The second request must carry the tool_result fed back to the model.
        let calls = await script.callCount
        XCTAssertEqual(calls, 2)
        let secondRequest = await script.request(1)
        let hasToolResult = secondRequest.messages.contains { message in
            message.content.contains { block in
                if case let .toolResult(id, content, _) = block {
                    return id == "t1" && content.contains("scoopable")
                }
                return false
            }
        }
        XCTAssertTrue(hasToolResult, "the tool result must be replayed to the model")
    }

    func testRefusalIsSurfaced() async throws {
        let script = Script([.failure(LLMError.refused)])
        let reply = try await pipeline(script).answer(question: "do something forbidden")
        XCTAssertTrue(reply.refused)
        XCTAssertEqual(reply.text, "")
    }

    func testRunCommandDispatchIsTerminalAndSilent() async throws {
        // The model dispatches a command; the command answers the user in-channel. The pipeline must
        // end the turn immediately (no second model call) and flag the reply as externally delivered,
        // so the assistant cannot double-post or fabricate a parallel answer.
        let script = Script([
            .success(toolUseResponse(
                name: "run_command", input: .object([("command", .string("gametime"))]), id: "c1"))
        ])
        let tools = [stubTool("run_command", returns: CommandDispatchTool.deliveredResult)]
        let reply = try await pipeline(script, tools: tools).answer(question: "what is the game time?")

        XCTAssertTrue(reply.deliveredExternally)
        XCTAssertEqual(reply.text, "")
        XCTAssertFalse(reply.refused)
        XCTAssertEqual(reply.toolRounds, 1)
        let calls = await script.callCount
        XCTAssertEqual(calls, 1, "a successful run_command must end the turn without another model call")
    }

    func testRunCommandErrorDoesNotShortCircuit() async throws {
        // A refused/failed command returns an error the model can see and must respond to, so the
        // loop continues rather than ending silently.
        let script = Script([
            .success(toolUseResponse(
                name: "run_command", input: .object([("command", .string("suspend"))]), id: "c1")),
            .success(textResponse("You can't do that."))
        ])
        let tools = [stubTool(
            "run_command", returns: #"{"error":"you do not have permission to use 'suspend'"}"#)]
        let reply = try await pipeline(script, tools: tools).answer(question: "suspend someone")

        XCTAssertFalse(reply.deliveredExternally)
        XCTAssertEqual(reply.text, "You can't do that.")
        let calls = await script.callCount
        XCTAssertEqual(calls, 2, "a failed run_command must feed the error back for the model to answer")
    }

    func testToolLoopIsCappedAndStillReturns() async throws {
        var responses = (0..<5).map {
            Result<LLMResponse, Error>.success(
                toolUseResponse(
                    name: "system_info", input: .object([("system", .string("Sol"))]), id: "t\($0)"))
        }
        responses.append(.success(textResponse("done after cap")))
        let script = Script(responses)
        let tools = [stubTool("system_info", returns: "{}")]

        let reply = try await pipeline(script, tools: tools).answer(question: "loop forever?")

        XCTAssertEqual(reply.toolRounds, 5, "tool rounds must be capped")
        XCTAssertEqual(reply.text, "done after cap")
        let calls = await script.callCount
        XCTAssertEqual(calls, 6, "5 capped rounds + 1 final tool-less call")
    }

    func testUnknownToolReturnsErrorResultWithoutCrashing() async throws {
        let script = Script([
            .success(toolUseResponse(name: "ghost_tool", input: .object([]), id: "t1")),
            .success(textResponse("recovered"))
        ])
        // No tools registered, so ghost_tool resolves to an error result the model can react to.
        let reply = try await pipeline(script, tools: []).answer(question: "call a missing tool")

        XCTAssertEqual(reply.text, "recovered")
        let secondRequest = await script.request(1)
        let carriesError = secondRequest.messages.contains { message in
            message.content.contains { block in
                if case let .toolResult(_, content, _) = block { return content.contains("unknown tool") }
                return false
            }
        }
        XCTAssertTrue(carriesError)
    }

    func testPauseTurnResumesInsteadOfEndingTheAnswer() async throws {
        let paused = LLMResponse(
            content: [.text("working on it", citations: [])], stopReason: .pauseTurn, usage: LLMUsage())
        let script = Script([.success(paused), .success(textResponse("final answer"))])
        let reply = try await pipeline(script).answer(question: "q")

        XCTAssertEqual(reply.text, "final answer", "a pause_turn must resume, not end the answer")
        let calls = await script.callCount
        XCTAssertEqual(calls, 2, "the paused turn is replayed and the model continues")
    }

    func testFailedToolResultIsFlaggedAsError() async throws {
        let script = Script([
            .success(toolUseResponse(
                name: "system_info", input: .object([("system", .string("Nowhere"))]), id: "t1")),
            .success(textResponse("recovered"))
        ])
        let tools = [stubTool("system_info", returns: ToolOutput.error("not found"))]
        _ = try await pipeline(script, tools: tools).answer(question: "q")

        let second = await script.request(1)
        let flaggedError = second.messages.contains { message in
            message.content.contains { block in
                if case let .toolResult(_, _, isError) = block { return isError }
                return false
            }
        }
        XCTAssertTrue(flaggedError, "an error tool result must be fed back with isError:true")
    }

    func testPipelineAccumulatesTokenUsageAcrossRounds() async throws {
        let toolResponse = LLMResponse(
            content: [.toolUse(id: "t1", name: "system_info", input: .object([("system", .string("Sol"))]))],
            stopReason: .toolUse,
            usage: LLMUsage(inputTokens: 100, outputTokens: 10, cacheReadInputTokens: 0))
        let finalResponse = LLMResponse(
            content: [.text("done", citations: [])],
            stopReason: .endTurn,
            usage: LLMUsage(inputTokens: 120, outputTokens: 15, cacheReadInputTokens: 90))
        let script = Script([.success(toolResponse), .success(finalResponse)])
        let tools = [stubTool("system_info", returns: "{}")]

        let reply = try await pipeline(script, tools: tools).answer(question: "is Sol scoopable?")

        XCTAssertEqual(reply.usage.inputTokens, 220)
        XCTAssertEqual(reply.usage.outputTokens, 25)
        XCTAssertEqual(reply.usage.cacheReadInputTokens, 90)
    }

    func testSystemPromptCarriesGroundingStyleAndPersona() {
        let prompt = AskPipeline.systemPrompt(locale: Locale(identifier: "en"))
        XCTAssertTrue(prompt.contains("GROUNDING"))
        XCTAssertTrue(prompt.contains("SINGLE IRC message"), "IRC single-line output rule must be present")
        XCTAssertTrue(prompt.contains("NEVER share a link"), "internal-doc no-link rule must be present")
        XCTAssertTrue(prompt.contains("VOICE"), "persona must be appended")
        XCTAssertTrue(prompt.contains("untrusted"), "injection guard must be present")
    }

    func testProvenanceMakesSOPLinkableButNotEDKnowledge() {
        let sop = AskPipeline.GroundingDoc(
            title: "Dispatch SOP", url: "https://docs.fuelrats.com/doc/dispatch", source: .sop, text: "x")
        let ed = AskPipeline.GroundingDoc(
            title: "Fuel Scooping", url: "https://docs.fuelrats.com/doc/scoop", source: .edKnowledge, text: "x")
        XCTAssertTrue(AskPipeline.provenance(for: sop).contains("https://docs.fuelrats.com/doc/dispatch"))
        XCTAssertTrue(AskPipeline.provenance(for: sop).contains("linkable"))
        XCTAssertTrue(AskPipeline.provenance(for: ed).contains("do not link"))
        XCTAssertFalse(AskPipeline.provenance(for: ed).contains("https://"), "internal ED doc URL must not be offered")
    }

    func testSearchQueryStripsFillerAndKeepsContentWords() {
        XCTAssertEqual(
            AskPipeline.searchQuery(from: "what happens when a ship runs out of fuel"), "ship runs fuel")
        XCTAssertEqual(AskPipeline.searchQuery(from: "how does supercruise work"), "supercruise")
        XCTAssertEqual(AskPipeline.searchQuery(from: "neutron star boost"), "neutron star boost")
        // An all-stopword query has nothing to strip to, so it falls back to the original.
        XCTAssertEqual(AskPipeline.searchQuery(from: "what is it"), "what is it")
    }

    func testSearchToolSchemaExposesQuery() {
        XCTAssertEqual(KnowledgeBaseSearchTool.tool.name, "search_knowledge_base")
        guard case let .object(pairs) = KnowledgeBaseSearchTool.tool.inputSchema else {
            return XCTFail("schema must be an object")
        }
        let keyed = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(keyed["required"], .array([.string("query")]))
    }
}
