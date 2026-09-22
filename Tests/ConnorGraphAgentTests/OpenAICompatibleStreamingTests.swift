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

@Test func openAICompatibleProviderSuppressesAndRecoversStreamedTextualToolCalls() async throws {
    let sseClient = OpenAIStreamingCapturingSSEClient(frames: [
        "data: {\"choices\":[{\"delta\":{\"content\":\"<to\"}}]}\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\"ol_calls><tool_call>{\\\"name\\\":\\\"graph_search\\\",\\\"arguments\\\":{\\\"query\\\":\\\"memory\\\"}}</tool_call></tool_calls>\"},\"finish_reason\":\"stop\"}]}\n",
        "data: [DONE]\n"
    ])
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(baseURL: URL(string: "https://llm.example.com/v1")!, apiKey: "test-key", model: "deepseek-test"),
        httpClient: OpenAIStreamingFallbackHTTPClient(),
        sseClient: sseClient
    )

    var events: [AgentModelStreamEvent] = []
    for try await event in provider.streamComplete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "Search")])) {
        events.append(event)
    }

    #expect(!events.contains { if case .textDelta = $0 { return true }; return false })
    let response = try #require(events.compactMap { if case .completed(let response) = $0 { return response }; return nil }.last)
    #expect(response.text == nil)
    #expect(response.finishReason == .toolCalls)
    #expect(response.toolCalls.map(\.name) == ["graph_search"])
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

@Test func openAICompatibleProviderDoesNotOverwriteStreamedToolNameWithEmptyDelta() async throws {
    let sseClient = OpenAIStreamingCapturingSSEClient(frames: [
        "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"agent_commit_strategy\",\"arguments\":\"{\\\"taskMode\\\":\"}}]}}]}\n",
        "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"name\":\"\",\"arguments\":\"\\\"mechanical\\\"}\"}}]},\"finish_reason\":\"tool_calls\"}]}\n",
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
    for try await event in provider.streamComplete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "Plan")])) {
        events.append(event)
    }

    let completed = try #require(events.compactMap { event -> AgentModelResponse? in
        if case .completed(let response) = event { return response }
        return nil
    }.last)
    #expect(completed.toolCalls == [
        AgentToolCall(id: "call_1", name: "agent_commit_strategy", argumentsJSON: "{\"taskMode\":\"mechanical\"}")
    ])
}

@Test func openAICompatibleProviderCapturesStreamedEncryptedThinkingBlock() async throws {
    let sseClient = OpenAIStreamingCapturingSSEClient(frames: [
        "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\",\"reasoning_content\":\"用户想查\"}}]}\n",
        "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"天气。\"}}]}\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\"\",\"reasoning_content\":\"\",\"encrypted_content\":\"ARK-ENCRYPTED-BLOCK-002\"}}]}\n",
        "data: {\"choices\":[{\"delta\":{\"content\":\"北京晴\"},\"finish_reason\":\"stop\"}]}\n",
        "data: [DONE]\n"
    ])
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(
            baseURL: URL(string: "https://ark.cn-beijing.volces.com/api/v3")!,
            apiKey: "ark-key",
            model: "doubao-seed-evolving"
        ),
        httpClient: OpenAIStreamingFallbackHTTPClient(),
        sseClient: sseClient
    )

    var events: [AgentModelStreamEvent] = []
    for try await event in provider.streamComplete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "北京天气")])) {
        events.append(event)
    }

    let completed = try #require(events.compactMap { event -> AgentModelResponse? in
        if case .completed(let response) = event { return response }
        return nil
    }.last)
    let metadata = try #require(completed.providerMetadata)
    #expect(metadata.reasoningContent == "用户想查天气。")
    #expect(metadata.encryptedContent == "ARK-ENCRYPTED-BLOCK-002")
    #expect(completed.text == "北京晴")
}

private func deepSeekStreamProvider(_ frames: [String]) -> OpenAICompatibleProvider {
    OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(baseURL: URL(string: "https://api.deepseek.com")!, apiKey: "test-key", model: "deepseek-flash"),
        httpClient: OpenAIStreamingFallbackHTTPClient(),
        sseClient: OpenAIStreamingCapturingSSEClient(frames: frames))
}

@Test func deepSeekStreamAcceptsUsageWithoutChoices() async throws {
    let provider = deepSeekStreamProvider([
        "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"finish_reason\":\"stop\"}]}\n",
        "data: {\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":2,\"total_tokens\":12,\"prompt_cache_hit_tokens\":4}}\n",
        "data: [DONE]\n"
    ])
    var result: AgentModelResponse?
    for try await event in provider.streamComplete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "hi")])) {
        if case .completed(let response) = event { result = response }
    }
    #expect(result?.text == "Hello")
    #expect(result?.usage?.totalTokens == 12)
    #expect(result?.usage?.cacheReadInputTokens == 4)
}

@Test func deepSeekStreamSurfacesErrorInsteadOfMissingChoices() async throws {
    let provider = deepSeekStreamProvider([
        "data: {\"error\":{\"message\":\"Model Not Exist\",\"type\":\"invalid_request_error\"}}\n",
        "data: [DONE]\n"
    ])
    do {
        for try await _ in provider.streamComplete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "hi")])) { }
        Issue.record("Expected upstream error")
    } catch let error as OpenAICompatibleProviderError {
        #expect(error == .streamError("Model Not Exist"))
    }
}

@Test func deepSeekStreamRejectsTruncationAndUnknownEnvelopes() async throws {
    for (frame, expected) in [
        ("data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n", OpenAICompatibleProviderError.incompleteStream),
        ("data: {\"unexpected\":true}\n", OpenAICompatibleProviderError.invalidResponse),
        ("data: {\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":0,\"total_tokens\":1}}\n", OpenAICompatibleProviderError.incompleteStream)
    ] {
        do {
            for try await event in deepSeekStreamProvider([frame]).streamComplete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "hi")])) {
                if case .completed = event { Issue.record("An unfinished response must not complete") }
            }
            Issue.record("Expected stream failure")
        } catch let error as OpenAICompatibleProviderError { #expect(error == expected) }
    }
}

@Test func deepSeekStreamAcceptsFinishReasonWithoutDone() async throws {
    let provider = deepSeekStreamProvider(["data: {\"choices\":[{\"delta\":{\"content\":\"ok\"},\"finish_reason\":\"stop\"}]}\n"])
    var completed = false
    for try await event in provider.streamComplete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "hi")])) {
        if case .completed = event { completed = true }
    }
    #expect(completed)
}
