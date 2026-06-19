import Foundation
import Testing
import ConnorGraphAgent

private struct AdvancedAnthropicCapturingHTTPClient: AgentHTTPClient {
    final class Storage: @unchecked Sendable { var capturedRequest: AgentHTTPRequest? }
    var storage = Storage()
    var response = AgentHTTPResponse(statusCode: 200, body: Data(#"{"content":[{"type":"text","text":"OK"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}"#.utf8))
    mutating func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse {
        storage.capturedRequest = request
        return response
    }
}


private func capturedJSONObject(_ request: AgentHTTPRequest?) throws -> [String: Any] {
    let body = try #require(request?.body)
    return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
}

private struct FixtureSSEClient: AgentSSEHTTPClient {
    final class Storage: @unchecked Sendable { var capturedRequest: AgentHTTPRequest? }
    var frames: [String]
    var storage = Storage()

    func stream(_ request: AgentHTTPRequest) async throws -> AsyncThrowingStream<String, Error> {
        storage.capturedRequest = request
        let frames = frames
        return AsyncThrowingStream { continuation in
            for frame in frames { continuation.yield(frame) }
            continuation.finish()
        }
    }
}

@Test func anthropicCompatibleConfigDefaultsRequestTimeoutTo180Seconds() throws {
    let config = AnthropicCompatibleConfig(
        baseURL: URL(string: "https://api.anthropic.com")!,
        apiKey: "sk-ant-test",
        model: "claude-sonnet-test"
    )

    #expect(config.requestTimeout == 180)
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
    #expect(response.toolCalls.first?.argumentsJSON.contains("INVALID_JSON") == true)
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
