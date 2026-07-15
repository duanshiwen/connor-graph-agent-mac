import AppKit
import Foundation
import Testing
import ConnorGraphStore
import ConnorGraphAgent
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

private final class WelcomeStateFakeCredentialStore: CredentialStore, @unchecked Sendable {
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

private final class WelcomeStateFakeSettingsStore: LLMSettingsStore, @unchecked Sendable {
    var values: [String: String] = [:]

    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
}

@MainActor
private func makeRuntime(
    settingsStore: WelcomeStateFakeSettingsStore = WelcomeStateFakeSettingsStore(),
    credentialStore: WelcomeStateFakeCredentialStore = WelcomeStateFakeCredentialStore(),
    runtimeSettings: AgentRuntimeSettings? = nil,
    llmConnectionSetupServiceFactory: @escaping @MainActor (AppLLMSettingsRepository) -> AppLLMConnectionSetupService = { AppLLMConnectionSetupService(settingsRepository: $0) }
) throws -> AppRuntimeLifecycle {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-app-vm-welcome-state-\(UUID().uuidString)", isDirectory: true)
    let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: root)
    try paths.ensureDirectoryHierarchy(fileManager: .default)
    if let runtimeSettings {
        try AppRuntimeSettingsRepository(configDirectory: paths.configDirectory).save(runtimeSettings)
    }
    let repository = try AppGraphRepository.bootstrap(paths: paths)
    let llmRepository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: credentialStore)
    return AppRuntimeLifecycle(
        entities: [],
        statements: [],
        observeLogEntries: [],
        repository: repository,
        databasePath: paths.databaseURL.path,
        storagePaths: paths,
        llmSettingsRepository: llmRepository,
        llmConnectionSetupServiceFactory: llmConnectionSetupServiceFactory
    )
}

@MainActor
@Test func runtimeUsesDisabledToolErrorFuseByDefault() throws {
    let runtime = try makeRuntime()

    #expect(runtime.effectiveLoopConfiguration.maxConsecutiveToolResultErrors == 0)
}

@MainActor
@Test func runtimePreservesLoadedLoopConfigurationWithoutEnablingToolErrorFuse() throws {
    var settings = AgentRuntimeSettings.default
    settings.loop.maxToolIterations = 17
    settings.loop.maxConsecutiveToolResultErrors = 0
    let runtime = try makeRuntime(runtimeSettings: settings)

    runtime.loadRuntimeSettings()

    #expect(runtime.effectiveLoopConfiguration.maxToolIterations == 17)
    #expect(runtime.effectiveLoopConfiguration.maxConsecutiveToolResultErrors == 0)
}

@MainActor
@Test func runtimeShowsWelcomeWhenNoLLMConnectionExists() throws {
    let runtime = try makeRuntime()

    runtime.aiConnectionsModel.loadSettings()
    runtime.aiConnectionsModel.updateWelcomeState()

    #expect(runtime.aiConnectionsModel.showsWelcome == true)
}

@MainActor
@Test func runtimeHidesWelcomeWhenAnyConnectionExists() throws {
    let settingsStore = WelcomeStateFakeSettingsStore()
    let credentialStore = WelcomeStateFakeCredentialStore()
    let repository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: credentialStore)
    let shell = AppLLMConnectionConfig(
        id: "shell",
        name: "Shell",
        providerMode: .openAICompatible,
        baseURLString: "https://example.com/v1",
        model: "gpt-4o-mini",
        selectedModel: "gpt-4o-mini",
        hasAPIKey: false
    )
    try repository.save(settings: AppLLMSettings(connections: [shell], defaultConnectionID: shell.id), apiKey: nil)

    let runtime = try makeRuntime(settingsStore: settingsStore, credentialStore: credentialStore)
    runtime.aiConnectionsModel.loadSettings()
    runtime.aiConnectionsModel.updateWelcomeState()

    #expect(runtime.aiConnectionsModel.showsWelcome == false)
}

