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

private func mediaRoutingFactory(mediaProvider: AnyAgentModelProvider?) throws -> (AppGraphAgentRuntimeFactory, URL, URL) {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
    let store = try SQLiteGraphKernelStore(path: databaseURL.path)
    try store.migrate()
    let repository = AppLLMSettingsRepository(settingsStore: MediaRoutingSettingsStore(), credentialStore: MediaRoutingCredentialStore())
    let connection = AppLLMConnectionConfig(
        id: "claude-chat",
        name: "Claude Chat",
        providerMode: .anthropicMessages,
        connectionKind: .anthropicCompatible,
        baseURLString: "https://api.anthropic.com/v1",
        model: "claude-sonnet-4-5"
    )
    try repository.save(settings: AppLLMSettings(connections: [connection], defaultConnectionID: connection.id), apiKey: "claude-key")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let paths = AppStoragePaths(applicationSupportDirectory: root)
    try paths.ensureDirectoryHierarchy()
    return (AppGraphAgentRuntimeFactory(
        store: store,
        settingsRepository: repository,
        storagePaths: paths,
        generatedMediaProviderResolver: { _ in mediaProvider }
    ), databaseURL, root)
}

private func fakeIndependentImageProvider() -> AnyAgentModelProvider {
    AnyAgentModelProvider(
        modelID: "independent-image-model",
        capabilities: AgentModelCapabilities(
            supportsStreaming: false,
            supportsToolCalling: false,
            supportsParallelToolCalls: false,
            supportsStructuredOutput: false,
            supportsVision: false,
            generatedMediaCapabilities: [.imageGeneration]
        ),
        complete: { _ in AgentModelResponse(text: "unused") },
        generateMedia: { _ in AsyncThrowingStream { $0.finish() } }
    )
}

@Test func runtimeFactoryCanRouteClaudeConversationToIndependentImageProvider() throws {
    let (factory, databaseURL, root) = try mediaRoutingFactory(mediaProvider: fakeIndependentImageProvider())
    defer { try? FileManager.default.removeItem(at: databaseURL); try? FileManager.default.removeItem(at: root) }

    let controller = factory.makeAgentLoopController()

    #expect(controller.modelProvider.modelID == "claude-sonnet-4-5")
    #expect(controller.modelProvider.capabilities.generatedMediaCapabilities.contains(.imageGeneration) == false)
    #expect(controller.toolRegistry.definitions.contains { $0.name == "generate_image" })
    #expect(controller.configuration.instructionAppendix.contains("use `generate_image`"))
}

@Test func runtimeFactoryDoesNotAdvertiseImageToolWhenResolverReturnsNil() throws {
    let (factory, databaseURL, root) = try mediaRoutingFactory(mediaProvider: nil)
    defer { try? FileManager.default.removeItem(at: databaseURL); try? FileManager.default.removeItem(at: root) }

    let controller = factory.makeAgentLoopController()

    // 主模型不支持图片生成时：不注册 generate_image，且明确告知模型“不可用”，
    // 避免模型凭空声称“图片已生成/已附在回答中”。
    #expect(controller.toolRegistry.definitions.contains { $0.name == "generate_image" } == false)
    #expect(controller.configuration.instructionAppendix.contains("Image generation (`generate_image`) and image editing (`edit_image`) are NOT available"))
    #expect(controller.configuration.instructionAppendix.contains("prefer `image_search`"))
}

@Test func runtimeFactoryFallsBackToVerifiedImageConnectionWhenChatModelCannotGenerate() throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
    let store = try SQLiteGraphKernelStore(path: databaseURL.path)
    try store.migrate()
    let settingsStore = MediaRoutingSettingsStore()
    let credentialStore = MediaRoutingCredentialStore()
    let repository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: credentialStore)
    let chat = AppLLMConnectionConfig(
        id: "claude-chat", name: "Claude Chat", providerMode: .anthropicMessages,
        connectionKind: .anthropicCompatible, baseURLString: "https://api.anthropic.com/v1", model: "claude-sonnet-4-5"
    )
    let image = AppLLMConnectionConfig(
        id: "image-conn", name: "Image Conn", providerMode: .openAIResponses,
        connectionKind: .openAIResponses, baseURLString: "https://ai.apecho.com/v1", model: "gpt-5.6"
    )
    try repository.save(settings: AppLLMSettings(connections: [chat, image], defaultConnectionID: chat.id), apiKey: "claude-key")
    try credentialStore.saveSecret(
        "image-key",
        service: AppLLMSettingsRepository.credentialNamespace,
        account: AppLLMSettingsRepository.apiKeyAccount(for: image.id)
    )
    let evidenceRepository = AppProviderCapabilityEvidenceRepository(settingsStore: settingsStore, credentialStore: credentialStore)
    let fingerprint = AppProviderCapabilityEvidenceRepository.bindingFingerprint(connection: image, credential: "image-key")
    try evidenceRepository.replaceEvidence(
        AppProviderCapabilityEvidence(
            capability: .hostedImageGeneration,
            status: .verified,
            endpointFamily: "openai_responses",
            modelID: "gpt-5.6",
            bindingFingerprint: fingerprint
        ),
        connectionID: image.id
    )
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let paths = AppStoragePaths(applicationSupportDirectory: root)
    try paths.ensureDirectoryHierarchy()
    defer {
        try? FileManager.default.removeItem(at: databaseURL)
        try? FileManager.default.removeItem(at: root)
    }
    let factory = AppGraphAgentRuntimeFactory(
        store: store,
        settingsRepository: repository,
        capabilityEvidenceRepository: evidenceRepository,
        storagePaths: paths
    )

    let controller = factory.makeAgentLoopController()

    // 主模型（Claude）不能生成图片，但存在已验证的 hosted_image_generation 连接 → 回退启用 generate_image。
    #expect(controller.modelProvider.modelID == "claude-sonnet-4-5")
    #expect(controller.modelProvider.capabilities.generatedMediaCapabilities.contains(.imageGeneration) == false)
    #expect(controller.toolRegistry.definitions.contains { $0.name == "generate_image" })
    #expect(controller.configuration.instructionAppendix.contains("use `generate_image`"))
}
