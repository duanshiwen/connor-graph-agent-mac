import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

private final class ConfiguredMediaStore: LLMSettingsStore, @unchecked Sendable { var values: [String: String] = [:]; func string(forKey key: String) -> String? { values[key] }; func set(_ value: String, forKey key: String) { values[key] = value } }
private final class ConfiguredMediaCredentials: CredentialStore, @unchecked Sendable { var values: [String: String] = [:]; func saveSecret(_ secret: String, service: String, account: String) throws { values["\(service):\(account)"] = secret }; func readSecret(service: String, account: String) throws -> String? { values["\(service):\(account)"] }; func deleteSecret(service: String, account: String) throws { values.removeValue(forKey: "\(service):\(account)") } }

@Test func runtimeFactoryUsesExplicitConfiguredMediaConnectionForClaudeChat() throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite"); defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = try SQLiteGraphKernelStore(path: databaseURL.path); try store.migrate()
    let llmStore = ConfiguredMediaStore(); let llmCredentials = ConfiguredMediaCredentials(); let llmRepository = AppLLMSettingsRepository(settingsStore: llmStore, credentialStore: llmCredentials)
    let claude = AppLLMConnectionConfig(id: "claude", name: "Claude", providerMode: .anthropicMessages, connectionKind: .anthropicCompatible, baseURLString: "https://api.anthropic.com/v1", model: "claude-sonnet-4-5")
    try llmRepository.save(settings: AppLLMSettings(connections: [claude], defaultConnectionID: claude.id), apiKey: "claude-key")
    let mediaStore = ConfiguredMediaStore(); let mediaCredentials = ConfiguredMediaCredentials(); let mediaRepository = AppGeneratedMediaSettingsRepository(settingsStore: mediaStore, credentialStore: mediaCredentials)
    let gemini = AppGeneratedMediaConnectionConfig(id: "gemini", name: "Gemini Image", providerKind: .geminiImage, baseURLString: "https://generativelanguage.googleapis.com/v1beta", model: "gemini-3.1-flash-image")
    try mediaRepository.save(settings: AppGeneratedMediaSettings(connections: [gemini], defaultImageConnectionID: gemini.id)); try mediaRepository.saveAPIKey("gemini-key", connectionID: gemini.id)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true); defer { try? FileManager.default.removeItem(at: root) }; let paths = AppStoragePaths(applicationSupportDirectory: root); try paths.ensureDirectoryHierarchy()
    let factory = AppGraphAgentRuntimeFactory(store: store, settingsRepository: llmRepository, generatedMediaSettingsRepository: mediaRepository, storagePaths: paths)

    let controller = factory.makeAgentLoopController()

    #expect(controller.modelProvider.modelID == "claude-sonnet-4-5")
    #expect(controller.toolRegistry.definitions.contains { $0.name == "generate_image" })
}

@Test func runtimeFactoryUsesExplicitOpenAIResponsesMediaConnectionForRelayChat() throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite"); defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = try SQLiteGraphKernelStore(path: databaseURL.path); try store.migrate()
    let llmStore = ConfiguredMediaStore(); let llmCredentials = ConfiguredMediaCredentials(); let llmRepository = AppLLMSettingsRepository(settingsStore: llmStore, credentialStore: llmCredentials)
    let relay = AppLLMConnectionConfig(id: "relay", name: "Relay GPT", providerMode: .openAICompatible, connectionKind: .openAICompatible, baseURLString: "https://relay.example.com/v1", model: "gpt-5.6")
    try llmRepository.save(settings: AppLLMSettings(connections: [relay], defaultConnectionID: relay.id), apiKey: "relay-key")
    let mediaStore = ConfiguredMediaStore(); let mediaCredentials = ConfiguredMediaCredentials(); let mediaRepository = AppGeneratedMediaSettingsRepository(settingsStore: mediaStore, credentialStore: mediaCredentials)
    let responses = AppGeneratedMediaConnectionConfig(id: "responses", name: "Relay Responses Image", providerKind: .openAIResponses, baseURLString: "https://relay.example.com/v1", model: "gpt-5.6")
    try mediaRepository.save(settings: AppGeneratedMediaSettings(connections: [responses], defaultImageConnectionID: responses.id)); try mediaRepository.saveAPIKey("responses-key", connectionID: responses.id)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true); defer { try? FileManager.default.removeItem(at: root) }; let paths = AppStoragePaths(applicationSupportDirectory: root); try paths.ensureDirectoryHierarchy()
    let factory = AppGraphAgentRuntimeFactory(store: store, settingsRepository: llmRepository, generatedMediaSettingsRepository: mediaRepository, storagePaths: paths)

    let controller = factory.makeAgentLoopController()

    #expect(controller.modelProvider.modelID == "gpt-5.6")
    #expect(!controller.modelProvider.capabilities.generatedMediaCapabilities.contains(.imageGeneration))
    #expect(controller.toolRegistry.definitions.contains { $0.name == "generate_image" })
}

@Test func runtimeFactoryDoesNotInferImageGenerationFromRelayGPTModelName() throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite"); defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = try SQLiteGraphKernelStore(path: databaseURL.path); try store.migrate()
    let llmStore = ConfiguredMediaStore(); let llmCredentials = ConfiguredMediaCredentials(); let llmRepository = AppLLMSettingsRepository(settingsStore: llmStore, credentialStore: llmCredentials)
    let relay = AppLLMConnectionConfig(id: "relay", name: "Relay GPT", providerMode: .openAICompatible, connectionKind: .openAICompatible, baseURLString: "https://relay.example.com/v1", model: "gpt-5.6")
    try llmRepository.save(settings: AppLLMSettings(connections: [relay], defaultConnectionID: relay.id), apiKey: "relay-key")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true); defer { try? FileManager.default.removeItem(at: root) }; let paths = AppStoragePaths(applicationSupportDirectory: root); try paths.ensureDirectoryHierarchy()
    let factory = AppGraphAgentRuntimeFactory(store: store, settingsRepository: llmRepository, storagePaths: paths)

    let controller = factory.makeAgentLoopController()

    #expect(!controller.modelProvider.capabilities.generatedMediaCapabilities.contains(.imageGeneration))
    #expect(!controller.toolRegistry.definitions.contains { $0.name == "generate_image" })
}
