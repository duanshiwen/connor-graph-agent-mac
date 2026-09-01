import Foundation
import Testing
import ConnorGraphAgent

private struct AdvancedAnthropicCapturingHTTPClient: AgentHTTPClient {
    final class Storage: @unchecked Sendable {
        var capturedRequest: AgentHTTPRequest?
        var requestCount = 0
    }
    var storage = Storage()
    var response = AgentHTTPResponse(statusCode: 200, body: Data(#"{"content":[{"type":"text","text":"OK"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}"#.utf8))
    mutating func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse {
        storage.capturedRequest = request
        storage.requestCount += 1
        return response
    }
}


private func capturedJSONObject(_ request: AgentHTTPRequest?) throws -> [String: Any] {
    let body = try #require(request?.body)
    return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
}

private struct FixtureSSEClient: AgentSSEHTTPClient {
    final class Storage: @unchecked Sendable {
        var capturedRequest: AgentHTTPRequest?
        var requestCount = 0
    }
    var frames: [String]
    var storage = Storage()

    func stream(_ request: AgentHTTPRequest) async throws -> AsyncThrowingStream<String, Error> {
        storage.capturedRequest = request
        storage.requestCount += 1
        let frames = frames
        return AsyncThrowingStream { continuation in
            for frame in frames { continuation.yield(frame) }
            continuation.finish()
        }
    }
}

private actor AnthropicSSECancellationState {
    private(set) var didStart = false
    private(set) var didTerminate = false

    func markStarted() { didStart = true }
    func markTerminated() { didTerminate = true }
}

private struct CancellationObservingSSEClient: AgentSSEHTTPClient {
    let state: AnthropicSSECancellationState

    func stream(_ request: AgentHTTPRequest) async throws -> AsyncThrowingStream<String, Error> {
        await state.markStarted()
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { @Sendable _ in
                Task { await state.markTerminated() }
            }
        }
    }
}

@Test func anthropicCompatibleConfigDefaultsRequestTimeoutTo180Seconds() throws {
    let config = AnthropicCompatibleConfig(
        baseURL: URL(string: "https://api.anthropic.com")!,
        apiKey: "sk-ant-test",
        model: "claude-sonnet-test"
    )

    #expect(config.requestTimeout == 300)
}

@Test func anthropicCompletionRequestUsesConfiguredTimeout() async throws {
    let client = AdvancedAnthropicCapturingHTTPClient()
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(
            baseURL: URL(string: "https://api.anthropic.com")!,
            apiKey: "sk-ant-test",
            model: "claude-sonnet-test",
            requestTimeout: 240
        ),
        httpClient: client
    )

    _ = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "Hello")]))

    #expect(client.storage.capturedRequest?.timeoutInterval == 240)
}

