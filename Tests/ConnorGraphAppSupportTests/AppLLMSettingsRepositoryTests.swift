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

private actor FakeAgentHTTPClientState {
    private(set) var observedRequests: [AgentHTTPRequest] = []

    func record(_ request: AgentHTTPRequest) {
        observedRequests.append(request)
    }

    func requests() -> [AgentHTTPRequest] {
        observedRequests
    }
}

private struct FakeAgentHTTPClient: AgentHTTPClient, Sendable {
    var response: AgentHTTPResponse
    var state: FakeAgentHTTPClientState = FakeAgentHTTPClientState()

    mutating func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse {
        await state.record(request)
        return response
    }
}

@Test func settingsRepositoryReturnsTrulyEmptySettingsWhenNoConfigurationExists() throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())

    let loaded = try repository.loadSettings()

    #expect(loaded.connections.isEmpty)
    #expect(loaded.defaultConnectionID.isEmpty)
    #expect(loaded.defaultConnection == nil)
    #expect(loaded.hasAPIKey == false)
}

@Test func settingsRepositoryPersistsExplicitlyEmptySettingsWithoutInjectingDefaultConnection() throws {
    let settingsStore = FakeSettingsStore()
    let credentialStore = FakeCredentialStore()
    let repository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: credentialStore)

    try repository.save(settings: .default, apiKey: nil)
    let loaded = try repository.loadSettings()

    #expect(loaded.connections.isEmpty)
    #expect(loaded.defaultConnectionID.isEmpty)
    #expect(loaded.defaultConnection == nil)
    #expect(settingsStore.values["llm.connections"] == "[]")
}

@Test func settingsRepositoryDefaultsMissingShouldFetchModelsListToTrue() throws {
    let settingsStore = FakeSettingsStore()
    settingsStore.set("""
    [{
      "id":"legacy-openai-compatible",
      "name":"Legacy OpenAI Compatible",
      "providerMode":"openai_compatible",
      "connectionKind":"openai_compatible",
      "baseURLString":"https://example.com/v1",
      "model":"gpt-5.6",
      "selectedModel":"gpt-5.6",
      "hasAPIKey":false,
      "extraHTTPHeaders":{}
    }]
    """, forKey: "llm.connections")
    settingsStore.set("legacy-openai-compatible", forKey: "llm.defaultConnectionID")
    let repository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: FakeCredentialStore())

    let loaded = try repository.loadSettings()

    #expect(loaded.defaultConnection?.shouldFetchModelsList == true)
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

@Test func settingsRepositoryDoesNotPersistOrphanedAPIKeyWithoutConnection() throws {
    let settingsStore = FakeSettingsStore()
    let credentialStore = FakeCredentialStore()
    let repository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: credentialStore)

    try repository.save(settings: .default, apiKey: "secret-key")
    let loaded = try repository.loadSettings()

    #expect(loaded.connections.isEmpty)
    #expect(loaded.hasAPIKey == false)
    #expect(settingsStore.values.values.contains("secret-key") == false)
    #expect(try credentialStore.readSecret(service: AppLLMSettingsRepository.credentialNamespace, account: AppLLMSettingsRepository.apiKeyAccount) == nil)
}

@Test func settingsRepositoryDoesNotReviveDefaultConnectionFromPartialLegacyShape() throws {
    let settingsStore = FakeSettingsStore()
    settingsStore.set("https://api.openai.com/v1", forKey: "llm.baseURLString")
    settingsStore.set("gpt-4o-mini", forKey: "llm.model")
    let repository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: FakeCredentialStore())

    let loaded = try repository.loadSettings()

    #expect(loaded.connections.isEmpty)
    #expect(loaded.defaultConnectionID.isEmpty)
    #expect(loaded.defaultConnection == nil)
}

@Test func settingsRepositoryMigratesOnlyCompleteLegacyConnectionShape() throws {
    let settingsStore = FakeSettingsStore()
    let credentialStore = FakeCredentialStore()
    settingsStore.set("openai_compatible", forKey: "llm.providerMode")
    settingsStore.set("https://example.com/v1", forKey: "llm.baseURLString")
    settingsStore.set("mimo-v2.5", forKey: "llm.model")
    settingsStore.set("mimo-v2.5", forKey: "llm.selectedModel")
    try credentialStore.saveSecret("legacy-key", service: AppLLMSettingsRepository.credentialNamespace, account: AppLLMSettingsRepository.apiKeyAccount)
    let repository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: credentialStore)

    let loaded = try repository.loadSettings()

    #expect(loaded.defaultConnectionID == "openai-compatible")
    #expect(loaded.defaultConnection?.baseURLString == "https://example.com/v1")
    #expect(loaded.defaultConnection?.effectiveModel == "mimo-v2.5")
    #expect(loaded.defaultConnection?.hasAPIKey == true)
}

