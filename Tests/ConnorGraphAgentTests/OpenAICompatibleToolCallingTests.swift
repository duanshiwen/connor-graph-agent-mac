import Foundation
import CoreFoundation
import Testing
import ConnorGraphAgent

private struct ToolCallingCapturingHTTPClient: AgentHTTPClient {
    final class Storage: @unchecked Sendable { var capturedBody: Data? }
    var responseBody: Data
    var storage = Storage()

    mutating func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse {
        storage.capturedBody = request.body
        return AgentHTTPResponse(statusCode: 200, body: responseBody)
    }
}

@Test func openAICompatibleProviderSendsToolDefinitionsAndParsesToolCalls() async throws {
    let body = #"""
    {
      "choices": [
        {
          "message": {
            "role": "assistant",
            "content": null,
            "reasoning_content": "I should search the graph before answering.",
            "tool_calls": [
              {
                "id": "call-1",
                "type": "function",
                "function": {
                  "name": "graph_search",
                  "arguments": "{\"query\":\"memory\",\"limit\":5}"
                }
              }
            ]
          },
          "finish_reason": "tool_calls"
        }
      ],
      "usage": { "prompt_tokens": 12, "completion_tokens": 5, "total_tokens": 17 }
    }
    """#.data(using: .utf8)!
    let client = ToolCallingCapturingHTTPClient(responseBody: body)
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(baseURL: URL(string: "https://llm.example.com/v1")!, apiKey: "test-key", model: "gpt-test"),
        httpClient: client
    )
    let tools = [AgentToolDefinition(
        name: "graph_search",
        description: "Search graph",
        inputSchema: .object(properties: ["query": .string(description: "Query")], required: ["query"])
    )]

    let response = try await provider.completeWithTools(AgentModelRequest(
        messages: [AgentModelMessage(role: .user, content: "Find memory")],
        tools: tools
    ))

    #expect(response.toolCalls.map(\.name) == ["graph_search"])
    #expect(response.toolCalls.first?.argumentsJSON.contains("memory") == true)
    #expect(response.usage?.totalTokens == 17)
    #expect(response.providerMetadata?.providerID == "openai-compatible")
    #expect(response.providerMetadata?.reasoningContent == "I should search the graph before answering.")
    let captured = try #require(client.storage.capturedBody)
    let requestText = String(data: captured, encoding: .utf8) ?? ""
    #expect(requestText.contains("tools"))
    #expect(requestText.contains("graph_search"))
}

@Test func openAICompatibleProviderRecoversTextualDeepSeekToolCalls() async throws {
    let body = #"{"choices":[{"message":{"role":"assistant","content":"<tool_calls>\n<tool_call>\n{\"name\":\"graph_search\",\"arguments\":{\"query\":\"memory\"}}\n</tool_call>\n</tool_calls>"},"finish_reason":"stop"}]}"#.data(using: .utf8)!
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(baseURL: URL(string: "https://llm.example.com/v1")!, apiKey: "test-key", model: "deepseek-test"),
        httpClient: ToolCallingCapturingHTTPClient(responseBody: body)
    )

    let response = try await provider.completeWithTools(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "Search")]))

    #expect(response.text == nil)
    #expect(response.finishReason == .toolCalls)
    #expect(response.toolCalls.map(\.name) == ["graph_search"])
    #expect(response.toolCalls.first?.argumentsJSON == #"{"query":"memory"}"#)
}

@Test func openAICompatibleProviderRequiresToolCallsWhenRequested() async throws {
    let body = #"{"choices":[{"message":{"role":"assistant","content":"done"},"finish_reason":"stop"}]}"#.data(using: .utf8)!
    let client = ToolCallingCapturingHTTPClient(responseBody: body)
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(baseURL: URL(string: "https://llm.example.com/v1")!, apiKey: "test-key", model: "gpt-test"),
        httpClient: client
    )
    let tool = AgentToolDefinition(name: "phase_gate", description: "Advance phase", inputSchema: .object(properties: [:], required: []))

    _ = try await provider.completeWithTools(AgentModelRequest(
        messages: [AgentModelMessage(role: .user, content: "advance")],
        tools: [tool],
        toolChoice: .required
    ))

    let captured = try #require(client.storage.capturedBody)
    let object = try #require(try JSONSerialization.jsonObject(with: captured) as? [String: Any])
    #expect(object["tool_choice"] as? String == "required")
}

@Test func openAICompatibleProviderOmitsAutomaticToolChoiceForThinkingCompatibility() async throws {
    let body = #"{"choices":[{"message":{"role":"assistant","content":"done"},"finish_reason":"stop"}]}"#.data(using: .utf8)!
    let client = ToolCallingCapturingHTTPClient(responseBody: body)
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(
            baseURL: URL(string: "https://llm.example.com/v1")!,
            apiKey: "test-key",
            model: "thinking-model",
            reasoningEffort: "high"
        ),
        httpClient: client
    )
    let tool = AgentToolDefinition(
        name: "assistant_tool_search",
        description: "Discover tools",
        inputSchema: .object(properties: [:], required: [])
    )

    _ = try await provider.completeWithTools(AgentModelRequest(
        messages: [AgentModelMessage(role: .user, content: "discover")],
        tools: [tool],
        toolChoice: .auto
    ))

    let captured = try #require(client.storage.capturedBody)
    let object = try #require(try JSONSerialization.jsonObject(with: captured) as? [String: Any])
    #expect(object["tools"] != nil)
    #expect(object["tool_choice"] == nil)
    #expect(object["reasoning_effort"] as? String == "high")
}

@Test func openAICompatibleProviderPreservesClosedObjectBooleanOnWire() async throws {
    let body = #"""
    {
      "choices": [
        {
          "message": { "role": "assistant", "content": "Done." },
          "finish_reason": "stop"
        }
      ],
      "usage": { "prompt_tokens": 8, "completion_tokens": 2, "total_tokens": 10 }
    }
    """#.data(using: .utf8)!
    let client = ToolCallingCapturingHTTPClient(responseBody: body)
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(baseURL: URL(string: "https://llm.example.com/v1")!, apiKey: "test-key", model: "gpt-test"),
        httpClient: client
    )

    _ = try await provider.completeWithTools(AgentModelRequest(
        messages: [AgentModelMessage(role: .user, content: "Read calendar")],
        tools: [AgentToolDefinition(
            name: "calendar_read",
            description: "Read calendar data",
            inputSchema: .closedObject(properties: [
                "operation": .stringEnumeration(values: ["list_calendars", "list_events"], description: "Read operation"),
                "calendarID": .nullable(.string(description: "Calendar identifier")),
                "limit": .integer(description: "Maximum results"),
                "confidence": .number(description: "Confidence threshold"),
                "includeDeclined": .boolean(description: "Include declined events"),
                "tags": .array(items: .string(description: "Tag"), description: "Event tags"),
                "filter": .closedObject(properties: [
                    "query": .string(description: "Filter query")
                ], required: ["query"])
            ], required: ["operation"])
        )]
    ))

    let captured = try #require(client.storage.capturedBody)
    let requestText = try #require(String(data: captured, encoding: .utf8))
    #expect(!requestText.contains(#""additionalProperties":0"#))

    let object = try #require(try JSONSerialization.jsonObject(with: captured) as? [String: Any])
    let tools = try #require(object["tools"] as? [[String: Any]])
    let function = try #require(tools.first?["function"] as? [String: Any])
    let parameters = try #require(function["parameters"] as? [String: Any])
    let additionalProperties = try #require(parameters["additionalProperties"])
    #expect(CFGetTypeID(additionalProperties as CFTypeRef) == CFBooleanGetTypeID())
    #expect(additionalProperties as? Bool == false)
    let properties = try #require(parameters["properties"] as? [String: Any])
    #expect((properties["limit"] as? [String: Any])?["type"] as? String == "integer")
    #expect((properties["confidence"] as? [String: Any])?["type"] as? String == "number")
    #expect((properties["includeDeclined"] as? [String: Any])?["type"] as? String == "boolean")
    #expect((properties["calendarID"] as? [String: Any])?["type"] as? [String] == ["string", "null"])
    let tags = try #require(properties["tags"] as? [String: Any])
    #expect((tags["items"] as? [String: Any])?["type"] as? String == "string")
    let filter = try #require(properties["filter"] as? [String: Any])
    let nestedAdditionalProperties = try #require(filter["additionalProperties"])
    #expect(CFGetTypeID(nestedAdditionalProperties as CFTypeRef) == CFBooleanGetTypeID())
    #expect(nestedAdditionalProperties as? Bool == false)
}

@Test func openAICompatibleProviderSerializesDeveloperInstructionPlacement() async throws {
    let body = #"""
    {
      "choices": [
        {
          "message": { "role": "assistant", "content": "Done." },
          "finish_reason": "stop"
        }
      ],
      "usage": { "prompt_tokens": 8, "completion_tokens": 2, "total_tokens": 10 }
    }
    """#.data(using: .utf8)!
    let client = ToolCallingCapturingHTTPClient(responseBody: body)
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(baseURL: URL(string: "https://llm.example.com/v1")!, apiKey: "test-key", model: "gpt-test"),
        httpClient: client
    )

    _ = try await provider.completeWithTools(AgentModelRequest(
        messages: [
            AgentModelMessage(role: .system, content: "Core instruction"),
            AgentModelMessage(role: .user, content: "Hello")
        ],
        instructionPlacement: .developerMessage
    ))

    let captured = try #require(client.storage.capturedBody)
    let object = try #require(try JSONSerialization.jsonObject(with: captured) as? [String: Any])
    let messages = try #require(object["messages"] as? [[String: Any]])
    #expect(messages.first?["role"] as? String == "developer")
    #expect(messages.first?["content"] as? String == "Core instruction")
}

@Test func openAICompatibleProviderSerializesImageContentParts() async throws {
    let body = #"""
    {
      "choices": [
        {
          "message": { "role": "assistant", "content": "I can see it." },
          "finish_reason": "stop"
        }
      ],
      "usage": { "prompt_tokens": 20, "completion_tokens": 4, "total_tokens": 24 }
    }
    """#.data(using: .utf8)!
    let client = ToolCallingCapturingHTTPClient(responseBody: body)
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(baseURL: URL(string: "https://llm.example.com/v1")!, apiKey: "test-key", model: "gpt-vision-test"),
        httpClient: client
    )

    _ = try await provider.completeWithTools(AgentModelRequest(messages: [
        AgentModelMessage(
            role: .user,
            content: "Describe the image",
            contentParts: [
                .text("Describe the image"),
                .imageDataURL("data:image/png;base64,aGVsbG8=", mimeType: "image/png", detail: "auto")
            ]
        )
    ]))

    let captured = try #require(client.storage.capturedBody)
    let object = try #require(try JSONSerialization.jsonObject(with: captured) as? [String: Any])
    let messages = try #require(object["messages"] as? [[String: Any]])
    let user = try #require(messages.first(where: { $0["role"] as? String == "user" }))
    let content = try #require(user["content"] as? [[String: Any]])
    #expect(content.first?["type"] as? String == "text")
    #expect(content.first?["text"] as? String == "Describe the image")
    #expect(content.dropFirst().first?["type"] as? String == "image_url")
    let imageURL = try #require(content.dropFirst().first?["image_url"] as? [String: Any])
    #expect(imageURL["url"] as? String == "data:image/png;base64,aGVsbG8=")
    #expect(imageURL["detail"] as? String == "auto")
}

@Test func openAICompatibleProviderSerializesAssistantToolCallsInConversationHistory() async throws {
    let body = #"""
    {
      "choices": [
        {
          "message": { "role": "assistant", "content": "Done." },
          "finish_reason": "stop"
        }
      ],
      "usage": { "prompt_tokens": 20, "completion_tokens": 3, "total_tokens": 23 }
    }
    """#.data(using: .utf8)!
    let client = ToolCallingCapturingHTTPClient(responseBody: body)
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(baseURL: URL(string: "https://llm.example.com/v1")!, apiKey: "test-key", model: "gpt-test"),
        httpClient: client
    )

    _ = try await provider.completeWithTools(AgentModelRequest(messages: [
        AgentModelMessage(role: .user, content: "Find memory"),
        AgentModelMessage(
            role: .assistant,
            content: "",
            toolCalls: [AgentToolCall(id: "call-1", name: "graph_search", argumentsJSON: #"{"query":"memory"}"#)],
            providerMetadata: AgentModelProviderMetadata(
                providerID: "openai-compatible",
                reasoningContent: "I need the graph result before answering."
            )
        ),
        AgentModelMessage(role: .tool, content: #"{"hits":[]}"#, toolCallID: "call-1", name: "graph_search")
    ]))

    let captured = try #require(client.storage.capturedBody)
    let object = try #require(try JSONSerialization.jsonObject(with: captured) as? [String: Any])
    let messages = try #require(object["messages"] as? [[String: Any]])
    let assistant = try #require(messages.first(where: { $0["role"] as? String == "assistant" }))
    #expect(assistant["reasoning_content"] as? String == "I need the graph result before answering.")
    let toolCalls = try #require(assistant["tool_calls"] as? [[String: Any]])
    #expect(toolCalls.first?["id"] as? String == "call-1")
    let function = try #require(toolCalls.first?["function"] as? [String: Any])
    #expect(function["name"] as? String == "graph_search")
    #expect(function["arguments"] as? String == #"{"query":"memory"}"#)
    let tool = try #require(messages.first(where: { $0["role"] as? String == "tool" }))
    #expect(tool["tool_call_id"] as? String == "call-1")
    #expect(tool["name"] as? String == "graph_search")
}

@Test func openAICompatibleProviderParsesOpenAIStyleCachedPromptTokens() async throws {
    let body = #"""
    {
      "choices": [{ "message": { "role": "assistant", "content": "Hi" }, "finish_reason": "stop" }],
      "usage": {
        "prompt_tokens": 1200,
        "completion_tokens": 5,
        "total_tokens": 1205,
        "prompt_tokens_details": { "cached_tokens": 1024 }
      }
    }
    """#.data(using: .utf8)!
    let client = ToolCallingCapturingHTTPClient(responseBody: body)
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(baseURL: URL(string: "https://llm.example.com/v1")!, apiKey: "test-key", model: "gpt-test"),
        httpClient: client
    )

    let response = try await provider.completeWithTools(AgentModelRequest(
        messages: [AgentModelMessage(role: .user, content: "Hello")]
    ))

    let usage = try #require(response.usage)
    #expect(usage.promptTokens == 1200)
    #expect(usage.cacheReadInputTokens == 1024)
    #expect(usage.uncachedInputTokens == 176)
}

@Test func openAICompatibleProviderParsesDeepSeekStyleCacheHitTokens() async throws {
    let body = #"""
    {
      "choices": [{ "message": { "role": "assistant", "content": "Hi" }, "finish_reason": "stop" }],
      "usage": {
        "prompt_tokens": 1200,
        "completion_tokens": 5,
        "total_tokens": 1205,
        "prompt_cache_hit_tokens": 1000,
        "prompt_cache_miss_tokens": 200
      }
    }
    """#.data(using: .utf8)!
    let client = ToolCallingCapturingHTTPClient(responseBody: body)
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(baseURL: URL(string: "https://llm.example.com/v1")!, apiKey: "test-key", model: "deepseek-test"),
        httpClient: client
    )

    let response = try await provider.completeWithTools(AgentModelRequest(
        messages: [AgentModelMessage(role: .user, content: "Hello")]
    ))

    let usage = try #require(response.usage)
    #expect(usage.cacheReadInputTokens == 1000)
    #expect(usage.uncachedInputTokens == 200)
}
