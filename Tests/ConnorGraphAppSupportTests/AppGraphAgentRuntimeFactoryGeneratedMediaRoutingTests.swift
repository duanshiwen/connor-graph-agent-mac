import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphStore

private final class MediaRoutingCredentialStore: CredentialStore, @unchecked Sendable {
    var secrets: [String: String] = [:]
    func saveSecret(_ secret: String, service: String, account: String) throws { secrets["\(service):\(account)"] = secret }
    func readSecret(service: String, account: String) throws -> String? { secrets["\(service):\(account)"] }
    func deleteSecret(service: String, account: String) throws { secrets.removeValue(forKey: "\(service):\(account)") }
}

private final class MediaRoutingSettingsStore: LLMSettingsStore, @unchecked Sendable {
    var values: [String: String] = [:]
    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
}

private func mediaRoutingFactory(chatConnection: AppLLMConnectionConfig, apiKey: String) throws -> (AppGraphAgentRuntimeFactory, URL, URL) {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
    let store = try SQLiteGraphKernelStore(path: databaseURL.path)
    try store.migrate()
    let repository = AppLLMSettingsRepository(settingsStore: MediaRoutingSettingsStore(), credentialStore: MediaRoutingCredentialStore())
    try repository.save(settings: AppLLMSettings(connections: [chatConnection], defaultConnectionID: chatConnection.id), apiKey: apiKey)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let paths = AppStoragePaths(applicationSupportDirectory: root)
    try paths.ensureDirectoryHierarchy()
    return (AppGraphAgentRuntimeFactory(store: store, settingsRepository: repository, storagePaths: paths), databaseURL, root)
}

@Test func runtimeFactoryExposesImageToolWhenCurrentModelSupportsImageGeneration() throws {
    let gpt = AppLLMConnectionConfig(
        id: "gpt-chat", name: "GPT Chat", providerMode: .openAIResponses,
        connectionKind: .openAIResponses, baseURLString: "https://ai.apecho.com/v1", model: "gpt-5.6"
    )
    let (factory, databaseURL, root) = try mediaRoutingFactory(chatConnection: gpt, apiKey: "gpt-key")
    defer { try? FileManager.default.removeItem(at: databaseURL); try? FileManager.default.removeItem(at: root) }

    let controller = factory.makeAgentLoopController()

    #expect(controller.modelProvider.modelID == "gpt-5.6")
    #expect(controller.modelProvider.capabilities.generatedMediaCapabilities.contains(.imageGeneration))
    #expect(controller.toolRegistry.definitions.contains { $0.name == "generate_image" })
    #expect(controller.toolRegistry.definitions.contains { $0.name == "edit_image" })
    #expect(controller.configuration.instructionAppendix.contains("use `generate_image`"))
}

@Test func runtimeFactoryHidesImageToolWhenCurrentModelCannotGenerateImages() throws {
    let claude = AppLLMConnectionConfig(
        id: "claude-chat", name: "Claude Chat", providerMode: .anthropicMessages,
        connectionKind: .anthropicCompatible, baseURLString: "https://api.anthropic.com/v1", model: "claude-sonnet-4-5"
    )
    let (factory, databaseURL, root) = try mediaRoutingFactory(chatConnection: claude, apiKey: "claude-key")
    defer { try? FileManager.default.removeItem(at: databaseURL); try? FileManager.default.removeItem(at: root) }

    let controller = factory.makeAgentLoopController()

    // 新策略：图片生成一律使用当前会话模型；当前模型不支持时不注册 generate_image/edit_image，
    // 也不回退到任何独立图片连接或其它已配置连接。
    #expect(controller.modelProvider.modelID == "claude-sonnet-4-5")
    #expect(controller.modelProvider.capabilities.generatedMediaCapabilities.contains(.imageGeneration) == false)
    #expect(controller.toolRegistry.definitions.contains { $0.name == "generate_image" } == false)
    #expect(controller.toolRegistry.definitions.contains { $0.name == "edit_image" } == false)
    #expect(controller.configuration.instructionAppendix.contains("Image generation (`generate_image`) and image editing (`edit_image`) are NOT available"))
    #expect(controller.configuration.instructionAppendix.contains("prefer `image_search`"))
}

@Test func runtimeFactoryDoesNotFallBackToOtherConfiguredImageConnection() throws {
    let settingsStore = MediaRoutingSettingsStore()
    let credentialStore = MediaRoutingCredentialStore()
    let repository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: credentialStore)
    let chat = AppLLMConnectionConfig(
        id: "claude-chat", name: "Claude Chat", providerMode: .anthropicMessages,
        connectionKind: .anthropicCompatible, baseURLString: "https://api.anthropic.com/v1", model: "claude-sonnet-4-5"
    )
    let otherImage = AppLLMConnectionConfig(
        id: "image-conn", name: "Image Conn", providerMode: .openAIResponses,
        connectionKind: .openAIResponses, baseURLString: "https://ai.apecho.com/v1", model: "gpt-5.6"
    )
    try repository.save(settings: AppLLMSettings(connections: [chat, otherImage], defaultConnectionID: chat.id), apiKey: "claude-key")
    try credentialStore.saveSecret("image-key", service: AppLLMSettingsRepository.credentialNamespace, account: AppLLMSettingsRepository.apiKeyAccount(for: otherImage.id))
    let evidenceRepository = AppProviderCapabilityEvidenceRepository(settingsStore: settingsStore, credentialStore: credentialStore)
    try evidenceRepository.replaceEvidence(
        AppProviderCapabilityEvidence(
            capability: .hostedImageGeneration, status: .verified, endpointFamily: "openai_responses",
            modelID: "gpt-5.6",
            bindingFingerprint: AppProviderCapabilityEvidenceRepository.bindingFingerprint(connection: otherImage, credential: "image-key")
        ),
        connectionID: otherImage.id
    )
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
    let store = try SQLiteGraphKernelStore(path: databaseURL.path); try store.migrate()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let paths = AppStoragePaths(applicationSupportDirectory: root); try paths.ensureDirectoryHierarchy()
    defer { try? FileManager.default.removeItem(at: databaseURL); try? FileManager.default.removeItem(at: root) }
    let factory = AppGraphAgentRuntimeFactory(
        store: store, settingsRepository: repository, capabilityEvidenceRepository: evidenceRepository, storagePaths: paths
    )

    let controller = factory.makeAgentLoopController()

    // 即便存在已通过 hosted_image_generation 探测的其它连接，也不能用它出图——工具组整组隐藏。
    #expect(controller.modelProvider.modelID == "claude-sonnet-4-5")
    #expect(controller.toolRegistry.definitions.contains { $0.name == "generate_image" } == false)
    #expect(controller.toolRegistry.definitions.contains { $0.name == "edit_image" } == false)
}
