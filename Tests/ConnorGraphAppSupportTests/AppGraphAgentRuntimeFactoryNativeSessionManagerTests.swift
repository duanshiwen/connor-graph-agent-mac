import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

private final class FactoryNativeSessionCredentialStore: CredentialStore, @unchecked Sendable {
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

private final class FactoryNativeSessionSettingsStore: LLMSettingsStore, @unchecked Sendable {
    var values: [String: String] = [:]

    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
}

private func temporaryFactoryNativeSessionDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func appGraphAgentRuntimeFactoryCreatesNativeSessionManagerBackedByRepository() async throws {
    let store = try SQLiteGraphKernelStore(path: temporaryFactoryNativeSessionDatabaseURL().path)
    try store.migrate()
    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: FactoryNativeSessionSettingsStore(),
        credentialStore: FactoryNativeSessionCredentialStore()
    )
    try settingsRepository.save(
        settings: AppLLMSettings(
            baseURLString: AppLLMSettings.default.baseURLString,
            model: AppLLMSettings.default.model,
            hasAPIKey: false,
            providerMode: .stub
        ),
        apiKey: nil
    )
    let factory = AppGraphAgentRuntimeFactory(store: store, settingsRepository: settingsRepository)
    let session = AgentSession(id: "factory-native-session", title: "New Chat")
    var manager = factory.makeNativeSessionManager(session: session)

    let response = try await manager.submit("Use the native session manager path")
    let loaded = try #require(try AppChatSessionRepository(store: store).loadSession(id: "factory-native-session"))

    #expect(response.session.id == "factory-native-session")
    #expect(loaded.messages.map(\.role) == [.user, .assistant])
    #expect(loaded.messages.first?.content == "Use the native session manager path")
    #expect(loaded.messages.last?.content.isEmpty == false)
}
