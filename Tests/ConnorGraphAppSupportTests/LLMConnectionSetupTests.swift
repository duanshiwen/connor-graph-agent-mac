import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport

private final class MemoryLLMSettingsStore: LLMSettingsStore, @unchecked Sendable {
    var values: [String: String] = [:]
    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private final class MemoryCredentialStore: CredentialStore, @unchecked Sendable {
    var values: [String: String] = [:]
    func saveSecret(_ secret: String, service: String, account: String) throws { values["\(service):\(account)"] = secret }
    func readSecret(service: String, account: String) throws -> String? { values["\(service):\(account)"] }
    func deleteSecret(service: String, account: String) throws { values.removeValue(forKey: "\(service):\(account)") }
}

@Suite("LLM Connection Setup Tests")
struct LLMConnectionSetupTests {
    @Test func openAICompatibleMissingAPIKeyDoesNotSave() async throws {
        let store = MemoryLLMSettingsStore()
        let credentials = MemoryCredentialStore()
        let repository = AppLLMSettingsRepository(settingsStore: store, credentialStore: credentials)
        let service = AppLLMConnectionSetupService(
            settingsRepository: repository,
            openAICompatibleHealthCheck: { _ in LLMProviderHealthCheckResult(ok: true, model: "gpt-test", message: "OK") }
        )

        await #expect(throws: AppLLMConnectionSetupError.missingAPIKey) {
            try await service.setupConnection(AppLLMConnectionSetupInput(
                kind: .openAICompatible,
                name: "Test",
                baseURLString: "https://api.example.com/v1",
                model: "gpt-test"
            ))
        }
        #expect(credentials.values.isEmpty)
    }

