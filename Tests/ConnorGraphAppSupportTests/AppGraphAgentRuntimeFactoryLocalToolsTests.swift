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

@Test func agentLoopRuntimeFactoryRegistersSessionStatusTools() throws {
    let storeURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-factory-session-status-tools-")
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

    #expect(names.contains("session_get_status"))
    #expect(names.contains("session_set_status"))
}

@Test func agentLoopRuntimeFactoryRegistersCurrentTimeTool() throws {
    let storeURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-factory-current-time-tool-")
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

    #expect(names.contains("get_current_time"))
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

@Test func agentLoopRuntimeFactoryAllowsHiddenConnorDataDirectoryWithoutShowingItAsWorkspaceRoot() async throws {
    let tempBase = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConnorFactoryHiddenDataWorkspace-", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempBase) }

    let appDirectory = tempBase.appendingPathComponent("ConnorData", isDirectory: true)
    let projectDirectory = tempBase.appendingPathComponent("VisibleProject", isDirectory: true)
    let storagePaths = AppStoragePaths(applicationSupportDirectory: appDirectory)
    try storagePaths.ensureDirectoryHierarchy()
    try FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)

    let skillFile = storagePaths.skillsDirectory.appendingPathComponent("assistant-skill.md")
    try "Hidden Connor skill content".write(to: skillFile, atomically: true, encoding: .utf8)

    var runtimeSettings = AgentRuntimeSettings.default
    runtimeSettings.workspace.roots = [
        AgentRuntimeWorkspaceRoot(id: "project", displayName: "Visible Project", path: projectDirectory.path, role: "project", isPrimary: true)
    ]
    runtimeSettings.workspace.syncLegacyFieldsFromRoots()
    try AppRuntimeSettingsRepository(configDirectory: storagePaths.configDirectory).save(runtimeSettings)

    let storeURL = tempBase.appendingPathComponent("store.sqlite")
    let store = try SQLiteGraphKernelStore(path: storeURL.path)
    try store.migrate()
    let settings = AppLLMSettingsRepository(
        settingsStore: LocalToolsSettingsStore(),
        credentialStore: LocalToolsCredentialStore()
    )
    let factory = AppGraphAgentRuntimeFactory(store: store, settingsRepository: settings, storagePaths: storagePaths)
    let controller = factory.makeAgentLoopController(permissionMode: .readOnly)

    let readResult = try await controller.toolRegistry.execute(
        AgentToolCall(name: "Read", argumentsJSON: #"{"file_path":"\#(skillFile.path)"}"#),
        context: AgentToolExecutionContext(
            runID: "run-hidden-data-read",
            sessionID: "session-hidden-data-read",
            groupID: "default",
            userPrompt: "read hidden Connor data",
            toolCallID: "read-hidden-data",
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )
    )

    let listResult = try await controller.toolRegistry.execute(
        AgentToolCall(name: "LS", argumentsJSON: #"{"path":"."}"#),
        context: AgentToolExecutionContext(
            runID: "run-hidden-data-ls",
            sessionID: "session-hidden-data-ls",
            groupID: "default",
            userPrompt: "list visible workspace",
            toolCallID: "ls-visible-workspace",
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )
    )

    #expect(readResult.contentText.contains("Hidden Connor skill content"))
    #expect(readResult.contentJSON?.contains("ConnorData") == true)
    #expect(listResult.contentJSON?.contains("VisibleProject") == true)
    #expect(listResult.contentJSON?.contains("ConnorData") != true)
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

@Test func agentLoopRuntimeFactoryRegistersMemoryOSToolsInsteadOfLegacyGraphWriteTools() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("connor-factory-memory-os-tools-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storagePaths = AppStoragePaths.resolving(applicationSupportBaseDirectory: root)
    try storagePaths.ensureDirectoryHierarchy(fileManager: .default)
    let store = try SQLiteGraphKernelStore(path: storagePaths.databaseURL.path)
    try store.migrate()
    let settings = AppLLMSettingsRepository(
        settingsStore: LocalToolsSettingsStore(),
        credentialStore: LocalToolsCredentialStore()
    )
    let factory = AppGraphAgentRuntimeFactory(store: store, settingsRepository: settings, storagePaths: storagePaths)

    let controller = factory.makeAgentLoopController(permissionMode: .readOnly)
    let names = controller.toolRegistry.definitions.map(\.name)

    #expect(!names.contains("memory_os_dashboard_summary"))
    #expect(names.contains("memory_os_ingest_observation"))
    #expect(names.contains("memory_os_project_structured_artifact"))
    #expect(names.contains("memory_os_search"))
    #expect(names.contains("memory_os_expand_l4"))
    #expect(names.contains("memory_os_read_record"))
    #expect(names.contains("memory_os_read_provenance"))
    #expect(!names.contains("graph_ingest_episode"))
    #expect(!names.contains("graph_propose_write"))
}