@Test func providerHealthCheckerReportsNotConfiguredWhenNoDefaultConnectionExists() async throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    let checker = AppLLMProviderHealthChecker(settingsRepository: repository)

    let result = await checker.testConnection()

    #expect(result.status == .notConfigured)
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

@Test func saveConnectionDoesNotMakeNewConnectionDefaultUnlessRequested() throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    let original = AppLLMConnectionConfig(
        id: "original",
        name: "Original",
        providerMode: .openAICompatible,
        baseURLString: "https://original.example/v1",
        model: "original-model",
        selectedModel: "original-model"
    )
    let added = AppLLMConnectionConfig(
        id: "added",
        name: "Added",
        providerMode: .openAICompatible,
        baseURLString: "https://added.example/v1",
        model: "added-model",
        selectedModel: "added-model"
    )
    try repository.save(settings: AppLLMSettings(connections: [original], defaultConnectionID: original.id), apiKey: "original-key")

    try repository.saveConnection(added, apiKey: "added-key")
    let loaded = try repository.loadSettings()

    #expect(loaded.connections.map(\.id).contains(original.id))
    #expect(loaded.connections.map(\.id).contains(added.id))
    #expect(loaded.defaultConnectionID == original.id)
}

@Test func saveConnectionCanExplicitlyMakeNewConnectionDefault() throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    let original = AppLLMConnectionConfig(
        id: "original",
        name: "Original",
        providerMode: .openAICompatible,
        baseURLString: "https://original.example/v1",
        model: "original-model",
        selectedModel: "original-model"
    )
    let added = AppLLMConnectionConfig(
        id: "added",
        name: "Added",
        providerMode: .openAICompatible,
        baseURLString: "https://added.example/v1",
        model: "added-model",
        selectedModel: "added-model"
    )
    try repository.save(settings: AppLLMSettings(connections: [original], defaultConnectionID: original.id), apiKey: "original-key")

    try repository.saveConnection(added, apiKey: "added-key", makeDefault: true)
    let loaded = try repository.loadSettings()

    #expect(loaded.defaultConnectionID == added.id)
}

@Test func saveConnectionMakesFirstConnectionDefaultWhenNoDefaultExists() throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    let added = AppLLMConnectionConfig(
        id: "first",
        name: "First",
        providerMode: .openAICompatible,
        baseURLString: "https://first.example/v1",
        model: "first-model",
        selectedModel: "first-model"
    )

    try repository.saveConnection(added, apiKey: "first-key")
    let loaded = try repository.loadSettings()

    #expect(loaded.defaultConnectionID == added.id)
    #expect(loaded.defaultConnection?.id == added.id)
}

@Test func modelCatalogLoadsOpenAICompatibleModelsFromProvider() async throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    let configuredConnection = AppLLMConnectionConfig(
        id: "openai-compatible",
        name: "OpenAI Compatible",
        providerMode: .openAICompatible,
        baseURLString: "https://example.com/v1",
        model: "gpt-current, gpt-local",
        selectedModel: "gpt-current",
        extraHTTPHeaders: [AppLLMSettingsRepository.openAIAPIKeyHeaderKindMetadataKey: OpenAICompatibleAPIKeyHeaderKind.apiKey.rawValue]
    )
    try repository.save(
        settings: AppLLMSettings(connections: [configuredConnection], defaultConnectionID: configuredConnection.id),
        apiKey: "secret-key"
    )
    let body = #"{"data":[{"id":"gpt-z"},{"id":"text-embedding-3-large"},{"id":"gpt-image-1"},{"id":"qwen-image-plus"},{"id":"whisper-1"},{"id":"omni-moderation-latest"},{"id":"gpt-a"}]}"#.data(using: .utf8)!
    let client = FakeAgentHTTPClient(response: AgentHTTPResponse(statusCode: 200, body: body))
    let state = client.state
    let catalog = AppLLMModelCatalog(
        settingsRepository: repository,
        httpClient: client
    )

    let connections = await catalog.loadConnections()
    let connection = try #require(connections.first)
    let request = try #require(await state.requests().first)

    #expect(connection.providerMode == .openAICompatible)
    #expect(connection.isLiveCatalog == true)
    #expect(connection.models.map(\.id) == ["gpt-a", "gpt-z"])
    #expect(request.headers["api-key"] == "secret-key")
    #expect(request.headers["Authorization"] == nil)
    #expect(request.headers[AppLLMSettingsRepository.openAIAPIKeyHeaderKindMetadataKey] == nil)
}

