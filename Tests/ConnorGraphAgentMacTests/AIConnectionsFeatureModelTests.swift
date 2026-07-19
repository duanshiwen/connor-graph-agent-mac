import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

private final class AIModelFakeCredentialStore: CredentialStore, @unchecked Sendable {
    private var values: [String: String] = [:]
    func readSecret(service: String, account: String) throws -> String? { values["\(service):\(account)"] }
    func saveSecret(_ secret: String, service: String, account: String) throws { values["\(service):\(account)"] = secret }
    func deleteSecret(service: String, account: String) throws { values.removeValue(forKey: "\(service):\(account)") }
}

private final class AIModelFakeSettingsStore: LLMSettingsStore, @unchecked Sendable {
    var values: [String: String] = [:]
    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
}

@MainActor
@Test func aiConnectionsModelHydratesCredentialsAndOwnsWelcomeState() throws {
    let settingsStore = AIModelFakeSettingsStore()
    let credentialStore = AIModelFakeCredentialStore()
    let repository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: credentialStore)
    let connection = AppLLMConnectionConfig(
        id: "hydrated",
        name: "Hydrated",
        providerMode: .openAICompatible,
        baseURLString: "https://example.com/v1",
        model: "model-a",
        selectedModel: "model-a",
        hasAPIKey: false
    )
    try repository.save(settings: AppLLMSettings(connections: [connection], defaultConnectionID: connection.id), apiKey: "secret")

    let model = AIConnectionsFeatureModel(settingsRepository: repository)
    model.loadSettings()

    #expect(model.connectionConfigs.count == 1)
    #expect(model.connectionConfigs[0].hasAPIKey)
    #expect(model.defaultConnectionID == "hydrated")
    #expect(!model.showsWelcome)
}

@MainActor
@Test func aiConnectionsModelPersistsDefaultBeforeUpdatingWelcome() throws {
    let settingsStore = AIModelFakeSettingsStore()
    let repository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: AIModelFakeCredentialStore())
    let first = AppLLMConnectionConfig(id: "first", name: "First", providerMode: .openAICompatible, baseURLString: "https://first.example/v1", model: "first-model", selectedModel: "first-model", hasAPIKey: false)
    let second = AppLLMConnectionConfig(id: "second", name: "Second", providerMode: .openAICompatible, baseURLString: "https://second.example/v1", model: "second-model", selectedModel: "second-model", hasAPIKey: false)
    try repository.save(settings: AppLLMSettings(connections: [first, second], defaultConnectionID: first.id), apiKey: nil)

    let model = AIConnectionsFeatureModel(settingsRepository: repository)
    model.loadSettings()
    model.selectDefaultConnection(second.id)

    #expect(try repository.loadSettings().defaultConnectionID == second.id)
    #expect(model.defaultConnectionID == second.id)
    #expect(!model.showsWelcome)
}

@MainActor
@Test func aiConnectionsModelDefaultSelectionPreservesCompleteConnectionConfigs() throws {
    let settingsStore = AIModelFakeSettingsStore()
    let repository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: AIModelFakeCredentialStore())
    let first = AppLLMConnectionConfig(
        id: "anthropic",
        name: "MiMo Token Plan",
        providerMode: .anthropicMessages,
        connectionKind: .anthropicCompatible,
        baseURLString: "https://token-plan.example/anthropic",
        model: "mimo-pro,mimo",
        selectedModel: "mimo-pro",
        extraHTTPHeaders: ["x-provider": "mimo"],
        explicitVisionSupport: true
    )
    let second = AppLLMConnectionConfig(
        id: "openai",
        name: "OpenAI Proxy",
        providerMode: .openAICompatible,
        baseURLString: "https://openai.example/v1",
        model: "gpt-test",
        selectedModel: "gpt-test"
    )
    try repository.save(settings: AppLLMSettings(connections: [first, second], defaultConnectionID: first.id), apiKey: nil)
    let model = AIConnectionsFeatureModel(settingsRepository: repository)
    model.loadSettings()

    // Simulate session-scoped display values from another connection.
    model.providerMode = .openAICompatible
    model.selectedModel = "gpt-test"
    model.selectDefaultConnection(second.id)

    let loaded = try repository.loadSettings()
    #expect(loaded.defaultConnectionID == second.id)
    #expect(loaded.connection(id: first.id) == first)
    #expect(loaded.connection(id: second.id) == second)
}

