import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore

public enum AppGraphAgentRuntimeFactoryError: Error, Sendable, Equatable, LocalizedError {
    case unsafeSidecarPermissionMode(AgentPermissionMode)
    case missingSidecarExecutablePath

    public var errorDescription: String? {
        switch self {
        case .unsafeSidecarPermissionMode(let mode):
            return "Governed Claude SDK sidecar path does not allow unsafe permission mode: \(mode.rawValue)."
        case .missingSidecarExecutablePath:
            return "Governed Claude SDK sidecar path requires a sidecar executable path."
        }
    }
}

public struct AppGraphAgentRuntimeFactory: @unchecked Sendable {
    public var store: SQLiteGraphKernelStore
    public var settingsRepository: AppLLMSettingsRepository
    public var groupID: String

    public init(
        store: SQLiteGraphKernelStore,
        settingsRepository: AppLLMSettingsRepository,
        groupID: String = "default"
    ) {
        self.store = store
        self.settingsRepository = settingsRepository
        self.groupID = groupID
    }

    /// Legacy simple ask runtime retained for compatibility and tests.
    /// Product chat should use `makeAgentLoopChatController` so tool calling,
    /// permissions, audit/events, memory staging, and graph retrieval evolve on one path.
    @available(*, deprecated, message: "Use makeAgentLoopChatController for the main app chat runtime.")
    public func makeChatController(
        session: AgentSession = AgentSession(id: "app-session")
    ) -> AgentChatController<AnyLLMProvider> {
        let provider = makeLLMProvider()
        let searchService = SQLiteGraphHybridSearchService(store: store)
        return AgentChatController(
            agent: GraphAgent(
                session: session,
                contextBuilder: AgentContextBuilder(hybridSearchService: searchService, groupID: groupID),
                llmProvider: provider
            )
        )
    }

    public func makeAgentLoopChatController(
        session: AgentSession = AgentSession(id: "app-session"),
        permissionMode: AgentPermissionMode = .askToWrite,
        configuration: AgentLoopConfiguration = AgentLoopConfiguration()
    ) -> AgentLoopChatController<AnyAgentModelProvider> {
        AgentLoopChatController(
            loopController: makeAgentLoopController(permissionMode: permissionMode, configuration: configuration),
            session: session,
            groupID: groupID,
            memoryStagingRepository: AppMemoryStagingBufferRepository(store: store)
        )
    }

    public func makeNativeSessionManager(
        session: AgentSession = AgentSession(id: "app-session"),
        permissionMode: AgentPermissionMode = .askToWrite,
        configuration: AgentLoopConfiguration = AgentLoopConfiguration()
    ) -> NativeSessionManager {
        if let sidecarManager = try? makeConfiguredGovernedClaudeSDKSidecarNativeSessionManager(session: session) {
            return sidecarManager
        }
        return NativeSessionManager(
            backend: AgentLoopBackend(loopController: makeAgentLoopController(permissionMode: permissionMode, configuration: configuration)),
            sessionRepository: AppChatSessionRepository(store: store),
            session: session,
            groupID: groupID,
            permissionMode: permissionMode,
            memoryStagingRepository: AppMemoryStagingBufferRepository(store: store)
        )
    }

    public func makeConfiguredGovernedClaudeSDKSidecarNativeSessionManager(
        session: AgentSession = AgentSession(id: "app-session")
    ) throws -> NativeSessionManager? {
        let settings = try settingsRepository.loadSettings()
        guard settings.providerMode == .governedClaudeSidecar else { return nil }
        let executablePath = settings.sidecarExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !executablePath.isEmpty else { throw AppGraphAgentRuntimeFactoryError.missingSidecarExecutablePath }
        return try makeGovernedClaudeSDKSidecarNativeSessionManager(
            session: session,
            sidecarExecutableURL: URL(fileURLWithPath: executablePath),
            sidecarArguments: Self.splitSidecarArguments(settings.sidecarArguments),
            workingDirectory: Self.sidecarWorkingDirectory(from: settings),
            permissionMode: settings.sidecarPermissionMode
        )
    }

    public func makeConfiguredGovernedClaudeSDKSidecarRuntime() throws -> GovernedClaudeSDKSidecarRuntime<ClaudeSDKSidecarPersistentProcessTransport>? {
        let settings = try settingsRepository.loadSettings()
        guard settings.providerMode == .governedClaudeSidecar else { return nil }
        let executablePath = settings.sidecarExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !executablePath.isEmpty else { throw AppGraphAgentRuntimeFactoryError.missingSidecarExecutablePath }
        guard settings.sidecarPermissionMode != .allowAll else {
            throw AppGraphAgentRuntimeFactoryError.unsafeSidecarPermissionMode(settings.sidecarPermissionMode)
        }
        let workingDirectory = Self.sidecarWorkingDirectory(from: settings)
        let transport = ClaudeSDKSidecarPersistentProcessTransport(
            executableURL: URL(fileURLWithPath: executablePath),
            arguments: Self.splitSidecarArguments(settings.sidecarArguments),
            currentDirectoryURL: workingDirectory
        )
        return try GovernedClaudeSDKSidecarRuntime(
            transport: transport,
            workingDirectory: workingDirectory,
            permissionMode: settings.sidecarPermissionMode
        )
    }

