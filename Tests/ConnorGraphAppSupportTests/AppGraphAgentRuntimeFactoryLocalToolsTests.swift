import Foundation
import Testing
import ConnorGraphAgent
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

@Test func agentLoopRuntimeFactoryRegistersScientificComputingTools() throws {
    let storeURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-factory-science-tools-")
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

    #expect(names.contains("science_compute"))
    #expect(names.contains("science_units"))
    #expect(names.contains("science_stats"))
    #expect(names.contains("science_linalg"))
    #expect(names.contains("science_symbolic"))
    #expect(names.contains("science_optimize"))
    #expect(names.contains("science_table_compute"))
}

@Test func agentLoopRuntimeFactoryNativeReadUsesRuntimeWorkspace() async throws {
    let appDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConnorFactoryLocalToolsRuntimeWorkspace-", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: appDirectory) }
    let storagePaths = AppStoragePaths(applicationSupportDirectory: appDirectory)
    try storagePaths.ensureDirectoryHierarchy()

    let runtimeWorkspace = appDirectory.appendingPathComponent("runtime-project", isDirectory: true)
    try FileManager.default.createDirectory(at: runtimeWorkspace, withIntermediateDirectories: true)
    try "Runtime workspace README".write(to: runtimeWorkspace.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

    var runtimeSettings = AgentRuntimeSettings.default
    runtimeSettings.workspace.defaultWorkingDirectoryPath = runtimeWorkspace.path
    try AppRuntimeSettingsRepository(configDirectory: storagePaths.configDirectory).save(runtimeSettings)

    let storeURL = appDirectory.appendingPathComponent("store.sqlite")
    let store = try SQLiteGraphKernelStore(path: storeURL.path)
    try store.migrate()
    let settings = AppLLMSettingsRepository(
        settingsStore: LocalToolsSettingsStore(),
        credentialStore: LocalToolsCredentialStore()
    )
    let factory = AppGraphAgentRuntimeFactory(store: store, settingsRepository: settings, storagePaths: storagePaths)
    let controller = factory.makeAgentLoopController(permissionMode: .readOnly)
    let result = try await controller.toolRegistry.execute(
        AgentToolCall(name: "Read", argumentsJSON: #"{"file_path":"README.md"}"#),
        context: AgentToolExecutionContext(
            runID: "run-local-runtime-workspace",
            sessionID: "session-local-runtime-workspace",
            groupID: "default",
            userPrompt: "read README",
            toolCallID: "read-runtime-workspace",
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )
    )

    #expect(result.contentText.contains("Runtime workspace README"))
    #expect(result.contentJSON?.contains("runtime-project") == true)
}

@Test func agentLoopRuntimeFactoryNativeReadUsesSessionWorkspaceBeforeRuntimeWorkspace() async throws {
    let appDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConnorFactoryLocalToolsSessionWorkspace-", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: appDirectory) }
    let storagePaths = AppStoragePaths(applicationSupportDirectory: appDirectory)
    try storagePaths.ensureDirectoryHierarchy()

    let runtimeWorkspace = appDirectory.appendingPathComponent("runtime-project", isDirectory: true)
    let sessionWorkspace = appDirectory.appendingPathComponent("session-project", isDirectory: true)
    try FileManager.default.createDirectory(at: runtimeWorkspace, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: sessionWorkspace, withIntermediateDirectories: true)
    try "Runtime workspace README".write(to: runtimeWorkspace.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
    try "Session workspace README".write(to: sessionWorkspace.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

    var runtimeSettings = AgentRuntimeSettings.default
    runtimeSettings.workspace.defaultWorkingDirectoryPath = runtimeWorkspace.path
    try AppRuntimeSettingsRepository(configDirectory: storagePaths.configDirectory).save(runtimeSettings)

    let storeURL = appDirectory.appendingPathComponent("store.sqlite")
    let store = try SQLiteGraphKernelStore(path: storeURL.path)
    try store.migrate()
    let settings = AppLLMSettingsRepository(
        settingsStore: LocalToolsSettingsStore(),
        credentialStore: LocalToolsCredentialStore()
    )
    let factory = AppGraphAgentRuntimeFactory(store: store, settingsRepository: settings, storagePaths: storagePaths)
    let sessionWorkspaceReference = AppSessionWorkspaceReference(
        workingDirectoryPath: sessionWorkspace.path,
        source: "session",
        roots: [
            AppSessionWorkspaceRootReference(id: "session", displayName: "Session", path: sessionWorkspace.path, role: "project", isPrimary: true)
        ]
    )
    let controller = factory.makeAgentLoopController(permissionMode: .readOnly, sessionWorkspace: sessionWorkspaceReference)
    let result = try await controller.toolRegistry.execute(
        AgentToolCall(name: "Read", argumentsJSON: #"{"file_path":"README.md"}"#),
        context: AgentToolExecutionContext(
            runID: "run-local-session-workspace",
            sessionID: "session-local-session-workspace",
            groupID: "default",
            userPrompt: "read README",
            toolCallID: "read-session-workspace",
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )
    )

    #expect(result.contentText.contains("Session workspace README"))
    #expect(!result.contentText.contains("Runtime workspace README"))
    #expect(result.contentJSON?.contains("session-project") == true)
}

@Test func agentLoopRuntimeFactoryNativeReadAllowsAdditionalWorkspaceRoot() async throws {
    let appDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConnorFactoryLocalToolsMultiRootWorkspace-", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: appDirectory) }
    let storagePaths = AppStoragePaths(applicationSupportDirectory: appDirectory)
    try storagePaths.ensureDirectoryHierarchy()

    let primaryWorkspace = appDirectory.appendingPathComponent("primary-project", isDirectory: true)
    let secondaryWorkspace = appDirectory.appendingPathComponent("shared-docs", isDirectory: true)
    try FileManager.default.createDirectory(at: primaryWorkspace, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: secondaryWorkspace, withIntermediateDirectories: true)
    let sharedFile = secondaryWorkspace.appendingPathComponent("shared.md")
    try "Shared workspace root content".write(to: sharedFile, atomically: true, encoding: .utf8)

    var runtimeSettings = AgentRuntimeSettings.default
    runtimeSettings.workspace.roots = [
        AgentRuntimeWorkspaceRoot(id: "primary", displayName: "Primary", path: primaryWorkspace.path, role: "project", isPrimary: true),
        AgentRuntimeWorkspaceRoot(id: "shared", displayName: "Shared", path: secondaryWorkspace.path, role: "docs", isPrimary: false)
    ]
    runtimeSettings.workspace.syncLegacyFieldsFromRoots()
    try AppRuntimeSettingsRepository(configDirectory: storagePaths.configDirectory).save(runtimeSettings)

    let storeURL = appDirectory.appendingPathComponent("store.sqlite")
    let store = try SQLiteGraphKernelStore(path: storeURL.path)
    try store.migrate()
    let settings = AppLLMSettingsRepository(
        settingsStore: LocalToolsSettingsStore(),
        credentialStore: LocalToolsCredentialStore()
    )
    let factory = AppGraphAgentRuntimeFactory(store: store, settingsRepository: settings, storagePaths: storagePaths)
    let controller = factory.makeAgentLoopController(permissionMode: .readOnly)
    let arguments = #"{"file_path":"\#(sharedFile.path)"}"#
    let result = try await controller.toolRegistry.execute(
        AgentToolCall(name: "Read", argumentsJSON: arguments),
        context: AgentToolExecutionContext(
            runID: "run-local-multi-root-workspace",
            sessionID: "session-local-multi-root-workspace",
            groupID: "default",
            userPrompt: "read shared root",
            toolCallID: "read-shared-root",
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )
    )

    #expect(result.contentText.contains("Shared workspace root content"))
    #expect(result.contentJSON?.contains("shared-docs") == true)
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
