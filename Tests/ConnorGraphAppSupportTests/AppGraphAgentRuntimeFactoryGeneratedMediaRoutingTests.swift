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

    #expect(controller.toolRegistry.definitions.contains { $0.name == "generate_image" } == false)
    #expect(controller.configuration.instructionAppendix.contains("generate_image") == false)
}