@MainActor
@Test func runtimeHidesWelcomeWhenConfiguredConnectionExists() throws {
    let settingsStore = WelcomeStateFakeSettingsStore()
    let credentialStore = WelcomeStateFakeCredentialStore()
    let repository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: credentialStore)
    let connection = AppLLMConnectionConfig(
        id: "usable",
        name: "Usable",
        providerMode: .openAICompatible,
        baseURLString: "https://example.com/v1",
        model: "gpt-4o-mini",
        selectedModel: "gpt-4o-mini",
        hasAPIKey: true
    )
    try repository.save(settings: AppLLMSettings(connections: [connection], defaultConnectionID: connection.id), apiKey: "real-key")

    let runtime = try makeRuntime(settingsStore: settingsStore, credentialStore: credentialStore)
    runtime.aiConnectionsModel.loadSettings()
    runtime.aiConnectionsModel.updateWelcomeState()

    #expect(runtime.aiConnectionsModel.showsWelcome == false)
}

@MainActor
@Test func runtimeHidesWelcomeWhenStoredConnectionHydratesAPIKeyFromCredentialStore() throws {
    let settingsStore = WelcomeStateFakeSettingsStore()
    let credentialStore = WelcomeStateFakeCredentialStore()
    let repository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: credentialStore)
    let persistedShell = AppLLMConnectionConfig(
        id: "hydrated",
        name: "Hydrated",
        providerMode: .openAICompatible,
        baseURLString: "https://example.com/v1",
        model: "gpt-4o-mini",
        selectedModel: "gpt-4o-mini",
        hasAPIKey: false
    )
    try repository.save(settings: AppLLMSettings(connections: [persistedShell], defaultConnectionID: persistedShell.id), apiKey: "real-key")

    let runtime = try makeRuntime(settingsStore: settingsStore, credentialStore: credentialStore)
    runtime.aiConnectionsModel.loadSettings()
    runtime.aiConnectionsModel.updateWelcomeState()

    #expect(runtime.aiConnectionsModel.connectionConfigs.first?.hasAPIKey == true)
    #expect(runtime.aiConnectionsModel.showsWelcome == false)
}

@MainActor
@Test func runtimeHidesWelcomeImmediatelyAfterFirstConnectionBecomesSelected() throws {
    let settingsStore = WelcomeStateFakeSettingsStore()
    let credentialStore = WelcomeStateFakeCredentialStore()
    let repository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: credentialStore)
    let shell = AppLLMConnectionConfig(
        id: "first",
        name: "First",
        providerMode: .openAICompatible,
        baseURLString: "https://example.com/v1",
        model: "gpt-4o-mini",
        selectedModel: "gpt-4o-mini",
        hasAPIKey: false
    )
    try repository.save(settings: AppLLMSettings(connections: [shell], defaultConnectionID: shell.id), apiKey: "real-key")

    let runtime = try makeRuntime(settingsStore: settingsStore, credentialStore: credentialStore)
    runtime.aiConnectionsModel.selectDefaultConnection("first")

    #expect(runtime.aiConnectionsModel.showsWelcome == false)
}

@MainActor
@Test func deletingViewedNonDefaultConnectionPreservesDefaultRoute() throws {
    let settingsStore = WelcomeStateFakeSettingsStore()
    let credentialStore = WelcomeStateFakeCredentialStore()
    let repository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: credentialStore)
    let first = AppLLMConnectionConfig(id: "first", name: "First", providerMode: .openAICompatible, baseURLString: "https://first.example/v1", model: "model-a", selectedModel: "model-a", hasAPIKey: true)
    let second = AppLLMConnectionConfig(id: "second", name: "Second", providerMode: .openAICompatible, baseURLString: "https://second.example/v1", model: "model-b", selectedModel: "model-b", hasAPIKey: true)
    try repository.save(settings: AppLLMSettings(connections: [first, second], defaultConnectionID: first.id), apiKey: "first-key")
    try repository.saveAPIKey("second-key", connectionID: second.id)
    let runtime = try makeRuntime(settingsStore: settingsStore, credentialStore: credentialStore)
    runtime.aiConnectionsModel.loadSettings()

    runtime.aiConnectionsModel.deleteConnection(second.id)

    let loaded = try repository.loadSettings()
    #expect(loaded.defaultConnectionID == first.id)
    #expect(loaded.connections.map(\.id) == [first.id])
    #expect(try repository.apiKey(for: second.id) == nil)
}

