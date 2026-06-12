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
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConnorFactoryConfiguredSidecar-")
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let sidecarURL = temporaryDirectory.appendingPathComponent("configured-sidecar.sh")
    try """
    #!/bin/sh
    IFS= read -r request
    printf '%s\n' '{"runStarted":{"sdkSessionID":"sdk-configured-session"}}'
    printf '%s\n' '{"textComplete":{"text":"Configured sidecar answer","citations":[],"contextSnapshot":null}}'
    printf '%s\n' '{"runCompleted":{}}'
    """.write(to: sidecarURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sidecarURL.path)

    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: FactoryNativeSessionSettingsStore(),
        credentialStore: FactoryNativeSessionCredentialStore()
    )
    try settingsRepository.save(
        settings: AppLLMSettings(
            baseURLString: AppLLMSettings.default.baseURLString,
            model: AppLLMSettings.default.model,
            hasAPIKey: false,
            providerMode: .governedClaudeSidecar,
            sidecarExecutablePath: "/bin/sh",
            sidecarArguments: sidecarURL.path,
            sidecarWorkingDirectoryPath: temporaryDirectory.path
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
    #expect(loaded.messages.last?.content == "Configured sidecar answer")
}

@Test func appGraphAgentRuntimeFactoryDoesNotUseLegacyDirectProviderForClaudeSidecarMode() async throws {
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
            providerMode: .governedClaudeSidecar
        ),
        apiKey: nil
    )
    let factory = AppGraphAgentRuntimeFactory(store: store, settingsRepository: settingsRepository)

    let provider = factory.makeAgentModelProvider()

    #expect(provider.modelID == "governed-claude-sidecar-requires-session-manager")
    await #expect(throws: AppGraphAgentRuntimeFactoryError.self) {
        _ = try await provider.complete(AgentModelRequest(messages: []))
    }
}

@Test func appGraphAgentRuntimeFactoryPersistsClaudeSidecarToolEvents() async throws {
    let store = try SQLiteGraphKernelStore(path: temporaryFactoryNativeSessionDatabaseURL().path)
    try store.migrate()
    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: FactoryNativeSessionSettingsStore(),
        credentialStore: FactoryNativeSessionCredentialStore()
    )
    let factory = AppGraphAgentRuntimeFactory(store: store, settingsRepository: settingsRepository)
    let session = AgentSession(id: "factory-sidecar-tool-session", title: "Sidecar Tool Chat")
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConnorFactorySidecarToolEvents-")
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let sidecarURL = temporaryDirectory.appendingPathComponent("tool-sidecar.sh")
    try """
    #!/bin/sh
    IFS= read -r request
    printf '%s\n' '{"runStarted":{"sdkSessionID":"sdk-tool-session"}}'
    printf '%s\n' '{"toolUseRequested":{"toolCallID":"tool-1","name":"Read","inputJSON":"{\\"file_path\\":\\"README.md\\"}"}}'
    printf '%s\n' '{"permissionRequested":{"requestID":"permission-tool-1","capability":"readSession","toolName":"Read","payloadJSON":"{\\"file_path\\":\\"README.md\\"}"}}'
    printf '%s\n' '{"toolUseStarted":{"toolCallID":"tool-1","name":"Read"}}'
    printf '%s\n' '{"toolUseCompleted":{"toolCallID":"tool-1","name":"Read","contentText":"README contents","contentJSON":null,"isError":false}}'
    printf '%s\n' '{"textComplete":{"text":"Done","citations":[],"contextSnapshot":null}}'
    printf '%s\n' '{"runCompleted":{}}'
    """.write(to: sidecarURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sidecarURL.path)
    var manager = factory.makeClaudeSDKSidecarNativeSessionManager(
        session: session,
        sidecarExecutableURL: URL(fileURLWithPath: "/bin/sh"),
        sidecarArguments: [sidecarURL.path],
        workingDirectory: temporaryDirectory,
        permissionMode: .readOnly
    )

    let response = try await manager.submit("Use a sidecar tool")
    let runID = try #require(response.events.first?.runID)
    let persisted = try store.events(runID: runID, limit: 20)

    #expect(response.events.map(\.kind) == [.runStarted, .toolRequested, .permissionRequested, .toolStarted, .toolFinished, .textComplete, .runCompleted])
    #expect(response.eventPresentations.map(\.title).contains("Tool requested: Read"))
    #expect(response.eventPresentations.map(\.title).contains("Permission requested: readSession"))
    #expect(manager.eventPresentations.map(\.title).contains("Tool finished: Read"))
    #expect(persisted.map(\.kind) == [.runStarted, .toolRequested, .permissionRequested, .toolStarted, .toolFinished, .textComplete, .runCompleted])
    #expect(persisted.map(\.sequence) == Array(0..<persisted.count))
    #expect(persisted.contains { $0.kind == .permissionRequested && $0.payloadJSON.contains("permission-tool-1") })

    let approvals = try store.pendingApprovals(runID: runID)
    #expect(approvals.count == 1)
    #expect(approvals.first?.requestID == "permission-tool-1")
    #expect(approvals.first?.status == .pending)
    #expect(approvals.first?.capability == .readSession)
    #expect(approvals.first?.toolName == "Read")
    #expect(approvals.first?.payloadJSON.contains("README.md") == true)
}

