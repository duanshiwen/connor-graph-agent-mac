import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore

private final class GeneratedMediaSettingsStore: LLMSettingsStore, @unchecked Sendable {
    var values: [String: String] = [:]
    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
}

private final class GeneratedMediaCredentialStore: CredentialStore, @unchecked Sendable {
    var values: [String: String] = [:]
    func saveSecret(_ secret: String, service: String, account: String) throws { values["\(service):\(account)"] = secret }
    func readSecret(service: String, account: String) throws -> String? { values["\(service):\(account)"] }
    func deleteSecret(service: String, account: String) throws { values.removeValue(forKey: "\(service):\(account)") }
}

@Test func generatedMediaSettingsPersistMetadataAndCredentialSeparately() throws {
    let settingsStore = GeneratedMediaSettingsStore()
    let credentialStore = GeneratedMediaCredentialStore()
    let repository = AppGeneratedMediaSettingsRepository(settingsStore: settingsStore, credentialStore: credentialStore)
    let connection = AppGeneratedMediaConnectionConfig(
        id: "gemini-image",
        name: "Gemini Image",
        providerKind: .geminiImage,
        baseURLString: "https://generativelanguage.googleapis.com/v1beta",
        model: "gemini-3.1-flash-image",
        hasAPIKey: true
    )

    try repository.save(settings: AppGeneratedMediaSettings(connections: [connection], defaultImageConnectionID: connection.id))
    try repository.saveAPIKey("secret-gemini-key", connectionID: connection.id)
    let loaded = try repository.loadSettings()

    #expect(loaded.defaultImageConnection?.providerKind == .geminiImage)
    #expect(loaded.defaultImageConnection?.hasAPIKey == true)
    #expect(settingsStore.values.values.contains { $0.contains("secret-gemini-key") } == false)
    #expect(try repository.apiKey(for: connection.id) == "secret-gemini-key")
    #expect(AppGeneratedMediaConnectionHealthChecker.status(for: try #require(loaded.defaultImageConnection)) == .ready)
}

@Test func generatedMediaSettingsRequireExplicitDefaultAndDoNotFallbackToFirstConnection() throws {
    let connection = AppGeneratedMediaConnectionConfig(
        id: "flux",
        name: "FLUX",
        providerKind: .blackForestLabs,
        baseURLString: "https://api.bfl.ai/v1",
        model: "flux-2-pro",
        hasAPIKey: true
    )
    let settings = AppGeneratedMediaSettings(connections: [connection])

    #expect(settings.defaultImageConnection == nil)
}

@Test func legacySessionLLMOverrideDecodesWithoutGeneratedMediaConnection() throws {
    let data = Data(#"{"providerMode":"anthropic_messages","model":"claude-sonnet","connectionID":"claude"}"#.utf8)

    let decoded = try JSONDecoder().decode(SessionLLMOverride.self, from: data)

    #expect(decoded.generatedMediaConnectionID == nil)
}
