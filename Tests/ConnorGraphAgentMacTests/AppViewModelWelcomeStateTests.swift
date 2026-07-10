import AppKit
import Foundation
import Testing
import ConnorGraphStore
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
private func makeWelcomeStateViewModel(
    settingsStore: WelcomeStateFakeSettingsStore = WelcomeStateFakeSettingsStore(),
    credentialStore: WelcomeStateFakeCredentialStore = WelcomeStateFakeCredentialStore()
) throws -> AppViewModel {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-app-vm-welcome-state-\(UUID().uuidString)", isDirectory: true)
    let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: root)
    try paths.ensureDirectoryHierarchy(fileManager: .default)
    let repository = try AppGraphRepository.bootstrap(paths: paths)
    let llmRepository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: credentialStore)
    return AppViewModel(
        entities: [],
        statements: [],
        observeLogEntries: [],
        repository: repository,
        databasePath: paths.databaseURL.path,
        storagePaths: paths,
        llmSettingsRepository: llmRepository
    )
}

@MainActor
@Test func appViewModelShowsWelcomeWhenNoLLMConnectionExists() throws {
    let viewModel = try makeWelcomeStateViewModel()

    viewModel.loadLLMSettings()
    viewModel.updateWelcomeState()

    #expect(viewModel.showWelcomePlaceholder == true)
}

@MainActor
@Test func appViewModelShowsWelcomeWhenOnlyUnusableConnectionShellExists() throws {
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

    let viewModel = try makeWelcomeStateViewModel(settingsStore: settingsStore, credentialStore: credentialStore)
    viewModel.loadLLMSettings()
    viewModel.updateWelcomeState()

    #expect(viewModel.showWelcomePlaceholder == true)
}

@MainActor
@Test func appViewModelHidesWelcomeWhenUsableDefaultConnectionExists() throws {
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

    let viewModel = try makeWelcomeStateViewModel(settingsStore: settingsStore, credentialStore: credentialStore)
    viewModel.loadLLMSettings()
    viewModel.updateWelcomeState()

    #expect(viewModel.showWelcomePlaceholder == false)
}

@MainActor
@Test func appViewModelHidesWelcomeWhenStoredConnectionHydratesAPIKeyFromCredentialStore() throws {
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

    let viewModel = try makeWelcomeStateViewModel(settingsStore: settingsStore, credentialStore: credentialStore)
    viewModel.loadLLMSettings()
    viewModel.updateWelcomeState()

    #expect(viewModel.llmConnectionConfigs.first?.hasAPIKey == true)
    #expect(viewModel.showWelcomePlaceholder == false)
}

@MainActor
@Test func appViewModelHidesWelcomeImmediatelyAfterFirstUsableConnectionBecomesDefault() throws {
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

    let viewModel = try makeWelcomeStateViewModel(settingsStore: settingsStore, credentialStore: credentialStore)
    viewModel.selectDefaultLLMConnection("first")

    #expect(viewModel.showWelcomePlaceholder == false)
}

@MainActor
@Test func selectingUsableDefaultConnectionPersistsBeforeWelcomeStateRecalculation() throws {
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

    let viewModel = try makeWelcomeStateViewModel(settingsStore: settingsStore, credentialStore: credentialStore)
    viewModel.loadLLMSettings()
    viewModel.selectDefaultLLMConnection("second")

    let loaded = try repository.loadSettings()
    #expect(loaded.defaultConnectionID == "second")
    #expect(viewModel.showWelcomePlaceholder == false)
}
