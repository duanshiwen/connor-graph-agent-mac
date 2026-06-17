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
    public var browserAssistedWebFetchHandler: BrowserAssistedWebFetchHandler?

    public init(
        store: SQLiteGraphKernelStore,
        settingsRepository: AppLLMSettingsRepository,
        groupID: String = "default",
        storagePaths: AppStoragePaths? = nil,
        browserAssistedSearchHandler: BrowserAssistedSearchHandler? = nil,
        browserAssistedWebFetchHandler: BrowserAssistedWebFetchHandler? = nil
    ) {
        self.store = store
        self.settingsRepository = settingsRepository
        self.groupID = groupID
        self.storagePaths = storagePaths
        self.browserAssistedSearchHandler = browserAssistedSearchHandler
        self.browserAssistedWebFetchHandler = browserAssistedWebFetchHandler
    }

    public func makeAgentLoopChatController(
        session: AgentSession = AgentSession(id: "app-session"),
        permissionMode: AgentPermissionMode = .askToWrite,
        configuration: AgentLoopConfiguration = AgentLoopConfiguration(),
        sessionWorkspace: AppSessionWorkspaceReference? = nil,
        sessionLLMOverride: SessionLLMOverride? = nil
    ) -> AgentLoopChatController<AnyAgentModelProvider> {
        AgentLoopChatController(
            loopController: makeAgentLoopController(permissionMode: permissionMode, configuration: configuration, sessionWorkspace: sessionWorkspace, sessionLLMOverride: sessionLLMOverride),
            session: session,
            groupID: groupID,
            memoryStagingRepository: AppMemoryStagingBufferRepository(store: store)
        )
    }

    public func makeNativeSessionManager(
        session: AgentSession = AgentSession(id: "app-session"),
        permissionMode: AgentPermissionMode = .askToWrite,
        configuration: AgentLoopConfiguration = AgentLoopConfiguration(),
        sessionWorkspace: AppSessionWorkspaceReference? = nil,
        sessionLLMOverride: SessionLLMOverride? = nil
    ) -> NativeSessionManager {
        if let sidecarManager = try? makeConfiguredGovernedClaudeSDKSidecarNativeSessionManager(session: session, sessionWorkspace: sessionWorkspace, sessionLLMOverride: sessionLLMOverride) {
            return sidecarManager
        }
        return NativeSessionManager(
            backend: AgentLoopBackend(loopController: makeAgentLoopController(permissionMode: permissionMode, configuration: configuration, sessionWorkspace: sessionWorkspace, sessionLLMOverride: sessionLLMOverride)),
            sessionRepository: AppChatSessionRepository(store: store),
            session: session,
            groupID: groupID,
            permissionMode: permissionMode,
            memoryStagingRepository: AppMemoryStagingBufferRepository(store: store)
        )
    }

    public func makeConfiguredGovernedClaudeSDKSidecarNativeSessionManager(
        session: AgentSession = AgentSession(id: "app-session"),
        sessionWorkspace: AppSessionWorkspaceReference? = nil,
        sessionLLMOverride: SessionLLMOverride? = nil
    ) throws -> NativeSessionManager? {
        let settings = try settingsRepository.loadSettings()
        let connection = settings.connection(id: sessionLLMOverride?.connectionID) ?? settings.defaultConnection
        let effectiveProviderMode = sessionLLMOverride.flatMap { AppLLMProviderMode(rawValue: $0.providerMode) } ?? connection.providerMode
        guard effectiveProviderMode == .governedClaudeSidecar else { return nil }
        let executablePath = connection.sidecarExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !executablePath.isEmpty else { throw AppGraphAgentRuntimeFactoryError.missingSidecarExecutablePath }
        return try makeGovernedClaudeSDKSidecarNativeSessionManager(
            session: session,
            sidecarExecutableURL: URL(fileURLWithPath: executablePath),
            sidecarArguments: Self.splitSidecarArguments(connection.sidecarArguments),
            sidecarEnvironment: claudeSidecarEnvironment(connectionID: connection.id),
            workingDirectory: resolvedProjectWorkingDirectory(llmSettings: settings, sessionWorkspace: sessionWorkspace).url,
            permissionMode: connection.sidecarPermissionMode,
            thinkingLevel: resolvedThinkingLevel(settings: settings, sessionLLMOverride: sessionLLMOverride)
        )
    }

    public func makeConfiguredGovernedClaudeSDKSidecarRuntime() throws -> GovernedClaudeSDKSidecarRuntime<ClaudeSDKSidecarPersistentProcessTransport>? {
        let settings = try settingsRepository.loadSettings()
        let connection = settings.defaultConnection
        guard connection.providerMode == .governedClaudeSidecar else { return nil }
        let executablePath = connection.sidecarExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !executablePath.isEmpty else { throw AppGraphAgentRuntimeFactoryError.missingSidecarExecutablePath }
        guard connection.sidecarPermissionMode != .allowAll else {
            throw AppGraphAgentRuntimeFactoryError.unsafeSidecarPermissionMode(connection.sidecarPermissionMode)
        }
        let workingDirectory = resolvedProjectWorkingDirectory(llmSettings: settings).url
        let transport = ClaudeSDKSidecarPersistentProcessTransport(
            executableURL: URL(fileURLWithPath: executablePath),
            arguments: Self.splitSidecarArguments(connection.sidecarArguments),
            environment: claudeSidecarEnvironment(connectionID: connection.id),
            currentDirectoryURL: workingDirectory
        )
        return try GovernedClaudeSDKSidecarRuntime(
            transport: transport,
            workingDirectory: workingDirectory,
            permissionMode: connection.sidecarPermissionMode,
            instructionAppendix: userBasicInfoPromptSection(),
            runtimeStore: makeClaudeSDKSidecarRuntimeStore(),
            thinkingLevel: settings.defaultThinkingLevel
        )
    }

    public func makeClaudeSDKSidecarNativeSessionManager(
        session: AgentSession = AgentSession(id: "app-session"),
        sidecarExecutableURL: URL,
        sidecarArguments: [String] = [],
        sidecarEnvironment: [String: String] = [:],
        workingDirectory: URL,
        permissionMode: AgentPermissionMode = .askToWrite,
        thinkingLevel: AppLLMThinkingLevel = .defaultLevel
    ) -> NativeSessionManager {
        let transport = ClaudeSDKSidecarProcessTransport(
            executableURL: sidecarExecutableURL,
            arguments: sidecarArguments,
            environment: sidecarEnvironment,
            currentDirectoryURL: workingDirectory
        )
        return makeClaudeSDKSidecarNativeSessionManager(
            backend: ClaudeSDKSidecarBackend(transport: transport, workingDirectory: workingDirectory, instructionAppendix: userBasicInfoPromptSection(), thinkingLevel: thinkingLevel),
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
        permissionMode: AgentPermissionMode = .askToWrite,
        thinkingLevel: AppLLMThinkingLevel = .defaultLevel
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
            instructionAppendix: userBasicInfoPromptSection(),
            runtimeStore: makeClaudeSDKSidecarRuntimeStore(),
            thinkingLevel: thinkingLevel
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

    private func claudeSidecarEnvironment(connectionID: String) -> [String: String] {
        guard let tokens = try? settingsRepository.oauthTokens(for: connectionID) else { return [:] }
        var environment: [String: String] = [:]
        environment["CLAUDE_CODE_OAUTH_TOKEN"] = tokens.accessToken
        if let refreshToken = tokens.refreshToken, !refreshToken.isEmpty {
            environment["CLAUDE_CODE_OAUTH_REFRESH_TOKEN"] = refreshToken
        }
        return environment
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
        configuration: AgentLoopConfiguration = AgentLoopConfiguration(),
        sessionWorkspace: AppSessionWorkspaceReference? = nil,
        sessionLLMOverride: SessionLLMOverride? = nil
    ) -> AgentLoopController<AnyAgentModelProvider> {
        let searchService = SQLiteGraphHybridSearchService(store: store)
        var registry = AgentToolRegistry()
        registry.register(GraphSearchTool(searchService: searchService))
        registry.register(GraphIngestEpisodeTool(repository: store))
        registry.register(GraphProposeWriteTool(repository: store))
        let settings = (try? settingsRepository.loadSettings()) ?? .default
        let runtimeSettings = loadRuntimeSettings()
        let resolvedWorkspace = AppProjectWorkingDirectoryResolver.resolveWorkspace(
            sessionWorkingDirectoryPath: sessionWorkspace?.workingDirectoryPath,
            sessionWorkspaceRoots: sessionWorkspace?.roots ?? [],
            runtimeSettings: runtimeSettings,
            llmSettings: settings
        )
        let localWorkspacePolicy = LocalWorkspacePolicy(
            workingDirectory: resolvedWorkspace.primary.url,
            additionalAllowedDirectories: hiddenConnorDataAllowedDirectories(
                appendingTo: resolvedWorkspace.additionalAllowedDirectories
            )
        )
        registry.register(LocalReadFileTool(policy: localWorkspacePolicy))
        registry.register(LocalListDirectoryTool(policy: localWorkspacePolicy))
        registry.register(LocalGlobTool(policy: localWorkspacePolicy))
        registry.register(LocalGrepTool(policy: localWorkspacePolicy))
        registry.register(LocalWriteFileTool(policy: localWorkspacePolicy))
        registry.register(LocalEditFileTool(policy: localWorkspacePolicy))
        registry.register(LocalMultiEditTool(policy: localWorkspacePolicy))
        registry.register(LocalBashTool(policy: localWorkspacePolicy))
        if let storagePaths {
            let skillMutationService = SkillManagerMutationService(storagePaths: storagePaths)
            registry.register(ConnorSkillCreateTool(service: skillMutationService))
            registry.register(ConnorSkillUpdateTool(service: skillMutationService))
            registry.register(ConnorSkillDeleteTool(service: skillMutationService))
        }
        let scientificRuntime = ScientificComputeRuntime(engines: [NativeSwiftScientificEngine()])
        registry.register(ScienceComputeTool(runtime: scientificRuntime))
        registry.register(ScienceUnitsTool(runtime: scientificRuntime))
        registry.register(ScienceStatsTool(runtime: scientificRuntime))
        registry.register(ScienceLinalgTool(runtime: scientificRuntime))
        registry.register(ScienceSymbolicTool())
        registry.register(ScienceOptimizeTool())
        registry.register(ScienceTableComputeTool())
        registry.register(BrowserFetchTool())
        registry.register(SearchEngineMCPTool(browserAssistedSearchHandler: browserAssistedSearchHandler))
        registry.register(SearchEngineMCPWebFetchTool(browserAssistedSearchHandler: browserAssistedSearchHandler, browserAssistedWebFetchHandler: browserAssistedWebFetchHandler))
        var skillCatalogSummary = ""
        if let storagePaths {
            let scanner = SkillPackageScanner()
            let snapshot = scanner.scan(storagePaths: storagePaths, projectRoots: sessionWorkspace?.roots.map { URL(fileURLWithPath: $0.path) } ?? [])
            if !snapshot.packages.isEmpty {
                registry.register(SkillActivateTool(packages: snapshot.packages))
                skillCatalogSummary = buildSkillCatalogSummary(from: snapshot.packages)
            }
        }
        var effectiveConfiguration = configuration
        effectiveConfiguration.permissionMode = permissionMode
        effectiveConfiguration.instructionAppendix = [
            configuration.instructionAppendix.trimmingCharacters(in: .whitespacesAndNewlines),
            userBasicInfoPromptSection().trimmingCharacters(in: .whitespacesAndNewlines),
            skillCatalogSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
        return AgentLoopController(
            modelProvider: makeAgentModelProvider(sessionLLMOverride: sessionLLMOverride),
            toolRegistry: registry,
            configuration: effectiveConfiguration,
            auditLog: SQLiteAgentAuditLog(store: store),
            eventRecorder: AgentEventRecorder(repository: store),
            contextBuilder: AgentContextBuilder(hybridSearchService: searchService, groupID: groupID)
        )
    }

    public func makeAgentModelProvider(
        sessionLLMOverride: SessionLLMOverride? = nil
    ) -> AnyAgentModelProvider {
        do {
            let settings = try settingsRepository.loadSettings()
            let connection = settings.connection(id: sessionLLMOverride?.connectionID) ?? settings.defaultConnection
            let effectiveProviderMode: AppLLMProviderMode
            let effectiveConnectionKind: AppLLMConnectionKind
            let effectiveModel: String
            let effectiveBaseURL: String?
            let effectiveConnectionID: String
            let effectiveThinkingLevel = resolvedThinkingLevel(settings: settings, sessionLLMOverride: sessionLLMOverride)
            if let override = sessionLLMOverride {
                effectiveProviderMode = AppLLMProviderMode(rawValue: override.providerMode) ?? connection.providerMode
                effectiveConnectionKind = connection.connectionKind
                effectiveModel = override.model
                effectiveBaseURL = override.baseURLString
                effectiveConnectionID = override.connectionID ?? connection.id
            } else {
                effectiveProviderMode = connection.providerMode
                effectiveConnectionKind = connection.connectionKind
                effectiveModel = connection.effectiveModel
                effectiveBaseURL = nil
                effectiveConnectionID = connection.id
            }
            switch effectiveProviderMode {
            case .governedClaudeSidecar:
                return AnyAgentModelProvider(modelID: "governed-claude-sidecar-requires-session-manager") { _ in
                    throw AppGraphAgentRuntimeFactoryError.sidecarRequiresSessionManager
                }
            case .openAICompatible:
                if effectiveConnectionKind == .anthropicCompatible {
                    guard let config = try anthropicCompatibleConfigWithOverride(connectionID: effectiveConnectionID, model: effectiveModel, baseURLOverride: effectiveBaseURL, thinkingLevel: effectiveThinkingLevel) else {
                        return AnyAgentModelProvider(modelID: "missing-anthropic-compatible-config") { _ in
                            throw OpenAICompatibleProviderError.missingAPIKey
                        }
                    }
                    return AnyAgentModelProvider(AnthropicCompatibleProvider(config: config))
                }
                guard let config = try openAICompatibleConfigWithOverride(connectionID: effectiveConnectionID, model: effectiveModel, baseURLOverride: effectiveBaseURL, thinkingLevel: effectiveThinkingLevel) else {
                    return AnyAgentModelProvider(modelID: "missing-openai-compatible-config") { _ in
                        throw OpenAICompatibleProviderError.missingAPIKey
                    }
                }
                if effectiveConnectionKind == .githubCopilot {
                    return AnyAgentModelProvider(GitHubCopilotTokenRefreshingAgentModelProvider(
                        connectionID: effectiveConnectionID,
                        modelID: config.model,
                        capabilities: OpenAICompatibleProvider(config: config).capabilities,
                        settingsRepository: settingsRepository,
                        modelOverride: effectiveModel,
                        baseURLOverride: effectiveBaseURL
                    ))
                }
                return AnyAgentModelProvider(OpenAICompatibleProvider(config: config))
            }
        } catch {
            return AnyAgentModelProvider(modelID: "settings-error") { _ in throw error }
        }
    }

    private func openAICompatibleConfigWithOverride(
        connectionID: String,
        model: String,
        baseURLOverride: String?,
        thinkingLevel: AppLLMThinkingLevel
    ) throws -> OpenAICompatibleConfig? {
        try settingsRepository.openAICompatibleConfig(
            connectionID: connectionID,
            modelOverride: model,
            baseURLOverride: baseURLOverride,
            thinkingLevelOverride: thinkingLevel
        )
    }

    private func anthropicCompatibleConfigWithOverride(
        connectionID: String,
        model: String,
        baseURLOverride: String?,
        thinkingLevel: AppLLMThinkingLevel
    ) throws -> AnthropicCompatibleConfig? {
        try settingsRepository.anthropicCompatibleConfig(
            connectionID: connectionID,
            modelOverride: model,
            baseURLOverride: baseURLOverride,
            thinkingLevelOverride: thinkingLevel
        )
    }

    private func resolvedThinkingLevel(settings: AppLLMSettings, sessionLLMOverride: SessionLLMOverride?) -> AppLLMThinkingLevel {
        AppLLMThinkingLevel.normalized(sessionLLMOverride?.thinkingLevel) ?? settings.defaultThinkingLevel
    }

    public func makeLLMProvider() -> AnyLLMProvider {
        do {
            let settings = try settingsRepository.loadSettings()
            let connection = settings.defaultConnection
            switch connection.providerMode {
            case .governedClaudeSidecar:
                return AnyLLMProvider { _, _ in
                    throw AppGraphAgentRuntimeFactoryError.sidecarRequiresSessionManager
                }
            case .openAICompatible:
                if connection.connectionKind == .anthropicCompatible {
                    guard let config = try settingsRepository.anthropicCompatibleConfig(connectionID: connection.id) else {
                        return AnyLLMProvider { _, _ in
                            throw OpenAICompatibleProviderError.missingAPIKey
                        }
                    }
                    return AnyLLMProvider(AnthropicCompatibleProvider(config: config))
                }
                guard let config = try settingsRepository.openAICompatibleConfig(connectionID: connection.id) else {
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

    private func userBasicInfoPromptSection() -> String {
        UserBasicInfoPromptBuilder(preferences: loadRuntimeSettings().preferences).promptSection
    }

    private func resolvedProjectWorkingDirectory(
        llmSettings: AppLLMSettings,
        sessionWorkspace: AppSessionWorkspaceReference? = nil
    ) -> ResolvedProjectWorkingDirectory {
        AppProjectWorkingDirectoryResolver.resolveWorkspace(
            sessionWorkingDirectoryPath: sessionWorkspace?.workingDirectoryPath,
            sessionWorkspaceRoots: sessionWorkspace?.roots ?? [],
            runtimeSettings: loadRuntimeSettings(),
            llmSettings: llmSettings
        ).primary
    }

    private func hiddenConnorDataAllowedDirectories(appendingTo visibleDirectories: [URL]) -> [URL] {
        guard let storagePaths else { return visibleDirectories }
        let hiddenDirectory = storagePaths.applicationSupportDirectory
        let hiddenPath = AppProjectWorkingDirectoryResolver.normalizedDirectoryPath(hiddenDirectory)
        let visiblePaths = Set(visibleDirectories.map { AppProjectWorkingDirectoryResolver.normalizedDirectoryPath($0) })
        guard !visiblePaths.contains(hiddenPath) else { return visibleDirectories }
        return visibleDirectories + [hiddenDirectory]
    }

    private static func splitSidecarArguments(_ arguments: String) -> [String] {
        arguments
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
    }

}