@Test func anthropicStreamRequestUsesConfiguredTimeout() async throws {
    let httpClient = AdvancedAnthropicCapturingHTTPClient()
    let sseClient = FixtureSSEClient(frames: [
        #"""
event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"input_tokens":1,"output_tokens":1}}
"""#,
        #"""
event: message_stop
data: {"type":"message_stop"}
"""#
    ])
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(
            baseURL: URL(string: "https://api.anthropic.com")!,
            apiKey: "sk-ant-test",
            model: "claude-sonnet-test",
            requestTimeout: 240
        ),
        httpClient: httpClient,
        sseClient: sseClient
    )

    for try await _ in provider.streamComplete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "Hi")])) {}

    #expect(sseClient.storage.capturedRequest?.timeoutInterval == 240)
}

@Test func anthropicStreamCancellationPropagatesToUnderlyingSSERequest() async throws {
    let state = AnthropicSSECancellationState()
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(
            baseURL: URL(string: "https://api.anthropic.com")!,
            apiKey: "sk-ant-test",
            model: "claude-sonnet-4-6"
        ),
        httpClient: AdvancedAnthropicCapturingHTTPClient(),
        sseClient: CancellationObservingSSEClient(state: state)
    )
    let consumer = Task {
        for try await _ in provider.streamComplete(.init(messages: [.init(role: .user, content: "Hello")])) {}
    }

    for _ in 0..<100 where !(await state.didStart) {
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await state.didStart)
    consumer.cancel()
    _ = await consumer.result
    for _ in 0..<100 where !(await state.didTerminate) {
        try await Task.sleep(for: .milliseconds(5))
    }

    #expect(await state.didTerminate)
}

@Test func anthropicRequestIncludesManualThinkingConfig() async throws {
    let client = AdvancedAnthropicCapturingHTTPClient()
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(
            baseURL: URL(string: "https://api.anthropic.com")!,
            apiKey: "sk-ant-test",
            model: "claude-sonnet-test",
            featureOptions: AnthropicCompatibleFeatureOptions(thinking: .enabled(budgetTokens: 10_000, display: .summarized))
        ),
        httpClient: client
    )

    _ = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "Think")]))

    let body = try #require(client.storage.capturedRequest?.body)
    let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    let thinking = try #require(object["thinking"] as? [String: Any])
    #expect(thinking["type"] as? String == "enabled")
    #expect(thinking["budget_tokens"] as? Int == 10_000)
    #expect(thinking["display"] as? String == "summarized")
}

@Test func anthropicRequestIncludesAdaptiveThinkingConfig() async throws {
    let client = AdvancedAnthropicCapturingHTTPClient()
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(
            baseURL: URL(string: "https://api.anthropic.com")!,
            apiKey: "sk-ant-test",
            model: "claude-sonnet-test",
            featureOptions: AnthropicCompatibleFeatureOptions(thinking: .adaptive(display: .omitted))
        ),
        httpClient: client
    )

    _ = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "Think")]))

    let object = try capturedJSONObject(client.storage.capturedRequest)
    let thinking = try #require(object["thinking"] as? [String: Any])
    #expect(thinking["type"] as? String == "adaptive")
    #expect(thinking["display"] as? String == "omitted")
}

@Test func anthropicRequestIncludesTopLevelPromptCacheControl() async throws {
    let client = AdvancedAnthropicCapturingHTTPClient()
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(
            baseURL: URL(string: "https://api.anthropic.com")!,
            apiKey: "sk-ant-test",
            model: "claude-sonnet-test",
            featureOptions: AnthropicCompatibleFeatureOptions(promptCache: AnthropicPromptCacheConfig(enabled: true, ttl: .oneHour))
        ),
        httpClient: client
    )

    _ = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "Cache")]))

    let object = try capturedJSONObject(client.storage.capturedRequest)
    let cache = try #require(object["cache_control"] as? [String: Any])
    #expect(cache["type"] as? String == "ephemeral")
    #expect(cache["ttl"] as? String == "1h")
}

@Test func anthropicExplicitBreakpointCachesOnlyStableSystemPrefix() async throws {
    let client = AdvancedAnthropicCapturingHTTPClient()
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(
            baseURL: URL(string: "https://api.anthropic.com")!,
            apiKey: "sk-ant-test",
            model: "claude-sonnet-test",
            featureOptions: AnthropicCompatibleFeatureOptions(promptCache: .init(enabled: true, ttl: .oneHour))
        ),
        httpClient: client
    )
    #expect(provider.capabilities.supportsExplicitPromptCacheBreakpoints)
    _ = try await provider.complete(.init(
        messages: [
            .init(role: .system, content: "stable kernel"),
            .init(role: .system, content: "Current Time: dynamic"),
            .init(role: .user, content: "request")
        ],
        promptCacheContext: .init(phase: .strategyResearch, promptVersion: "v1", stableToolBundleVersion: "tools", explicitBreakpointIndex: 1)
    ))

    let object = try capturedJSONObject(client.storage.capturedRequest)
    let system = try #require(object["system"] as? [[String: Any]])
    #expect(system.map { $0["text"] as? String } == ["stable kernel", "Current Time: dynamic"])
    #expect(system[0]["cache_control"] != nil)
    #expect(system[1]["cache_control"] == nil)
}

@Test func anthropicAdaptiveThinkingSerializesEffortWithoutManualBudget() async throws {
    let client = AdvancedAnthropicCapturingHTTPClient()
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(
            baseURL: URL(string: "https://api.anthropic.com")!,
            apiKey: "sk-ant-test",
            model: "claude-sonnet-4-6",
            featureOptions: AnthropicCompatibleFeatureOptions(
                thinking: .adaptive(display: .omitted),
                effort: "medium"
            )
        ),
        httpClient: client
    )

    _ = try await provider.complete(.init(messages: [.init(role: .user, content: "Hello")]))

    let object = try capturedJSONObject(client.storage.capturedRequest)
    let thinking = try #require(object["thinking"] as? [String: Any])
    let outputConfig = try #require(object["output_config"] as? [String: Any])
    #expect(thinking["type"] as? String == "adaptive")
    #expect(thinking["budget_tokens"] == nil)
    #expect(outputConfig["effort"] as? String == "medium")
}

@Test func anthropicMessageDeltaWaitsForRequiredMessageStop() throws {
    var accumulator = AnthropicStreamAccumulator()
    _ = accumulator.append(.contentBlockStart(
        index: 0,
        type: "text",
        rawJSON: #"{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#
    ))
    _ = accumulator.append(.textDelta(index: 0, text: "Done"))
    _ = accumulator.append(.contentBlockStop(index: 0))

    let deltaEvent = accumulator.append(.messageDelta(
        stopReason: "end_turn",
        usage: AgentModelUsage(promptTokens: 0, completionTokens: 7)
    ))
    #expect(deltaEvent == nil)

    guard case .completed(let response)? = accumulator.append(.messageStop) else {
        Issue.record("Expected message_stop to complete the stream")
        return
    }
    #expect(response.text == "Done")
    #expect(response.usage?.completionTokens == 7)
}

@Test func anthropicCompatibleEmptyStreamFallsBackOnceAndDisablesStreaming() async throws {
    let httpClient = AdvancedAnthropicCapturingHTTPClient()
    let sseClient = FixtureSSEClient(frames: [
        #"""
event: vendor_status
data: {"type":"vendor_status","status":"done"}
"""#
    ])
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(
            baseURL: URL(string: "https://gateway.example.com/anthropic")!,
            apiKey: "test-key",
            model: "deepseek-v4-flash"
        ),
        httpClient: httpClient,
        sseClient: sseClient
    )
    let request = AgentModelRequest(messages: [.init(role: .user, content: "Hello")])

    var firstResponse: AgentModelResponse?
    for try await event in provider.streamComplete(request) {
        if case .completed(let response) = event { firstResponse = response }
    }
    var secondResponse: AgentModelResponse?
    for try await event in provider.streamComplete(request) {
        if case .completed(let response) = event { secondResponse = response }
    }

    #expect(firstResponse?.text == "OK")
    #expect(secondResponse?.text == "OK")
    #expect(sseClient.storage.requestCount == 1)
    #expect(httpClient.storage.requestCount == 2)
}

@Test func anthropicNativeStreamEndingBeforeMessageStopThrows() async throws {
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(
            baseURL: URL(string: "https://api.anthropic.com")!,
            apiKey: "sk-ant-test",
            model: "claude-sonnet-test"
        ),
        httpClient: AdvancedAnthropicCapturingHTTPClient(),
        sseClient: FixtureSSEClient(frames: [
            #"""
event: message_start
data: {"type":"message_start","message":{"content":[],"usage":{"input_tokens":1,"output_tokens":0}}}
"""#
        ])
    )

    await #expect(throws: AnthropicCompatibleProviderError.streamError("Anthropic stream ended before message_stop.")) {
        for try await _ in provider.streamComplete(.init(messages: [.init(role: .user, content: "Hello")])) {}
    }
}

@Test func anthropicNonStreamingRejectsResponseWithoutContentOrStopReason() async throws {
    var httpClient = AdvancedAnthropicCapturingHTTPClient()
    httpClient.response = AgentHTTPResponse(statusCode: 200, body: Data(#"{"content":[]}"#.utf8))
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(
            baseURL: URL(string: "https://gateway.example.com/anthropic")!,
            apiKey: "test-key",
            model: "deepseek-v4-flash"
        ),
        httpClient: httpClient
    )

    await #expect(throws: AnthropicCompatibleProviderError.missingAssistantMessage) {
        _ = try await provider.complete(.init(messages: [.init(role: .user, content: "Hello")]))
    }
}

@Test func anthropicNonStreamingAcceptsDocumentedEmptyEndTurnResponse() async throws {
    var httpClient = AdvancedAnthropicCapturingHTTPClient()
    httpClient.response = AgentHTTPResponse(
        statusCode: 200,
        body: Data(#"{"content":[],"stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":3}}"#.utf8)
    )
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(
            baseURL: URL(string: "https://api.anthropic.com")!,
            apiKey: "sk-ant-test",
            model: "claude-sonnet-test"
        ),
        httpClient: httpClient
    )

    let response = try await provider.complete(.init(messages: [.init(role: .user, content: "Hello")]))
    #expect(response.text == nil)
    #expect(response.providerMetadata?.stopReason == "end_turn")
}

@Test func anthropicToolDefinitionsCanBeCachedAndEagerStreamed() async throws {
    let client = AdvancedAnthropicCapturingHTTPClient()
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(
            baseURL: URL(string: "https://api.anthropic.com")!,
            apiKey: "sk-ant-test",
            model: "claude-sonnet-test",
            featureOptions: AnthropicCompatibleFeatureOptions(
                eagerInputStreamingToolNames: ["write_file"],
                cachedToolNames: ["write_file"]
            )
        ),
        httpClient: client
    )

    _ = try await provider.complete(AgentModelRequest(
        messages: [AgentModelMessage(role: .user, content: "Write")],
        tools: [AgentToolDefinition(name: "write_file", description: "Write file", inputSchema: .object(properties: ["path": .string(description: "Path")], required: ["path"]))]
    ))

    let object = try capturedJSONObject(client.storage.capturedRequest)
    let tools = try #require(object["tools"] as? [[String: Any]])
    let tool = try #require(tools.first)
    #expect(tool["eager_input_streaming"] as? Bool == true)
    #expect(tool["cache_control"] != nil)
}

@Test func anthropicServerWebSearchToolMapsIntoRequestBody() async throws {
    let client = AdvancedAnthropicCapturingHTTPClient()
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(
            baseURL: URL(string: "https://api.anthropic.com")!,
            apiKey: "sk-ant-test",
            model: "claude-sonnet-test",
            featureOptions: AnthropicCompatibleFeatureOptions(serverTools: [.webSearch(maxUses: 3, allowedDomains: ["example.com"])])
        ),
        httpClient: client
    )

    _ = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "Search")]))

    let object = try capturedJSONObject(client.storage.capturedRequest)
    let tools = try #require(object["tools"] as? [[String: Any]])
    let serverTool = try #require(tools.first { $0["name"] as? String == "web_search" })
    #expect(serverTool["type"] as? String == "web_search_20250305")
    #expect(serverTool["max_uses"] as? Int == 3)
    #expect(serverTool["allowed_domains"] as? [String] == ["example.com"])
}

@Test func anthropicStreamRequestSetsStreamTrueAndEmitsTextDeltas() async throws {
    let httpClient = AdvancedAnthropicCapturingHTTPClient()
    let sseClient = FixtureSSEClient(frames: [
        #"""
event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}
"""#,
        #"""
