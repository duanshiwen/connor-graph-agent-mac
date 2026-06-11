import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore

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
    ) -> NativeSessionManager<AnyAgentModelProvider> {
        NativeSessionManager(
            loopController: makeAgentLoopController(permissionMode: permissionMode, configuration: configuration),
            sessionRepository: AppChatSessionRepository(store: store),
            session: session,
            groupID: groupID,
            memoryStagingRepository: AppMemoryStagingBufferRepository(store: store)
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
            case .stub:
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
            case .stub:
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
}
