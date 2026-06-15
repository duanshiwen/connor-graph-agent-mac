import Foundation
import Testing
import ConnorGraphSearch
import ConnorGraphAgent

private struct CapturingHTTPClient: AgentHTTPClient {
    final class Storage: @unchecked Sendable {
        var captured: CapturedRequest?
    }

    var responseBody: Data
    var statusCode: Int
    var storage: Storage

    var captured: CapturedRequest? { storage.captured }

    struct CapturedRequest: Sendable, Equatable {
        var url: URL
        var method: String
        var headers: [String: String]
        var body: Data
    }

    init(responseBody: Data, statusCode: Int = 200) {
        self.responseBody = responseBody
        self.statusCode = statusCode
        self.storage = Storage()
    }

    mutating func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse {
        storage.captured = CapturedRequest(url: request.url, method: request.method, headers: request.headers, body: request.body)
        return AgentHTTPResponse(statusCode: statusCode, body: responseBody)
    }
}

@Test func openAICompatibleConfigReadsEnvironmentWithoutHardcodingSecrets() throws {
    let environment = [
        "CONNOR_LLM_BASE_URL": "https://llm.example.com/v1",
        "CONNOR_LLM_API_KEY": "test-key",
        "CONNOR_LLM_MODEL": "gpt-test"
    ]

    let config = try OpenAICompatibleConfig.fromEnvironment(environment)

    #expect(config.baseURL.absoluteString == "https://llm.example.com/v1")
    #expect(config.apiKey == "test-key")
    #expect(config.model == "gpt-test")
}

@Test func openAICompatibleConfigReturnsNilWhenApiKeyMissing() throws {
    let config = try OpenAICompatibleConfig.optionalFromEnvironment(["CONNOR_LLM_MODEL": "gpt-test"])

    #expect(config == nil)
}

@Test func openAICompatibleProviderBuildsChatCompletionRequestAndParsesResponse() async throws {
    let body = """
    {
      "choices": [
        { "message": { "role": "assistant", "content": "Graph grounded answer." } }
      ]
    }
    """.data(using: .utf8)!
    let client = CapturingHTTPClient(responseBody: body)
    let config = OpenAICompatibleConfig(
        baseURL: URL(string: "https://llm.example.com/v1")!,
        apiKey: "test-key",
        model: "gpt-test"
    )
    let provider = OpenAICompatibleProvider(config: config, httpClient: client)
    let context = AgentContext(
        query: "memory",
        items: [AgentContextItem(sourceID: "entity:memory", kind: .node, content: "Graph memory context", reason: "matched node")]
    )

    let response = try await provider.complete(prompt: "How should memory work?", context: context)

    #expect(response.text == "Graph grounded answer.")
    #expect(response.citations == ["entity:memory"])
    #expect(client.captured?.url.absoluteString == "https://llm.example.com/v1/chat/completions")
    #expect(client.captured?.method == "POST")
    #expect(client.captured?.headers["Authorization"] == "Bearer test-key")
    let requestJSON = try #require(client.captured?.body)
    let requestText = String(data: requestJSON, encoding: .utf8) ?? ""
    #expect(requestText.contains("gpt-test"))
    #expect(requestText.contains("You are Connor, a general-purpose local AI assistant."))
    #expect(requestText.contains("Connor Graph Agent") == false)
    #expect(requestText.contains("How should memory work?"))
    #expect(requestText.contains("Graph memory context"))
}

@Test func openAICompatibleProviderUsesFirstModelFromCommaSeparatedModelList() async throws {
    let body = """
    {
      "choices": [
        { "message": { "role": "assistant", "content": "OK" } }
      ]
    }
    """.data(using: .utf8)!
    let client = CapturingHTTPClient(responseBody: body)
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(
            baseURL: URL(string: "https://llm.example.com/v1")!,
            apiKey: "test-key",
            model: "mimo-v2.5-pro, mimo-v2.5, mimo-v2.5-tts"
        ),
        httpClient: client
    )
    let context = AgentContext(query: "ping", items: [])

    _ = try await provider.complete(prompt: "ping", context: context)

    let requestBody = try #require(client.captured?.body)
    let requestObject = try JSONSerialization.jsonObject(with: requestBody) as? [String: Any]
    #expect(requestObject?["model"] as? String == "mimo-v2.5-pro")
}

@Test func openAICompatibleProviderReportsHTTPError() async throws {
    let body = #"{"error":{"message":"bad key"}}"#.data(using: .utf8)!
    let client = CapturingHTTPClient(responseBody: body, statusCode: 401)
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(baseURL: URL(string: "https://llm.example.com/v1")!, apiKey: "bad", model: "gpt-test"),
        httpClient: client
    )
    let context = AgentContext(query: "memory", items: [])

    await #expect(throws: OpenAICompatibleProviderError.httpStatus(401)) {
        try await provider.complete(prompt: "memory", context: context)
    }
}

@Test func openAICompatibleProviderHealthCheckUsesChatCompletionEndpoint() async throws {
    let body = """
    {
      "choices": [
        { "message": { "role": "assistant", "content": "OK" } }
      ]
    }
    """.data(using: .utf8)!
    let client = CapturingHTTPClient(responseBody: body)
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(baseURL: URL(string: "https://llm.example.com/v1")!, apiKey: "secret-key", model: "gpt-health"),
        httpClient: client
    )

    let result = try await provider.healthCheck()

    #expect(result.ok == true)
    #expect(result.model == "gpt-health")
    #expect(result.message.contains("gpt-health"))
    #expect(result.message.contains("secret-key") == false)
    #expect(client.captured?.url.absoluteString == "https://llm.example.com/v1/chat/completions")
    #expect(client.captured?.headers["Authorization"] == "Bearer secret-key")
    let requestBody = try #require(client.captured?.body)
    let requestText = String(data: requestBody, encoding: .utf8) ?? ""
    #expect(requestText.contains("Reply with exactly: OK"))
}

@Test func openAICompatibleProviderHealthCheckFailsOnHTTPError() async throws {
    let body = #"{\"error\":{\"message\":\"bad key\"}}"#.data(using: .utf8)!
    let client = CapturingHTTPClient(responseBody: body, statusCode: 403)
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(baseURL: URL(string: "https://llm.example.com/v1")!, apiKey: "bad", model: "gpt-health"),
        httpClient: client
    )

    await #expect(throws: OpenAICompatibleProviderError.httpStatus(403)) {
        try await provider.healthCheck()
    }
}

@Test func realOpenAICompatibleProviderSmokeSkipsWithoutApiKey() async throws {
    guard let config = try OpenAICompatibleConfig.optionalFromEnvironment(ProcessInfo.processInfo.environment) else {
        return
    }

    let provider = OpenAICompatibleProvider(config: config)
    let context = AgentContext(query: "ping", items: [])
    let response = try await provider.complete(prompt: "Reply with one short sentence.", context: context)

    #expect(!response.text.isEmpty)
}