@Test func modelCatalogPreservesOpenAIResponsesProviderMode() async throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    let connection = AppLLMConnectionConfig(
        id: "openai-responses",
        name: "OpenAI Responses",
        providerMode: .openAIResponses,
        connectionKind: .openAIResponses,
        baseURLString: "https://api.openai.com/v1",
        model: "gpt-4.1",
        selectedModel: "gpt-4.1"
    )
    try repository.save(
        settings: AppLLMSettings(connections: [connection], defaultConnectionID: connection.id),
        apiKey: "secret-key"
    )
    let body = #"{"data":[{"id":"gpt-5"}]}"#.data(using: .utf8)!
    let catalog = AppLLMModelCatalog(
        settingsRepository: repository,
        httpClient: FakeAgentHTTPClient(response: AgentHTTPResponse(statusCode: 200, body: body))
    )

    let connections = await catalog.loadConnections()
    let loadedConnection = try #require(connections.first)

    #expect(loadedConnection.providerMode == .openAIResponses)
    #expect(loadedConnection.isLiveCatalog == true)
    #expect(loadedConnection.models.map(\.id) == ["gpt-5"])
}

@Test func modelCatalogFallsBackWhenRemoteCatalogHasNoChatModels() async throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    let connection = AppLLMConnectionConfig(
        id: "non-chat-only",
        name: "Non-chat Catalog",
        providerMode: .openAICompatible,
        baseURLString: "https://example.com/v1",
        model: "configured-chat-model",
        selectedModel: "configured-chat-model"
    )
    try repository.save(
        settings: AppLLMSettings(connections: [connection], defaultConnectionID: connection.id),
        apiKey: "secret-key"
    )
    let body = #"{"data":[{"id":"text-embedding-3-large"},{"id":"gpt-image-1"}]}"#.data(using: .utf8)!
    let catalog = AppLLMModelCatalog(
        settingsRepository: repository,
        httpClient: FakeAgentHTTPClient(response: AgentHTTPResponse(statusCode: 200, body: body))
    )

    let connections = await catalog.loadConnections()
    let loadedConnection = try #require(connections.first)

    #expect(loadedConnection.providerMode == .openAICompatible)
    #expect(loadedConnection.isLiveCatalog == false)
    #expect(loadedConnection.models.map(\.id) == ["configured-chat-model"])
    #expect(loadedConnection.subtitle.contains("未发现可用聊天模型"))
}

@Test func modelCatalogLoadsGitHubCopilotModelsWithRequiredHeaders() async throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    let connection = AppLLMConnectionConfig(
        id: "github-copilot",
        name: "GitHub Copilot",
        providerMode: .openAICompatible,
        connectionKind: .githubCopilot,
        baseURLString: "https://api.githubcopilot.com",
        model: "gpt-4.1",
        selectedModel: "gpt-4.1",
        extraHTTPHeaders: [
            "User-Agent": "GitHubCopilotChat/0.35.0",
            "Editor-Version": "vscode/1.107.0",
            "Copilot-Integration-Id": "vscode-chat"
        ]
    )
    try repository.save(
        settings: AppLLMSettings(connections: [connection], defaultConnectionID: connection.id),
        apiKey: "copilot-token"
    )
    let body = #"{"data":[{"id":"gpt-4.1"},{"id":"claude-sonnet-4"}]}"#.data(using: .utf8)!
    let client = FakeAgentHTTPClient(response: AgentHTTPResponse(statusCode: 200, body: body))
    let state = client.state
    let catalog = AppLLMModelCatalog(settingsRepository: repository, httpClient: client)

    let connections = await catalog.loadConnections()
    let loadedConnection = try #require(connections.first)
    let request = try #require(await state.requests().first)

    #expect(loadedConnection.isLiveCatalog == true)
    #expect(loadedConnection.models.map(\.id) == ["claude-sonnet-4", "gpt-4.1"])
    #expect(request.url.absoluteString == "https://api.githubcopilot.com/models")
    #expect(request.headers["Authorization"] == "Bearer copilot-token")
    #expect(request.headers["Accept"] == "application/json")
    #expect(request.headers["User-Agent"] == "GitHubCopilotChat/0.35.0")
    #expect(request.headers["Editor-Version"] == "vscode/1.107.0")
    #expect(request.headers["Copilot-Integration-Id"] == "vscode-chat")
}