@MainActor
@Test func capabilityDetailIsReadonlyAcrossRenameAndUnavailableAfterDelete() throws {
    let settingsStore = WelcomeStateFakeSettingsStore()
    let credentialStore = WelcomeStateFakeCredentialStore()
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
    let runtime = try makeRuntime(settingsStore: settingsStore, credentialStore: credentialStore)
    runtime.aiConnectionsModel.loadSettings()

    #expect(runtime.aiConnectionsModel.capabilityDetailPresentation(for: second.id)?.capabilities.first?.status == .verified)

    runtime.aiConnectionsModel.renameConnection(second.id, name: "Renamed")

    #expect(runtime.aiConnectionsModel.capabilityDetailPresentation(for: second.id)?.connectionName == "Renamed")
    #expect(runtime.aiConnectionsModel.capabilityDetailPresentation(for: second.id)?.capabilities.first?.status == .verified)

    runtime.aiConnectionsModel.deleteConnection(second.id)

    #expect(runtime.aiConnectionsModel.capabilityDetailPresentation(for: second.id) == nil)
    #expect(evidenceRepository.loadAll().first { $0.connectionID == second.id }?.evidence.isEmpty == true)
}

@MainActor
@Test func selectingConnectionPersistsBeforeWelcomeStateRecalculation() throws {
    let settingsStore = WelcomeStateFakeSettingsStore()
    let credentialStore = WelcomeStateFakeCredentialStore()
    let repository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: credentialStore)

    let first = AppLLMConnectionConfig(
        id: "first",
        name: "First",
        providerMode: .openAICompatible,
        baseURLString: "https://example.com/v1",
        model: "gpt-4o-mini",
        selectedModel: "gpt-4o-mini",
        hasAPIKey: true
    )
    let second = AppLLMConnectionConfig(
        id: "second",
        name: "Second",
        providerMode: .openAICompatible,
        baseURLString: "https://example.org/v1",
        model: "gpt-4.1-mini",
        selectedModel: "gpt-4.1-mini",
        hasAPIKey: true
    )
    try repository.save(settings: AppLLMSettings(connections: [first, second], defaultConnectionID: first.id), apiKey: "real-key")
    try repository.saveAPIKey("other-key", connectionID: second.id)

    let runtime = try makeRuntime(settingsStore: settingsStore, credentialStore: credentialStore)
    runtime.aiConnectionsModel.loadSettings()
    runtime.aiConnectionsModel.selectDefaultConnection("second")

    let loaded = try repository.loadSettings()
    #expect(loaded.defaultConnectionID == "second")
    #expect(runtime.aiConnectionsModel.showsWelcome == false)
}

@MainActor
@Test func setupLLMConnectionPublishesNewConnectionAndCapabilitySummary() async throws {
    let store = WelcomeStateFakeSettingsStore()
    let credentials = WelcomeStateFakeCredentialStore()
    let repository = AppLLMSettingsRepository(settingsStore: store, credentialStore: credentials)
    let service = AppLLMConnectionSetupService(
        settingsRepository: repository,
        capabilityDiscoveryService: AppProviderCapabilityDiscoveryService(
            settingsRepository: repository,
            evidenceRepository: AppProviderCapabilityEvidenceRepository(settingsStore: store, credentialStore: credentials),
            openAICompatibleProbe: { _ in LLMProviderHealthCheckResult(ok: true, model: "model-a", message: "OK") },
            openAIResponsesProbe: { _ in throw OpenAICompatibleProviderError.httpStatus(404, message: "not found") },
            functionCallingProbe: { _ in AgentModelResponse(text: "OK") }
        ),
        openAICompatibleHealthCheck: { _ in LLMProviderHealthCheckResult(ok: true, model: "model-a", message: "OK") }
    )
    let runtime = try makeRuntime(settingsStore: store, credentialStore: credentials, llmConnectionSetupServiceFactory: { _ in service })

    let result = try await runtime.aiConnectionsModel.setupConnection(AppLLMConnectionSetupInput(
        id: "new-connection",
        kind: .openAICompatible,
        name: "New",
        baseURLString: "https://example.com/v1",
        model: "model-a",
        apiKey: "secret"
    ))

    #expect(runtime.aiConnectionsModel.lastAddedConnectionID == result.id)
    #expect(runtime.aiConnectionsModel.lastAddedCapabilityEvidence.count == 3)
    #expect(runtime.aiConnectionsModel.settingsMessage?.contains("已发现") == true)
}