@MainActor
@Test func deletingDefaultConnectionPreservesReplacementConnectionConfig() throws {
    let settingsStore = AIModelFakeSettingsStore()
    let repository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: AIModelFakeCredentialStore())
    let first = AppLLMConnectionConfig(
        id: "anthropic",
        name: "MiMo Token Plan",
        providerMode: .anthropicMessages,
        connectionKind: .anthropicCompatible,
        baseURLString: "https://token-plan.example/anthropic",
        model: "mimo-pro",
        selectedModel: "mimo-pro"
    )
    let second = AppLLMConnectionConfig(
        id: "openai",
        name: "OpenAI Proxy",
        providerMode: .openAICompatible,
        baseURLString: "https://openai.example/v1",
        model: "gpt-test",
        selectedModel: "gpt-test",
        extraHTTPHeaders: ["x-provider": "proxy"]
    )
    try repository.save(settings: AppLLMSettings(connections: [first, second], defaultConnectionID: first.id), apiKey: nil)
    let model = AIConnectionsFeatureModel(settingsRepository: repository)
    model.loadSettings()

    model.deleteConnection(first.id)

    let loaded = try repository.loadSettings()
    #expect(loaded.defaultConnectionID == second.id)
    #expect(loaded.connections == [second])
}

@MainActor
@Test func aiConnectionsModelRenamePreservesEvidenceAndDeleteClearsIt() throws {
    let settingsStore = AIModelFakeSettingsStore()
    let credentialStore = AIModelFakeCredentialStore()
    let repository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: credentialStore)
    let evidenceRepository = AppProviderCapabilityEvidenceRepository(settingsStore: settingsStore, credentialStore: credentialStore)
    let first = AppLLMConnectionConfig(id: "first", name: "First", providerMode: .openAICompatible, baseURLString: "https://first.example/v1", model: "model-a", selectedModel: "model-a", hasAPIKey: true)
    let second = AppLLMConnectionConfig(id: "second", name: "Second", providerMode: .openAICompatible, baseURLString: "https://second.example/v1", model: "model-b", selectedModel: "model-b", hasAPIKey: true)
    try repository.save(settings: AppLLMSettings(connections: [first, second], defaultConnectionID: first.id), apiKey: "first-key")
    try repository.saveAPIKey("second-key", connectionID: second.id)
    let binding = AppProviderCapabilityEvidenceRepository.bindingFingerprint(connection: second, credential: "second-key")
    try evidenceRepository.save(AppProviderCapabilitySnapshot(connectionID: second.id, evidence: [
        AppProviderCapabilityEvidence(capability: .responses, status: .verified, endpointFamily: "openai_responses", modelID: "model-b", bindingFingerprint: binding)
    ]))
    let model = AIConnectionsFeatureModel(settingsRepository: repository)
    model.loadSettings()

    #expect(model.capabilityDetailPresentation(for: second.id)?.capabilities.first?.status == .verified)
    model.renameConnection(second.id, name: "Renamed")
    #expect(model.capabilityDetailPresentation(for: second.id)?.connectionName == "Renamed")
    #expect(model.capabilityDetailPresentation(for: second.id)?.capabilities.first?.status == .verified)

    model.deleteConnection(second.id)
    #expect(model.capabilityDetailPresentation(for: second.id) == nil)
    #expect(evidenceRepository.loadAll().first { $0.connectionID == second.id }?.evidence.isEmpty == true)
    #expect(try repository.apiKey(for: second.id) == nil)
}

@MainActor
@Test func aiConnectionsModelSetupPublishesEvidenceAndNarrowCallbacks() async throws {
    let settingsStore = AIModelFakeSettingsStore()
    let repository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: AIModelFakeCredentialStore())
    let connection = AppLLMConnectionConfig(id: "new", name: "New", providerMode: .openAICompatible, baseURLString: "https://example.com/v1", model: "model-a", selectedModel: "model-a", hasAPIKey: true)
    let model = AIConnectionsFeatureModel(
        settingsRepository: repository,
        setupServiceFactory: { repository in
            AppLLMConnectionSetupService(
                settingsRepository: repository,
                capabilityDiscoveryService: nil,
                openAICompatibleHealthCheck: { _ in LLMProviderHealthCheckResult(ok: true, model: "model-a", message: "ok") }
            )
        }
    )
    var rebuilt: [Bool] = []
    var setupConnections: [String] = []
    model.onRuntimeSettingsChanged = { rebuilt.append($0) }
    model.onConnectionSetup = { setupConnections.append($0.id) }

    let result = try await model.setupConnection(AppLLMConnectionSetupInput(
        id: connection.id,
        kind: .openAICompatible,
        name: connection.name,
        baseURLString: connection.baseURLString,
        model: connection.model,
        selectedModel: connection.selectedModel,
        validationModel: connection.selectedModel,
        apiKey: "secret",
        makeDefault: true
    ))

    #expect(result.id == connection.id)
    #expect(setupConnections == [connection.id])
    #expect(rebuilt == [true])
    #expect(!model.showsWelcome)
    #expect(model.settingsMessage?.contains("连接验证成功") == true)
}
