import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

// MARK: - Test Helpers

private final class SessionLLMOverrideCredentialStore: CredentialStore, @unchecked Sendable {
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

private final class SessionLLMOverrideSettingsStore: LLMSettingsStore, @unchecked Sendable {
    var values: [String: String] = [:]

    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
}

private func temporarySessionLLMOverrideDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("SessionLLMOverride-\(UUID().uuidString).sqlite")
}

private func makeSessionLLMOverrideStore() throws -> (SQLiteGraphKernelStore, URL) {
    let url = temporarySessionLLMOverrideDatabaseURL()
    let store = try SQLiteGraphKernelStore(path: url.path)
    try store.migrate()
    return (store, url)
}

// MARK: - SessionLLMOverride Codable Tests

@Test func sessionLLMOverrideEncodesAndDecodesRoundTrip() throws {
    let override = SessionLLMOverride(
        providerMode: "openai_compatible",
        model: "gpt-4o",
        baseURLString: "https://api.openai.com/v1",
        connectionID: "openai-us"
    )
    let data = try JSONEncoder().encode(override)
    let decoded = try JSONDecoder().decode(SessionLLMOverride.self, from: data)
    #expect(decoded.providerMode == "openai_compatible")
    #expect(decoded.model == "gpt-4o")
    #expect(decoded.baseURLString == "https://api.openai.com/v1")
    #expect(decoded.connectionID == "openai-us")
}

@Test func sessionLLMOverrideDecodesWithNilBaseURL() throws {
    let json = """
    {"providerMode":"openai_compatible","model":"claude-sonnet-4-20250514"}
    """
    let decoded = try JSONDecoder().decode(SessionLLMOverride.self, from: json.data(using: .utf8)!)
    #expect(decoded.providerMode == "openai_compatible")
    #expect(decoded.model == "claude-sonnet-4-20250514")
    #expect(decoded.baseURLString == nil)
    #expect(decoded.connectionID == nil)
}

// MARK: - AppSessionStateSnapshot with llmOverride

@Test func sessionStateSnapshotWithLLMOverrideEncodesAndDecodes() throws {
    let override = SessionLLMOverride(providerMode: "openai_compatible", model: "gpt-4o")
    let snapshot = AppSessionStateSnapshot(
        sessionID: "test-session",
        llmOverride: override
    )
    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(AppSessionStateSnapshot.self, from: data)
    #expect(decoded.llmOverride?.providerMode == "openai_compatible")
    #expect(decoded.llmOverride?.model == "gpt-4o")
}

@Test func sessionStateSnapshotWithNilLLMOverrideDecodes() throws {
    let snapshot = AppSessionStateSnapshot(sessionID: "test-session")
    #expect(snapshot.llmOverride == nil)

    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(AppSessionStateSnapshot.self, from: data)
    #expect(decoded.llmOverride == nil)
}

@Test func sessionStateSnapshotBackwardCompatibleWithoutLLMOverrideField() throws {
    // Simulates an old session-state.json without llmOverride key
    // Date is encoded as Double (seconds since 1970) by default JSONEncoder
    let json = """
    {"schemaVersion":1,"sessionID":"old-session","updatedAt":740140800}
    """
    let decoded = try JSONDecoder().decode(AppSessionStateSnapshot.self, from: json.data(using: .utf8)!)
    #expect(decoded.sessionID == "old-session")
    #expect(decoded.llmOverride == nil)
}

// MARK: - Factory uses session override

@Test func factoryAgentModelProviderUsesSessionOverrideModel() throws {
    let (store, dbURL) = try makeSessionLLMOverrideStore()
    defer { try? FileManager.default.removeItem(at: dbURL) }

    let settingsStore = SessionLLMOverrideSettingsStore()
    settingsStore.values["llm.providerMode"] = "openai_compatible"
    settingsStore.values["llm.baseURLString"] = "https://api.openai.com/v1"
    settingsStore.values["llm.model"] = "gpt-4o-mini"
    settingsStore.values["llm.selectedModel"] = "gpt-4o-mini"

    let credentialStore = SessionLLMOverrideCredentialStore()
    credentialStore.secrets["\(AppLLMSettingsRepository.keychainService):\(AppLLMSettingsRepository.apiKeyAccount)"] = "test-api-key"

    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: settingsStore,
        credentialStore: credentialStore
    )

    let factory = AppGraphAgentRuntimeFactory(
        store: store,
        settingsRepository: settingsRepository
    )

    // Without override — uses global model
    let globalProvider = factory.makeAgentModelProvider()
    #expect(globalProvider.modelID == "gpt-4o-mini")

    // With session override — uses override model
    let override = SessionLLMOverride(providerMode: "openai_compatible", model: "claude-sonnet-4-20250514")
    let overriddenProvider = factory.makeAgentModelProvider(sessionLLMOverride: override)
    #expect(overriddenProvider.modelID == "claude-sonnet-4-20250514")
}

@Test func factoryAgentModelProviderFallsBackToGlobalWhenOverrideNil() throws {
    let (store, dbURL) = try makeSessionLLMOverrideStore()
    defer { try? FileManager.default.removeItem(at: dbURL) }

    let settingsStore = SessionLLMOverrideSettingsStore()
    settingsStore.values["llm.providerMode"] = "openai_compatible"
    settingsStore.values["llm.baseURLString"] = "https://api.openai.com/v1"
    settingsStore.values["llm.model"] = "gpt-4o"
    settingsStore.values["llm.selectedModel"] = "gpt-4o"

    let credentialStore = SessionLLMOverrideCredentialStore()
    credentialStore.secrets["\(AppLLMSettingsRepository.keychainService):\(AppLLMSettingsRepository.apiKeyAccount)"] = "test-api-key"

    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: settingsStore,
        credentialStore: credentialStore
    )

    let factory = AppGraphAgentRuntimeFactory(
        store: store,
        settingsRepository: settingsRepository
    )

    let provider = factory.makeAgentModelProvider(sessionLLMOverride: nil)
    #expect(provider.modelID == "gpt-4o")
}

@Test func factoryNativeSessionManagerReceivesSessionLLMOverride() throws {
    let (store, dbURL) = try makeSessionLLMOverrideStore()
    defer { try? FileManager.default.removeItem(at: dbURL) }

    let settingsStore = SessionLLMOverrideSettingsStore()
    settingsStore.values["llm.providerMode"] = "openai_compatible"
    settingsStore.values["llm.baseURLString"] = "https://api.openai.com/v1"
    settingsStore.values["llm.model"] = "gpt-4o-mini"
    settingsStore.values["llm.selectedModel"] = "gpt-4o-mini"

    let credentialStore = SessionLLMOverrideCredentialStore()
    credentialStore.secrets["\(AppLLMSettingsRepository.keychainService):\(AppLLMSettingsRepository.apiKeyAccount)"] = "test-api-key"

    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: settingsStore,
        credentialStore: credentialStore
    )

    let factory = AppGraphAgentRuntimeFactory(
        store: store,
        settingsRepository: settingsRepository
    )

    let override = SessionLLMOverride(providerMode: "openai_compatible", model: "gpt-4o")
    let manager = factory.makeNativeSessionManager(
        session: AgentSession(id: "test-session"),
        sessionLLMOverride: override
    )
    // Manager is created successfully with session override
    #expect(manager.session.id == "test-session")
}
