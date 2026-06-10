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