event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}}
"""#,
        #"""
event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"lo"}}
"""#,
        #"""
event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"input_tokens":2,"output_tokens":1}}
"""#,
        #"""
event: message_stop
data: {"type":"message_stop"}
"""#
    ])
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(baseURL: URL(string: "https://api.anthropic.com")!, apiKey: "sk-ant-test", model: "claude-sonnet-test"),
        httpClient: httpClient,
        sseClient: sseClient
    )

    var events: [AgentModelStreamEvent] = []
    for try await event in provider.streamComplete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "Hi")])) {
        events.append(event)
    }

    let body = try #require(sseClient.storage.capturedRequest?.body)
    let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(object["stream"] as? Bool == true)
    #expect(events.contains(.textDelta("Hel")))
    #expect(events.contains(.textDelta("lo")))
    #expect(events.filter { if case .completed = $0 { true } else { false } }.count == 1)
    guard case .completed(let response)? = events.last else {
        Issue.record("Expected completed event")
        return
    }
    #expect(response.text == "Hello")
    #expect(response.usage?.promptTokens == 2)
}

@Test func anthropicSSEParserEmitsToolInputDeltaAndAccumulatorBuildsToolCall() throws {
    let parser = AnthropicSSEParser()
    var accumulator = AnthropicStreamAccumulator()
    let frames = [
        #"""
