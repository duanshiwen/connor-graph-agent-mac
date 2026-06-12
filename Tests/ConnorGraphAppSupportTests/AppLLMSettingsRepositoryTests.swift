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

@Test func settingsRepositoryReturnsNilConfigWhenKeyMissing() throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    try repository.save(settings: AppLLMSettings.default, apiKey: nil)

    let config = try repository.openAICompatibleConfig()

    #expect(config == nil)
}

@Test func modelCatalogLoadsOpenAICompatibleModelsFromProvider() async throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    try repository.save(
        settings: AppLLMSettings(baseURLString: "https://example.com/v1", model: "gpt-current", hasAPIKey: false, providerMode: .openAICompatible),
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
    #expect(connection.models.map(\.id) == ["gpt-current", "gpt-a", "gpt-z"])
}

@Test func modelCatalogFallsBackToConfiguredModelWhenOpenAIKeyMissing() async throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    try repository.save(
        settings: AppLLMSettings(baseURLString: "https://example.com/v1", model: "configured-model", hasAPIKey: false, providerMode: .openAICompatible),
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
    #expect(connection.models.map(\.id) == ["configured-model"])
}

@Test func settingsRepositoryPersistsGovernedSidecarSettingsAndClampsAllowAll() throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    let settings = AppLLMSettings(
        baseURLString: "https://example.com/v1",
        model: "unused-in-sidecar",
        hasAPIKey: false,
        providerMode: .governedClaudeSidecar,
        sidecarExecutablePath: "/usr/local/bin/node",
        sidecarArguments: "sidecars/claude-agent-engine/claude-sidecar.mjs",
        sidecarWorkingDirectoryPath: "/tmp/project",
        sidecarPermissionMode: .allowAll
    )

    try repository.save(settings: settings, apiKey: nil)
    let loaded = try repository.loadSettings()

    #expect(loaded.providerMode == .governedClaudeSidecar)
    #expect(loaded.sidecarExecutablePath == "/usr/local/bin/node")
    #expect(loaded.sidecarArguments == "sidecars/claude-agent-engine/claude-sidecar.mjs")
    #expect(loaded.sidecarWorkingDirectoryPath == "/tmp/project")
    #expect(loaded.sidecarPermissionMode == .readOnly)
}
