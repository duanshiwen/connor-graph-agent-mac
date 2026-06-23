import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport

private final class FakeCredentialStore: CredentialStore, @unchecked Sendable {
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

private final class FakeSettingsStore: LLMSettingsStore, @unchecked Sendable {
    var values: [String: String] = [:]

    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
}

private struct FakeAgentHTTPClient: AgentHTTPClient, Sendable {
    var response: AgentHTTPResponse
    var observedRequests: [AgentHTTPRequest] = []

    mutating func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse {
        observedRequests.append(request)
        return response
    }
}

@Test func settingsRepositoryPersistsNonSecretSettings() throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    let settings = AppLLMSettings(
        baseURLString: "https://example.com/v1",
        model: "custom-model",
        hasAPIKey: false,
        providerMode: .openAICompatible
    )

    try repository.save(settings: settings, apiKey: nil)
    let loaded = try repository.loadSettings()

    #expect(loaded.baseURLString == "https://example.com/v1")
    #expect(loaded.model == "custom-model")
    #expect(loaded.providerMode == .openAICompatible)
}

@Test func settingsRepositoryStoresAPIKeyOnlyInCredentialStore() throws {
    let settingsStore = FakeSettingsStore()
    let credentialStore = FakeCredentialStore()
    let repository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: credentialStore)

    try repository.save(settings: .default, apiKey: "secret-key")
    let loaded = try repository.loadSettings()

    #expect(loaded.hasAPIKey == true)
    #expect(settingsStore.values.values.contains("secret-key") == false)
    #expect(try credentialStore.readSecret(service: AppLLMSettingsRepository.keychainService, account: AppLLMSettingsRepository.apiKeyAccount) == "secret-key")
}

@Test func settingsRepositoryClearsAPIKey() throws {
    let credentialStore = FakeCredentialStore()
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: credentialStore)
    try repository.save(settings: .default, apiKey: "secret-key")

    try repository.clearAPIKey()
    let loaded = try repository.loadSettings()

    #expect(loaded.hasAPIKey == false)
}

@Test func settingsRepositoryBuildsOpenAICompatibleConfigWhenKeyExists() throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    try repository.save(
        settings: AppLLMSettings(baseURLString: "https://example.com/v1", model: "model-a", hasAPIKey: false, providerMode: .openAICompatible),
        apiKey: "secret-key"
    )

    let config = try #require(try repository.openAICompatibleConfig())

    #expect(config.baseURL.absoluteString == "https://example.com/v1")
    #expect(config.model == "model-a")
    #expect(config.apiKey == "secret-key")
}

@Test func settingsRepositorySeparatesModelListFromSelectedModel() throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    try repository.save(
        settings: AppLLMSettings(
            baseURLString: "https://example.com/v1",
            model: "mimo-v2.5-pro, mimo-v2.5, mimo-v2.5-tts",
            selectedModel: "mimo-v2.5",
            hasAPIKey: false,
            providerMode: .openAICompatible
        ),
        apiKey: "secret-key"
    )

    let loaded = try repository.loadSettings()
    let config = try #require(try repository.openAICompatibleConfig())

    #expect(loaded.model == "mimo-v2.5-pro, mimo-v2.5, mimo-v2.5-tts")
    #expect(loaded.modelOptions == ["mimo-v2.5-pro", "mimo-v2.5", "mimo-v2.5-tts"])
    #expect(loaded.selectedModel == "mimo-v2.5")
    #expect(loaded.effectiveModel == "mimo-v2.5")
    #expect(config.model == "mimo-v2.5")
}

@Test func settingsRepositoryReturnsNilConfigWhenKeyMissing() throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    try repository.save(settings: AppLLMSettings.default, apiKey: nil)

    let config = try repository.openAICompatibleConfig()

    #expect(config == nil)
}

@Test func settingsRepositoryDoesNotInjectReasoningEffortIntoOpenAICompatibleConfigByDefault() throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    try repository.save(
        settings: AppLLMSettings(
            connections: [
                AppLLMConnectionConfig(
                    id: "compatible",
                    name: "Compatible Gateway",
                    providerMode: .openAICompatible,
                    baseURLString: "https://example.com/v1",
                    model: "gpt-compatible",
                    selectedModel: "gpt-compatible"
                )
            ],
            defaultConnectionID: "compatible",
            defaultThinkingLevel: .medium
        ),
        apiKey: "secret-key"
    )

    let config = try #require(try repository.openAICompatibleConfig(connectionID: "compatible"))

    #expect(config.reasoningEffort == nil)
}

@Test func modelCatalogLoadsOpenAICompatibleModelsFromProvider() async throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    try repository.save(
        settings: AppLLMSettings(baseURLString: "https://example.com/v1", model: "gpt-current, gpt-local", selectedModel: "gpt-current", hasAPIKey: false, providerMode: .openAICompatible),
        apiKey: "secret-key"
    )
    let body = #"{"data":[{"id":"gpt-z"},{"id":"gpt-a"}]}"#.data(using: .utf8)!
    let catalog = AppLLMModelCatalog(
        settingsRepository: repository,
        httpClient: FakeAgentHTTPClient(response: AgentHTTPResponse(statusCode: 200, body: body))
    )

    let connections = await catalog.loadConnections()
    let connection = try #require(connections.first)

    #expect(connection.providerMode == .openAICompatible)
    #expect(connection.isLiveCatalog == true)
    #expect(connection.models.map(\.id) == ["gpt-current", "gpt-local", "gpt-a", "gpt-z"])
}