event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"write_file","input":{}}}
"""#,
        #"""
event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"path\":"}}
"""#,
        #"""
event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\"README.md\"}"}}
"""#,
        #"""
event: content_block_stop
data: {"type":"content_block_stop","index":0}
"""#,
        #"""
event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use"}}
"""#,
        #"""
event: message_stop
data: {"type":"message_stop"}
"""#
    ]

    var completed: AgentModelResponse?
    for frame in frames {
        for event in parser.parse(frame) {
            if case .completed(let response)? = accumulator.append(event) {
                completed = response
            }
        }
    }

    let response = try #require(completed)
    #expect(response.finishReason == .toolCalls)
    #expect(response.toolCalls.first?.id == "toolu_1")
    #expect(response.toolCalls.first?.name == "write_file")
    #expect(response.toolCalls.first?.argumentsJSON == #"{"path":"README.md"}"#)
    let rawContent = try #require(response.providerMetadata?.rawAssistantContentJSON)
    let blocks = try #require(try JSONSerialization.jsonObject(with: Data(rawContent.utf8)) as? [[String: Any]])
    #expect(blocks.count == 1)
    #expect(blocks.first?["type"] as? String == "tool_use")
    #expect(!rawContent.contains("content_block_start"))
}

@Test func anthropicAccumulatorPreservesInvalidFineGrainedToolInput() throws {
    let parser = AnthropicSSEParser()
    var accumulator = AnthropicStreamAccumulator()
    let frames = [
        #"""
