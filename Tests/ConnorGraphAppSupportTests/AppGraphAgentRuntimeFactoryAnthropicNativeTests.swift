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

@Test func appLLMProviderModeIncludesNativePipelines() throws {
    #expect(AppLLMProviderMode.allCases.contains(.openAIResponses))
    #expect(AppLLMProviderMode.openAIResponses.displayName == "OpenAI Responses")
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

@Test func runtimeFactoryRoutesOpenAIResponsesThroughNativeResponsesProvider() throws {
    let store = try SQLiteGraphKernelStore(path: anthropicNativeTemporaryDatabaseURL().path)
    try store.migrate()
    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: AnthropicNativeSettingsStore(),
        credentialStore: AnthropicNativeCredentialStore()
    )
    let connection = AppLLMConnectionConfig(
        id: "openai-responses",
        name: "OpenAI Responses",
        providerMode: .openAIResponses,
        connectionKind: .openAIResponses,
        baseURLString: "https://api.openai.com/v1",
        model: "gpt-4.1",
        selectedModel: "gpt-4.1"
    )
    try settingsRepository.save(settings: AppLLMSettings(connections: [connection], defaultConnectionID: "openai-responses"), apiKey: "openai-key")
    let factory = AppGraphAgentRuntimeFactory(store: store, settingsRepository: settingsRepository)

    let provider = factory.makeAgentModelProvider()

    #expect(provider.modelID == "gpt-4.1")
    #expect(provider.capabilities.supportsParallelToolCalls == true)
    #expect(provider.capabilities.supportsStructuredOutput == true)
}

@Test func runtimeFactoryConditionallyRegistersGeneratedImageToolAndInstructionForGPT56Responses() throws {
    let databaseURL = anthropicNativeTemporaryDatabaseURL()
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = try SQLiteGraphKernelStore(path: databaseURL.path)
    try store.migrate()
    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: AnthropicNativeSettingsStore(),
        credentialStore: AnthropicNativeCredentialStore()
    )
    let connection = AppLLMConnectionConfig(
        id: "gpt-5.6-responses",
        name: "GPT-5.6 Responses",
        providerMode: .openAIResponses,
        connectionKind: .openAIResponses,
        baseURLString: "https://api.openai.com/v1",
        model: "gpt-5.6",
        selectedModel: "gpt-5.6"
    )
    try settingsRepository.save(settings: AppLLMSettings(connections: [connection], defaultConnectionID: connection.id), apiKey: "openai-key")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppStoragePaths(applicationSupportDirectory: root)
    try paths.ensureDirectoryHierarchy()
    let baseInstruction = "Keep this existing appendix unchanged."
    let factory = AppGraphAgentRuntimeFactory(store: store, settingsRepository: settingsRepository, storagePaths: paths)

    let controller = factory.makeAgentLoopController(configuration: AgentLoopConfiguration(instructionAppendix: baseInstruction))
    let names = controller.toolRegistry.definitions.map(\.name)

    #expect(names.filter { $0 == "generate_image" }.count == 1)
    #expect(controller.modelProvider.supportsGeneratedMediaExecution)
    #expect(controller.configuration.instructionAppendix.contains(baseInstruction))
    #expect(controller.configuration.instructionAppendix.contains("When the user asks to create or generate an image, use `generate_image`."))
}

@Test func runtimeFactoryDoesNotAdvertiseGeneratedImageWithoutStorageOrSupportedProvider() throws {
    let databaseURL = anthropicNativeTemporaryDatabaseURL()
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = try SQLiteGraphKernelStore(path: databaseURL.path)
    try store.migrate()
    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: AnthropicNativeSettingsStore(),
        credentialStore: AnthropicNativeCredentialStore()
    )
    let connection = AppLLMConnectionConfig(
        id: "compatible-gpt-5.6",
        name: "Compatible GPT-5.6",
        providerMode: .openAICompatible,
        connectionKind: .openAICompatible,
        baseURLString: "https://example.test/v1",
        model: "gpt-5.6",
        selectedModel: "gpt-5.6"
    )
    try settingsRepository.save(settings: AppLLMSettings(connections: [connection], defaultConnectionID: connection.id), apiKey: "compatible-key")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppStoragePaths(applicationSupportDirectory: root)
    try paths.ensureDirectoryHierarchy()
    let factory = AppGraphAgentRuntimeFactory(store: store, settingsRepository: settingsRepository, storagePaths: paths)

    let controller = factory.makeAgentLoopController()

    #expect(controller.toolRegistry.definitions.contains { $0.name == "generate_image" } == false)
    #expect(controller.configuration.instructionAppendix.contains("generate_image") == false)
}

@Test func runtimeFactoryDoesNotAdvertiseGeneratedImageWithoutAttachmentStorage() throws {
    let databaseURL = anthropicNativeTemporaryDatabaseURL()
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = try SQLiteGraphKernelStore(path: databaseURL.path)
    try store.migrate()
    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: AnthropicNativeSettingsStore(),
        credentialStore: AnthropicNativeCredentialStore()
    )
    let connection = AppLLMConnectionConfig(
        id: "gpt-5.6-no-storage",
        name: "GPT-5.6",
        providerMode: .openAIResponses,
        connectionKind: .openAIResponses,
        baseURLString: "https://api.openai.com/v1",
        model: "gpt-5.6",
        selectedModel: "gpt-5.6"
    )
    try settingsRepository.save(settings: AppLLMSettings(connections: [connection], defaultConnectionID: connection.id), apiKey: "openai-key")
    let factory = AppGraphAgentRuntimeFactory(store: store, settingsRepository: settingsRepository)

    let controller = factory.makeAgentLoopController()

    #expect(controller.toolRegistry.definitions.contains { $0.name == "generate_image" } == false)
    #expect(controller.configuration.instructionAppendix.contains("generate_image") == false)
}

@Test func runtimeFactoryRoutesOpenAICompatibleConnectionThroughChatCompletionsCompatibilityProvider() throws {
    let store = try SQLiteGraphKernelStore(path: anthropicNativeTemporaryDatabaseURL().path)
    try store.migrate()
    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: AnthropicNativeSettingsStore(),
        credentialStore: AnthropicNativeCredentialStore()
    )
    let connection = AppLLMConnectionConfig(
        id: "third-party-compatible",
        name: "OpenAI Compatible",
        providerMode: .openAICompatible,
        connectionKind: .openAICompatible,
        baseURLString: "https://example.test/v1",
        model: "compatible-model",
        selectedModel: "compatible-model"
    )
    try settingsRepository.save(settings: AppLLMSettings(connections: [connection], defaultConnectionID: "third-party-compatible"), apiKey: "compatible-key")
    let factory = AppGraphAgentRuntimeFactory(store: store, settingsRepository: settingsRepository)

    let provider = factory.makeAgentModelProvider()

    #expect(provider.modelID == "compatible-model")
    #expect(provider.capabilities.supportsParallelToolCalls == false)
    #expect(provider.capabilities.supportsStructuredOutput == false)
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
        selectedModel: "claude-sonnet-4-5"
    )
    try settingsRepository.save(settings: AppLLMSettings(connections: [connection], defaultConnectionID: "anthropic"), apiKey: "anthropic-key")
    let factory = AppGraphAgentRuntimeFactory(store: store, settingsRepository: settingsRepository)

    let provider = factory.makeAgentModelProvider()

    #expect(provider.modelID == "claude-sonnet-4-5")
    #expect(provider.capabilities.supportsToolCalling == true)
}
