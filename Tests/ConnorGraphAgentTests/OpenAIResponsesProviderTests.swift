import Foundation
import CoreFoundation
import Testing
@testable import ConnorGraphAgent

private struct ResponsesCapturingHTTPClient: AgentHTTPClient {
    final class Storage: @unchecked Sendable {
        var captured: AgentHTTPRequest?
    }

    var responseBody: Data
    var statusCode: Int
    var storage = Storage()

    var captured: AgentHTTPRequest? { storage.captured }

    init(responseBody: Data, statusCode: Int = 200) {
        self.responseBody = responseBody
        self.statusCode = statusCode
    }

    mutating func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse {
        storage.captured = request
        return AgentHTTPResponse(statusCode: statusCode, body: responseBody)
    }
}

private struct ResponsesCapturingSSEClient: AgentSSEHTTPClient {
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

@Test func openAIResponsesProviderBuildsResponsesRequest() async throws {
    let body = """
    {
      "id": "resp_1",
      "output": [
        {"type":"message","content":[{"type":"output_text","text":"Hello from Responses"}]}
      ],
      "usage": {"input_tokens": 2, "output_tokens": 3, "total_tokens": 5}
    }
    """.data(using: .utf8)!
    let client = ResponsesCapturingHTTPClient(responseBody: body, statusCode: 200)
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: "test-key",
            model: "gpt-test",
            requestTimeout: 240
        ),
        httpClient: client
    )

    let response = try await provider.complete(AgentModelRequest(messages: [
        AgentModelMessage(role: .system, content: "Connor system"),
        AgentModelMessage(role: .user, content: "Say hello")
    ], promptCacheContext: .init(phase: .strategyResearch, promptVersion: "v1", stableToolBundleVersion: "tools-v1", explicitBreakpointIndex: 1)))

    #expect(response.text == "Hello from Responses")
    #expect(client.captured?.url.absoluteString == "https://api.openai.com/v1/responses")
    #expect(client.captured?.method == "POST")
    #expect(client.captured?.headers["Authorization"] == "Bearer test-key")
    #expect(client.captured?.timeoutInterval == 240)
    let requestBody = try #require(client.captured?.body)
    let object = try #require(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
    #expect(object["model"] as? String == "gpt-test")
    #expect(object["store"] as? Bool == false)
    #expect((object["prompt_cache_key"] as? String)?.hasPrefix("connor:") == true)
    #expect(object["messages"] == nil)
    let input = try #require(object["input"] as? [[String: Any]])
    #expect(input.count == 2)
    #expect(input[0]["role"] as? String == "system")
    #expect(input[1]["role"] as? String == "user")
}

@Test func openAIResponsesProviderParsesPromptCacheUsageDetails() async throws {
    let body = """
    {
      "id": "resp_cache",
      "output": [{"type":"message","content":[{"type":"output_text","text":"Cached"}]}],
      "usage": {
        "input_tokens": 2006,
        "output_tokens": 30,
        "total_tokens": 2036,
        "input_tokens_details": {"cached_tokens": 1920, "cache_write_tokens": 64}
      }
    }
    """.data(using: .utf8)!
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "test-key", model: "gpt-test"),
        httpClient: ResponsesCapturingHTTPClient(responseBody: body)
    )

    let response = try await provider.complete(AgentModelRequest(messages: [
        AgentModelMessage(role: .system, content: "Stable prefix"),
        AgentModelMessage(role: .user, content: "Hello")
    ]))

    #expect(response.usage?.promptTokens == 2006)
    #expect(response.usage?.completionTokens == 30)
    #expect(response.usage?.cacheReadInputTokens == 1920)
    #expect(response.usage?.cacheCreationInputTokens == 64)
    #expect(response.usage?.uncachedInputTokens == 86)
}

