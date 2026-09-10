import XCTest

@testable import mechasqueak

final class AnthropicTests: XCTestCase {
    // MARK: - Encoding

    private func encodedRequestString(_ request: LLMRequest) throws -> String {
        let data = try Anthropic.encodeRequestBody(request)
        return String(data: data, encoding: .utf8) ?? ""
    }

    func testRequestEncodesWireKeysVerbatim() throws {
        let tool = LLMTool(
            name: "system_info",
            description: "Look up a star system",
            inputSchema: .objectSchema(
                properties: [("system", .stringSchema("System name"))],
                required: ["system"]))

        let request = LLMRequest(
            model: Anthropic.answerModel,
            maxTokens: 512,
            system: "You are MechaSqueak.",
            messages: [
                LLMMessage(role: .user, content: [
                    .document(LLMDocument(title: "Dispatch SOP", text: "Use !md for medical.")),
                    .text("When do I use !md?", citations: [])
                ])
            ],
            tools: [tool])

        let json = try encodedRequestString(request)

        // Tool schema keys must not be snake_case-converted.
        XCTAssertTrue(json.contains("\"input_schema\""), "input_schema must serialize verbatim")
        XCTAssertTrue(
            json.contains("\"additionalProperties\":false"),
            "additionalProperties must not be converted to snake_case")
        XCTAssertFalse(json.contains("additional_properties"))

        // Document blocks must carry citations + ephemeral cache control.
        XCTAssertTrue(json.contains("\"citations\":{\"enabled\":true}"))
        XCTAssertTrue(json.contains("\"cache_control\":{\"type\":\"ephemeral\"}"))

        // max_tokens present; temperature never sent.
        XCTAssertTrue(json.contains("\"max_tokens\":512"))
        XCTAssertFalse(json.contains("temperature"))
    }

    func testToolResultEncodesSnakeCaseKeys() throws {
        // A non-error result: tool_use_id present, is_error omitted (Anthropic treats absence as false).
        let okRequest = LLMRequest(
            model: Anthropic.answerModel,
            maxTokens: 256,
            messages: [
                LLMMessage(role: .user, content: [
                    .toolResult(toolUseId: "toolu_42", content: "Sol: G-type, scoopable", isError: false)
                ])
            ])
        let okJSON = try encodedRequestString(okRequest)
        XCTAssertTrue(okJSON.contains("\"tool_use_id\":\"toolu_42\""))
        XCTAssertTrue(okJSON.contains("\"type\":\"tool_result\""))
        XCTAssertFalse(okJSON.contains("is_error"), "is_error should be omitted when false")

        // An error result must surface is_error:true so the model can recover.
        let errorRequest = LLMRequest(
            model: Anthropic.answerModel,
            maxTokens: 256,
            messages: [
                LLMMessage(role: .user, content: [
                    .toolResult(toolUseId: "toolu_43", content: "system not found", isError: true)
                ])
            ])
        let errorJSON = try encodedRequestString(errorRequest)
        XCTAssertTrue(errorJSON.contains("\"is_error\":true"))
    }

    // MARK: - Decoding (Phase 0.1 fixtures)

    func testDecodesFinalTurnWithCitations() throws {
        let fixture = """
        {"id":"msg_1","type":"message","role":"assistant","model":"claude-opus-4-8",
         "content":[{"type":"text","text":"Use !md for medical dispatch.","citations":[
            {"type":"char_location","cited_text":"medical dispatch","document_index":0,
             "document_title":"Dispatch SOP","start_char_index":10,"end_char_index":26}]}],
         "stop_reason":"end_turn",
         "usage":{"input_tokens":1200,"output_tokens":20,
                  "cache_read_input_tokens":1000,"cache_creation_input_tokens":0}}
        """
        let response = try Anthropic.parseSuccess(Data(fixture.utf8))

        XCTAssertEqual(response.stopReason, .endTurn)
        XCTAssertEqual(response.text, "Use !md for medical dispatch.")
        XCTAssertEqual(response.citations.count, 1)
        let citation = try XCTUnwrap(response.citations.first)
        XCTAssertEqual(citation.citedText, "medical dispatch")
        XCTAssertEqual(citation.documentIndex, 0)
        XCTAssertEqual(citation.documentTitle, "Dispatch SOP")
        XCTAssertEqual(citation.startCharIndex, 10)
        XCTAssertEqual(citation.endCharIndex, 26)
        // Cache hit observed on the follow-up (the load-bearing 0.1 assertion).
        XCTAssertEqual(response.usage.cacheReadInputTokens, 1000)
    }

