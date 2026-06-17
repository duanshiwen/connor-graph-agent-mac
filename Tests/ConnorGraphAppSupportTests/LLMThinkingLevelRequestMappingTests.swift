import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore

private final class ThinkingFakeCredentialStore: CredentialStore, @unchecked Sendable {
    var secrets: [String: String] = [:]

    func saveSecret(_ secret: String, service: String, account: String) throws {
        secrets["\(service):\(account)"] = secret
    }

    func readSecret(service: String, account: String) throws -> String? {
        secrets["\(service):\(account)"]
    }

    func deleteSecret(service: String, account: String) throws {
        secrets.removeValue(forKey: "\(service):\(account)")
    }
}

private final class ThinkingFakeSettingsStore: LLMSettingsStore, @unchecked Sendable {
    var values: [String: String] = [:]

    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
}

private struct ThinkingOpenAICapturingHTTPClient: AgentHTTPClient {
    final class Storage: @unchecked Sendable {
        var capturedRequest: AgentHTTPRequest?
    }

    let storage = Storage()

    mutating func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse {
        storage.capturedRequest = request
        let body = #"{"choices":[{"message":{"role":"assistant","content":"OK"}}]}"#.data(using: .utf8)!
        return AgentHTTPResponse(statusCode: 200, body: body)
    }
}

private struct ThinkingAnthropicCapturingHTTPClient: AgentHTTPClient {
    final class Storage: @unchecked Sendable {
        var capturedRequest: AgentHTTPRequest?
    }

    let storage = Storage()

    mutating func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse {
        storage.capturedRequest = request
        let body = #"{"id":"msg_1","type":"message","role":"assistant","model":"claude-test","content":[{"type":"text","text":"OK"}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}"#.data(using: .utf8)!
        return AgentHTTPResponse(statusCode: 200, body: body)
    }
}

@Test func openAICompatibleRequestIncludesReasoningEffortWhenThinkingEnabled() async throws {
    let client = ThinkingOpenAICapturingHTTPClient()
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(
            baseURL: URL(string: "https://llm.example.com/v1")!,
            apiKey: "test-key",
            model: "gpt-test",
            reasoningEffort: AppLLMThinkingLevel.medium.openAIReasoningEffort
        ),
        httpClient: client
    )

    _ = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "ping")]))

    let body = try #require(client.storage.capturedRequest?.body)
    let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(object["reasoning_effort"] as? String == "medium")
}

@Test func openAICompatibleRequestOmitsReasoningEffortWhenThinkingOff() async throws {
    let client = ThinkingOpenAICapturingHTTPClient()
    let provider = OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(
            baseURL: URL(string: "https://llm.example.com/v1")!,
            apiKey: "test-key",
            model: "gpt-test",
            reasoningEffort: AppLLMThinkingLevel.off.openAIReasoningEffort
        ),
        httpClient: client
    )

    _ = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "ping")]))

    let body = try #require(client.storage.capturedRequest?.body)
    let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(object["reasoning_effort"] == nil)
}

@Test func anthropicCompatibleRequestIncludesThinkingBudgetWhenThinkingEnabled() async throws {
    let client = ThinkingAnthropicCapturingHTTPClient()
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(
            baseURL: URL(string: "https://api.anthropic.com")!,
            apiKey: "sk-test",
            model: "claude-test",
            featureOptions: AnthropicCompatibleFeatureOptions(thinking: AppLLMThinkingLevel.high.anthropicThinking)
        ),
        httpClient: client
    )

    _ = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "ping")]))

    let body = try #require(client.storage.capturedRequest?.body)
    let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    let thinking = try #require(object["thinking"] as? [String: Any])
    #expect(thinking["type"] as? String == "enabled")
    #expect(thinking["budget_tokens"] as? Int == 20_000)
    #expect(thinking["display"] as? String == "omitted")
}

@Test func anthropicCompatibleRequestOmitsThinkingWhenThinkingOff() async throws {
    let client = ThinkingAnthropicCapturingHTTPClient()
    let provider = AnthropicCompatibleProvider(
        config: AnthropicCompatibleConfig(
            baseURL: URL(string: "https://api.anthropic.com")!,
            apiKey: "sk-test",
            model: "claude-test",
            featureOptions: AnthropicCompatibleFeatureOptions(thinking: AppLLMThinkingLevel.off.anthropicThinking)
        ),
        httpClient: client
    )

    _ = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "ping")]))

    let body = try #require(client.storage.capturedRequest?.body)
    let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(object["thinking"] == nil)
}

@Test func settingsRepositoryInjectsDefaultThinkingIntoOpenAICompatibleConfig() throws {
    let repository = AppLLMSettingsRepository(settingsStore: ThinkingFakeSettingsStore(), credentialStore: ThinkingFakeCredentialStore())
    try repository.save(
        settings: AppLLMSettings(
            connections: [AppLLMConnectionConfig(
                id: "openai-test",
                name: "OpenAI Test",
                providerMode: .openAICompatible,
                baseURLString: "https://llm.example.com/v1",
                model: "gpt-test",
                selectedModel: "gpt-test"
            )],
            defaultConnectionID: "openai-test",
            defaultThinkingLevel: .xhigh
        ),
        apiKey: "test-key"
    )

    let optionalConfig = try repository.openAICompatibleConfig(connectionID: "openai-test")
    let config = try #require(optionalConfig)

    #expect(config.reasoningEffort == "high")
}

@Test func settingsRepositoryInjectsDefaultThinkingIntoAnthropicCompatibleConfig() throws {
    let repository = AppLLMSettingsRepository(settingsStore: ThinkingFakeSettingsStore(), credentialStore: ThinkingFakeCredentialStore())
    try repository.save(
        settings: AppLLMSettings(
            connections: [AppLLMConnectionConfig(
                id: "anthropic-test",
                name: "Anthropic Test",
                providerMode: .openAICompatible,
                connectionKind: .anthropicCompatible,
                baseURLString: "https://api.anthropic.com",
                model: "claude-test",
                selectedModel: "claude-test"
            )],
            defaultConnectionID: "anthropic-test",
            defaultThinkingLevel: .medium
        ),
        apiKey: "sk-test"
    )

    let optionalConfig = try repository.anthropicCompatibleConfig(connectionID: "anthropic-test")
    let config = try #require(optionalConfig)

    #expect(config.featureOptions.thinking == AnthropicThinkingConfig.enabled(budgetTokens: 10_000, display: AnthropicThinkingDisplay.omitted))
}

@Test func claudeSDKSidecarRequestIncludesEffortWhenThinkingEnabled() throws {
    let request = AgentChatRequest(
        runID: "run-thinking",
        sessionID: "session-thinking",
        groupID: "default",
        userMessage: "ping",
        permissionMode: .readOnly
    )

    let sidecarRequest = ClaudeSDKSidecarRequest(
        request: request,
        workingDirectory: URL(fileURLWithPath: "/tmp/project"),
        effort: AppLLMThinkingLevel.max.effortValue
    )

    #expect(sidecarRequest.options.effort == "max")
}

@Test func claudeSDKSidecarRequestOmitsEffortWhenThinkingOff() throws {
    let request = AgentChatRequest(
        runID: "run-thinking-off",
        sessionID: "session-thinking-off",
        groupID: "default",
        userMessage: "ping",
        permissionMode: .readOnly
    )

    let sidecarRequest = ClaudeSDKSidecarRequest(
        request: request,
        workingDirectory: URL(fileURLWithPath: "/tmp/project"),
        effort: AppLLMThinkingLevel.off.effortValue
    )

    #expect(sidecarRequest.options.effort == nil)
}