@Test func openAIResponsesProviderRequiresToolCallsWhenRequested() async throws {
    let responseBody = #"{"id":"r","output":[{"type":"message","content":[{"type":"output_text","text":"ok"}]}]}"#.data(using: .utf8)!
    let client = ResponsesCapturingHTTPClient(responseBody: responseBody)
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "key", model: "gpt-test"),
        httpClient: client
    )
    let tool = AgentToolDefinition(name: "phase_gate", description: "Advance phase", inputSchema: .object(properties: [:], required: []))

    _ = try await provider.complete(.init(
        messages: [.init(role: .user, content: "advance")],
        tools: [tool],
        toolChoice: .required
    ))

    let body = try #require(client.captured?.body)
    let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(object["tool_choice"] as? String == "required")
}

@Test func openAIResponsesPromptCacheKeyStaysStableAcrossAgentLoopPhases() async throws {
    let responseBody = #"{"id":"r","output":[{"type":"message","content":[{"type":"output_text","text":"ok"}]}]}"#.data(using: .utf8)!
    let firstClient = ResponsesCapturingHTTPClient(responseBody: responseBody)
    let secondClient = ResponsesCapturingHTTPClient(responseBody: responseBody)
    let config = OpenAIResponsesConfig(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "key", model: "gpt-test")
    let firstCache = AgentPromptCacheContext(phase: .strategyResearch, promptVersion: "v3", stableToolBundleVersion: "a,b", explicitBreakpointIndex: 1)
    let secondCache = AgentPromptCacheContext(phase: .finalSynthesis, promptVersion: "v3", stableToolBundleVersion: "a,b", explicitBreakpointIndex: 1)
    _ = try await OpenAIResponsesProvider(config: config, httpClient: firstClient).complete(.init(
        messages: [.init(role: .system, content: "Current Time: first")],
        promptCacheContext: firstCache
    ))
    _ = try await OpenAIResponsesProvider(config: config, httpClient: secondClient).complete(.init(
        messages: [.init(role: .system, content: "Current Time: second")],
        promptCacheContext: secondCache
    ))
    let firstBody = try #require(firstClient.captured?.body)
    let secondBody = try #require(secondClient.captured?.body)
    let first = try #require(try JSONSerialization.jsonObject(with: firstBody) as? [String: Any])
    let second = try #require(try JSONSerialization.jsonObject(with: secondBody) as? [String: Any])
    #expect(first["prompt_cache_key"] as? String == second["prompt_cache_key"] as? String)
}

@Test func openAIResponsesProviderPreservesSanitizedHTTPErrorMessage() async throws {
    let body = #"{"error":{"message":"Invalid schema for function 'calendar_read': 0 is not of type 'object', 'boolean'"}}"#.data(using: .utf8)!
    let client = ResponsesCapturingHTTPClient(responseBody: body, statusCode: 400)
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(baseURL: URL(string: "https://relay.example.com/v1")!, apiKey: "test-key", model: "gpt-test"),
        httpClient: client
    )

    do {
        _ = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "test")]))
        Issue.record("Expected HTTP error")
    } catch let error as OpenAICompatibleProviderError {
        #expect(error == .httpStatus(400, message: "Invalid schema for function 'calendar_read': 0 is not of type 'object', 'boolean'"))
    }
}

@Test func openAIResponsesProviderMapsReasoningEffortAndIncludeEncryptedReasoning() async throws {
    let body = #"{"id":"resp_1","output":[{"type":"message","content":[{"type":"output_text","text":"OK"}]}]}"#.data(using: .utf8)!
    let client = ResponsesCapturingHTTPClient(responseBody: body, statusCode: 200)
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: "test-key",
            model: "o-test",
            reasoningEffort: "high",
            includeEncryptedReasoning: true
        ),
        httpClient: client
    )

    _ = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "think")]))

    let requestBody = try #require(client.captured?.body)
    let object = try #require(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
    let reasoning = try #require(object["reasoning"] as? [String: Any])
    #expect(reasoning["effort"] as? String == "high")
    let include = try #require(object["include"] as? [String])
    #expect(include.contains("reasoning.encrypted_content"))
}

