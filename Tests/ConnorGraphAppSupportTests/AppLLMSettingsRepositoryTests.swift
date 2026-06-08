import Foundation
import Testing
import ConnorGraphAppSupport

private final class FakeCredentialStore: CredentialStore, @unchecked Sendable {
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

private final class FakeSettingsStore: LLMSettingsStore, @unchecked Sendable {
    var values: [String: String] = [:]

    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
}

@Test func settingsRepositoryPersistsNonSecretSettings() throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    let settings = AppLLMSettings(
        baseURLString: "https://example.com/v1",
        model: "custom-model",
        hasAPIKey: false,
        providerMode: .openAICompatible
    )

    try repository.save(settings: settings, apiKey: nil)
    let loaded = try repository.loadSettings()

    #expect(loaded.baseURLString == "https://example.com/v1")
    #expect(loaded.model == "custom-model")
    #expect(loaded.providerMode == .openAICompatible)
}

@Test func settingsRepositoryStoresAPIKeyOnlyInCredentialStore() throws {
    let settingsStore = FakeSettingsStore()
    let credentialStore = FakeCredentialStore()
    let repository = AppLLMSettingsRepository(settingsStore: settingsStore, credentialStore: credentialStore)

    try repository.save(settings: .default, apiKey: "secret-key")
    let loaded = try repository.loadSettings()

    #expect(loaded.hasAPIKey == true)
    #expect(settingsStore.values.values.contains("secret-key") == false)
    #expect(try credentialStore.readSecret(service: AppLLMSettingsRepository.keychainService, account: AppLLMSettingsRepository.apiKeyAccount) == "secret-key")
}

@Test func settingsRepositoryClearsAPIKey() throws {
    let credentialStore = FakeCredentialStore()
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: credentialStore)
    try repository.save(settings: .default, apiKey: "secret-key")

    try repository.clearAPIKey()
    let loaded = try repository.loadSettings()

    #expect(loaded.hasAPIKey == false)
}

@Test func settingsRepositoryBuildsOpenAICompatibleConfigWhenKeyExists() throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    try repository.save(
        settings: AppLLMSettings(baseURLString: "https://example.com/v1", model: "model-a", hasAPIKey: false, providerMode: .openAICompatible),
        apiKey: "secret-key"
    )

    let config = try #require(try repository.openAICompatibleConfig())

    #expect(config.baseURL.absoluteString == "https://example.com/v1")
    #expect(config.model == "model-a")
    #expect(config.apiKey == "secret-key")
}

@Test func settingsRepositoryReturnsNilConfigWhenKeyMissing() throws {
    let repository = AppLLMSettingsRepository(settingsStore: FakeSettingsStore(), credentialStore: FakeCredentialStore())
    try repository.save(settings: AppLLMSettings.default, apiKey: nil)

    let config = try repository.openAICompatibleConfig()

    #expect(config == nil)
}
