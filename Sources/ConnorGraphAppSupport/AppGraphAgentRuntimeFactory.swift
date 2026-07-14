import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore

public enum AppLLMRuntimeConfigurationError: Error, LocalizedError, Equatable, Sendable {
    case missingConnection(connectionID: String?, providerMode: AppLLMProviderMode, connectionKind: AppLLMConnectionKind)
    case missingCredentialOrConfiguration(connectionID: String, providerMode: AppLLMProviderMode, connectionKind: AppLLMConnectionKind)

    public var errorDescription: String? {
        switch self {
        case let .missingConnection(connectionID, providerMode, connectionKind):
            if let connectionID, !connectionID.isEmpty {
                return "未找到可用于运行时的 AI 连接：\(connectionID)（mode=\(providerMode.rawValue), kind=\(connectionKind.rawValue)）。"
            }
            return "当前没有可用于运行时的 AI 连接（mode=\(providerMode.rawValue), kind=\(connectionKind.rawValue)）。"
        case let .missingCredentialOrConfiguration(connectionID, providerMode, connectionKind):
            return "连接 \(connectionID) 无法构造运行时配置：缺少凭据或兼容模式/Endpoint/模型配置不匹配（mode=\(providerMode.rawValue), kind=\(connectionKind.rawValue)）。"
        }
    }
}

public struct AppGraphAgentRuntimeFactory: @unchecked Sendable {
    public var store: SQLiteGraphKernelStore
    public var settingsRepository: AppLLMSettingsRepository
    public var generatedMediaSettingsRepository: AppGeneratedMediaSettingsRepository
    public var capabilityEvidenceRepository: AppProviderCapabilityEvidenceRepository
    public var groupID: String
    public var storagePaths: AppStoragePaths?
    public var rssRuntime: RSSRuntime?
    public var browserAssistedSearchHandler: BrowserAssistedSearchHandler?
    public var browserAssistedWebFetchHandler: BrowserAssistedWebFetchHandler?
    public var generatedMediaProviderResolver: (@Sendable (_ conversationProvider: AnyAgentModelProvider) -> AnyAgentModelProvider?)?

