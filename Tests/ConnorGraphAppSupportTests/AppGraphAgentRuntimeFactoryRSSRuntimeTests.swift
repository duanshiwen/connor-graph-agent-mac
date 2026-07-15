import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

private final class FactoryRSSSettingsStore: LLMSettingsStore, @unchecked Sendable {
    private var values: [String: String] = [:]
    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String, forKey key: String) { values[key] = value }
}

private final class FactoryRSSCredentialStore: CredentialStore, @unchecked Sendable {
    private var values: [String: String] = [:]
    func saveSecret(_ secret: String, service: String, account: String) throws { values["\(service):\(account)"] = secret }
    func readSecret(service: String, account: String) throws -> String? { values["\(service):\(account)"] }
    func deleteSecret(service: String, account: String) throws { values["\(service):\(account)"] = nil }
}

@Test func agentRuntimeFactoryUsesInjectedRSSRuntimeAsSingleStoreOwner() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-factory-rss-runtime-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let storagePaths = AppStoragePaths(applicationSupportDirectory: root)
    try storagePaths.ensureDirectoryHierarchy()
    let store = try SQLiteGraphKernelStore(path: root.appendingPathComponent("graph.sqlite").path)
    try store.migrate()
    let settings = AppLLMSettingsRepository(
        settingsStore: FactoryRSSSettingsStore(),
        credentialStore: FactoryRSSCredentialStore()
    )
    let repository = InMemoryRSSSourceRepository()
    let cache = InMemoryRSSSourceCache()
    let runtime = RSSRuntime(repository: repository, cache: cache)
    let factory = AppGraphAgentRuntimeFactory(
        store: store,
        settingsRepository: settings,
        storagePaths: storagePaths,
        rssRuntime: runtime
    )
    let controller = factory.makeAgentLoopController(permissionMode: .allowAll)

    #expect(controller.toolRegistry.definitions.contains { $0.name == "rss_add_source" })
    _ = try await controller.toolRegistry.execute(
        AgentToolCall(
            name: "rss_add_source",
            argumentsJSON: #"{"feedURL":"https://example.com/feed.xml","displayName":"Shared Fixture"}"#
        ),
        context: AgentToolExecutionContext(
            runID: "rss-runtime-run",
            sessionID: "rss-runtime-session",
            groupID: "default",
            userPrompt: "add source",
            toolCallID: "rss-add-source",
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )
    )

    let sources = try await repository.listSources()
    #expect(sources.count == 1)
    #expect(sources.first?.displayName == "Shared Fixture")
}
