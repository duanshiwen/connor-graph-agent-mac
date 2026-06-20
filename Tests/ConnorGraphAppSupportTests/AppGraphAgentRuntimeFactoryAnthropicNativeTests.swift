import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphStore

private final class AnthropicNativeCredentialStore: CredentialStore, @unchecked Sendable {
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

private final class AnthropicNativeSettingsStore: LLMSettingsStore, @unchecked Sendable {
    var values: [String: String] = [:]

    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
}

private func anthropicNativeTemporaryDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func appLLMProviderModeIncludesAnthropicMessagesNativePipeline() throws {
    #expect(AppLLMProviderMode.allCases.contains(.anthropicMessages))
    #expect(AppLLMProviderMode.anthropicMessages.displayName == "Anthropic Messages")
}

@Test func anthropicMessagesConnectionDefaultsToAnthropicConnectionKind() throws {
    let connection = AppLLMConnectionConfig(
        id: "anthropic",
        name: "Claude",
        providerMode: .anthropicMessages,
        baseURLString: "https://api.anthropic.com/v1",
        model: "claude-sonnet-4-5"
    )

    #expect(connection.connectionKind == .anthropicCompatible)
}

@Test func settingsRepositoryBuildsAnthropicMessagesConfigWithAPIKey() throws {
    let settingsStore = AnthropicNativeSettingsStore()
    let credentialStore = AnthropicNativeCredentialStore()
    let repository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: credentialStore)
    let connection = AppLLMConnectionConfig(
        id: "anthropic",
        name: "Claude",
        providerMode: .anthropicMessages,
        connectionKind: .anthropicCompatible,
        baseURLString: "https://api.anthropic.com/v1",
        model: "claude-sonnet-4-5",
        selectedModel: "claude-sonnet-4-5"
    )
    try repository.save(settings: AppLLMSettings(connections: [connection], defaultConnectionID: "anthropic"), apiKey: "anthropic-key")

    let loadedConfig = try repository.anthropicCompatibleConfig(connectionID: "anthropic")
    let config = try #require(loadedConfig)

    #expect(config.baseURL.absoluteString == "https://api.anthropic.com/v1")
    #expect(config.apiKey == "anthropic-key")
    #expect(config.model == "claude-sonnet-4-5")
}

@Test func runtimeFactoryRoutesAnthropicMessagesThroughNativeProvider() throws {
    let store = try SQLiteGraphKernelStore(path: anthropicNativeTemporaryDatabaseURL().path)
    try store.migrate()
    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: AnthropicNativeSettingsStore(),
        credentialStore: AnthropicNativeCredentialStore()
    )
    let connection = AppLLMConnectionConfig(
        id: "anthropic",
        name: "Claude",
        providerMode: .anthropicMessages,
        connectionKind: .anthropicCompatible,
        baseURLString: "https://api.anthropic.com/v1",
        model: "claude-sonnet-4-5",
        selectedModel: "claude-sonnet-4-5",
        sidecarExecutablePath: ""
    )
    try settingsRepository.save(settings: AppLLMSettings(connections: [connection], defaultConnectionID: "anthropic"), apiKey: "anthropic-key")
    let factory = AppGraphAgentRuntimeFactory(store: store, settingsRepository: settingsRepository)

    let provider = factory.makeAgentModelProvider()

    #expect(provider.modelID == "claude-sonnet-4-5")
    #expect(provider.modelID != "governed-claude-sidecar-requires-session-manager")
    #expect(provider.capabilities.supportsToolCalling == true)
}