event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_bad","name":"write_file","input":{}}}
"""#,
        #"""
event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"path\":"}}
"""#,
        #"""
event: content_block_stop
data: {"type":"content_block_stop","index":0}
"""#,
        #"""
event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"}}
"""#,
        #"""
event: message_stop
data: {"type":"message_stop"}
"""#
    ]
    var completed: AgentModelResponse?
    for frame in frames {
        for event in parser.parse(frame) {
            if case .completed(let response)? = accumulator.append(event) { completed = response }
        }
    }
    let response = try #require(completed)
    #expect(response.finishReason == .length)
    let argumentsJSON = try #require(response.toolCalls.first?.argumentsJSON)
    #expect(argumentsJSON.contains("INVALID_JSON") == true)
    // 标记升级后带诊断元数据（原文在标记内被 JSON 转义，无损解包由下方 payload.raw 断言保证）。
    #expect(argumentsJSON.contains("\"__length\":") == true)
    #expect(argumentsJSON.contains("\"__json_error\":") == true)
    #expect(ToolArgumentJSONDiagnostics.analyze(argumentsJSON) == nil)
    let payload = ToolArgumentJSONDiagnostics.unwrapInvalidJSONMarker(argumentsJSON)
    #expect(payload?.raw == #"{"path":"#)
}

@Test func anthropicThinkingDeltasArePreservedInProviderMetadata() throws {
    let parser = AnthropicSSEParser()
    var accumulator = AnthropicStreamAccumulator()
    let frames = [
        #"""
event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}
"""#,
        #"""
event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"I should reason."}}
"""#,
        #"""
event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig_123"}}
"""#,
        #"""
event: content_block_stop
data: {"type":"content_block_stop","index":0}
"""#,
        #"""