@Test func modelCatalogRefreshesExpiredGitHubCopilotTokenAndEndpoint() async throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    let connection = AppLLMConnectionConfig(
        id: "github-copilot-refresh",
        name: "GitHub Copilot",
        providerMode: .openAICompatible,
        connectionKind: .githubCopilot,
        baseURLString: "https://api.old.githubcopilot.com",
        model: "gpt-4.1",
        selectedModel: "gpt-4.1",
        extraHTTPHeaders: ["Copilot-Integration-Id": "vscode-chat"]
    )
    try repository.save(
        settings: AppLLMSettings(connections: [connection], defaultConnectionID: connection.id),
        apiKey: "old-copilot-token"
    )
    try repository.saveOAuthTokens(
        AppLLMOAuthTokens(accessToken: "old-copilot-token", refreshToken: "github-access-token", expiresAt: 1_000),
        connectionID: connection.id
    )
    let body = #"{"data":[{"id":"gpt-5"}]}"#.data(using: .utf8)!
    let client = FakeAgentHTTPClient(response: AgentHTTPResponse(statusCode: 200, body: body))
    let state = client.state
    let refreshedToken = "tid=new;proxy-ep=proxy.business.githubcopilot.com;exp=200"
    let catalog = AppLLMModelCatalog(
        settingsRepository: repository,
        httpClient: client,
        now: { Date(timeIntervalSince1970: 1) },
        refreshGitHubCopilotTokens: { githubAccessToken in
            #expect(githubAccessToken == "github-access-token")
            return AppLLMOAuthTokens(accessToken: refreshedToken, refreshToken: githubAccessToken, expiresAt: 2_000_000)
        }
    )

    let connections = await catalog.loadConnections()
    let loadedConnection = try #require(connections.first)
    let request = try #require(await state.requests().first)

    #expect(loadedConnection.isLiveCatalog == true)
    #expect(loadedConnection.models.map(\.id) == ["gpt-5"])
    #expect(request.url.absoluteString == "https://api.business.githubcopilot.com/models")
    #expect(request.headers["Authorization"] == "Bearer \(refreshedToken)")
    #expect(try repository.apiKey(for: connection.id) == refreshedToken)
    #expect(try repository.oauthTokens(for: connection.id)?.accessToken == refreshedToken)
    #expect(try repository.loadSettings().connection(id: connection.id)?.baseURLString == "https://api.business.githubcopilot.com")
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

@Test func modelCatalogUsesConfiguredModelsWithoutRequestWhenFetchModelsListDisabled() async throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    let connection = AppLLMConnectionConfig(
        id: "manual-only",
        name: "Manual Only",
        providerMode: .openAICompatible,
        baseURLString: "https://example.com/v1",
        model: "gpt-5.6, gpt-5.6-mini",
        selectedModel: "gpt-5.6",
        hasAPIKey: true,
        shouldFetchModelsList: false
    )
    try repository.save(
        settings: AppLLMSettings(connections: [connection], defaultConnectionID: connection.id),
        apiKey: "secret-key"
    )
    let client = FakeAgentHTTPClient(response: AgentHTTPResponse(statusCode: 200, body: #"{"data":[{"id":"should-not-be-used"}]}"#.data(using: .utf8)!))
    let state = client.state
    let catalog = AppLLMModelCatalog(
        settingsRepository: repository,
        httpClient: client
    )

    let connections = await catalog.loadConnections()
    let loadedConnection = try #require(connections.first)
    let requests = await state.requests()

    #expect(loadedConnection.isLiveCatalog == false)
    #expect(loadedConnection.models.map(\.id) == ["gpt-5.6", "gpt-5.6-mini"])
    #expect(requests.isEmpty)
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

@Test func tokenPlanAnthropicConnectionProvidesOpenAICompatibleMiMOSpeechConfiguration() throws {
    let repository = AppLLMSettingsRepository(
        settingsStore: FakeSettingsStore(),
        credentialStore: FakeCredentialStore()
    )
    let connection = AppLLMConnectionConfig(
        id: "mimo-token-plan",
        name: "Xiaomi MiMo Token Plan",
        providerMode: .anthropicMessages,
        connectionKind: .anthropicCompatible,
        baseURLString: "https://token-plan-cn.xiaomimimo.com/anthropic",
        model: "mimo-v2.5-pro,mimo-v2.5",
        selectedModel: "mimo-v2.5-pro"
    )
    try repository.save(
        settings: AppLLMSettings(connections: [connection], defaultConnectionID: connection.id),
        apiKey: "tp-secret"
    )

    let configuration = try #require(try repository.xiaomiMiMOSpeechConfiguration())

    #expect(configuration.baseURL.absoluteString == "https://token-plan-cn.xiaomimimo.com/v1")
    #expect(configuration.apiKey == "tp-secret")
    #expect(configuration.apiKeyHeaderKind == .apiKey)
}
