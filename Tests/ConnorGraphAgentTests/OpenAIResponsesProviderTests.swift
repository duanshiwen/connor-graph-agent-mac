import Foundation
import Testing
import ConnorGraphAgent

private struct ResponsesCapturingHTTPClient: AgentHTTPClient {
    final class Storage: @unchecked Sendable {
        var captured: AgentHTTPRequest?
    }

    var responseBody: Data
    var statusCode: Int
    var storage = Storage()

    var captured: AgentHTTPRequest? { storage.captured }

    init(responseBody: Data, statusCode: Int = 200) {
        self.responseBody = responseBody
        self.statusCode = statusCode
    }

    mutating func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse {
        storage.captured = request
        return AgentHTTPResponse(statusCode: statusCode, body: responseBody)
    }
}

private struct ResponsesCapturingSSEClient: AgentSSEHTTPClient {
    final class Storage: @unchecked Sendable {
        var captured: AgentHTTPRequest?
    }

    var frames: [String]
    var storage = Storage()

    var captured: AgentHTTPRequest? { storage.captured }

    func stream(_ request: AgentHTTPRequest) async throws -> AsyncThrowingStream<String, Error> {
        storage.captured = request
        let frames = frames
        return AsyncThrowingStream { continuation in
            for frame in frames { continuation.yield(frame) }
            continuation.finish()
        }
    }
}

@Test func openAIResponsesProviderBuildsResponsesRequest() async throws {
    let body = """
    {
      "id": "resp_1",
      "output": [
        {"type":"message","content":[{"type":"output_text","text":"Hello from Responses"}]}
      ],
      "usage": {"input_tokens": 2, "output_tokens": 3, "total_tokens": 5}
    }
    """.data(using: .utf8)!
    let client = ResponsesCapturingHTTPClient(responseBody: body, statusCode: 200)
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: "test-key",
            model: "gpt-test",
            requestTimeout: 240
        ),
        httpClient: client
    )

    let response = try await provider.complete(AgentModelRequest(messages: [
        AgentModelMessage(role: .system, content: "Connor system"),
        AgentModelMessage(role: .user, content: "Say hello")
    ]))

    #expect(response.text == "Hello from Responses")
    #expect(client.captured?.url.absoluteString == "https://api.openai.com/v1/responses")
    #expect(client.captured?.method == "POST")
    #expect(client.captured?.headers["Authorization"] == "Bearer test-key")
    #expect(client.captured?.timeoutInterval == 240)
    let requestBody = try #require(client.captured?.body)
    let object = try #require(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
    #expect(object["model"] as? String == "gpt-test")
    #expect(object["store"] as? Bool == false)
    #expect(object["messages"] == nil)
    let input = try #require(object["input"] as? [[String: Any]])
    #expect(input.count == 2)
    #expect(input[0]["role"] as? String == "system")
    #expect(input[1]["role"] as? String == "user")
}

@Test func openAIResponsesProviderMapsReasoningEffortAndIncludeEncryptedReasoning() async throws {
    let body = #"{"id":"resp_1","output":[{"type":"message","content":[{"type":"output_text","text":"OK"}]}]}"#.data(using: .utf8)!
    let client = ResponsesCapturingHTTPClient(responseBody: body, statusCode: 200)
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: "test-key",
            model: "o-test",
            reasoningEffort: "high",
            includeEncryptedReasoning: true
        ),
        httpClient: client
    )

    _ = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "think")]))

    let requestBody = try #require(client.captured?.body)
    let object = try #require(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
    let reasoning = try #require(object["reasoning"] as? [String: Any])
    #expect(reasoning["effort"] as? String == "high")
    let include = try #require(object["include"] as? [String])
    #expect(include.contains("reasoning.encrypted_content"))
}

@Test func openAIResponsesProviderParsesFunctionCallItems() async throws {
    let body = """
    {
      "id": "resp_1",
      "output": [
        {"id":"rs_1","type":"reasoning","summary":[]},
        {"id":"fc_1","type":"function_call","call_id":"call_1","name":"graph_search","arguments":"{\\"query\\":\\"memory\\"}","status":"completed"}
      ],
      "usage": {"input_tokens": 10, "output_tokens": 4, "total_tokens": 14}
    }
    """.data(using: .utf8)!
    let client = ResponsesCapturingHTTPClient(responseBody: body, statusCode: 200)
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "test-key", model: "gpt-test"),
        httpClient: client
    )

    let response = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "search")]))

    #expect(response.finishReason == .toolCalls)
    #expect(response.toolCalls == [AgentToolCall(id: "call_1", name: "graph_search", argumentsJSON: "{\"query\":\"memory\"}")])
    #expect(response.usage == AgentModelUsage(promptTokens: 10, completionTokens: 4, totalTokens: 14))
    #expect(response.providerMetadata?.providerID == "openai-responses")
    #expect(response.providerMetadata?.responseID == "resp_1")
    #expect(response.providerMetadata?.rawOutputItemsJSON?.contains("function_call") == true)
}

