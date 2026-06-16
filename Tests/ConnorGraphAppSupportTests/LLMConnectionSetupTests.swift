import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport

private final class MemoryLLMSettingsStore: LLMSettingsStore, @unchecked Sendable {
    var values: [String: String] = [:]
    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
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
        #expect(loaded.defaultConnectionID == "provider-1")
        #expect(loaded.defaultConnection.connectionKind == .openAICompatible)
        #expect(loaded.defaultConnection.hasAPIKey)
        #expect(store.values.values.contains(where: { $0.contains("Provider 1") }))
        #expect(!store.values.values.contains(where: { $0.contains("secret") }))
        #expect(try repository.apiKey(for: "provider-1") == "secret")
    }

    @Test func claudeSidecarRejectsAllowAll() async throws {
        let repository = AppLLMSettingsRepository(settingsStore: MemoryLLMSettingsStore(), credentialStore: MemoryCredentialStore())
        let service = AppLLMConnectionSetupService(settingsRepository: repository)

        await #expect(throws: AppLLMConnectionSetupError.unsafePermissionMode) {
            try await service.setupConnection(AppLLMConnectionSetupInput(
                kind: .claudeSidecar,
                name: "Claude",
                model: "claude-sdk-default",
                sidecarExecutablePath: "/bin/echo",
                sidecarPermissionMode: .allowAll
            ))
        }
    }

    @Test func claudeSidecarSuccessSavesOAuthToken() async throws {
        let store = MemoryLLMSettingsStore()
        let credentials = MemoryCredentialStore()
        let repository = AppLLMSettingsRepository(settingsStore: store, credentialStore: credentials)
        let service = AppLLMConnectionSetupService(
            settingsRepository: repository,
            sidecarValidator: { connection in LLMProviderHealthCheckResult(ok: true, model: connection.effectiveModel, message: "OK") }
        )

        let result = try await service.setupConnection(AppLLMConnectionSetupInput(
            id: "claude-test",
            kind: .claudeSidecar,
            name: "Claude",
            model: "claude-sdk-default",
            oauthTokens: AppLLMOAuthTokens(accessToken: "claude-token"),
            sidecarExecutablePath: "/bin/echo",
            sidecarPermissionMode: .readOnly
        ))

        #expect(result.connection.connectionKind == .claudeSidecar)
        #expect(try repository.oauthTokens(for: "claude-test")?.accessToken == "claude-token")
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
                #expect(config.extraHeaders["Copilot-Integration-Id"] == "vscode-chat")
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
        #expect(result.connection.extraHTTPHeaders["Copilot-Integration-Id"] == "vscode-chat")
        #expect(try repository.apiKey(for: "github-test") == "copilot-token")
    }

    @Test func legacyConnectionWithoutKindLoadsWithCompatibleDefault() throws {
        let store = MemoryLLMSettingsStore()
        let raw = """
        [{"id":"old","name":"Old","providerMode":"openai_compatible","baseURLString":"https://api.example.com/v1","model":"gpt","selectedModel":"gpt","hasAPIKey":false,"sidecarExecutablePath":"","sidecarArguments":"","sidecarWorkingDirectoryPath":"","sidecarPermissionMode":"readOnly"}]
        """
        store.set(raw, forKey: "llm.connections")
        store.set("old", forKey: "llm.defaultConnectionID")
        let repository = AppLLMSettingsRepository(settingsStore: store, credentialStore: MemoryCredentialStore())

        let settings = try repository.loadSettings()
        #expect(settings.defaultConnection.connectionKind == .openAICompatible)
    }
}
