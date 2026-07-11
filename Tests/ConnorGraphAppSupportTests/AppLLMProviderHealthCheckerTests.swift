import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport

private final class HealthCheckFakeCredentialStore: CredentialStore, @unchecked Sendable {
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

private final class HealthCheckFakeSettingsStore: LLMSettingsStore, @unchecked Sendable {
    var values: [String: String] = [:]

    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
}

private final class HealthCheckCapturedAnthropicConfig: @unchecked Sendable {
    var value: AnthropicCompatibleConfig?
}

@Test func healthCheckerReportsDefaultOpenAIResponsesProviderNeedsConfiguration() async throws {
    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: HealthCheckFakeSettingsStore(),
        credentialStore: HealthCheckFakeCredentialStore()
    )
    let checker = AppLLMProviderHealthChecker(settingsRepository: settingsRepository)

    let result = await checker.testConnection()

    #expect(result.status == .notConfigured)
    #expect(result.message.contains("尚未配置 AI 连接"))
}

@Test func healthCheckerReportsMissingOpenAICompatibleConfig() async throws {
    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: HealthCheckFakeSettingsStore(),
        credentialStore: HealthCheckFakeCredentialStore()
    )
    try settingsRepository.save(
        settings: AppLLMSettings(baseURLString: "https://example.com/v1", model: "model-a", hasAPIKey: false, providerMode: .openAICompatible),
        apiKey: nil
    )
    let checker = AppLLMProviderHealthChecker(settingsRepository: settingsRepository)

    let result = await checker.testConnection()

    #expect(result.status == .notConfigured)
    #expect(result.message.contains("API Key"))
}

@Test func healthCheckerReportsOpenAICompatibleSuccess() async throws {
    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: HealthCheckFakeSettingsStore(),
        credentialStore: HealthCheckFakeCredentialStore()
    )
    try settingsRepository.save(
        settings: AppLLMSettings(baseURLString: "https://example.com/v1", model: "model-a", hasAPIKey: false, providerMode: .openAICompatible),
        apiKey: "secret-key"
    )
    let checker = AppLLMProviderHealthChecker(
        settingsRepository: settingsRepository,
        openAICompatibleHealthCheck: { config in
            #expect(config.apiKey == "secret-key")
            return LLMProviderHealthCheckResult(ok: true, model: config.model, message: "Connection OK: \(config.model)")
        }
    )

    let result = await checker.testConnection()

    #expect(result.status == .success)
    #expect(result.message == "Connection OK: model-a")
}

@Test func healthCheckerRunsAnthropicCompatibleHealthCheck() async throws {
    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: HealthCheckFakeSettingsStore(),
        credentialStore: HealthCheckFakeCredentialStore()
    )
    let connection = AppLLMConnectionConfig(
        id: "anthropic-native",
        name: "Anthropic Native",
        providerMode: .anthropicMessages,
        connectionKind: .anthropicCompatible,
        baseURLString: "https://api.anthropic.com/v1",
        model: "claude-sonnet-test",
        selectedModel: "claude-sonnet-test",
        hasAPIKey: true
    )
    try settingsRepository.save(settings: AppLLMSettings(connections: [connection], defaultConnectionID: connection.id), apiKey: "sk-ant-test")
    let receivedConfig = HealthCheckCapturedAnthropicConfig()
    let checker = AppLLMProviderHealthChecker(
        settingsRepository: settingsRepository,
        anthropicCompatibleHealthCheck: { config in
            receivedConfig.value = config
            return LLMProviderHealthCheckResult(ok: true, model: config.model, message: "Connection OK: \(config.model)")
        }
    )

    let result = await checker.testConnection()

    #expect(result.status == .success)
    #expect(result.message == "Connection OK: claude-sonnet-test")
    #expect(receivedConfig.value?.apiKey == "sk-ant-test")
    #expect(receivedConfig.value?.baseURL.absoluteString == "https://api.anthropic.com/v1")
}

@Test func healthCheckerReportsMissingAnthropicCompatibleConfig() async throws {
    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: HealthCheckFakeSettingsStore(),
        credentialStore: HealthCheckFakeCredentialStore()
    )
    let connection = AppLLMConnectionConfig(
        id: "anthropic-native",
        name: "Anthropic Native",
        providerMode: .anthropicMessages,
        connectionKind: .anthropicCompatible,
        baseURLString: "https://api.anthropic.com/v1",
        model: "claude-sonnet-test",
        selectedModel: "claude-sonnet-test",
        hasAPIKey: false
    )
    try settingsRepository.save(settings: AppLLMSettings(connections: [connection], defaultConnectionID: connection.id), apiKey: nil)
    let checker = AppLLMProviderHealthChecker(settingsRepository: settingsRepository)

    let result = await checker.testConnection()

    #expect(result.status == .notConfigured)
    #expect(result.message.contains("API Key"))
}

@Test func healthCheckerMapsProviderErrorToFailureMessageWithoutSecret() async throws {
    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: HealthCheckFakeSettingsStore(),
        credentialStore: HealthCheckFakeCredentialStore()
    )
    try settingsRepository.save(
        settings: AppLLMSettings(baseURLString: "https://example.com/v1", model: "model-a", hasAPIKey: false, providerMode: .openAICompatible),
        apiKey: "secret-key"
    )
    let checker = AppLLMProviderHealthChecker(
        settingsRepository: settingsRepository,
        openAICompatibleHealthCheck: { _ in
            throw OpenAICompatibleProviderError.httpStatus(401, message: "bad key")
        }
    )

    let result = await checker.testConnection()

    #expect(result.status == .failed)
    #expect(result.message.contains("401"))
    #expect(result.message.contains("secret-key") == false)
}

@Test func healthCheckerMapsAnthropicHTTPErrorToUserFacingMessage() async throws {
    let message = AppLLMProviderHealthChecker.userFacingMessage(
        for: AnthropicCompatibleProviderError.httpStatus(400, message: "tool_use ids were found without tool_result blocks immediately after")
    )

    #expect(message.contains("HTTP 400"))
    #expect(message.contains("tool_use ids"))
    #expect(message.contains("请求参数"))
}

@Test func healthCheckerExplainsAnthropicServiceUnavailableHTTPStatus() async throws {
    let message = AppLLMProviderHealthChecker.userFacingMessage(
        for: AnthropicCompatibleProviderError.httpStatus(503, message: "upstream unavailable")
    )

    #expect(message.contains("服务暂时不可用"))
    #expect(message.contains("HTTP 503"))
    #expect(message.contains("upstream unavailable"))
    #expect(message.contains("兼容模式"))
}

@Test func healthCheckerExplainsServiceUnavailableHTTPStatus() async throws {
    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: HealthCheckFakeSettingsStore(),
        credentialStore: HealthCheckFakeCredentialStore()
    )
    try settingsRepository.save(
        settings: AppLLMSettings(baseURLString: "https://example.com/v1", model: "model-a", hasAPIKey: false, providerMode: .openAICompatible),
        apiKey: "secret-key"
    )
    let checker = AppLLMProviderHealthChecker(
        settingsRepository: settingsRepository,
        openAICompatibleHealthCheck: { _ in
            throw OpenAICompatibleProviderError.httpStatus(503, message: nil)
        }
    )

    let result = await checker.testConnection()

    #expect(result.status == .failed)
    #expect(result.message.contains("服务暂时不可用"))
    #expect(result.message.contains("HTTP 503"))
    #expect(result.message.contains("兼容模式"))
    #expect(result.message.contains("secret-key") == false)
}
