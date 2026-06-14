import Foundation
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
    let captured = try #require(client.storage.capturedBody)
    let requestText = String(data: captured, encoding: .utf8) ?? ""
    #expect(requestText.contains("tools"))
    #expect(requestText.contains("graph_search"))
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
            toolCalls: [AgentToolCall(id: "call-1", name: "graph_search", argumentsJSON: #"{"query":"memory"}"#)]
        ),
        AgentModelMessage(role: .tool, content: #"{"hits":[]}"#, toolCallID: "call-1", name: "graph_search")
    ]))

    let captured = try #require(client.storage.capturedBody)
    let object = try #require(try JSONSerialization.jsonObject(with: captured) as? [String: Any])
    let messages = try #require(object["messages"] as? [[String: Any]])
    let assistant = try #require(messages.first(where: { $0["role"] as? String == "assistant" }))
    let toolCalls = try #require(assistant["tool_calls"] as? [[String: Any]])
    #expect(toolCalls.first?["id"] as? String == "call-1")
    let function = try #require(toolCalls.first?["function"] as? [String: Any])
    #expect(function["name"] as? String == "graph_search")
    #expect(function["arguments"] as? String == #"{"query":"memory"}"#)
    let tool = try #require(messages.first(where: { $0["role"] as? String == "tool" }))
    #expect(tool["tool_call_id"] as? String == "call-1")
    #expect(tool["name"] as? String == "graph_search")
}