@Test func openAIResponsesProviderSerializesFunctionCallOutputs() async throws {
    let body = #"{"id":"resp_2","output":[{"type":"message","content":[{"type":"output_text","text":"Done"}]}]}"#.data(using: .utf8)!
    let client = ResponsesCapturingHTTPClient(responseBody: body, statusCode: 200)
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "test-key", model: "gpt-test"),
        httpClient: client
    )

    _ = try await provider.complete(AgentModelRequest(messages: [
        AgentModelMessage(role: .assistant, content: "", toolCalls: [AgentToolCall(id: "call_1", name: "graph_search", argumentsJSON: "{\"query\":\"memory\"}")]),
        AgentModelMessage(role: .tool, content: "{\"result\":\"found\"}", toolCallID: "call_1", name: "graph_search")
    ]))

    let requestBody = try #require(client.captured?.body)
    let object = try #require(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
    let input = try #require(object["input"] as? [[String: Any]])
    let functionCall = try #require(input.first { $0["type"] as? String == "function_call" })
    #expect(functionCall["call_id"] as? String == "call_1")
    #expect(functionCall["name"] as? String == "graph_search")
    let output = try #require(input.first { $0["type"] as? String == "function_call_output" })
    #expect(output["call_id"] as? String == "call_1")
    #expect(output["output"] as? String == "{\"result\":\"found\"}")
}

@Test func openAIResponsesProviderStreamsTypedTextEvents() async throws {
    let sseClient = ResponsesCapturingSSEClient(frames: [
        "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_1\"}}\n",
        "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Hel\"}\n",
        "data: {\"type\":\"response.output_text.delta\",\"delta\":\"lo\"}\n",
        "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_1\",\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"Hello\"}]}]}}\n"
    ])
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "test-key", model: "gpt-test"),
        httpClient: ResponsesCapturingHTTPClient(responseBody: Data()),
        sseClient: sseClient
    )

    var events: [AgentModelStreamEvent] = []
    for try await event in provider.streamComplete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "hello")])) {
        events.append(event)
    }

    #expect(events.contains(.textDelta("Hel")))
    #expect(events.contains(.textDelta("lo")))
    let completed = try #require(events.compactMap { event -> AgentModelResponse? in
        if case .completed(let response) = event { return response }
        return nil
    }.last)
    #expect(completed.text == "Hello")
    let requestBody = try #require(sseClient.captured?.body)
    let object = try #require(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
    #expect(object["stream"] as? Bool == true)
}

@Test func openAIResponsesProviderStreamsFunctionArgumentDeltas() async throws {
    let sseClient = ResponsesCapturingSSEClient(frames: [
        "data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"id\":\"fc_1\",\"type\":\"function_call\",\"call_id\":\"call_1\",\"name\":\"graph_search\",\"arguments\":\"\"}}\n",
        "data: {\"type\":\"response.function_call_arguments.delta\",\"item_id\":\"fc_1\",\"output_index\":0,\"delta\":\"{\\\"query\\\":\"}\n",
        "data: {\"type\":\"response.function_call_arguments.delta\",\"item_id\":\"fc_1\",\"output_index\":0,\"delta\":\"\\\"memory\\\"}\"}\n",
        "data: {\"type\":\"response.function_call_arguments.done\",\"output_index\":0,\"item\":{\"id\":\"fc_1\",\"type\":\"function_call\",\"call_id\":\"call_1\",\"name\":\"graph_search\",\"arguments\":\"{\\\"query\\\":\\\"memory\\\"}\"}}\n",
        "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_1\",\"output\":[{\"id\":\"fc_1\",\"type\":\"function_call\",\"call_id\":\"call_1\",\"name\":\"graph_search\",\"arguments\":\"{\\\"query\\\":\\\"memory\\\"}\"}]}}\n"
    ])
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "test-key", model: "gpt-test"),
        httpClient: ResponsesCapturingHTTPClient(responseBody: Data()),
        sseClient: sseClient
    )

    var events: [AgentModelStreamEvent] = []
    for try await event in provider.streamComplete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "search")])) {
        events.append(event)
    }

    #expect(events.contains(.toolInputDelta(toolCallID: "call_1", name: "graph_search", partialJSON: "{\"query\":")))
    #expect(events.contains(.toolInputDelta(toolCallID: "call_1", name: "graph_search", partialJSON: "\"memory\"}")))
    let completed = try #require(events.compactMap { event -> AgentModelResponse? in
        if case .completed(let response) = event { return response }
        return nil
    }.last)
    #expect(completed.finishReason == .toolCalls)
    #expect(completed.toolCalls == [AgentToolCall(id: "call_1", name: "graph_search", argumentsJSON: "{\"query\":\"memory\"}")])
}
