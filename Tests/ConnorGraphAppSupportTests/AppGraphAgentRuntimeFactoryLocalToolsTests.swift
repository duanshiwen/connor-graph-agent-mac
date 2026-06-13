import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

@Test func agentLoopRuntimeFactoryRegistersNativeLocalWorkspaceTools() throws {
    let storeURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-factory-local-tools-")
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("sqlite")
    try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let store = try SQLiteGraphKernelStore(path: storeURL.path)
    try store.migrate()
    let settings = AppLLMSettingsRepository(
        settingsStore: LocalToolsSettingsStore(),
        credentialStore: LocalToolsCredentialStore()
    )
    let factory = AppGraphAgentRuntimeFactory(store: store, settingsRepository: settings)

    let controller = factory.makeAgentLoopController(permissionMode: .readOnly)
    let names = controller.toolRegistry.definitions.map(\.name)

    #expect(names.contains("Read"))
    #expect(names.contains("LS"))
    #expect(names.contains("Glob"))
    #expect(names.contains("Grep"))
    #expect(names.contains("Write"))
    #expect(names.contains("Edit"))
    #expect(names.contains("MultiEdit"))
    #expect(names.contains("Bash"))
}

private final class LocalToolsSettingsStore: LLMSettingsStore, @unchecked Sendable {
    private var values: [String: String] = [:]

    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
}

private final class LocalToolsCredentialStore: CredentialStore, @unchecked Sendable {
    private var secrets: [String: String] = [:]

    func saveSecret(_ secret: String, service: String, account: String) throws { secrets[service + ":" + account] = secret }
    func readSecret(service: String, account: String) throws -> String? { secrets[service + ":" + account] }
    func deleteSecret(service: String, account: String) throws { secrets.removeValue(forKey: service + ":" + account) }
}
