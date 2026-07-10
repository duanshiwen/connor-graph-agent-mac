import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

@Test func appGraphBootstrapperCreatesEmptyGraphStoreByDefault() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConnorEmptyBootstrapGraph-", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let paths = AppStoragePaths(applicationSupportDirectory: root)
    let store = try AppGraphBootstrapper(paths: paths).bootstrapStore()

    #expect(try store.entities(graphID: "default").isEmpty)
    #expect(try store.statements(graphID: "default").isEmpty)
    #expect(try store.ontologyClasses(graphID: "default").isEmpty)
}

@Test func appGraphAgentRuntimeFactoryCreatesEmptyMemoryOSStoreByDefault() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConnorEmptyBootstrapMemoryOS-", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let paths = AppStoragePaths(applicationSupportDirectory: root)
    try paths.ensureDirectoryHierarchy()

    let graphStore = try SQLiteGraphKernelStore(path: paths.databaseURL.path)
    try graphStore.migrate()
    let settings = AppLLMSettingsRepository(
        settingsStore: EmptyBootstrapSettingsStore(),
        credentialStore: EmptyBootstrapCredentialStore()
    )
    let factory = AppGraphAgentRuntimeFactory(store: graphStore, settingsRepository: settings, storagePaths: paths)

    _ = factory.makeNativeSessionManager(permissionMode: AgentPermissionMode.readOnly)
    #expect(FileManager.default.fileExists(atPath: paths.memoryOSDatabaseURL.path))

    let memoryStore = try SQLiteMemoryOSStore(path: paths.memoryOSDatabaseURL.path)
    let builtin = try memoryStore.builtinDataset(id: FoundationKGMemoryOSMapper.builtinDatasetID)
    let l4Entities = try memoryStore.query(sql: "SELECT COUNT(*) FROM memory_l4_entities;").first?.first.flatMap(Int.init) ?? -1

    #expect(builtin == nil)
    #expect(l4Entities == 0)
}

private final class EmptyBootstrapSettingsStore: LLMSettingsStore, @unchecked Sendable {
    private var values: [String: String] = [:]

    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
}

private final class EmptyBootstrapCredentialStore: CredentialStore, @unchecked Sendable {
    private var secrets: [String: String] = [:]

    func saveSecret(_ secret: String, service: String, account: String) throws { secrets[service + ":" + account] = secret }
    func readSecret(service: String, account: String) throws -> String? { secrets[service + ":" + account] }
    func deleteSecret(service: String, account: String) throws { secrets.removeValue(forKey: service + ":" + account) }
}