    @Test func openAICompatibleHealthCheckFailureDoesNotSaveSecret() async throws {
        let store = MemoryLLMSettingsStore()
        let credentials = MemoryCredentialStore()
        let repository = AppLLMSettingsRepository(settingsStore: store, credentialStore: credentials)
        let service = AppLLMConnectionSetupService(
            settingsRepository: repository,
            openAICompatibleHealthCheck: { _ in LLMProviderHealthCheckResult(ok: false, model: "gpt-test", message: "bad token") }
        )

        await #expect(throws: AppLLMConnectionSetupError.healthCheckFailed("bad token")) {
            try await service.setupConnection(AppLLMConnectionSetupInput(
                kind: .openAICompatible,
                name: "Test",
                baseURLString: "https://api.example.com/v1",
                model: "gpt-test",
                apiKey: "secret"
            ))
        }
        #expect(credentials.values.isEmpty)
    }

    @Test func openAICompatibleSetupDiscoversCapabilitiesBeforePersistingEvidence() async throws {
        let store = MemoryLLMSettingsStore()
        let credentials = MemoryCredentialStore()
        let repository = AppLLMSettingsRepository(settingsStore: store, credentialStore: credentials)
        let evidenceRepository = AppProviderCapabilityEvidenceRepository(settingsStore: store, credentialStore: credentials)
        let discovery = AppProviderCapabilityDiscoveryService(
            settingsRepository: repository,
            evidenceRepository: evidenceRepository,
            openAICompatibleProbe: { config in LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK") },
            openAIResponsesProbe: { _ in throw OpenAICompatibleProviderError.httpStatus(404, message: "not found") },
            functionCallingProbe: { _ in AgentModelResponse(text: "OK") },
            hostedImageGenerationProbe: { _ in
                Issue.record("Image probe must not run when Responses is unsupported")
                return true
            }
        )
        let service = AppLLMConnectionSetupService(
            settingsRepository: repository,
            capabilityDiscoveryService: discovery,
            openAICompatibleHealthCheck: { config in LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK") }
        )

        let result = try await service.setupConnection(AppLLMConnectionSetupInput(
            id: "discovered-provider",
            kind: .openAICompatible,
            name: "Discovered",
            baseURLString: "https://api.example.com/v1",
            model: "gpt-test",
            apiKey: "secret"
        ))

        #expect(result.capabilityEvidence.first { $0.capability == .chatCompletions }?.status == .verified)
        #expect(result.capabilityEvidence.first { $0.capability == .functionCalling }?.status == .verified)
        #expect(result.capabilityEvidence.first { $0.capability == .responses }?.status == .unsupported)
        #expect(try evidenceRepository.effectiveEvidence(for: .chatCompletions, connection: result.connection)?.status == .verified)
        #expect(result.capabilityEvidence.contains { $0.capability == .hostedImageGeneration } == false)
        #expect(try repository.apiKey(for: result.connection.id) == "secret")
    }

    @Test func openAICompatibleSetupPersistsHostedImageEvidenceWhenResponsesAreVerified() async throws {
        let store = MemoryLLMSettingsStore()
        let credentials = MemoryCredentialStore()
        let repository = AppLLMSettingsRepository(settingsStore: store, credentialStore: credentials)
        let evidenceRepository = AppProviderCapabilityEvidenceRepository(settingsStore: store, credentialStore: credentials)
        let imageProbeCount = LockedCounter()
        let discovery = AppProviderCapabilityDiscoveryService(
            settingsRepository: repository,
            evidenceRepository: evidenceRepository,
            openAICompatibleProbe: { config in LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK") },
            openAIResponsesProbe: { config in LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK") },
            functionCallingProbe: { _ in AgentModelResponse(text: "OK") },
            hostedImageGenerationProbe: { config in
                imageProbeCount.increment()
                #expect(config.model == "gpt-test")
                return true
            }
        )
        let service = AppLLMConnectionSetupService(
            settingsRepository: repository,
            capabilityDiscoveryService: discovery,
            openAICompatibleHealthCheck: { config in LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK") }
        )

        let result = try await service.setupConnection(AppLLMConnectionSetupInput(
            id: "image-provider",
            kind: .openAICompatible,
            name: "Image Provider",
            baseURLString: "https://api.example.com/v1",
            model: "gpt-test",
            apiKey: "secret"
        ))

        #expect(imageProbeCount.value == 1)
        #expect(result.capabilityEvidence.count == 4)
        #expect(result.capabilityEvidence.first { $0.capability == .hostedImageGeneration }?.status == .verified)
        #expect(try evidenceRepository.effectiveEvidence(for: .hostedImageGeneration, connection: result.connection)?.status == .verified)
    }

    @Test(arguments: [
        (OpenAICompatibleProviderError.httpStatus(400, message: "unsupported tool image_generation"), AppProviderCapabilityStatus.unsupported),
        (OpenAICompatibleProviderError.httpStatus(503, message: "upstream unavailable"), AppProviderCapabilityStatus.unknown)
    ])
    func imageProbeFailureDoesNotRejectValidPrimaryConnection(error: OpenAICompatibleProviderError, expectedStatus: AppProviderCapabilityStatus) async throws {
        let store = MemoryLLMSettingsStore()
        let credentials = MemoryCredentialStore()
        let repository = AppLLMSettingsRepository(settingsStore: store, credentialStore: credentials)
        let evidenceRepository = AppProviderCapabilityEvidenceRepository(settingsStore: store, credentialStore: credentials)
        let discovery = AppProviderCapabilityDiscoveryService(
            settingsRepository: repository,
            evidenceRepository: evidenceRepository,
            openAICompatibleProbe: { config in LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK") },
            openAIResponsesProbe: { config in LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK") },
            functionCallingProbe: { _ in AgentModelResponse(text: "OK") },
            hostedImageGenerationProbe: { _ in throw error }
        )
        let service = AppLLMConnectionSetupService(
            settingsRepository: repository,
            capabilityDiscoveryService: discovery,
            openAICompatibleHealthCheck: { config in LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK") }
        )

        let result = try await service.setupConnection(AppLLMConnectionSetupInput(
            id: "partial-capability-provider-\(expectedStatus.rawValue)",
            kind: .openAICompatible,
            name: "Partial Capability Provider",
            baseURLString: "https://api.example.com/v1",
            model: "gpt-test",
            apiKey: "secret"
        ))

        #expect(result.capabilityEvidence.first { $0.capability == .hostedImageGeneration }?.status == expectedStatus)
        #expect(try repository.apiKey(for: result.connection.id) == "secret")
        #expect(try evidenceRepository.effectiveEvidence(for: .hostedImageGeneration, connection: result.connection)?.status == expectedStatus)
    }

    @Test func openAICompatibleSuccessSavesMetadataAndSecretSeparately() async throws {
        let store = MemoryLLMSettingsStore()
        let credentials = MemoryCredentialStore()
        let repository = AppLLMSettingsRepository(settingsStore: store, credentialStore: credentials)
        let service = AppLLMConnectionSetupService(
            settingsRepository: repository,
            openAICompatibleHealthCheck: { config in LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK") }
        )

        let result = try await service.setupConnection(AppLLMConnectionSetupInput(
            id: "provider-1",
            kind: .openAICompatible,
            name: "Provider 1",
            baseURLString: "https://api.example.com/v1",
            model: "gpt-test",
            apiKey: "secret"
        ))

        #expect(result.connection.id == "provider-1")
        let loaded = try repository.loadSettings()
        let savedConnection = try #require(loaded.connections.first { $0.id == "provider-1" })
        #expect(loaded.defaultConnectionID == "provider-1")
        #expect(savedConnection.connectionKind == .openAICompatible)
        #expect(savedConnection.hasAPIKey)
        #expect(store.values.values.contains(where: { $0.contains("Provider 1") }))
        #expect(!store.values.values.contains(where: { $0.contains("secret") }))
        #expect(try repository.apiKey(for: "provider-1") == "secret")
    }

    @Test func setupConnectionMakesFirstCreatedConnectionDefaultWithoutExplicitMakeDefault() async throws {
        let store = MemoryLLMSettingsStore()
        let credentials = MemoryCredentialStore()
        let repository = AppLLMSettingsRepository(settingsStore: store, credentialStore: credentials)
        let service = AppLLMConnectionSetupService(
            settingsRepository: repository,
            openAICompatibleHealthCheck: { config in LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK") }
        )

        _ = try await service.setupConnection(AppLLMConnectionSetupInput(
            id: "first-provider",
            kind: .openAICompatible,
            name: "First Provider",
            baseURLString: "https://api.example.com/v1",
            model: "gpt-test",
            apiKey: "secret"
        ))

        let loaded = try repository.loadSettings()
        #expect(loaded.defaultConnectionID == "first-provider")
        #expect(loaded.defaultConnection?.id == "first-provider")
    }

    @Test func openAICompatibleUsesValidationModelWithoutPersistingItAsCatalogModel() async throws {
        let store = MemoryLLMSettingsStore()
        let credentials = MemoryCredentialStore()
        let repository = AppLLMSettingsRepository(settingsStore: store, credentialStore: credentials)
        let service = AppLLMConnectionSetupService(
            settingsRepository: repository,
            openAICompatibleHealthCheck: { config in
                #expect(config.model == "anthropic/claude-sonnet-4")
                return LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK")
            }
        )

        let result = try await service.setupConnection(AppLLMConnectionSetupInput(
            id: "connor-gateway-anthropic",
            kind: .openAICompatible,
            name: "Connor AI Gateway · Anthropic",
            baseURLString: "https://cnai.connor.run/v1",
            model: "",
            selectedModel: "",
            validationModel: "anthropic/claude-sonnet-4",
            apiKey: "secret"
        ))

        #expect(result.connection.model == "")
        #expect(result.connection.selectedModel == "")
        let loaded = try repository.loadSettings()
        let savedConnection = try #require(loaded.connections.first { $0.id == "connor-gateway-anthropic" })
        #expect(savedConnection.model == "")
        #expect(savedConnection.selectedModel == "")
    }

    @Test func openAICompatibleValidationFallsBackToFirstConfiguredModelBeforeSelectedModel() async throws {
        let store = MemoryLLMSettingsStore()
        let credentials = MemoryCredentialStore()
        let repository = AppLLMSettingsRepository(settingsStore: store, credentialStore: credentials)
        let service = AppLLMConnectionSetupService(
            settingsRepository: repository,
            openAICompatibleHealthCheck: { config in
                #expect(config.model == "deepseek-v4-flash")
                return LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK")
            }
        )

        let result = try await service.setupConnection(AppLLMConnectionSetupInput(
            id: "custom-openai-compatible",
            kind: .openAICompatible,
            name: "Custom OpenAI Compatible",
            baseURLString: "https://cnai.connor.run/v1",
            model: "deepseek-v4-flash, deepseek-v4-pro, gpt-5.5",
            selectedModel: "gpt-4o-mini",
            validationModel: "",
            apiKey: "secret"
        ))

        #expect(result.connection.model == "deepseek-v4-flash, deepseek-v4-pro, gpt-5.5")
        #expect(result.connection.selectedModel == "gpt-4o-mini")
    }

    @Test func xiaomiMiMoOpenAICompatiblePersistsAPIKeyHeaderKind() async throws {
        let store = MemoryLLMSettingsStore()
        let credentials = MemoryCredentialStore()
        let repository = AppLLMSettingsRepository(settingsStore: store, credentialStore: credentials)
        let service = AppLLMConnectionSetupService(
            settingsRepository: repository,
            openAICompatibleHealthCheck: { config in
                #expect(config.baseURL.absoluteString == "https://api.xiaomimimo.com/v1")
                #expect(config.model == "mimo-v2.5-pro")
                #expect(config.apiKeyHeaderKind == .apiKey)
                return LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK")
            }
        )

        let result = try await service.setupConnection(AppLLMConnectionSetupInput(
            id: "xiaomi-mimo-test",
            kind: .openAICompatible,
            name: "Xiaomi MiMo",
            baseURLString: "https://api.xiaomimimo.com/v1",
            model: "mimo-v2.5-pro",
            apiKey: "mimo-secret",
            openAIAPIKeyHeaderKind: .apiKey
        ))

        #expect(result.connection.extraHTTPHeaders[AppLLMSettingsRepository.openAIAPIKeyHeaderKindMetadataKey] == OpenAICompatibleAPIKeyHeaderKind.apiKey.rawValue)
        let config = try #require(try repository.openAICompatibleConfig(connectionID: "xiaomi-mimo-test"))
        #expect(config.apiKeyHeaderKind == .apiKey)
        #expect(try repository.apiKey(for: "xiaomi-mimo-test") == "mimo-secret")
        #expect(!store.values.values.contains(where: { $0.contains("mimo-secret") }))
    }

    @Test func xiaomiMiMoTokenPlanUsesTokenPlanEndpointAndAPIKeyHeaderKind() async throws {
        let store = MemoryLLMSettingsStore()
        let credentials = MemoryCredentialStore()
        let repository = AppLLMSettingsRepository(settingsStore: store, credentialStore: credentials)
        let service = AppLLMConnectionSetupService(
            settingsRepository: repository,
            openAICompatibleHealthCheck: { config in
                #expect(config.baseURL.absoluteString == "https://token-plan-cn.xiaomimimo.com/v1")
                #expect(config.model == "mimo-v2.5-pro")
                #expect(config.apiKeyHeaderKind == .apiKey)
                return LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK")
            }
        )

        let result = try await service.setupConnection(AppLLMConnectionSetupInput(
            id: "xiaomi-mimo-token-plan-test",
            kind: .openAICompatible,
            name: "token-plan-cn.xiaomimimo",
            baseURLString: "https://token-plan-cn.xiaomimimo.com/v1",
            model: "mimo-v2.5-pro",
            apiKey: "tp-secret",
            openAIAPIKeyHeaderKind: .apiKey
        ))

        #expect(result.connection.baseURLString == "https://token-plan-cn.xiaomimimo.com/v1")
        #expect(result.connection.extraHTTPHeaders[AppLLMSettingsRepository.openAIAPIKeyHeaderKindMetadataKey] == OpenAICompatibleAPIKeyHeaderKind.apiKey.rawValue)
        let config = try #require(try repository.openAICompatibleConfig(connectionID: "xiaomi-mimo-token-plan-test"))
        #expect(config.baseURL.absoluteString == "https://token-plan-cn.xiaomimimo.com/v1")
        #expect(config.apiKeyHeaderKind == .apiKey)
        #expect(try repository.apiKey(for: "xiaomi-mimo-token-plan-test") == "tp-secret")
        #expect(!store.values.values.contains(where: { $0.contains("tp-secret") }))
    }


    @Test func codexRequiresIDTokenAndSavesDerivedAPIKey() async throws {
        let credentials = MemoryCredentialStore()
        let repository = AppLLMSettingsRepository(settingsStore: MemoryLLMSettingsStore(), credentialStore: credentials)
        let service = AppLLMConnectionSetupService(
            settingsRepository: repository,
            openAICompatibleHealthCheck: { config in LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK") },
            codexAPIKeyExchange: { idToken in "api-key-for-\(idToken)" }
        )

        await #expect(throws: AppLLMConnectionSetupError.missingOAuthToken("id_token")) {
            try await service.setupConnection(AppLLMConnectionSetupInput(
                kind: .chatGPTCodex,
                name: "Codex",
                oauthTokens: AppLLMOAuthTokens(accessToken: "access")
            ))
        }

        let result = try await service.setupConnection(AppLLMConnectionSetupInput(
            id: "codex-test",
            kind: .chatGPTCodex,
            name: "Codex",
            baseURLString: "https://api.openai.com/v1",
            model: "gpt-4o-mini",
            oauthTokens: AppLLMOAuthTokens(accessToken: "access", idToken: "id-token")
        ))
        #expect(result.connection.connectionKind == .chatGPTCodex)
        #expect(try repository.apiKey(for: "codex-test") == "api-key-for-id-token")
    }

    @Test func githubCopilotSuccessStoresKindAndHeaders() async throws {
        let repository = AppLLMSettingsRepository(settingsStore: MemoryLLMSettingsStore(), credentialStore: MemoryCredentialStore())
        let service = AppLLMConnectionSetupService(
            settingsRepository: repository,
            openAICompatibleHealthCheck: { config in
                #expect(config.extraHeaders["User-Agent"] == "GitHubCopilotChat/0.35.0")
                #expect(config.extraHeaders["Editor-Version"] == "vscode/1.107.0")
                #expect(config.extraHeaders["Editor-Plugin-Version"] == "copilot-chat/0.35.0")
                #expect(config.extraHeaders["Copilot-Integration-Id"] == "vscode-chat")
                #expect(config.extraHeaders["Openai-Intent"] == "conversation-edits")
                #expect(config.extraHeaders["X-Initiator"] == "user")
                #expect(config.extraHeaders["OpenAI-Organization"] == nil)
                return LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK")
            }
        )

        let result = try await service.setupConnection(AppLLMConnectionSetupInput(
            id: "github-test",
            kind: .githubCopilot,
            name: "GitHub Copilot",
            baseURLString: "https://api.githubcopilot.com",
            model: "gpt-4.1",
            apiKey: "copilot-token",
            oauthTokens: AppLLMOAuthTokens(accessToken: "copilot-token")
        ))

        #expect(result.connection.connectionKind == .githubCopilot)
        #expect(result.connection.extraHTTPHeaders["User-Agent"] == "GitHubCopilotChat/0.35.0")
        #expect(result.connection.extraHTTPHeaders["Editor-Version"] == "vscode/1.107.0")
        #expect(result.connection.extraHTTPHeaders["Editor-Plugin-Version"] == "copilot-chat/0.35.0")
        #expect(result.connection.extraHTTPHeaders["Copilot-Integration-Id"] == "vscode-chat")
        #expect(result.connection.extraHTTPHeaders["Openai-Intent"] == "conversation-edits")
        #expect(result.connection.extraHTTPHeaders["X-Initiator"] == "user")
        #expect(result.connection.extraHTTPHeaders["OpenAI-Organization"] == nil)
        #expect(try repository.apiKey(for: "github-test") == "copilot-token")
    }

    @Test func githubCopilotDerivesBaseURLFromProxyEndpointWhenInputBaseURLIsEmpty() async throws {
        let repository = AppLLMSettingsRepository(settingsStore: MemoryLLMSettingsStore(), credentialStore: MemoryCredentialStore())
        let token = "tid=abc;proxy-ep=proxy.individual.githubcopilot.com;exp=123"
        let service = AppLLMConnectionSetupService(
            settingsRepository: repository,
            openAICompatibleHealthCheck: { config in
                #expect(config.baseURL.absoluteString == "https://api.individual.githubcopilot.com")
                return LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK")
            }
        )

        let result = try await service.setupConnection(AppLLMConnectionSetupInput(
            id: "github-derived-endpoint-test",
            kind: .githubCopilot,
            name: "GitHub Copilot",
            baseURLString: "",
            model: "gpt-4.1",
            apiKey: token,
            oauthTokens: AppLLMOAuthTokens(accessToken: token, refreshToken: "github-token", expiresAt: 1_800_000)
        ))

        #expect(result.connection.baseURLString == "https://api.individual.githubcopilot.com")
        let storedConfig = try repository.openAICompatibleConfig(connectionID: "github-derived-endpoint-test")
        #expect(storedConfig?.baseURL.absoluteString == "https://api.individual.githubcopilot.com")
        #expect(storedConfig?.extraHeaders["Openai-Intent"] == "conversation-edits")
        #expect(storedConfig?.extraHeaders["X-Initiator"] == "user")
        #expect(try repository.oauthTokens(for: "github-derived-endpoint-test")?.refreshToken == "github-token")
    }

    @Test func githubCopilotRefreshingProviderRefreshesExpiringTokenAndUpdatesEndpoint() async throws {
        let repository = AppLLMSettingsRepository(settingsStore: MemoryLLMSettingsStore(), credentialStore: MemoryCredentialStore())
        let oldToken = "tid=old;proxy-ep=proxy.old.githubcopilot.com;exp=100"
        let newToken = "tid=new;proxy-ep=proxy.business.githubcopilot.com;exp=200"
        try repository.save(settings: AppLLMSettings(
            connections: [AppLLMConnectionConfig(
                id: "github-refresh-test",
                name: "GitHub Copilot",
                providerMode: .openAICompatible,
                connectionKind: .githubCopilot,
                baseURLString: "https://api.old.githubcopilot.com",
                model: "gpt-4.1",
                selectedModel: "gpt-4.1",
                extraHTTPHeaders: ["Copilot-Integration-Id": "vscode-chat"]
            )],
            defaultConnectionID: "github-refresh-test"
        ), apiKey: oldToken)
        try repository.saveOAuthTokens(AppLLMOAuthTokens(
            accessToken: oldToken,
            refreshToken: "github-access-token",
            expiresAt: 1_000
        ), connectionID: "github-refresh-test")

        final class CapturedConfigBox: @unchecked Sendable {
            var configs: [OpenAICompatibleConfig] = []
        }
        let box = CapturedConfigBox()
        let provider = GitHubCopilotTokenRefreshingAgentModelProvider(
            connectionID: "github-refresh-test",
            modelID: "gpt-4.1",
            capabilities: AgentModelCapabilities(supportsStreaming: false, supportsToolCalling: true, supportsParallelToolCalls: false, supportsStructuredOutput: false, supportsVision: false),
            settingsRepository: repository,
            refreshSkew: 300,
            now: { Date(timeIntervalSince1970: 1) },
            refreshTokens: { githubAccessToken in
                #expect(githubAccessToken == "github-access-token")
                return AppLLMOAuthTokens(accessToken: newToken, refreshToken: githubAccessToken, expiresAt: 2_000_000)
            },
            makeProvider: { config in
                box.configs.append(config)
                return AnyAgentModelProvider(
                    modelID: config.model,
                    capabilities: AgentModelCapabilities(supportsStreaming: false, supportsToolCalling: true, supportsParallelToolCalls: false, supportsStructuredOutput: false, supportsVision: false),
                    complete: { _ in AgentModelResponse(text: "ok") }
                )
            }
        )

        let response = try await provider.complete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "hi")]))
        _ = try await provider.complete(AgentModelRequest(messages: [
            AgentModelMessage(role: .assistant, content: "calling tool"),
            AgentModelMessage(role: .tool, content: "tool result")
        ]))

        #expect(response.text == "ok")
        #expect(box.configs.first?.apiKey == newToken)
        #expect(box.configs.first?.baseURL.absoluteString == "https://api.business.githubcopilot.com")
        #expect(box.configs.first?.extraHeaders["Openai-Intent"] == "conversation-edits")
        #expect(box.configs.first?.extraHeaders["X-Initiator"] == "user")
        #expect(box.configs.last?.extraHeaders["X-Initiator"] == "agent")
        #expect(try repository.apiKey(for: "github-refresh-test") == newToken)
        #expect(try repository.oauthTokens(for: "github-refresh-test")?.accessToken == newToken)
        #expect(try repository.loadSettings().connection(id: "github-refresh-test")?.baseURLString == "https://api.business.githubcopilot.com")
    }

    @Test func anthropicCompatibleConnectionKindRoundTrips() throws {
        let encoded = try JSONEncoder().encode(AppLLMConnectionKind.anthropicCompatible)
        let decoded = try JSONDecoder().decode(AppLLMConnectionKind.self, from: encoded)
        #expect(decoded == .anthropicCompatible)
    }

    @Test func anthropicCompatibleMissingAPIKeyDoesNotSave() async throws {
        let store = MemoryLLMSettingsStore()
        let credentials = MemoryCredentialStore()
        let repository = AppLLMSettingsRepository(settingsStore: store, credentialStore: credentials)
        let service = AppLLMConnectionSetupService(
            settingsRepository: repository,
            anthropicCompatibleHealthCheck: { _ in LLMProviderHealthCheckResult(ok: true, model: "claude-test", message: "OK") }
        )

        await #expect(throws: AppLLMConnectionSetupError.missingAPIKey) {
            try await service.setupConnection(AppLLMConnectionSetupInput(
                kind: .anthropicCompatible,
                name: "Anthropic",
                baseURLString: "https://api.anthropic.com",
                model: "claude-test"
            ))
        }
        #expect(credentials.values.isEmpty)
    }

    @Test func anthropicCompatibleHealthCheckFailureDoesNotSaveSecret() async throws {
        let store = MemoryLLMSettingsStore()
        let credentials = MemoryCredentialStore()
        let repository = AppLLMSettingsRepository(settingsStore: store, credentialStore: credentials)
        let service = AppLLMConnectionSetupService(
            settingsRepository: repository,
            anthropicCompatibleHealthCheck: { _ in LLMProviderHealthCheckResult(ok: false, model: "claude-test", message: "bad key") }
        )

        await #expect(throws: AppLLMConnectionSetupError.healthCheckFailed("bad key")) {
            try await service.setupConnection(AppLLMConnectionSetupInput(
                kind: .anthropicCompatible,
                name: "Anthropic",
                baseURLString: "https://api.anthropic.com",
                model: "claude-test",
                apiKey: "secret"
            ))
        }
        #expect(credentials.values.isEmpty)
    }

    @Test func anthropicCompatibleSuccessSavesMetadataAndSecret() async throws {
        let store = MemoryLLMSettingsStore()
        let credentials = MemoryCredentialStore()
        let repository = AppLLMSettingsRepository(settingsStore: store, credentialStore: credentials)
        let service = AppLLMConnectionSetupService(
            settingsRepository: repository,
            anthropicCompatibleHealthCheck: { config in
                #expect(config.authHeaderKind == .xAPIKey)
                return LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK")
            }
        )

        let result = try await service.setupConnection(AppLLMConnectionSetupInput(
            id: "anthropic-test",
            kind: .anthropicCompatible,
            name: "Anthropic",
            baseURLString: "https://api.anthropic.com",
            model: "claude-test",
            apiKey: "secret"
        ))

        #expect(result.connection.connectionKind == .anthropicCompatible)
        #expect(result.connection.providerMode == .anthropicMessages)
        #expect(result.connection.baseURLString == "https://api.anthropic.com")
        #expect(result.connection.hasAPIKey)
        #expect(try repository.apiKey(for: "anthropic-test") == "secret")
        #expect(!store.values.values.contains(where: { $0.contains("secret") }))
    }

    @Test func anthropicCompatibleValidationFallsBackToFirstConfiguredModelBeforeSelectedModel() async throws {
        let store = MemoryLLMSettingsStore()
        let credentials = MemoryCredentialStore()
        let repository = AppLLMSettingsRepository(settingsStore: store, credentialStore: credentials)
        let service = AppLLMConnectionSetupService(
            settingsRepository: repository,
            anthropicCompatibleHealthCheck: { config in
                #expect(config.model == "deepseek-v4-flash")
                return LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK")
            }
        )

        let result = try await service.setupConnection(AppLLMConnectionSetupInput(
            id: "custom-anthropic-compatible",
            kind: .anthropicCompatible,
            name: "Custom Anthropic Compatible",
            baseURLString: "https://cnai.connor.run/v1",
            model: "deepseek-v4-flash, deepseek-v4-pro, gpt-5.5",
            selectedModel: "gpt-4o-mini",
            validationModel: "",
            apiKey: "secret"
        ))

        #expect(result.connection.model == "deepseek-v4-flash, deepseek-v4-pro, gpt-5.5")
        #expect(result.connection.selectedModel == "gpt-4o-mini")
    }

    @Test func anthropicCompatibleBearerAuthKindPersistsAndLoadsIntoRuntimeConfig() async throws {
        let repository = AppLLMSettingsRepository(settingsStore: MemoryLLMSettingsStore(), credentialStore: MemoryCredentialStore())
        let service = AppLLMConnectionSetupService(
            settingsRepository: repository,
            anthropicCompatibleHealthCheck: { config in
                #expect(config.authHeaderKind == .bearer)
                return LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK")
            }
        )

        _ = try await service.setupConnection(AppLLMConnectionSetupInput(
            id: "openrouter-anthropic-test",
            kind: .anthropicCompatible,
            name: "OpenRouter · Anthropic",
            baseURLString: "https://openrouter.ai/api",
            model: "anthropic/claude-sonnet-test",
            apiKey: "sk-or-secret",
            anthropicAuthHeaderKind: .bearer
        ))

        let config = try #require(try repository.anthropicCompatibleConfig(connectionID: "openrouter-anthropic-test"))
        #expect(config.authHeaderKind == .bearer)
        #expect(config.extraHeaders[AppLLMSettingsRepository.anthropicAuthHeaderKindMetadataKey] == nil)
    }

    @Test func legacyConnectionWithoutKindLoadsWithCompatibleDefault() throws {
        let store = MemoryLLMSettingsStore()
        let raw = """
        [{"id":"old","name":"Old","providerMode":"openai_compatible","baseURLString":"https://api.example.com/v1","model":"gpt","selectedModel":"gpt","hasAPIKey":false}]
        """
        store.set(raw, forKey: "llm.connections")
        store.set("old", forKey: "llm.defaultConnectionID")
        let repository = AppLLMSettingsRepository(settingsStore: store, credentialStore: MemoryCredentialStore())

        let settings = try repository.loadSettings()
        #expect(settings.defaultConnection?.connectionKind == .openAICompatible)
    }

    @Test func chatGPTCodexOAuthURLMatchesCraftOSSConfiguration() throws {
        let flow = try AppLLMOAuthService().prepareChatGPTOAuth()
        let components = try #require(URLComponents(url: flow.authURL, resolvingAgainstBaseURL: false))
        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        #expect(components.scheme == "https")
        #expect(components.host == "auth.openai.com")
        #expect(components.path == "/oauth/authorize")
        #expect(queryItems["client_id"] == "app_EMoamEEZ73f0CkXaXp7hrann")
        #expect(queryItems["response_type"] == "code")
        #expect(queryItems["redirect_uri"] == "http://localhost:1455/auth/callback")
        #expect(queryItems["scope"] == "openid profile email offline_access")
        #expect(queryItems["code_challenge_method"] == "S256")
        #expect(queryItems["codex_cli_simplified_flow"] == "true")
        #expect(queryItems["id_token_add_organizations"] == "true")
        #expect(queryItems["state"]?.isEmpty == false)
        #expect(queryItems["code_challenge"]?.isEmpty == false)
    }
}
