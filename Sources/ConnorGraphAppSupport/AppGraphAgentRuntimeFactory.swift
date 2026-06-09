import Foundation
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore

public struct AppGraphAgentRuntimeFactory: @unchecked Sendable {
    public var store: SQLiteGraphStore
    public var settingsRepository: AppLLMSettingsRepository
    public var groupID: String

    public init(
        store: SQLiteGraphStore,
        settingsRepository: AppLLMSettingsRepository,
        groupID: String = "default"
    ) {
        self.store = store
        self.settingsRepository = settingsRepository
        self.groupID = groupID
    }

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
