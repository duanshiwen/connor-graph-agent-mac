import Foundation
import Testing
import ConnorGraphAgent

private struct AnthropicCapturingHTTPClient: AgentHTTPClient {
    final class Storage: @unchecked Sendable {
        var capturedRequest: AgentHTTPRequest?
    }

    var response: AgentHTTPResponse
    var storage = Storage()

    init(statusCode: Int = 200, body: String = AnthropicFixtures.textResponse) {
        self.response = AgentHTTPResponse(statusCode: statusCode, body: body.data(using: .utf8)!)
    }

    mutating func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse {
        storage.capturedRequest = request
        return response
    }
}

private enum AnthropicFixtures {
    static let textResponse = #"""
    {
      "id": "msg_123",
      "type": "message",
      "role": "assistant",
      "model": "claude-sonnet-test",
      "content": [
        { "type": "text", "text": "OK" }
      ],
      "stop_reason": "end_turn",
      "usage": { "input_tokens": 5, "output_tokens": 1 }
    }
    """#

    static let toolUseResponse = #"""
    {
      "id": "msg_456",
      "type": "message",
      "role": "assistant",
      "model": "claude-sonnet-test",
      "content": [
        { "type": "text", "text": "I'll search." },
        { "type": "tool_use", "id": "toolu_123", "name": "graph_search", "input": { "query": "memory", "limit": 5 } }
      ],
      "stop_reason": "tool_use",
      "usage": { "input_tokens": 12, "output_tokens": 7 }
    }
    """#
}

@Test func anthropicBaseURLWithoutV1BuildsMessagesEndpoint() async throws {
    let client = AnthropicCapturingHTTPClient()
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(baseURL: URL(string: "https://api.anthropic.com")!, apiKey: "sk-ant-test", model: "claude-sonnet-test"),
        httpClient: client
    )

    _ = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "Hello")]))

    let request = try #require(client.storage.capturedRequest)
    #expect(request.url.absoluteString == "https://api.anthropic.com/v1/messages")
}

@Test func anthropicBaseURLWithV1BuildsMessagesEndpointWithoutDuplicatingV1() async throws {
    let client = AnthropicCapturingHTTPClient()
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(baseURL: URL(string: "https://api.anthropic.com/v1")!, apiKey: "sk-ant-test", model: "claude-sonnet-test"),
        httpClient: client
    )

    _ = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "Hello")]))

    let request = try #require(client.storage.capturedRequest)
    #expect(request.url.absoluteString == "https://api.anthropic.com/v1/messages")
}

@Test func anthropicXAPIKeyAuthBuildsAnthropicHeaders() async throws {
    let client = AnthropicCapturingHTTPClient()
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(
            baseURL: URL(string: "https://api.anthropic.com")!,
            apiKey: "sk-ant-test",
            model: "claude-sonnet-test",
            authHeaderKind: .xAPIKey,
            anthropicVersion: "2023-06-01"
        ),
        httpClient: client
    )

    _ = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "Hello")]))

    let headers = try #require(client.storage.capturedRequest?.headers)
    #expect(headers["x-api-key"] == "sk-ant-test")
    #expect(headers["anthropic-version"] == "2023-06-01")
    #expect(headers["Content-Type"] == "application/json")
    #expect(headers["Authorization"] == nil)
}

@Test func anthropicBearerAuthBuildsAuthorizationHeader() async throws {
    let client = AnthropicCapturingHTTPClient()
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(
            baseURL: URL(string: "https://openrouter.ai/api")!,
            apiKey: "sk-or-test",
            model: "anthropic/claude-sonnet-test",
            authHeaderKind: .bearer
        ),
        httpClient: client
    )

    _ = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "Hello")]))

    let headers = try #require(client.storage.capturedRequest?.headers)
    #expect(headers["Authorization"] == "Bearer sk-or-test")
    #expect(headers["x-api-key"] == nil)
}

@Test func anthropicPlainPromptBuildsMessagesRequestWithTopLevelSystem() async throws {
    let client = AnthropicCapturingHTTPClient()
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(baseURL: URL(string: "https://api.anthropic.com")!, apiKey: "sk-ant-test", model: "claude-sonnet-test"),
        httpClient: client
    )

    _ = try await provider.complete(AgentModelRequest(messages: [
        AgentModelMessage(role: .system, content: "Core instruction"),
        AgentModelMessage(role: .user, content: "Hello")
    ]))

    let body = try #require(client.storage.capturedRequest?.body)
    let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(object["model"] as? String == "claude-sonnet-test")
    #expect(object["system"] as? String == "Core instruction")
    #expect(object["max_tokens"] as? Int == 4096)
    let messages = try #require(object["messages"] as? [[String: Any]])
    #expect(messages.count == 1)
    #expect(messages.first?["role"] as? String == "user")
    let content = try #require(messages.first?["content"] as? [[String: Any]])
    #expect(content.first?["type"] as? String == "text")
    #expect(content.first?["text"] as? String == "Hello")
}

@Test func anthropicParsesTextResponse() async throws {
    let client = AnthropicCapturingHTTPClient(body: AnthropicFixtures.textResponse)
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(baseURL: URL(string: "https://api.anthropic.com")!, apiKey: "sk-ant-test", model: "claude-sonnet-test"),
        httpClient: client
    )

    let response = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "Health")]))

    #expect(response.text == "OK")
    #expect(response.toolCalls.isEmpty)
    #expect(response.usage?.promptTokens == 5)
    #expect(response.usage?.completionTokens == 1)
    #expect(response.finishReason == .stop)
}

@Test func anthropicToolDefinitionsMapToAnthropicTools() async throws {
    let client = AnthropicCapturingHTTPClient()
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(baseURL: URL(string: "https://api.anthropic.com")!, apiKey: "sk-ant-test", model: "claude-sonnet-test"),
        httpClient: client
    )
    let tools = [AgentToolDefinition(
        name: "graph_search",
        description: "Search graph",
        inputSchema: .object(properties: ["query": .string(description: "Query")], required: ["query"])
    )]

    _ = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "Find memory")], tools: tools))

    let body = try #require(client.storage.capturedRequest?.body)
    let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    let requestTools = try #require(object["tools"] as? [[String: Any]])
    #expect(requestTools.first?["name"] as? String == "graph_search")
    #expect(requestTools.first?["description"] as? String == "Search graph")
    #expect(requestTools.first?["input_schema"] != nil)
}

@Test func anthropicParsesToolUseResponseIntoAgentToolCalls() async throws {
    let client = AnthropicCapturingHTTPClient(body: AnthropicFixtures.toolUseResponse)
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(baseURL: URL(string: "https://api.anthropic.com")!, apiKey: "sk-ant-test", model: "claude-sonnet-test"),
        httpClient: client
    )

    let response = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "Find memory")]))

    #expect(response.text == "I'll search.")
    #expect(response.toolCalls.map(\.name) == ["graph_search"])
    #expect(response.toolCalls.first?.id == "toolu_123")
    #expect(response.toolCalls.first?.argumentsJSON.contains("memory") == true)
    #expect(response.finishReason == .toolCalls)
}

@Test func anthropicToolResultMessageMapsToUserToolResultBlock() async throws {
    let client = AnthropicCapturingHTTPClient()
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(baseURL: URL(string: "https://api.anthropic.com")!, apiKey: "sk-ant-test", model: "claude-sonnet-test"),
        httpClient: client
    )

    _ = try await provider.complete(AgentModelRequest(messages: [
        AgentModelMessage(role: .user, content: "Find memory"),
        AgentModelMessage(role: .assistant, content: "", toolCalls: [AgentToolCall(id: "toolu_123", name: "graph_search", argumentsJSON: #"{"query":"memory"}"#)]),
        AgentModelMessage(role: .tool, content: #"{"hits":[]}"#, toolCallID: "toolu_123", name: "graph_search")
    ]))

    let body = try #require(client.storage.capturedRequest?.body)
    let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    let messages = try #require(object["messages"] as? [[String: Any]])
    let assistant = try #require(messages.first(where: { $0["role"] as? String == "assistant" }))
    let assistantContent = try #require(assistant["content"] as? [[String: Any]])
    #expect(assistantContent.first?["type"] as? String == "tool_use")
    #expect(assistantContent.first?["id"] as? String == "toolu_123")
    let toolResultMessage = try #require(messages.last)
    #expect(toolResultMessage["role"] as? String == "user")
    let content = try #require(toolResultMessage["content"] as? [[String: Any]])
    #expect(content.first?["type"] as? String == "tool_result")
    #expect(content.first?["tool_use_id"] as? String == "toolu_123")
}

@Test func anthropicHealthCheckReturnsOKWhenProviderRespondsWithText() async throws {
    let client = AnthropicCapturingHTTPClient(body: AnthropicFixtures.textResponse)
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(baseURL: URL(string: "https://api.anthropic.com")!, apiKey: "sk-ant-test", model: "claude-sonnet-test"),
        httpClient: client
    )

    let result = try await provider.healthCheck()

    #expect(result.ok)
    #expect(result.model == "claude-sonnet-test")
}

@Test func anthropicHealthCheckThrowsOnHTTPFailure() async throws {
    let client = AnthropicCapturingHTTPClient(statusCode: 401, body: #"{"error":{"message":"unauthorized"}}"#)
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(baseURL: URL(string: "https://api.anthropic.com")!, apiKey: "bad-key", model: "claude-sonnet-test"),
        httpClient: client
    )

    await #expect(throws: AnthropicCompatibleProviderError.httpStatus(401)) {
        _ = try await provider.healthCheck()
    }
}