@Test func appGraphAgentRuntimeFactoryCreatesGovernedPersistentClaudeSidecarNativeSessionManagerWithRuntimeStore() async throws {
    let appDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConnorFactoryGovernedPersistentSidecarRuntimeStore-")
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: appDirectory) }
    let storagePaths = AppStoragePaths(applicationSupportDirectory: appDirectory)
    try storagePaths.ensureDirectoryHierarchy()

    let store = try SQLiteGraphKernelStore(path: temporaryFactoryNativeSessionDatabaseURL().path)
    try store.migrate()
    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: FactoryNativeSessionSettingsStore(),
        credentialStore: FactoryNativeSessionCredentialStore()
    )
    let factory = AppGraphAgentRuntimeFactory(store: store, settingsRepository: settingsRepository, storagePaths: storagePaths)
    let session = AgentSession(id: "factory-governed-runtime-store", title: "Governed Sidecar Chat")
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConnorFactoryGovernedPersistentSidecarRuntimeStoreScript-")
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let sidecarURL = temporaryDirectory.appendingPathComponent("persistent-sidecar.sh")
    try """
    #!/bin/sh
    while IFS= read -r command; do
      case "$command" in
        *'"start"'*)
          printf '%s\n' '{"runStarted":{"sdkSessionID":"sdk-factory-runtime-store"}}'
          printf '%s\n' '{"textComplete":{"text":"ready","citations":[],"contextSnapshot":null}}'
          printf '%s\n' '{"runCompleted":{}}'
          ;;
      esac
    done
    """.write(to: sidecarURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sidecarURL.path)

    var manager = try factory.makeGovernedClaudeSDKSidecarNativeSessionManager(
        session: session,
        sidecarExecutableURL: URL(fileURLWithPath: "/bin/sh"),
        sidecarArguments: [sidecarURL.path],
        workingDirectory: temporaryDirectory,
        permissionMode: .askToWrite
    )

    _ = try await manager.submit("Use governed persistent sidecar with runtime store")
    let runtimeRecord = try AppClaudeSDKSidecarRuntimeStore(configDirectory: storagePaths.configDirectory).load(connorSessionID: session.id)

    #expect(runtimeRecord?.sdkSessionID == "sdk-factory-runtime-store")
    #expect(runtimeRecord?.status == .ready)
}