@MainActor
@Test func setupLLMConnectionUsesServicePersistenceAsSingleSourceOfTruth() async throws {
    let settingsStore = WelcomeStateFakeSettingsStore()
    let credentialStore = WelcomeStateFakeCredentialStore()
    let repository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: credentialStore)
    let service = AppLLMConnectionSetupService(
        settingsRepository: repository,
        openAICompatibleHealthCheck: { config in
            LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK")
        }
    )
    let input = AppLLMConnectionSetupInput(
        id: "provider-setup",
        kind: .openAICompatible,
        name: "Provider Setup",
        baseURLString: "https://api.example.com/v1",
        model: "gpt-4o-mini",
        selectedModel: "gpt-4o-mini",
        apiKey: "real-key"
    )

    _ = try await service.setupConnection(input)

    let runtime = try makeRuntime(settingsStore: settingsStore, credentialStore: credentialStore)
    runtime.aiConnectionsModel.loadSettings()
    runtime.aiConnectionsModel.updateWelcomeState()

    let loaded = try repository.loadSettings()
    #expect(loaded.defaultConnectionID == "provider-setup")
    #expect(loaded.defaultConnection?.id == "provider-setup")
    #expect(runtime.aiConnectionsModel.showsWelcome == false)
}

@MainActor
@Test func successfulLLMSetupDirectlyHidesWelcome() throws {
    let settingsStore = WelcomeStateFakeSettingsStore()
    let credentialStore = WelcomeStateFakeCredentialStore()
    let repository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: credentialStore)

    let runtime = try makeRuntime(settingsStore: settingsStore, credentialStore: credentialStore)
    #expect(runtime.aiConnectionsModel.showsWelcome == true)

    let connection = AppLLMConnectionConfig(
        id: "usable",
        name: "Usable",
        providerMode: .openAICompatible,
        baseURLString: "https://example.com/v1",
        model: "gpt-4o-mini",
        selectedModel: "gpt-4o-mini",
        hasAPIKey: true
    )
    try repository.save(settings: AppLLMSettings(connections: [connection], defaultConnectionID: connection.id), apiKey: "real-key")

    runtime.aiConnectionsModel.handleSuccessfulSetup()

    #expect(runtime.aiConnectionsModel.showsWelcome == false)
}

@MainActor
@Test func setupAnthropicCompatibleConnectionRebindsActiveSessionOverrideToNewConnection() async throws {
    let settingsStore = WelcomeStateFakeSettingsStore()
    let credentialStore = WelcomeStateFakeCredentialStore()
    let repository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: credentialStore)

    let legacyConnection = AppLLMConnectionConfig(
        id: "legacy-openai",
        name: "Legacy OpenAI",
        providerMode: .openAICompatible,
        baseURLString: "https://legacy.example.com/v1",
        model: "gpt-4o-mini",
        selectedModel: "gpt-4o-mini",
        hasAPIKey: true
    )
    try repository.save(settings: AppLLMSettings(connections: [legacyConnection], defaultConnectionID: legacyConnection.id), apiKey: "legacy-secret")

    let runtime = try makeRuntime(
        settingsStore: settingsStore,
        credentialStore: credentialStore,
        llmConnectionSetupServiceFactory: { repo in
            AppLLMConnectionSetupService(
                settingsRepository: repo,
                anthropicCompatibleHealthCheck: { config in
                    LLMProviderHealthCheckResult(ok: true, model: config.model, message: "OK")
                }
            )
        }
    )
    runtime.aiConnectionsRuntimeCoordinator.selectModel("gpt-4o-mini", providerMode: .openAICompatible, connectionID: "legacy-openai")
    #expect(runtime.aiConnectionsRuntimeCoordinator.sessionHasOverride == true)

    let activeSessionID = try #require(runtime.chatFeatureModel.sessions.selectedSessionID)
    let before = try #require(runtime.chatWorkspaceCoordinator.stateSnapshotsBySessionID[activeSessionID]?.llmOverride)
    #expect(before.connectionID == "legacy-openai")

    _ = try await runtime.aiConnectionsModel.setupConnection(AppLLMConnectionSetupInput(
        id: "anthropic-compatible-new",
        kind: .anthropicCompatible,
        name: "Anthropic Compatible",
        baseURLString: "https://anthropic.example.com/v1",
        model: "claude-sonnet-4-5",
        selectedModel: "claude-sonnet-4-5",
        apiKey: "anthropic-secret"
    ))

    let override = try #require(runtime.chatWorkspaceCoordinator.stateSnapshotsBySessionID[activeSessionID]?.llmOverride)
    #expect(override.connectionID == "anthropic-compatible-new")
    #expect(override.providerMode == AppLLMProviderMode.anthropicMessages.rawValue)
    #expect(override.model == "claude-sonnet-4-5")
}
