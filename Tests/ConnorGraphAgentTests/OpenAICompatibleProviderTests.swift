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
        var timeoutInterval: TimeInterval?
    }

    init(responseBody: Data, statusCode: Int = 200) {
        self.responseBody = responseBody
        self.statusCode = statusCode
        self.storage = Storage()
    }

    mutating func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse {
        storage.captured = CapturedRequest(
            url: request.url,
            method: request.method,
            headers: request.headers,
            body: request.body,
            timeoutInterval: request.timeoutInterval
        )
        return AgentHTTPResponse(statusCode: statusCode, body: responseBody)
    }
}

@Test func openAICompatibleConfigDefaultsRequestTimeoutToThreeMinutes() throws {
    let config = OpenAICompatibleConfig(
        baseURL: URL(string: "https://llm.example.com/v1")!,
        apiKey: "test-key",
        model: "gpt-test"
    )

    #expect(config.requestTimeout == 300)
}

@Test func openAICompatibleProviderAppliesConfiguredRequestTimeout() async throws {
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
            model: "gpt-test",
            requestTimeout: 240
        ),
        httpClient: client
    )

    _ = try await provider.complete(prompt: "ping", context: AgentContext(query: "ping", items: []))

    #expect(client.captured?.timeoutInterval == 240)
}

@Test func openAICompatibleToolCallingRequestAppliesConfiguredRequestTimeout() async throws {
    let body = """
    {
      "choices": [
        { "message": { "role": "assistant", "content": "OK" }, "finish_reason": "stop" }
      ]
    }
    """.data(using: .utf8)!
    let client = CapturingHTTPClient(responseBody: body)
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(
            baseURL: URL(string: "https://llm.example.com/v1")!,
            apiKey: "test-key",
            model: "gpt-test",
            requestTimeout: 240
        ),
        httpClient: client
    )

    _ = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "ping")]))

    #expect(client.captured?.timeoutInterval == 240)
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
    #expect(requestText.contains("You are 康纳同学 (Connor), a personal AI assistant for everyday work and life."))
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

@Test func openAICompatibleProviderPreservesUnifiedAgentPromptAndTools() async throws {
    let body = """
    {
      "choices": [
        { "message": { "role": "assistant", "content": "OK" }, "finish_reason": "stop" }
      ]
    }
    """.data(using: .utf8)!
    let client = CapturingHTTPClient(responseBody: body)
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(baseURL: URL(string: "https://llm.example.com/v1")!, apiKey: "test-key", model: "gpt-test"),
        httpClient: client
    )
    let tool = AgentToolDefinition(
        name: "graph_search",
        description: "Search graph memory",
        inputSchema: .object(properties: ["query": .string(description: "Query")], required: ["query"])
    )

    _ = try await provider.complete(AgentModelRequest(
        messages: [
            AgentModelMessage(role: .system, content: "Connor core\n\n## 用户基本信息\n- 称呼：段诗闻"),
            AgentModelMessage(role: .user, content: "我叫什么？")
        ],
        tools: [tool]
    ))

    let requestBody = try #require(client.captured?.body)
    let object = try #require(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
    let messages = try #require(object["messages"] as? [[String: Any]])
    #expect(messages.first?["role"] as? String == "system")
    #expect((messages.first?["content"] as? String)?.contains("## 用户基本信息") == true)
    #expect((messages.first?["content"] as? String)?.contains("段诗闻") == true)
    let tools = try #require(object["tools"] as? [[String: Any]])
    let function = try #require(tools.first?["function"] as? [String: Any])
    #expect(function["name"] as? String == "graph_search")
    #expect(function["description"] as? String == "Search graph memory")
}

@Test func openAICompatibleProviderCanUseAPIKeyHeaderInsteadOfBearer() async throws {
    let body = """
    {
      "choices": [{"message": {"role": "assistant", "content": "OK"}}],
      "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}
    }
    """.data(using: .utf8)!
    let client = CapturingHTTPClient(responseBody: body)
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(
            baseURL: URL(string: "https://api.xiaomimimo.com/v1")!,
            apiKey: "mimo-secret",
            model: "mimo-v2.5-pro",
            apiKeyHeaderKind: .apiKey
        ),
        httpClient: client
    )

    _ = try await provider.complete(prompt: "hello", context: AgentContext(query: "hello", items: []))

    #expect(client.captured?.headers["api-key"] == "mimo-secret")
    #expect(client.captured?.headers["Authorization"] == nil)
}