@Test func appGraphAgentRuntimeFactoryCreatesGovernedPersistentClaudeSidecarNativeSessionManager() async throws {
    let store = try SQLiteGraphKernelStore(path: temporaryFactoryNativeSessionDatabaseURL().path)
    try store.migrate()
    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: FactoryNativeSessionSettingsStore(),
        credentialStore: FactoryNativeSessionCredentialStore()
    )
    let factory = AppGraphAgentRuntimeFactory(store: store, settingsRepository: settingsRepository)
    let session = AgentSession(id: "factory-governed-persistent-sidecar", title: "Governed Sidecar Chat")
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConnorFactoryGovernedPersistentSidecar-")
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let sidecarURL = temporaryDirectory.appendingPathComponent("persistent-sidecar.sh")
    try """
    #!/bin/sh
    while IFS= read -r command; do
      case "$command" in
        *'"start"'*)
          printf '%s\n' '{"runStarted":{"sdkSessionID":"sdk-governed-persistent"}}'
          printf '%s\n' '{"permissionRequested":{"requestID":"permission-tool-1","capability":"commitGraphWrite","toolName":"Write","payloadJSON":"{}"}}'
          printf '%s\n' '{"textComplete":{"text":"Waiting for Connor approval","citations":[],"contextSnapshot":null}}'
          printf '%s\n' '{"runCompleted":{}}'
          ;;
      esac
    done
    """.write(to: sidecarURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sidecarURL.path)

    var manager = try factory.makeGovernedClaudeSDKSidecarNativeSessionManager(
        session: session,
        sidecarExecutableURL: URL(fileURLWithPath: "/bin/sh"),
        sidecarArguments: [sidecarURL.path],
        workingDirectory: temporaryDirectory,
        permissionMode: .askToWrite
    )

    let response = try await manager.submit("Use governed persistent sidecar")
    let runID = try #require(response.events.first?.runID)
    let approvals = try store.pendingApprovals(runID: runID)

    #expect(response.events.map(\.kind) == [.runStarted, .permissionRequested, .textComplete, .runCompleted])
    #expect(approvals.count == 1)
    #expect(approvals.first?.capability == .commitGraphWrite)
    #expect(approvals.first?.status == .pending)
    #expect(manager.permissionMode == .askToWrite)
}

@Test func appGraphAgentRuntimeFactoryRejectsAllowAllForGovernedClaudeSidecar() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryFactoryNativeSessionDatabaseURL().path)
    try store.migrate()
    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: FactoryNativeSessionSettingsStore(),
        credentialStore: FactoryNativeSessionCredentialStore()
    )
    let factory = AppGraphAgentRuntimeFactory(store: store, settingsRepository: settingsRepository)

    do {
        _ = try factory.makeGovernedClaudeSDKSidecarNativeSessionManager(
            sidecarExecutableURL: URL(fileURLWithPath: "/bin/sh"),
            workingDirectory: FileManager.default.temporaryDirectory,
            permissionMode: .allowAll
        )
        Issue.record("Expected governed Claude sidecar path to reject allowAll")
    } catch let error as AppGraphAgentRuntimeFactoryError {
        #expect(error == .unsafeSidecarPermissionMode(.allowAll))
    } catch {
        Issue.record("Expected AppGraphAgentRuntimeFactoryError.unsafeSidecarPermissionMode, got \(error)")
    }
}

@Test func appGraphAgentRuntimeFactoryCreatesClaudeSidecarNativeSessionManager() async throws {
    let store = try SQLiteGraphKernelStore(path: temporaryFactoryNativeSessionDatabaseURL().path)
    try store.migrate()
    let settingsRepository = AppLLMSettingsRepository(
        settingsStore: FactoryNativeSessionSettingsStore(),
        credentialStore: FactoryNativeSessionCredentialStore()
    )
    let factory = AppGraphAgentRuntimeFactory(store: store, settingsRepository: settingsRepository)
    let session = AgentSession(id: "factory-sidecar-session", title: "Sidecar Chat")
    let sidecarURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sidecars/claude-agent-engine/mock-sidecar.sh")
    var manager = factory.makeClaudeSDKSidecarNativeSessionManager(
        session: session,
        sidecarExecutableURL: sidecarURL,
        workingDirectory: sidecarURL.deletingLastPathComponent(),
        permissionMode: .readOnly
    )

    let response = try await manager.submit("Use the Claude SDK sidecar process path")
    let loaded = try #require(try AppChatSessionRepository(store: store).loadSession(id: "factory-sidecar-session"))

    #expect(response.events.map(\.kind).contains(.runStarted))
    #expect(response.events.map(\.kind).contains(.runCompleted))
    #expect(loaded.messages.map(\.role) == [.user, .assistant])
    #expect(loaded.messages.first?.content == "Use the Claude SDK sidecar process path")
    #expect(loaded.messages.last?.content == "Mock Claude shell sidecar received a Connor request")
}