event: message_stop
data: {"type":"message_stop"}
"""#
    ]
    var completed: AgentModelResponse?
    for frame in frames {
        for event in parser.parse(frame) {
            if case .completed(let response)? = accumulator.append(event) { completed = response }
        }
    }
    let metadata = try #require(completed?.providerMetadata)
    #expect(metadata.rawAssistantContentJSON?.contains("I should reason.") == true)
    #expect(metadata.rawAssistantContentJSON?.contains("sig_123") == true)
    #expect(metadata.rawAssistantContentJSON?.contains("content_block_start") == false)
}

@Test func anthropicRawAssistantContentRoundTripsIntoNextRequest() async throws {
    let client = AdvancedAnthropicCapturingHTTPClient()
    let rawContent = #"[{"type":"thinking","thinking":"Reason","signature":"sig"},{"type":"tool_use","id":"toolu_1","name":"graph_search","input":{"query":"memory"}}]"#
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(baseURL: URL(string: "https://api.anthropic.com")!, apiKey: "sk-ant-test", model: "claude-sonnet-test"),
        httpClient: client
    )

    _ = try await provider.complete(AgentModelRequest(messages: [
        AgentModelMessage(role: .user, content: "Find"),
        AgentModelMessage(role: .assistant, content: "", providerMetadata: AgentModelProviderMetadata(providerID: "anthropic-compatible", rawAssistantContentJSON: rawContent, stopReason: "tool_use")),
        AgentModelMessage(role: .tool, content: "[]", toolCallID: "toolu_1", name: "graph_search")
    ]))

    let object = try capturedJSONObject(client.storage.capturedRequest)
    let messages = try #require(object["messages"] as? [[String: Any]])
    let assistant = try #require(messages.first { $0["role"] as? String == "assistant" })
    let content = try #require(assistant["content"] as? [[String: Any]])
    #expect(content.first?["type"] as? String == "thinking")
    #expect(content.dropFirst().first?["type"] as? String == "tool_use")
}

@Test func anthropicUsageNormalizesCacheTokensIntoPromptTokens() async throws {
    var client = AdvancedAnthropicCapturingHTTPClient()
    client.response = AgentHTTPResponse(
        statusCode: 200,
        body: Data(#"{"content":[{"type":"text","text":"OK"}],"stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":4,"cache_creation_input_tokens":200,"cache_read_input_tokens":3000}}"#.utf8)
    )
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(baseURL: URL(string: "https://api.anthropic.com")!, apiKey: "sk-ant-test", model: "claude-sonnet-test"),
        httpClient: client
    )

    let response = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "Hello")]))

    let usage = try #require(response.usage)
    // input_tokens excludes cache tokens on Anthropic; promptTokens is
    // normalized to the full input so cacheRead ⊆ promptTokens everywhere.
    #expect(usage.promptTokens == 3210)
    #expect(usage.cacheCreationInputTokens == 200)
    #expect(usage.cacheReadInputTokens == 3000)
    #expect(usage.uncachedInputTokens == 210)
}

@Test func anthropicStreamAccumulatorCapturesCacheUsageFromMessageStart() throws {
    let parser = AnthropicSSEParser()
    var accumulator = AnthropicStreamAccumulator()
    let frames = [
        #"""
event: message_start
data: {"type":"message_start","message":{"id":"msg_1","usage":{"input_tokens":10,"output_tokens":1,"cache_creation_input_tokens":200,"cache_read_input_tokens":3000}}}
"""#,
        #"""
event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}
"""#,
        #"""
event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}
"""#,
        #"""
event: content_block_stop
data: {"type":"content_block_stop","index":0}
"""#,
        #"""
event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":42}}
"""#,
        #"""
event: message_stop
data: {"type":"message_stop"}
"""#
    ]

    var completed: AgentModelResponse?
    for frame in frames {
        for event in parser.parse(frame) {
            if case .completed(let response)? = accumulator.append(event) { completed = response }
        }
    }

    let usage = try #require(completed?.usage)
    #expect(usage.promptTokens == 3210)
    #expect(usage.completionTokens == 42)
    #expect(usage.cacheCreationInputTokens == 200)
    #expect(usage.cacheReadInputTokens == 3000)
}