@Test func openAIResponsesProviderEnablesStrictOnlyForCompatibleSchemas() async throws {
    let body = #"{"id":"resp_1","output":[{"type":"message","content":[{"type":"output_text","text":"OK"}]}]}"#.data(using: .utf8)!
    let client = ResponsesCapturingHTTPClient(responseBody: body, statusCode: 200)
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "test-key", model: "gpt-test"),
        httpClient: client
    )
    let strictTool = AgentToolDefinition(
        name: "strict_tool",
        description: "Strict tool",
        inputSchema: .closedObject(properties: ["query": .string(description: "Query")], required: ["query"])
    )
    let flexibleTool = AgentToolDefinition(
        name: "flexible_tool",
        description: "Flexible tool",
        inputSchema: .object(properties: ["query": .string(description: "Query")], required: ["query"])
    )

    _ = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "test")], tools: [strictTool, flexibleTool]))

    let requestBody = try #require(client.captured?.body)
    let object = try #require(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
    let tools = try #require(object["tools"] as? [[String: Any]])
    let strict = try #require(tools.first { $0["name"] as? String == "strict_tool" })
    let flexible = try #require(tools.first { $0["name"] as? String == "flexible_tool" })
    let strictFlag = try #require(strict["strict"])
    let flexibleFlag = try #require(flexible["strict"])
    #expect(CFGetTypeID(strictFlag as CFTypeRef) == CFBooleanGetTypeID())
    #expect(CFGetTypeID(flexibleFlag as CFTypeRef) == CFBooleanGetTypeID())
    #expect(strictFlag as? Bool == true)
    #expect(flexibleFlag as? Bool == false)
    let strictParameters = try #require(strict["parameters"] as? [String: Any])
    let additionalProperties = try #require(strictParameters["additionalProperties"])
    #expect(CFGetTypeID(additionalProperties as CFTypeRef) == CFBooleanGetTypeID())
    #expect(additionalProperties as? Bool == false)
}

@Test func openAIResponsesProviderParsesFunctionCallItems() async throws {
    let body = """
    {
      "id": "resp_1",
      "output": [
        {"id":"rs_1","type":"reasoning","summary":[]},
        {"id":"fc_1","type":"function_call","call_id":"call_1","name":"graph_search","arguments":"{\\"query\\":\\"memory\\"}","status":"completed"}
      ],
      "usage": {"input_tokens": 10, "output_tokens": 4, "total_tokens": 14}
    }
    """.data(using: .utf8)!
    let client = ResponsesCapturingHTTPClient(responseBody: body, statusCode: 200)
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "test-key", model: "gpt-test"),
        httpClient: client
    )

    let response = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "search")]))

    #expect(response.finishReason == .toolCalls)
    #expect(response.toolCalls == [AgentToolCall(id: "call_1", name: "graph_search", argumentsJSON: "{\"query\":\"memory\"}")])
    #expect(response.usage == AgentModelUsage(promptTokens: 10, completionTokens: 4, totalTokens: 14))
    #expect(response.providerMetadata?.providerID == "openai-responses")
    #expect(response.providerMetadata?.responseID == "resp_1")
    #expect(response.providerMetadata?.rawOutputItemsJSON?.contains("function_call") == true)
}

@Test func openAIResponsesProviderMapsIncompleteStatusToLength() async throws {
    let body = """
    {
      "id": "resp_trunc",
      "status": "incomplete",
      "output": [
        {"id":"msg_1","type":"message","content":[{"type":"output_text","text":"Half of the answer..."}]}
      ],
      "usage": {"input_tokens": 10, "output_tokens": 100, "total_tokens": 110}
    }
    """.data(using: .utf8)!
    let client = ResponsesCapturingHTTPClient(responseBody: body, statusCode: 200)
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "test-key", model: "gpt-test"),
        httpClient: client
    )

    let response = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "answer")]))

    #expect(response.finishReason == .length)
    #expect(response.text?.hasPrefix("Half of the answer") == true)
    #expect(response.providerMetadata?.stopReason == "incomplete")
}