@Test func modelCatalogDoesNotInjectConfiguredModelsIntoLiveOpenAICompatibleCatalog() async throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    let connection = AppLLMConnectionConfig(
        id: "connor-gateway-anthropic",
        name: "Connor AI Gateway · Anthropic",
        providerMode: .openAICompatible,
        connectionKind: .openAICompatible,
        baseURLString: "https://cnai.connor.run/v1",
        model: "anthropic/claude-sonnet-4",
        selectedModel: "anthropic/claude-sonnet-4"
    )
    try repository.save(
        settings: AppLLMSettings(connections: [connection], defaultConnectionID: connection.id),
        apiKey: "secret-key"
    )
    let body = #"{"data":[{"id":"deepseek-v4-flash"},{"id":"deepseek-v4-pro"},{"id":"gpt-5.5"}]}"#.data(using: .utf8)!
    let catalog = AppLLMModelCatalog(
        settingsRepository: repository,
        httpClient: FakeAgentHTTPClient(response: AgentHTTPResponse(statusCode: 200, body: body))
    )

    let connections = await catalog.loadConnections()
    let loadedConnection = try #require(connections.first)

    #expect(loadedConnection.isLiveCatalog == true)
    #expect(loadedConnection.models.map(\.id) == ["deepseek-v4-flash", "deepseek-v4-pro", "gpt-5.5"])
}

@Test func anthropicCompatibleCatalogDoesNotHardcodeSonnetFallbackWhenNoModelConfigured() async throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    let connection = AppLLMConnectionConfig(
        id: "anthropic-compatible-empty",
        name: "Anthropic Compatible",
        providerMode: .anthropicMessages,
        connectionKind: .anthropicCompatible,
        baseURLString: "https://api.anthropic.com/v1",
        model: "",
        selectedModel: ""
    )
    try repository.save(
        settings: AppLLMSettings(connections: [connection], defaultConnectionID: connection.id),
        apiKey: "secret-key"
    )
    let catalog = AppLLMModelCatalog(
        settingsRepository: repository,
        httpClient: FakeAgentHTTPClient(response: AgentHTTPResponse(statusCode: 200, body: Data()))
    )

    let connections = await catalog.loadConnections()
    let loadedConnection = try #require(connections.first)

    #expect(loadedConnection.providerMode == .anthropicMessages)
    #expect(loadedConnection.isLiveCatalog == false)
    #expect(loadedConnection.models.isEmpty)
}

@Test func modelCatalogFallsBackToConfiguredModelWhenOpenAIKeyMissing() async throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    try repository.save(
        settings: AppLLMSettings(baseURLString: "https://example.com/v1", model: "configured-model, backup-model", selectedModel: "backup-model", hasAPIKey: false, providerMode: .openAICompatible),
        apiKey: nil
    )
    let catalog = AppLLMModelCatalog(
        settingsRepository: repository,
        httpClient: FakeAgentHTTPClient(response: AgentHTTPResponse(statusCode: 200, body: Data()))
    )

    let connections = await catalog.loadConnections()
    let connection = try #require(connections.first)

    #expect(connection.providerMode == .openAICompatible)
    #expect(connection.isLiveCatalog == false)
    #expect(connection.models.map(\.id) == ["configured-model", "backup-model"])
}

@Test func settingsRepositoryPersistsMultipleConnectionsWithIndependentCredentials() throws {
    let credentialStore = FakeCredentialStore()
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: credentialStore)
    let primary = AppLLMConnectionConfig(
        id: "mimo",
        name: "小米 MiMo",
        providerMode: .openAICompatible,
        baseURLString: "https://token-plan-cn.xiaomimimo.com/v1",
        model: "mimo-v2.5-pro,mimo-v2.5",
        selectedModel: "mimo-v2.5-pro"
    )
    let secondary = AppLLMConnectionConfig(
        id: "deepseek",
        name: "DeepSeek",
        providerMode: .openAICompatible,
        baseURLString: "https://api.deepseek.com/v1",
        model: "deepseek-chat",
        selectedModel: "deepseek-chat"
    )

    try repository.save(settings: AppLLMSettings(connections: [primary, secondary], defaultConnectionID: "mimo"), apiKey: "mimo-key")
    try repository.save(settings: AppLLMSettings(connections: [primary, secondary], defaultConnectionID: "deepseek"), apiKey: "deepseek-key")

    let loaded = try repository.loadSettings()
    let mimoConfig = try #require(try repository.openAICompatibleConfig(connectionID: "mimo"))
    let deepseekConfig = try #require(try repository.openAICompatibleConfig(connectionID: "deepseek"))

    #expect(loaded.connections.map(\.id) == ["mimo", "deepseek"])
    #expect(loaded.defaultConnectionID == "deepseek")
    #expect(mimoConfig.apiKey == "mimo-key")
    #expect(mimoConfig.model == "mimo-v2.5-pro")
    #expect(deepseekConfig.apiKey == "deepseek-key")
    #expect(deepseekConfig.baseURL.absoluteString == "https://api.deepseek.com/v1")
}