    func testDecodesToolUseTurn() throws {
        let fixture = """
        {"id":"msg_2","type":"message","role":"assistant","model":"claude-opus-4-8",
         "content":[{"type":"text","text":"Checking.","citations":null},
          {"type":"tool_use","id":"toolu_1","name":"system_info","input":{"system":"Sol"}}],
         "stop_reason":"tool_use",
         "usage":{"input_tokens":1300,"output_tokens":15,
                  "cache_read_input_tokens":1200,"cache_creation_input_tokens":0}}
        """
        let response = try Anthropic.parseSuccess(Data(fixture.utf8))

        XCTAssertEqual(response.stopReason, .toolUse)
        XCTAssertEqual(response.toolCalls.count, 1)
        let call = try XCTUnwrap(response.toolCalls.first)
        XCTAssertEqual(call.name, "system_info")
        XCTAssertEqual(call.input["system"]?.stringValue, "Sol")
    }

    func testRefusalStopReasonThrows() throws {
        let fixture = """
        {"id":"msg_3","type":"message","role":"assistant","model":"claude-opus-4-8",
         "content":[],"stop_reason":"refusal","usage":{"input_tokens":10,"output_tokens":0}}
        """
        XCTAssertThrowsError(try Anthropic.parseSuccess(Data(fixture.utf8))) { error in
            guard case LLMError.refused = error else {
                return XCTFail("Expected .refused, got \(error)")
            }
        }
    }

    // MARK: - Retry behaviour

    private actor Recorder {
        private let responses: [Anthropic.HTTPParts]
        private(set) var transportCalls = 0
        private(set) var sleeps: [Double] = []

        init(responses: [Anthropic.HTTPParts]) {
            self.responses = responses
        }

        func next() -> Anthropic.HTTPParts {
            let index = min(transportCalls, responses.count - 1)
            transportCalls += 1
            return responses[index]
        }

        func recordSleep(_ seconds: Double) {
            sleeps.append(seconds)
        }
    }

    private func successBody() -> Data {
        Data("""
        {"id":"m","type":"message","role":"assistant","content":[{"type":"text","text":"ok"}],
         "stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}
        """.utf8)
    }

    func test429HonorsRetryAfterThenSucceeds() async throws {
        let recorder = Recorder(responses: [
            Anthropic.HTTPParts(status: 429, retryAfter: 1.5, body: Data()),
            Anthropic.HTTPParts(status: 200, retryAfter: nil, body: successBody())
        ])
        let client = Anthropic(
            maxRetries: 3,
            transport: { _ in await recorder.next() },
            sleeper: { await recorder.recordSleep($0) })

        let response = try await client.complete(
            LLMRequest(model: "m", maxTokens: 8, messages: [.text(.user, "hi")]))

        XCTAssertEqual(response.text, "ok")
        let calls = await recorder.transportCalls
        let sleeps = await recorder.sleeps
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(sleeps, [1.5], "429 backoff must honor the Retry-After header")
    }

    func test429RetryAfterIsClampedToCeiling() async throws {
        // A hostile/misconfigured Retry-After must not pin an in-flight slot for minutes.
        let recorder = Recorder(responses: [
            Anthropic.HTTPParts(status: 429, retryAfter: 3600, body: Data()),
            Anthropic.HTTPParts(status: 200, retryAfter: nil, body: successBody())
        ])
        let client = Anthropic(
            maxRetries: 3,
            transport: { _ in await recorder.next() },
            sleeper: { await recorder.recordSleep($0) })

        _ = try await client.complete(
            LLMRequest(model: "m", maxTokens: 8, messages: [.text(.user, "hi")]))

        let sleeps = await recorder.sleeps
        XCTAssertEqual(sleeps, [Anthropic.maxRetryDelay], "a huge Retry-After must be clamped to the ceiling")
    }

    func test400IsNotRetried() async throws {
        let recorder = Recorder(responses: [
            Anthropic.HTTPParts(status: 400, retryAfter: nil, body: Data(#"{"error":"bad"}"#.utf8))
        ])
        let client = Anthropic(
            maxRetries: 3,
            transport: { _ in await recorder.next() },
            sleeper: { await recorder.recordSleep($0) })

        do {
            _ = try await client.complete(
                LLMRequest(model: "m", maxTokens: 8, messages: [.text(.user, "hi")]))
            XCTFail("Expected a badRequest error")
        } catch LLMError.badRequest(let status, _) {
            XCTAssertEqual(status, 400)
        }

        let calls = await recorder.transportCalls
        XCTAssertEqual(calls, 1, "A 400 must not be retried")
    }
}