    public init(
        store: SQLiteGraphKernelStore,
        settingsRepository: AppLLMSettingsRepository,
        generatedMediaSettingsRepository: AppGeneratedMediaSettingsRepository = AppGeneratedMediaSettingsRepository(),
        capabilityEvidenceRepository: AppProviderCapabilityEvidenceRepository = AppProviderCapabilityEvidenceRepository(),
        groupID: String = "default",
        storagePaths: AppStoragePaths? = nil,
        rssRuntime: RSSRuntime? = nil,
        browserAssistedSearchHandler: BrowserAssistedSearchHandler? = nil,
        browserAssistedWebFetchHandler: BrowserAssistedWebFetchHandler? = nil,
        generatedMediaProviderResolver: (@Sendable (_ conversationProvider: AnyAgentModelProvider) -> AnyAgentModelProvider?)? = nil
    ) {
        self.store = store
        self.settingsRepository = settingsRepository
        self.generatedMediaSettingsRepository = generatedMediaSettingsRepository
        self.capabilityEvidenceRepository = capabilityEvidenceRepository
        self.groupID = groupID
        self.storagePaths = storagePaths
        self.rssRuntime = rssRuntime
        self.browserAssistedSearchHandler = browserAssistedSearchHandler
        self.browserAssistedWebFetchHandler = browserAssistedWebFetchHandler
        self.generatedMediaProviderResolver = generatedMediaProviderResolver
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
            let store = try SQLiteMemoryOSStore(path: storagePaths.memoryOSDatabaseURL.path)
            try store.migrate()
            let searchKernel = try AppMemoryOSSearchKernelFactory.makeLiveIfHealthy(paths: storagePaths)
            let facade = AppMemoryOSFacade(store: store, searchKernel: searchKernel)
            try facade.ensureCurrentUserAnchor()
            return facade
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

    private func makePersonRegistryContactRuntime() -> (any AgentContactRuntime)? {
        guard let storagePaths else { return nil }
        let databaseURL = storagePaths.applicationSupportDirectory
            .appendingPathComponent("contacts", isDirectory: true)
            .appendingPathComponent("person-profiles.sqlite")
        guard let profileStore = try? SQLitePersonProfileStore(databaseURL: databaseURL) else { return nil }
        return PersonRegistryAgentContactRuntime(profileStore: profileStore)
    }


    public func makeAgentLoopController(
        permissionMode: AgentPermissionMode = .askToWrite,
        configuration: AgentLoopConfiguration = AgentLoopConfiguration(),
        sessionWorkspace: AppSessionWorkspaceReference? = nil,
        sessionLLMOverride: SessionLLMOverride? = nil
    ) -> AgentLoopController<AnyAgentModelProvider> {
        let searchService = SQLiteGraphHybridSearchService(store: store)
        let modelProvider = makeAgentModelProvider(sessionLLMOverride: sessionLLMOverride)
        var registry = AgentToolRegistry()
        let governanceConfig = storagePaths.flatMap { try? AppSessionGovernanceConfigRepository(configDirectory: $0.configDirectory).loadOrCreateDefault() } ?? .default
        registry.registerSessionStatusTools(repository: AppChatSessionRepository(store: store, storagePaths: storagePaths), governanceConfig: governanceConfig)
        registry.register(GraphSearchTool(searchService: searchService))
        let memoryOSFacade = makeMemoryOSFacade()
        if let memoryOSFacade {
            registry.registerMemoryOSReadTools(facade: memoryOSFacade)
        }
        let nativeSourceReferenceRecorder = memoryOSFacade.map { AppMemoryOSNativeSourceReferenceRecorder(facade: $0) }
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
            let calendarStore = FileBackedCalendarSourceRuntimeStore(storagePaths: storagePaths)
            let calendarCredentialStore = AppCalendarCredentialStore()
            let calDAVAdapter = CalDAVCalendarMutationAdapter { account in
                guard account.configuration.authMode != .none, let username = account.configuration.username else { return nil }
                let binding = AppCalendarCredentialStore.binding(accountID: account.id, username: username, authMode: account.configuration.authMode)
                return try calendarCredentialStore.readCredential(binding: binding)
            }
            let calendarMutationService = CalendarMutationService(store: calendarStore, adapters: [
                .macOSEventKit: EventKitCalendarMutationAdapter(),
                .genericCalDAV: calDAVAdapter,
                .appleICloudCalDAV: calDAVAdapter,
                .fastmailCalDAV: calDAVAdapter,
                .nextcloudCalDAV: calDAVAdapter
            ])
            registry.registerNativeCalendarTools(runtime: CalendarSourceAgentRuntimeBridge(store: calendarStore, mutationService: calendarMutationService), recorder: nativeSourceReferenceRecorder)
            let effectiveRSSRuntime = rssRuntime ?? RSSRuntime(
                repository: FileBackedRSSSourceRepository(storagePaths: storagePaths),
                cache: FileBackedRSSSourceCache(storagePaths: storagePaths)
            )
            registry.registerNativeRSSTools(runtime: effectiveRSSRuntime, recorder: nativeSourceReferenceRecorder)
            let mailStore = FileBackedMailSourceStore(storagePaths: storagePaths)
            registry.registerNativeMailTools(runtime: MailRuntime(repository: mailStore, cache: mailStore, preferencesStore: FileBackedMailPreferencesStore(storagePaths: storagePaths)), recorder: nativeSourceReferenceRecorder)
            registry.registerBrowserHistoryTools(store: BrowserHistoryStore(historyURL: storagePaths.browserHistoryURL), recorder: nativeSourceReferenceRecorder)
        } else {
            registry.registerNativeCalendarTools(runtime: InMemoryAgentCalendarRuntime())
        }
        registry.registerNativeContactsAggregateTools(runtime: makePersonRegistryContactRuntime() ?? InMemoryAgentContactRuntime())
        registry.register(BrowserFetchTool(browserAssistedWebFetchHandler: browserAssistedWebFetchHandler))
        registry.register(NativeWebSearchTool(browserAssistedSearchHandler: browserAssistedSearchHandler))
        registry.register(NativeWebFetchTool(browserAssistedWebFetchHandler: browserAssistedWebFetchHandler))
        registerPersistedMCPSourceTools(into: &registry, workingDirectory: resolvedWorkspace.primary.url)
        if let storagePaths {
            let scanner = SkillPackageScanner()
            let snapshot = scanner.scan(storagePaths: storagePaths)
            registry.register(SkillActivateTool(packages: snapshot.packages))
            registry.register(SkillListTool(packages: snapshot.packages))
        }
        let generatedMediaProvider = generatedMediaProviderResolver?(modelProvider)
            ?? makeConfiguredGeneratedMediaProvider(connectionID: sessionLLMOverride?.generatedMediaConnectionID)
            ?? makeVerifiedConversationMediaProvider(sessionLLMOverride: sessionLLMOverride)
            ?? (modelProvider.supportsGeneratedMediaExecution ? modelProvider : nil)
        let generatedImageToolIsAvailable = storagePaths != nil
            && generatedMediaProvider?.supportsGeneratedMediaExecution == true
            && generatedMediaProvider?.capabilities.generatedMediaCapabilities.contains(.imageGeneration) == true
        if generatedImageToolIsAvailable, let storagePaths, let generatedMediaProvider {
            registry.register(GeneratedImageAgentTool(
                provider: generatedMediaProvider,
                ingestionService: GeneratedMediaIngestionService(store: AppSessionAttachmentStore(paths: storagePaths))
            ))
        }
        var effectiveConfiguration = configuration
        effectiveConfiguration.permissionMode = permissionMode
        let generatedImageInstruction = generatedImageToolIsAvailable
            ? "When the user asks to create or generate an image, use `generate_image`. Do not claim that image generation is unavailable before attempting the available tool; if the tool fails, report the actual failure briefly."
            : ""
        effectiveConfiguration.instructionAppendix = [
            configuration.instructionAppendix.trimmingCharacters(in: .whitespacesAndNewlines),
            userBasicInfoPromptSection().trimmingCharacters(in: .whitespacesAndNewlines),
            generatedImageInstruction
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
        return AgentLoopController(
            modelProvider: modelProvider,
            toolRegistry: registry,
            configuration: effectiveConfiguration,
            auditLog: SQLiteAgentAuditLog(store: store),
            eventRecorder: AgentEventRecorder(repository: store),
            contextBuilder: AgentContextBuilder(hybridSearchService: searchService, groupID: groupID)
        )
    }

    private func makeVerifiedConversationMediaProvider(sessionLLMOverride: SessionLLMOverride?) -> AnyAgentModelProvider? {
        guard let settings = try? settingsRepository.loadSettings(),
              let connection = settings.connection(id: sessionLLMOverride?.connectionID),
              let evidence = try? capabilityEvidenceRepository.effectiveEvidence(for: .hostedImageGeneration, connection: connection),
              evidence.status == .verified,
              let apiKey = (try? settingsRepository.apiKey(for: connection.id)) ?? nil,
              !apiKey.isEmpty,
              let baseURL = URL(string: sessionLLMOverride?.baseURLString ?? connection.baseURLString)
        else { return nil }
        let model = sessionLLMOverride?.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveModel = model?.isEmpty == false ? model! : connection.effectiveModel
        let apiKeyHeaderKind = OpenAICompatibleAPIKeyHeaderKind(rawValue: connection.extraHTTPHeaders[AppLLMSettingsRepository.openAIAPIKeyHeaderKindMetadataKey] ?? "") ?? .bearer
        var extraHeaders = connection.extraHTTPHeaders
        extraHeaders.removeValue(forKey: AppLLMSettingsRepository.openAIAPIKeyHeaderKindMetadataKey)
        return AnyAgentModelProvider(OpenAIResponsesProvider(
            config: OpenAIResponsesConfig(
                baseURL: baseURL,
                apiKey: apiKey,
                model: effectiveModel,
                extraHeaders: extraHeaders,
                apiKeyHeaderKind: apiKeyHeaderKind,
                explicitVisionSupport: connection.explicitVisionSupport
            ),
            httpClient: URLSessionAgentHTTPClient(),
            sseClient: URLSessionAgentSSEHTTPClient()
        ))
    }

    private func makeConfiguredGeneratedMediaProvider(connectionID: String?) -> AnyAgentModelProvider? {
        guard let settings = try? generatedMediaSettingsRepository.loadSettings() else { return nil }
        let connection: AppGeneratedMediaConnectionConfig?
        if let connectionID, !connectionID.isEmpty {
            connection = settings.connections.first { $0.id == connectionID }
        } else {
            connection = settings.defaultImageConnection
        }
        guard let connection, connection.isConfigured,
              let baseURL = URL(string: connection.baseURLString),
              let apiKey = try? generatedMediaSettingsRepository.apiKey(for: connection.id),
              !apiKey.isEmpty else { return nil }
        switch connection.providerKind {
        case .geminiImage:
            return AnyAgentModelProvider(generatedMediaProvider: GeminiImageGeneratedMediaProvider(
                config: GeminiImageGeneratedMediaConfig(baseURL: baseURL, apiKey: apiKey, model: connection.model),
                httpClient: URLSessionAgentHTTPClient()
            ))
        case .blackForestLabs:
            return AnyAgentModelProvider(generatedMediaProvider: FluxImageGeneratedMediaProvider(
                config: FluxImageGeneratedMediaConfig(baseURL: baseURL, apiKey: apiKey, model: connection.model),
                httpClient: URLSessionAgentHTTPClient()
            ))
        case .stabilityAI:
            return AnyAgentModelProvider(generatedMediaProvider: StabilityImageGeneratedMediaProvider(
                config: StabilityImageGeneratedMediaConfig(baseURL: baseURL, apiKey: apiKey, model: connection.model),
                httpClient: URLSessionAgentHTTPClient()
            ))
        case .openAIResponses:
            return AnyAgentModelProvider(OpenAIResponsesProvider(
                config: OpenAIResponsesConfig(
                    baseURL: baseURL,
                    apiKey: apiKey,
                    model: connection.model,
                    extraHeaders: connection.extraHTTPHeaders
                ),
                httpClient: URLSessionAgentHTTPClient(),
                sseClient: URLSessionAgentSSEHTTPClient()
            ))
        case .openAIImages:
            return nil
        }
    }

    public func makeAgentModelProvider(
        sessionLLMOverride: SessionLLMOverride? = nil
    ) -> AnyAgentModelProvider {
        do {
            let settings = try settingsRepository.loadSettings()
            guard let connection = settings.connection(id: sessionLLMOverride?.connectionID) ?? settings.connections.first else {
                let requestedMode = sessionLLMOverride.flatMap { AppLLMProviderMode(rawValue: $0.providerMode) } ?? settings.defaultConnection?.providerMode ?? .openAICompatible
                let requestedKind = settings.connection(id: sessionLLMOverride?.connectionID)?.connectionKind
                    ?? settings.defaultConnection?.connectionKind
                    ?? .openAICompatible
                return AnyAgentModelProvider(modelID: "missing-llm-connection") { _ in
                    throw AppLLMRuntimeConfigurationError.missingConnection(
                        connectionID: sessionLLMOverride?.connectionID,
                        providerMode: requestedMode,
                        connectionKind: requestedKind
                    )
                }
            }
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
                        throw AppLLMRuntimeConfigurationError.missingCredentialOrConfiguration(
                            connectionID: effectiveConnectionID,
                            providerMode: .openAIResponses,
                            connectionKind: effectiveConnectionKind
                        )
                    }
                }
                return AnyAgentModelProvider(OpenAIResponsesProvider(config: config))
            case .anthropicMessages:
                guard let config = try anthropicCompatibleConfigWithOverride(connectionID: effectiveConnectionID, model: effectiveModel, baseURLOverride: effectiveBaseURL, thinkingLevel: effectiveThinkingLevel) else {
                    return AnyAgentModelProvider(modelID: "missing-anthropic-compatible-config") { _ in
                        throw AppLLMRuntimeConfigurationError.missingCredentialOrConfiguration(
                            connectionID: effectiveConnectionID,
                            providerMode: .anthropicMessages,
                            connectionKind: effectiveConnectionKind
                        )
                    }
                }
                return AnyAgentModelProvider(AnthropicCompatibleProvider(config: config))
            case .openAICompatible:
                if effectiveConnectionKind == .anthropicCompatible {
                    guard let config = try anthropicCompatibleConfigWithOverride(connectionID: effectiveConnectionID, model: effectiveModel, baseURLOverride: effectiveBaseURL, thinkingLevel: effectiveThinkingLevel) else {
                        return AnyAgentModelProvider(modelID: "missing-anthropic-compatible-config") { _ in
                            throw AppLLMRuntimeConfigurationError.missingCredentialOrConfiguration(
                                connectionID: effectiveConnectionID,
                                providerMode: .openAICompatible,
                                connectionKind: effectiveConnectionKind
                            )
                        }
                    }
                    return AnyAgentModelProvider(AnthropicCompatibleProvider(config: config))
                }
                guard let config = try openAICompatibleConfigWithOverride(connectionID: effectiveConnectionID, model: effectiveModel, baseURLOverride: effectiveBaseURL, thinkingLevel: effectiveThinkingLevel) else {
                    return AnyAgentModelProvider(modelID: "missing-openai-compatible-config") { _ in
                        throw AppLLMRuntimeConfigurationError.missingCredentialOrConfiguration(
                            connectionID: effectiveConnectionID,
                            providerMode: .openAICompatible,
                            connectionKind: effectiveConnectionKind
                        )
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
            guard let connection = settings.defaultConnection else {
                return AnyLLMProvider { _, _ in
                    throw OpenAICompatibleProviderError.missingAPIKey
                }
            }
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