@Test func openAICompatibleProviderSerializesImageDataURLContentPartsWhenModelSupportsVision() async throws {
    let body = """
    {
      "choices": [
        { "message": { "role": "assistant", "content": "I can see it." }, "finish_reason": "stop" }
      ]
    }
    """.data(using: .utf8)!
    let client = CapturingHTTPClient(responseBody: body)
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(baseURL: URL(string: "https://llm.example.com/v1")!, apiKey: "test-key", model: "gpt-4o-mini"),
        httpClient: client
    )

    _ = try await provider.complete(AgentModelRequest(messages: [
        AgentModelMessage(
            role: .user,
            content: "Describe this image",
            contentParts: [.text("Describe this image"), .imageDataURL("data:image/png;base64,iVBORw0KGgo=", mimeType: "image/png", detail: "auto")]
        )
    ]))

    let requestBody = try #require(client.captured?.body)
    let object = try #require(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
    let messages = try #require(object["messages"] as? [[String: Any]])
    let content = try #require(messages.first?["content"] as? [[String: Any]])
    #expect(content.first?["type"] as? String == "text")
    #expect(content.first?["text"] as? String == "Describe this image")
    let imagePart = try #require(content.first { $0["type"] as? String == "image_url" })
    let imageURL = try #require(imagePart["image_url"] as? [String: Any])
    #expect(imageURL["url"] as? String == "data:image/png;base64,iVBORw0KGgo=")
    #expect(imageURL["detail"] as? String == "auto")
}

@Test func openAICompatibleProviderRejectsImageContentWhenCapabilityKernelDeniesVision() async throws {
    let body = """
    {
      "choices": [
        { "message": { "role": "assistant", "content": "OK" }, "finish_reason": "stop" }
      ]
    }
    """.data(using: .utf8)!
    let client = CapturingHTTPClient(responseBody: body)
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(baseURL: URL(string: "https://llm.example.com/v1")!, apiKey: "test-key", model: "text-only-test"),
        httpClient: client
    )

    let result = try await provider.complete(AgentModelRequest(messages: [
        AgentModelMessage(
            role: .user,
            content: "Describe this image",
            contentParts: [.text("Describe this image"), .imageDataURL("data:image/png;base64,iVBORw0KGgo=", mimeType: "image/png")]
        )
    ]))

    #expect(result.text == "OK")
    #expect(result.warnings.contains("⚠️ 当前模型不支持图片输入，已自动发送文字内容。图片内容已忽略。"))
    let requestBody = String(decoding: try #require(client.captured?.body), as: UTF8.self)
    #expect(requestBody.contains("Describe this image"))
    #expect(!requestBody.contains("image_url"))
    #expect(!requestBody.contains("iVBORw0KGgo="))
}

@Test func openAICompatibleProviderReportsHTTPError() async throws {
    let body = #"{"error":{"message":"bad key"}}"#.data(using: .utf8)!
    let client = CapturingHTTPClient(responseBody: body, statusCode: 401)
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(baseURL: URL(string: "https://llm.example.com/v1")!, apiKey: "bad", model: "gpt-test"),
        httpClient: client
    )
    let context = AgentContext(query: "memory", items: [])

    await #expect(throws: OpenAICompatibleProviderError.httpStatus(401, message: "bad key")) {
        try await provider.complete(prompt: "memory", context: context)
    }
}

@Test func openAICompatibleProviderHTTPErrorDescriptionIncludesSafeResponseMessage() async throws {
    let body = #"{"error":{"message":"unsupported parameter: temperature","type":"invalid_request_error"}}"#.data(using: .utf8)!
    let client = CapturingHTTPClient(responseBody: body, statusCode: 400)
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(baseURL: URL(string: "https://llm.example.com/v1")!, apiKey: "secret-key", model: "gpt-test"),
        httpClient: client
    )
    let context = AgentContext(query: "memory", items: [])

    do {
        _ = try await provider.complete(prompt: "memory", context: context)
        Issue.record("Expected HTTP error")
    } catch {
        let description = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        #expect(description.contains("HTTP 400"))
        #expect(description.contains("unsupported parameter: temperature"))
        #expect(description.contains("secret-key") == false)
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
    let requestObject = try #require(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
    let messages = try #require(requestObject["messages"] as? [[String: Any]])
    #expect(requestObject["model"] as? String == "gpt-health")
    #expect(messages.count == 1)
    #expect(messages.first?["role"] as? String == "user")
    #expect(messages.first?["content"] as? String == "Reply with exactly: OK")
    #expect(requestObject["temperature"] == nil)
    #expect(requestObject["reasoning_effort"] == nil)
    #expect(requestObject["tools"] == nil)
    #expect(requestObject["tool_choice"] == nil)
    #expect(requestObject["stream"] == nil)
}

@Test func openAICompatibleProviderHealthCheckFailsOnHTTPError() async throws {
    let body = #"{"error":{"message":"bad key"}}"#.data(using: .utf8)!
    let client = CapturingHTTPClient(responseBody: body, statusCode: 403)
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(baseURL: URL(string: "https://llm.example.com/v1")!, apiKey: "bad", model: "gpt-health"),
        httpClient: client
    )

    await #expect(throws: OpenAICompatibleProviderError.httpStatus(403, message: "bad key")) {
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
