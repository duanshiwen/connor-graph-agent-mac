import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore

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
            memoryOSFacade: makeMemoryOSFacade()
        )
    }

    public func makeNativeSessionManager(
        session: AgentSession = AgentSession(id: "app-session"),
        permissionMode: AgentPermissionMode = .askToWrite,
        configuration: AgentLoopConfiguration = AgentLoopConfiguration(),
        sessionWorkspace: AppSessionWorkspaceReference? = nil,
        sessionLLMOverride: SessionLLMOverride? = nil
    ) -> NativeSessionManager {
        NativeSessionManager(
            backend: AgentLoopBackend(loopController: makeAgentLoopController(permissionMode: permissionMode, configuration: configuration, sessionWorkspace: sessionWorkspace, sessionLLMOverride: sessionLLMOverride)),
            sessionRepository: AppChatSessionRepository(store: store),
            session: session,
            groupID: groupID,
            permissionMode: permissionMode,
            memoryOSFacade: makeMemoryOSFacade()
        )
    }

    private func makeMemoryOSFacade() -> AppMemoryOSFacade? {
        guard let storagePaths else { return nil }
        do {
            if let builtinURL = FoundationKGBuiltinBootstrapper.builtinDatabaseURL() {
                _ = try FoundationKGBuiltinBootstrapper.ensureBuiltinDatabaseIfNeeded(memoryOSDatabaseURL: storagePaths.memoryOSDatabaseURL, builtinDatabaseURL: builtinURL)
            }
            let store = try SQLiteMemoryOSStore(path: storagePaths.memoryOSDatabaseURL.path)
            try store.migrate()
            return AppMemoryOSFacade(store: store)
        } catch {
            return nil
        }
    }

    private func registerPersistedMCPSourceTools(into registry: inout AgentToolRegistry, workingDirectory: URL) {
        guard let storagePaths else { return }
        let repository = AppMCPSourceRuntimeRepository(storagePaths: storagePaths)
        guard let catalog = try? MCPClientPool.loadEnabledPersistedCatalog(repository: repository), !catalog.isEmpty else { return }
        let pool = MCPClientPool(repository: repository, currentDirectoryURL: workingDirectory)
        MCPToolRegistryBridge().registerTools(catalog: catalog, into: &registry, router: pool)
    }


    public func makeAgentLoopController(
        permissionMode: AgentPermissionMode = .askToWrite,
        configuration: AgentLoopConfiguration = AgentLoopConfiguration(),
        sessionWorkspace: AppSessionWorkspaceReference? = nil,
        sessionLLMOverride: SessionLLMOverride? = nil
    ) -> AgentLoopController<AnyAgentModelProvider> {
        let searchService = SQLiteGraphHybridSearchService(store: store)
        var registry = AgentToolRegistry()
        registry.registerSessionStatusTools(repository: AppChatSessionRepository(store: store, storagePaths: storagePaths))
        registry.register(GraphSearchTool(searchService: searchService))
        if let memoryOSFacade = makeMemoryOSFacade() {
            registry.registerMemoryOSTools(facade: memoryOSFacade)
        }
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
            registry.registerTaskManagementTools(repository: AppTaskManagementRepository(storagePaths: storagePaths))
        }
        registry.registerCurrentTimeTool()
        let scientificRuntime = ScientificComputeRuntime(engines: [NativeSwiftScientificEngine()])
        registry.register(ScienceComputeTool(runtime: scientificRuntime))
        registry.register(ScienceUnitsTool(runtime: scientificRuntime))
        registry.register(ScienceStatsTool(runtime: scientificRuntime))
        registry.register(ScienceLinalgTool(runtime: scientificRuntime))
        registry.register(ScienceSymbolicTool())
        registry.register(ScienceOptimizeTool())
        registry.register(ScienceTableComputeTool())
        registry.registerTimeAnalysisTool()
        if let storagePaths {
            registry.registerNativeCalendarTools(runtime: CalendarSourceAgentRuntimeBridge(store: FileBackedCalendarSourceRuntimeStore(storagePaths: storagePaths)))
            let mailStore = FileBackedMailSourceStore(storagePaths: storagePaths)
            let mailDraftStore = FileBackedMailDraftRepository(
                storeURL: storagePaths.applicationSupportDirectory
                    .appendingPathComponent("mail", isDirectory: true)
                    .appendingPathComponent("drafts.json")
            )
            registry.registerNativeMailTools(runtime: MailRuntime(
                repository: mailStore,
                cache: mailStore,
                draftStore: mailDraftStore,
                credentialStore: AppMailCredentialStore(credentialStore: settingsRepository.credentialStore)
            ))
        } else {
            registry.registerNativeCalendarTools(runtime: InMemoryAgentCalendarRuntime())
        }
        registry.registerNativeContactsAggregateTools(runtime: InMemoryAgentContactRuntime())
        registry.register(BrowserFetchTool())
        registry.register(NativeWebSearchTool(browserAssistedSearchHandler: browserAssistedSearchHandler))
        registry.register(NativeWebFetchTool(browserAssistedWebFetchHandler: browserAssistedWebFetchHandler))
        registerPersistedMCPSourceTools(into: &registry, workingDirectory: resolvedWorkspace.primary.url)
        var skillCatalogSummary = ""
        if let storagePaths {
            let scanner = SkillPackageScanner()
            let snapshot = scanner.scan(storagePaths: storagePaths)
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
            case .openAIResponses:
                guard let config = try openAIResponsesConfigWithOverride(connectionID: effectiveConnectionID, model: effectiveModel, baseURLOverride: effectiveBaseURL, thinkingLevel: effectiveThinkingLevel) else {
                    return AnyAgentModelProvider(modelID: "missing-openai-responses-config") { _ in
                        throw OpenAICompatibleProviderError.missingAPIKey
                    }
                }
                return AnyAgentModelProvider(OpenAIResponsesProvider(config: config))
            case .anthropicMessages:
                guard let config = try anthropicCompatibleConfigWithOverride(connectionID: effectiveConnectionID, model: effectiveModel, baseURLOverride: effectiveBaseURL, thinkingLevel: effectiveThinkingLevel) else {
                    return AnyAgentModelProvider(modelID: "missing-anthropic-compatible-config") { _ in
                        throw OpenAICompatibleProviderError.missingAPIKey
                    }
                }
                return AnyAgentModelProvider(AnthropicCompatibleProvider(config: config))
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

    private func openAIResponsesConfigWithOverride(
        connectionID: String,
        model: String,
        baseURLOverride: String?,
        thinkingLevel: AppLLMThinkingLevel
    ) throws -> OpenAIResponsesConfig? {
        try settingsRepository.openAIResponsesConfig(
            connectionID: connectionID,
            modelOverride: model,
            baseURLOverride: baseURLOverride,
            thinkingLevelOverride: thinkingLevel
        )
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
            case .openAIResponses:
                guard let config = try settingsRepository.openAIResponsesConfig(connectionID: connection.id) else {
                    return AnyLLMProvider { _, _ in
                        throw OpenAICompatibleProviderError.missingAPIKey
                    }
                }
                return AnyLLMProvider(OpenAIResponsesProvider(config: config))
            case .anthropicMessages:
                guard let config = try settingsRepository.anthropicCompatibleConfig(connectionID: connection.id) else {
                    return AnyLLMProvider { _, _ in
                        throw OpenAICompatibleProviderError.missingAPIKey
                    }
                }
                return AnyLLMProvider(AnthropicCompatibleProvider(config: config))
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

}