@Test func openAIResponsesProviderSerializesFunctionCallOutputs() async throws {
    let body = #"{"id":"resp_2","output":[{"type":"message","content":[{"type":"output_text","text":"Done"}]}]}"#.data(using: .utf8)!
    let client = ResponsesCapturingHTTPClient(responseBody: body, statusCode: 200)
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "test-key", model: "gpt-test"),
        httpClient: client
    )

    _ = try await provider.complete(AgentModelRequest(messages: [
        AgentModelMessage(
            role: .assistant,
            content: "",
            toolCalls: [AgentToolCall(id: "call_1", name: "graph_search", argumentsJSON: "{\"query\":\"memory\"}")],
            providerMetadata: AgentModelProviderMetadata(
                providerID: "openai-responses",
                rawOutputItemsJSON: #"[{"id":"rs_1","type":"reasoning","encrypted_content":"opaque"},{"id":"fc_1","type":"function_call","call_id":"call_1","name":"graph_search","arguments":"{\"query\":\"memory\"}","status":"completed"}]"#,
                reasoningEncryptedContentPresent: true
            )
        ),
        AgentModelMessage(role: .tool, content: "{\"result\":\"found\"}", toolCallID: "call_1", name: "graph_search")
    ]))

    let requestBody = try #require(client.captured?.body)
    let object = try #require(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
    let input = try #require(object["input"] as? [[String: Any]])
    let reasoning = try #require(input.first { $0["type"] as? String == "reasoning" })
    #expect(reasoning["encrypted_content"] as? String == "opaque")
    let functionCall = try #require(input.first { $0["type"] as? String == "function_call" })
    #expect(functionCall["call_id"] as? String == "call_1")
    #expect(functionCall["name"] as? String == "graph_search")
    let output = try #require(input.first { $0["type"] as? String == "function_call_output" })
    #expect(output["call_id"] as? String == "call_1")
    #expect(output["output"] as? String == "{\"result\":\"found\"}")
}

@Test func openAIResponsesProviderDropsDeferredFunctionCallsWhileKeepingReasoning() async throws {
    let body = #"{"id":"resp_2","output":[{"type":"message","content":[{"type":"output_text","text":"Done"}]}]}"#.data(using: .utf8)!
    let client = ResponsesCapturingHTTPClient(responseBody: body, statusCode: 200)
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "test-key", model: "gpt-test"),
        httpClient: client
    )

    _ = try await provider.complete(AgentModelRequest(messages: [
        AgentModelMessage(
            role: .assistant,
            content: "",
            toolCalls: [AgentToolCall(id: "call_1", name: "graph_search", argumentsJSON: "{\"query\":\"memory\"}")],
            providerMetadata: AgentModelProviderMetadata(
                providerID: "openai-responses",
                rawOutputItemsJSON: #"[{"id":"rs_1","type":"reasoning","encrypted_content":"opaque"},{"id":"fc_1","type":"function_call","call_id":"call_1","name":"graph_search","arguments":"{\"query\":\"memory\"}","status":"completed"},{"id":"fc_2","type":"function_call","call_id":"call_2","name":"task_write","arguments":"{}","status":"completed"}]"#,
                reasoningEncryptedContentPresent: true
            )
        ),
        AgentModelMessage(role: .tool, content: "{\"result\":\"found\"}", toolCallID: "call_1", name: "graph_search")
    ]))

    let requestBody = try #require(client.captured?.body)
    let object = try #require(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
    let input = try #require(object["input"] as? [[String: Any]])
    let reasoning = try #require(input.first { $0["type"] as? String == "reasoning" })
    #expect(reasoning["encrypted_content"] as? String == "opaque")
    let functionCalls = input.filter { $0["type"] as? String == "function_call" }
    #expect(functionCalls.map { $0["call_id"] as? String } == ["call_1"])
    #expect(!input.contains { $0["type"] as? String == "function_call" && $0["call_id"] as? String == "call_2" })
    let output = try #require(input.first { $0["type"] as? String == "function_call_output" })
    #expect(output["call_id"] as? String == "call_1")
}

