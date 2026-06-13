import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore

public enum AppGraphAgentRuntimeFactoryError: Error, Sendable, Equatable, LocalizedError {
    case unsafeSidecarPermissionMode(AgentPermissionMode)
    case missingSidecarExecutablePath
    case sidecarRequiresSessionManager

    public var errorDescription: String? {
        switch self {
        case .unsafeSidecarPermissionMode(let mode):
            return "Governed Claude SDK sidecar path does not allow unsafe permission mode: \(mode.rawValue)."
        case .missingSidecarExecutablePath:
            return "Governed Claude SDK sidecar path requires a sidecar executable path."
        case .sidecarRequiresSessionManager:
            return "Governed Claude SDK sidecar must run through NativeSessionManager/ClaudeSDKSidecarBackend, not the legacy direct model provider path."
        }
    }
}

public struct AppGraphAgentRuntimeFactory: @unchecked Sendable {
    public var store: SQLiteGraphKernelStore
    public var settingsRepository: AppLLMSettingsRepository
    public var groupID: String
    public var storagePaths: AppStoragePaths?
    public var browserAssistedSearchHandler: BrowserAssistedSearchHandler?

    public init(
        store: SQLiteGraphKernelStore,
        settingsRepository: AppLLMSettingsRepository,
        groupID: String = "default",
        storagePaths: AppStoragePaths? = nil,
        browserAssistedSearchHandler: BrowserAssistedSearchHandler? = nil
    ) {
        self.store = store
        self.settingsRepository = settingsRepository
        self.groupID = groupID
        self.storagePaths = storagePaths
        self.browserAssistedSearchHandler = browserAssistedSearchHandler
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
            workingDirectory: resolvedProjectWorkingDirectory(llmSettings: settings).url,
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
        let workingDirectory = resolvedProjectWorkingDirectory(llmSettings: settings).url
        let transport = ClaudeSDKSidecarPersistentProcessTransport(
            executableURL: URL(fileURLWithPath: executablePath),
            arguments: Self.splitSidecarArguments(settings.sidecarArguments),
            currentDirectoryURL: workingDirectory
        )
        return try GovernedClaudeSDKSidecarRuntime(
            transport: transport,
            workingDirectory: workingDirectory,
            permissionMode: settings.sidecarPermissionMode,
            runtimeStore: makeClaudeSDKSidecarRuntimeStore()
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
            permissionMode: permissionMode,
            runtimeStore: makeClaudeSDKSidecarRuntimeStore()
        )
        return makeClaudeSDKSidecarNativeSessionManager(
            backend: runtime,
            session: session,
            permissionMode: permissionMode
        )
    }

    private func makeClaudeSDKSidecarRuntimeStore() -> AppClaudeSDKSidecarRuntimeStore? {
        guard let storagePaths else { return nil }
        return AppClaudeSDKSidecarRuntimeStore(configDirectory: storagePaths.configDirectory)
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
        let settings = (try? settingsRepository.loadSettings()) ?? .default
        let runtimeSettings = loadRuntimeSettings()
        let resolvedWorkspace = AppProjectWorkingDirectoryResolver.resolveWorkspace(runtimeSettings: runtimeSettings, llmSettings: settings)
        let localWorkspacePolicy = LocalWorkspacePolicy(
            workingDirectory: resolvedWorkspace.primary.url,
            additionalAllowedDirectories: resolvedWorkspace.additionalAllowedDirectories
        )
        registry.register(LocalReadFileTool(policy: localWorkspacePolicy))
        registry.register(LocalListDirectoryTool(policy: localWorkspacePolicy))
        registry.register(LocalGlobTool(policy: localWorkspacePolicy))
        registry.register(LocalGrepTool(policy: localWorkspacePolicy))
        registry.register(LocalWriteFileTool(policy: localWorkspacePolicy))
        registry.register(LocalEditFileTool(policy: localWorkspacePolicy))
        registry.register(LocalMultiEditTool(policy: localWorkspacePolicy))
        registry.register(LocalBashTool(policy: localWorkspacePolicy))
        registry.register(BrowserFetchTool())
        registry.register(SearchEngineMCPTool(browserAssistedSearchHandler: browserAssistedSearchHandler))
        registry.register(SearchEngineMCPWebFetchTool(browserAssistedSearchHandler: browserAssistedSearchHandler))
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
            case .governedClaudeSidecar:
                return AnyAgentModelProvider(modelID: "governed-claude-sidecar-requires-session-manager") { _ in
                    throw AppGraphAgentRuntimeFactoryError.sidecarRequiresSessionManager
                }
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
            case .governedClaudeSidecar:
                return AnyLLMProvider { _, _ in
                    throw AppGraphAgentRuntimeFactoryError.sidecarRequiresSessionManager
                }
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

    private func loadRuntimeSettings() -> AgentRuntimeSettings {
        guard let storagePaths else { return .default }
        return (try? AppRuntimeSettingsRepository(configDirectory: storagePaths.configDirectory).loadOrCreateDefault()) ?? .default
    }

    private func resolvedProjectWorkingDirectory(llmSettings: AppLLMSettings) -> ResolvedProjectWorkingDirectory {
        AppProjectWorkingDirectoryResolver.resolveWorkspace(runtimeSettings: loadRuntimeSettings(), llmSettings: llmSettings).primary
    }

    private static func splitSidecarArguments(_ arguments: String) -> [String] {
        arguments
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
    }

}
