import Foundation
import Testing
import ConnorGraphAgent

private struct OpenAIStreamingCapturingSSEClient: AgentSSEHTTPClient {
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

private struct OpenAIStreamingFallbackHTTPClient: AgentHTTPClient {
    var responseBody: Data = """
    {
      "choices": [
        { "message": { "role": "assistant", "content": "fallback" }, "finish_reason": "stop" }
      ]
    }
    """.data(using: .utf8)!

    mutating func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse {
        AgentHTTPResponse(statusCode: 200, body: responseBody)
    }
}

@Test func openAICompatibleProviderAdvertisesStreamingCapability() throws {
    let provider = OpenAICompatibleProvider(config: OpenAICompatibleConfig(
        baseURL: URL(string: "https://llm.example.com/v1")!,
        apiKey: "test-key",
        model: "gpt-test"
    ))

    #expect(provider.capabilities.supportsStreaming == true)
}

@Test func openAICompatibleProviderStreamsTextDeltasAndCompletedResponse() async throws {
    let sseClient = OpenAIStreamingCapturingSSEClient(frames: [
        "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\",\"content\":\"Hel\"}}]}\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\"lo\"},\"finish_reason\":\"stop\"}]}\n",
        "data: [DONE]\n"
    ])
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(
            baseURL: URL(string: "https://llm.example.com/v1")!,
            apiKey: "test-key",
            model: "gpt-test",
            requestTimeout: 240
        ),
        httpClient: OpenAIStreamingFallbackHTTPClient(),
        sseClient: sseClient
    )

    var events: [AgentModelStreamEvent] = []
    for try await event in provider.streamComplete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "Say hello")])) {
        events.append(event)
    }

    #expect(events.contains(.textDelta("Hel")))
    #expect(events.contains(.textDelta("lo")))
    let completed = try #require(events.compactMap { event -> AgentModelResponse? in
        if case .completed(let response) = event { return response }
        return nil
    }.last)
    #expect(completed.text == "Hello")
    #expect(completed.finishReason == .stop)
    #expect(sseClient.captured?.timeoutInterval == 240)
    let requestBody = try #require(sseClient.captured?.body)
    let object = try #require(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
    #expect(object["stream"] as? Bool == true)
}

@Test func anyAgentModelProviderPreservesOpenAICompatibleStreamingPath() async throws {
    let sseClient = OpenAIStreamingCapturingSSEClient(frames: [
        "data: {\"choices\":[{\"delta\":{\"content\":\"streamed\"},\"finish_reason\":\"stop\"}]}\n",
        "data: [DONE]\n"
    ])
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(
            baseURL: URL(string: "https://llm.example.com/v1")!,
            apiKey: "test-key",
            model: "gpt-test"
        ),
        httpClient: OpenAIStreamingFallbackHTTPClient(),
        sseClient: sseClient
    )
    let erased = AnyAgentModelProvider(provider)

    var events: [AgentModelStreamEvent] = []
    for try await event in erased.streamComplete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "stream")])) {
        events.append(event)
    }

    #expect(erased.capabilities.supportsStreaming == true)
    #expect(events.contains(.textDelta("streamed")))
    #expect(sseClient.captured != nil)
}

@Test func openAICompatibleProviderStreamsToolCallArgumentsAndCompletedResponse() async throws {
    let sseClient = OpenAIStreamingCapturingSSEClient(frames: [
        "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"I should search \"}}]}\n",
        "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"the graph.\",\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"graph_search\",\"arguments\":\"{\\\"query\\\":\"}}]}}]}\n",
        "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"memory\\\"}\"}}]},\"finish_reason\":\"tool_calls\"}]}\n",
        "data: [DONE]\n"
    ])
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(
            baseURL: URL(string: "https://llm.example.com/v1")!,
            apiKey: "test-key",
            model: "gpt-test"
        ),
        httpClient: OpenAIStreamingFallbackHTTPClient(),
        sseClient: sseClient
    )

    var events: [AgentModelStreamEvent] = []
    for try await event in provider.streamComplete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "Search memory")])) {
        events.append(event)
    }

    #expect(events.contains(.toolInputDelta(toolCallID: "call_1", name: "graph_search", partialJSON: "{\"query\":")))
    #expect(events.contains(.toolInputDelta(toolCallID: "call_1", name: "graph_search", partialJSON: "memory\"}")))
    #expect(events.contains(.thinkingDelta("I should search ")))
    #expect(events.contains(.thinkingDelta("the graph.")))
    let completed = try #require(events.compactMap { event -> AgentModelResponse? in
        if case .completed(let response) = event { return response }
        return nil
    }.last)
    #expect(completed.finishReason == .toolCalls)
    #expect(completed.toolCalls == [AgentToolCall(id: "call_1", name: "graph_search", argumentsJSON: "{\"query\":memory\"}")])
    #expect(completed.providerMetadata?.reasoningContent == "I should search the graph.")
}