@Test func openAIResponsesProviderSerializesImageDataURLContentParts() async throws {
    let body = #"{"id":"resp_1","output":[{"type":"message","content":[{"type":"output_text","text":"I can see it."}]}]}"#.data(using: .utf8)!
    let client = ResponsesCapturingHTTPClient(responseBody: body, statusCode: 200)
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "test-key", model: "gpt-4o-mini"),
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
    let input = try #require(object["input"] as? [[String: Any]])
    let message = try #require(input.first)
    let content = try #require(message["content"] as? [[String: Any]])
    #expect(content.first?["type"] as? String == "input_text")
    #expect(content.first?["text"] as? String == "Describe this image")
    let imagePart = try #require(content.first { $0["type"] as? String == "input_image" })
    #expect(imagePart["image_url"] as? String == "data:image/png;base64,iVBORw0KGgo=")
    #expect(imagePart["detail"] as? String == "auto")
}

@Test func openAIResponsesProviderRejectsImageWhenCapabilityKernelDeniesVision() async throws {
    let body = #"{"id":"resp_1","output":[{"type":"message","content":[{"type":"output_text","text":"OK"}]}]}"#.data(using: .utf8)!
    let client = ResponsesCapturingHTTPClient(responseBody: body, statusCode: 200)
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "test-key", model: "text-only-test"),
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
    #expect(!requestBody.contains("input_image"))
    #expect(!requestBody.contains("iVBORw0KGgo="))
}

@Test func openAIResponsesProviderGeneratesImageUsingCurrentModelHostedTool() async throws {
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    let body = """
    {"id":"resp_image","output":[{"id":"ig_1","type":"image_generation_call","status":"completed","output_format":"png","revised_prompt":"A lake","result":"\(png.base64EncodedString())"}]}
    """.data(using: .utf8)!
    let client = ResponsesCapturingHTTPClient(responseBody: body)
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "test-key", model: "gpt-5"),
        httpClient: client
    )

    var artifact: AgentGeneratedMediaArtifact?
    for try await event in provider.generateMedia(AgentGeneratedMediaRequest(kind: .image, prompt: "A lake", options: ["size": "1024x1024"])) {
        if case .completed(let value) = event { artifact = value }
    }

    let generated = try #require(artifact)
    #expect(try Data(contentsOf: generated.temporaryFileURL) == png)
    #expect(generated.mimeType == "image/png")
    #expect(generated.generationMetadata.modelID == "gpt-5")
    #expect(generated.generationMetadata.responseID == "resp_image")
    defer { try? FileManager.default.removeItem(at: generated.temporaryFileURL) }

    let request = try #require(client.captured)
    let object = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    let tools = try #require(object["tools"] as? [[String: Any]])
    #expect(tools.first?["type"] as? String == "image_generation")
    #expect(tools.first?["size"] as? String == "1024x1024")
    #expect(object["model"] as? String == "gpt-5")
}

@Test func openAIResponsesProviderDoesNotRequestImageForUnsupportedCurrentModel() async throws {
    let client = ResponsesCapturingHTTPClient(responseBody: Data())
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "test-key", model: "text-only-test"),
        httpClient: client
    )

    do {
        for try await _ in provider.generateMedia(AgentGeneratedMediaRequest(kind: .image, prompt: "A lake")) {}
        Issue.record("Expected unsupported current model")
    } catch let error as OpenAIGeneratedMediaError {
        if case .unsupportedByCurrentModel(let reason) = error { #expect(reason.contains("请切换")) }
        else { Issue.record("Unexpected error \(error)") }
    }
    #expect(client.captured == nil)
}