    public func makeClaudeSDKSidecarNativeSessionManager(
        session: AgentSession = AgentSession(id: "app-session"),
        sidecarExecutableURL: URL,
        sidecarArguments: [String] = [],
        sidecarEnvironment: [String: String] = [:],
        workingDirectory: URL,
        permissionMode: AgentPermissionMode = .askToWrite
    ) -> NativeSessionManager {
        let transport = ClaudeSDKSidecarProcessTransport(
            executableURL: sidecarExecutableURL,
            arguments: sidecarArguments,
            environment: sidecarEnvironment,
            currentDirectoryURL: workingDirectory
        )
        return makeClaudeSDKSidecarNativeSessionManager(
            backend: ClaudeSDKSidecarBackend(transport: transport, workingDirectory: workingDirectory),
            session: session,
            permissionMode: permissionMode
        )
    }

    public func makeGovernedClaudeSDKSidecarNativeSessionManager(
        session: AgentSession = AgentSession(id: "app-session"),
        sidecarExecutableURL: URL,
        sidecarArguments: [String] = [],
        sidecarEnvironment: [String: String] = [:],
        workingDirectory: URL,
        permissionMode: AgentPermissionMode = .askToWrite
    ) throws -> NativeSessionManager {
        guard permissionMode != .allowAll else {
            throw AppGraphAgentRuntimeFactoryError.unsafeSidecarPermissionMode(permissionMode)
        }
        let transport = ClaudeSDKSidecarPersistentProcessTransport(
            executableURL: sidecarExecutableURL,
            arguments: sidecarArguments,
            environment: sidecarEnvironment,
            currentDirectoryURL: workingDirectory
        )
        let runtime = try GovernedClaudeSDKSidecarRuntime(
            transport: transport,
            workingDirectory: workingDirectory,
            permissionMode: permissionMode
        )
        return makeClaudeSDKSidecarNativeSessionManager(
            backend: runtime,
            session: session,
            permissionMode: permissionMode
        )
    }

    private func makeClaudeSDKSidecarNativeSessionManager<Backend: AgentBackend>(
        backend: Backend,
        session: AgentSession,
        permissionMode: AgentPermissionMode
    ) -> NativeSessionManager {
        NativeSessionManager(
            backend: backend,
            sessionRepository: AppChatSessionRepository(store: store),
            session: session,
            groupID: groupID,
            permissionMode: permissionMode,
            memoryStagingRepository: AppMemoryStagingBufferRepository(store: store),
            eventRecorder: AgentEventRecorder(repository: store),
            pendingApprovalRepository: store
        )
    }

    public func makeAgentLoopController(
        permissionMode: AgentPermissionMode = .askToWrite,
        configuration: AgentLoopConfiguration = AgentLoopConfiguration()
    ) -> AgentLoopController<AnyAgentModelProvider> {
        let searchService = SQLiteGraphHybridSearchService(store: store)
        var registry = AgentToolRegistry()
        registry.register(GraphSearchTool(searchService: searchService))
        registry.register(GraphIngestEpisodeTool(repository: store))
        registry.register(GraphProposeWriteTool(repository: store))
        registry.register(BrowserFetchTool())
        registry.register(SearchEngineMCPTool())
        registry.register(SearchEngineMCPWebFetchTool())
        var effectiveConfiguration = configuration
        effectiveConfiguration.permissionMode = permissionMode
        return AgentLoopController(
            modelProvider: makeAgentModelProvider(),
            toolRegistry: registry,
            configuration: effectiveConfiguration,
            auditLog: SQLiteAgentAuditLog(store: store),
            eventRecorder: AgentEventRecorder(repository: store),
            contextBuilder: AgentContextBuilder(hybridSearchService: searchService, groupID: groupID)
        )
    }

    public func makeAgentModelProvider() -> AnyAgentModelProvider {
        do {
            let settings = try settingsRepository.loadSettings()
            switch settings.providerMode {
            case .stub, .governedClaudeSidecar:
                return AnyAgentModelProvider(StubAgentModelProvider())
            case .openAICompatible:
                guard let config = try settingsRepository.openAICompatibleConfig() else {
                    return AnyAgentModelProvider(modelID: "missing-openai-compatible-config") { _ in
                        throw OpenAICompatibleProviderError.missingAPIKey
                    }
                }
                return AnyAgentModelProvider(OpenAICompatibleProvider(config: config))
            }
        } catch {
            return AnyAgentModelProvider(modelID: "settings-error") { _ in throw error }
        }
    }

    public func makeLLMProvider() -> AnyLLMProvider {
        do {
            let settings = try settingsRepository.loadSettings()
            switch settings.providerMode {
            case .stub, .governedClaudeSidecar:
                return AnyLLMProvider(StubLLMProvider())
            case .openAICompatible:
                guard let config = try settingsRepository.openAICompatibleConfig() else {
                    return AnyLLMProvider { _, _ in
                        throw OpenAICompatibleProviderError.missingAPIKey
                    }
                }
                return AnyLLMProvider(OpenAICompatibleProvider(config: config))
            }
        } catch {
            return AnyLLMProvider { _, _ in throw error }
        }
    }

    private static func splitSidecarArguments(_ arguments: String) -> [String] {
        arguments
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private static func sidecarWorkingDirectory(from settings: AppLLMSettings) -> URL {
        let path = settings.sidecarWorkingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty {
            return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