@Test func openAIResponsesProviderEditsImageUsingBinarySourceInput() async throws {
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    let body = """
    {"id":"resp_edit","output":[{"id":"ig_edit","type":"image_generation_call","status":"completed","output_format":"png","result":"\(png.base64EncodedString())"}]}
    """.data(using: .utf8)!
    let client = ResponsesCapturingHTTPClient(responseBody: body)
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "test-key", model: "gpt-5"),
        httpClient: client
    )
    let input = AgentGeneratedMediaInputImage(attachmentID: "source", mimeType: "image/png", data: png)

    for try await _ in provider.generateMedia(AgentGeneratedMediaRequest(kind: .image, prompt: "Make it warmer", inputImages: [input], imageAction: .edit)) {}

    let request = try #require(client.captured)
    let object = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
    let tools = try #require(object["tools"] as? [[String: Any]])
    let inputItems = try #require(object["input"] as? [[String: Any]])
    let content = try #require(inputItems.first?["content"] as? [[String: Any]])
    #expect(tools.first?["action"] as? String == "edit")
    #expect(content.contains { $0["type"] as? String == "input_image" && ($0["image_url"] as? String)?.contains(png.base64EncodedString()) == true })
}

@Test func openAIResponsesProviderStreamsTypedTextEvents() async throws {
    let sseClient = ResponsesCapturingSSEClient(frames: [
        "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_1\"}}\n",
        "data: {\"type\":\"response.output_text.delta\",\"delta\":\"Hel\"}\n",
        "data: {\"type\":\"response.output_text.delta\",\"delta\":\"lo\"}\n",
        "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_1\",\"output\":[{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"Hello\"}]}]}}\n"
    ])
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "test-key", model: "gpt-test"),
        httpClient: ResponsesCapturingHTTPClient(responseBody: Data()),
        sseClient: sseClient
    )

    var events: [AgentModelStreamEvent] = []
    for try await event in provider.streamComplete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "hello")])) {
        events.append(event)
    }

    #expect(events.contains(.textDelta("Hel")))
    #expect(events.contains(.textDelta("lo")))
    let completed = try #require(events.compactMap { event -> AgentModelResponse? in
        if case .completed(let response) = event { return response }
        return nil
    }.last)
    #expect(completed.text == "Hello")
    let requestBody = try #require(sseClient.captured?.body)
    let object = try #require(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
    #expect(object["stream"] as? Bool == true)
}

@Test func openAIResponsesProviderStreamsFunctionArgumentDeltas() async throws {
    let sseClient = ResponsesCapturingSSEClient(frames: [
        "data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"id\":\"fc_1\",\"type\":\"function_call\",\"call_id\":\"call_1\",\"name\":\"graph_search\",\"arguments\":\"\"}}\n",
        "data: {\"type\":\"response.function_call_arguments.delta\",\"item_id\":\"fc_1\",\"output_index\":0,\"delta\":\"{\\\"query\\\":\"}\n",
        "data: {\"type\":\"response.function_call_arguments.delta\",\"item_id\":\"fc_1\",\"output_index\":0,\"delta\":\"\\\"memory\\\"}\"}\n",
        "data: {\"type\":\"response.function_call_arguments.done\",\"output_index\":0,\"item\":{\"id\":\"fc_1\",\"type\":\"function_call\",\"call_id\":\"call_1\",\"name\":\"graph_search\",\"arguments\":\"{\\\"query\\\":\\\"memory\\\"}\"}}\n",
        "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_1\",\"output\":[{\"id\":\"fc_1\",\"type\":\"function_call\",\"call_id\":\"call_1\",\"name\":\"graph_search\",\"arguments\":\"{\\\"query\\\":\\\"memory\\\"}\"}]}}\n"
    ])
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "test-key", model: "gpt-test"),
        httpClient: ResponsesCapturingHTTPClient(responseBody: Data()),
        sseClient: sseClient
    )

    var events: [AgentModelStreamEvent] = []
    for try await event in provider.streamComplete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "search")])) {
        events.append(event)
    }

    #expect(events.contains(.toolInputDelta(toolCallID: "call_1", name: "graph_search", partialJSON: "{\"query\":")))
    #expect(events.contains(.toolInputDelta(toolCallID: "call_1", name: "graph_search", partialJSON: "\"memory\"}")))
    let completed = try #require(events.compactMap { event -> AgentModelResponse? in
        if case .completed(let response) = event { return response }
        return nil
    }.last)
    #expect(completed.finishReason == .toolCalls)
    #expect(completed.toolCalls == [AgentToolCall(id: "call_1", name: "graph_search", argumentsJSON: "{\"query\":\"memory\"}")])
}

private final class SequencedImageHTTPClient: AgentHTTPClient, @unchecked Sendable {
    private let queue: DispatchQueue
    private var responses: [(statusCode: Int, body: Data)]
    private(set) var requestCount = 0

    init(responses: [(Int, Data)]) {
        self.queue = DispatchQueue(label: "SequencedImageHTTPClient")
        self.responses = responses
    }

    func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse {
        let index = queue.sync {
            requestCount += 1
            return requestCount - 1
        }
        let pair = responses[min(index, responses.count - 1)]
        return AgentHTTPResponse(statusCode: pair.statusCode, body: pair.body)
    }
}

@Test func openAIResponsesProviderRetriesAndSurfacesUpstreamErrorForImageGeneration() async throws {
    let upstreamError = ["error": ["message": "上游图片服务暂时不可用，请稍后重试"]]
    let errorBody = try JSONSerialization.data(withJSONObject: upstreamError)
    let client = SequencedImageHTTPClient(responses: [
        (503, errorBody),
        (502, errorBody),
        (503, errorBody)
    ])
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "test-key", model: "gpt-5"),
        httpClient: client
    )

    do {
        for try await _ in provider.generateMedia(AgentGeneratedMediaRequest(kind: .image, prompt: "A lake")) {}
        Issue.record("Expected 503 after retries")
    } catch let error as OpenAIGeneratedMediaError {
        if case .providerRejected(let statusCode, let upstreamMessage) = error {
            #expect(statusCode == 503)
            #expect(upstreamMessage?.contains("上游图片服务暂时不可用") == true)
            #expect(error.errorDescription?.contains("HTTP 503") == true)
            #expect(error.errorDescription?.contains("上游图片服务暂时不可用") == true)
        } else {
            Issue.record("Unexpected error \(error)")
        }
    }
    #expect(client.requestCount == OpenAIImageGenerationRetry.maxAttempts)
}

@Test func openAIResponsesProviderRecoversAfterRetriableImageStatus() async throws {
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    let success = """
    {"id":"resp_retry","output":[{"type":"image_generation_call","status":"completed","output_format":"png","result":"\(png.base64EncodedString())"}]}
    """.data(using: .utf8)!
    let errorBody = try JSONSerialization.data(withJSONObject: ["error": ["message": "busy"]])
    let client = SequencedImageHTTPClient(responses: [(503, errorBody), (502, errorBody), (200, success)])
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "test-key", model: "gpt-5"),
        httpClient: client
    )

    var artifact: AgentGeneratedMediaArtifact?
    for try await event in provider.generateMedia(AgentGeneratedMediaRequest(kind: .image, prompt: "A lake")) {
        if case .completed(let value) = event { artifact = value }
    }
    #expect(artifact != nil)
    #expect(client.requestCount == 3)
    if let url = artifact?.temporaryFileURL {
        #expect(try Data(contentsOf: url) == png)
        try? FileManager.default.removeItem(at: url)
    }
}

@Test func openAIResponsesProviderDoesNotRetryNonRetriableImageStatus() async throws {
    let errorBody = try JSONSerialization.data(withJSONObject: ["error": ["message": "content policy blocked"]])
    let client = SequencedImageHTTPClient(responses: [(400, errorBody)])
    let provider = OpenAIResponsesProvider(
        config: OpenAIResponsesConfig(baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "test-key", model: "gpt-5"),
        httpClient: client
    )

    do {
        for try await _ in provider.generateMedia(AgentGeneratedMediaRequest(kind: .image, prompt: "A lake")) {}
        Issue.record("Expected 400")
    } catch let error as OpenAIGeneratedMediaError {
        if case .providerRejected(let statusCode, let upstreamMessage) = error {
            #expect(statusCode == 400)
            #expect(upstreamMessage == "content policy blocked")
        } else {
            Issue.record("Unexpected error \(error)")
        }
    }
    #expect(client.requestCount == 1)
}
