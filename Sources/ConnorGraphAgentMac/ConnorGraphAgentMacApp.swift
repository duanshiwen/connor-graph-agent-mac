import SwiftUI
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

@main
struct ConnorGraphAgentMacApp: App {
    var body: some Scene {
        WindowGroup {
            AppShellView(viewModel: AppViewModel.live())
        }
    }
}

enum SidebarItem: String, CaseIterable, Identifiable {
    case entities = "图谱节点"
    case search = "搜索"
    case observeLog = "观察日志"
    case agentChat = "智能体聊天"
    case promotionQueue = "提升队列"
    case graphWriteCandidates = "写入候选"
    case memoryChangeLog = "记忆变更"
    case extractionDiagnostics = "记忆准入"
    case llmSettings = "模型设置"

    var id: String { rawValue }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var selection: SidebarItem? = .agentChat
    @Published var query: String = "记忆"
    @Published var searchResults: [GraphSearchHit] = []
    @Published var chatInput: String = "记忆"
    @Published var transcript: [AgentMessage] = []
    @Published var lastContext: AgentContext?
    @Published var lastPromptInspection: AgentChatPromptInspection?
    @Published var errorMessage: String?
    @Published var entities: [GraphEntity]
    @Published var statements: [GraphStatement]
    @Published var episodes: [GraphEpisodeV3]
    @Published var observeLogEntries: [ObserveLogEntry]
    @Published var databasePath: String?
    @Published var schemaHealthReport: GraphSchemaHealthReport?
    @Published var promotionCandidates: [ObserveLogEntry] = []
    @Published var graphWriteCandidates: [GraphWriteCandidate] = []
    @Published var graphWriteCandidateAudits: [String: [GraphWriteCandidateAuditPresentation]] = [:]
    @Published var graphExtractionTraces: [AppGraphExtractionTracePresentation] = []
    @Published var admissionHoldQueueItems: [AppGraphAdmissionHoldQueuePresentation] = []
    @Published var memoryChangeLogEntries: [AppGraphMemoryChangeLogPresentation] = []
    @Published var lastPromotionResultSummary: String?
    @Published var lastGraphWriteCandidateResultSummary: String?
    @Published var lastAdmissionHoldQueueActionSummary: String?
    @Published var llmProviderMode: AppLLMProviderMode = .stub
    @Published var llmBaseURLString: String = AppLLMSettings.default.baseURLString
    @Published var llmModel: String = AppLLMSettings.default.model
    @Published var llmAPIKeyInput: String = ""
    @Published var llmHasAPIKey: Bool = false
    @Published var llmSettingsMessage: String?
    @Published var llmHealthCheckMessage: String?
    @Published var isTestingLLMConnection: Bool = false
    @Published var chatSessions: [AgentSession] = []
    @Published var selectedChatSessionID: String?
    @Published var latestChatSummary: AgentSessionSummary?
    @Published var isSummarizingChatSession: Bool = false
    @Published var chatSummaryMessage: String?
    @Published var isSubmittingChat: Bool = false
    @Published var agentEventTimeline: [AgentEventPresentation] = []
    @Published var isBrowserVisible: Bool = false

    private var repository: AppGraphRepository?
    private var promotionRepository: AppPromotionQueueRepository?
    private var graphWriteCandidateRepository: AppGraphWriteCandidateRepository?
    private var graphExtractionTraceRepository: AppGraphExtractionTraceRepository?
    private var admissionHoldQueueRepository: AppGraphAdmissionHoldQueueRepository?
    private var memoryChangeLogRepository: AppGraphMemoryChangeLogRepository?
    private var chatSessionRepository: AppChatSessionRepository?
    private var llmSettingsRepository: AppLLMSettingsRepository
    private var llmProviderHealthChecker: AppLLMProviderHealthChecker
    private var agentRuntimeFactory: AppGraphAgentRuntimeFactory?
    private var hybridSearchService: (any GraphHybridSearchService)?
    private var backgroundJobRunner: AppGraphBackgroundJobRunner?
    // Legacy simple ask controller is kept only for demo/no-store fallback and compatibility helpers.
    // The app's product chat path is AgentLoopChatController.
    private var legacyChatController: AgentChatController<AnyLLMProvider>
    private var loopChatController: AgentLoopChatController<AnyAgentModelProvider>?

    private var activeChatSession: AgentSession {
        loopChatController?.session ?? legacyChatController.agent.session
    }

    private var activeChatTranscript: [AgentMessage] {
        loopChatController?.transcript ?? legacyChatController.transcript
    }

    var latestChatSummaryFreshness: AgentSessionSummaryFreshness? {
        latestChatSummary?.freshness(for: activeChatSession)
    }

    var latestChatSummaryContextMessage: String {
        guard let freshness = latestChatSummaryFreshness else { return "" }
        if freshness.isFresh {
            return "会话摘要已是最新，将包含在下一次回答中。"
        }
        return "会话摘要已过期：还有 \(freshness.uncoveredMessageCount) 条消息未覆盖，因此不会包含在下一次回答中。"
    }

    var latestChatSummaryRefreshState: AgentSessionSummaryRefreshState {
        AgentSessionSummaryRefreshState(
            isSummarizing: isSummarizingChatSession,
            hasTranscriptMessages: !transcript.isEmpty,
            freshness: latestChatSummaryFreshness
        )
    }

    var summarizeChatSessionButtonTitle: String {
        latestChatSummaryRefreshState.buttonTitle
    }

    var canSummarizeSelectedChatSession: Bool {
        latestChatSummaryRefreshState.canSubmit
    }

    init(
        entities: [GraphEntity],
        statements: [GraphStatement],
        episodes: [GraphEpisodeV3] = [],
        observeLogEntries: [ObserveLogEntry],
        repository: AppGraphRepository? = nil,
        databasePath: String? = nil,
        llmSettingsRepository: AppLLMSettingsRepository = AppLLMSettingsRepository()
    ) {
        self.entities = entities
        self.statements = statements
        self.episodes = episodes
        self.observeLogEntries = observeLogEntries
        self.repository = repository
        if let repository {
            self.promotionRepository = AppPromotionQueueRepository(store: repository.store)
            self.graphWriteCandidateRepository = AppGraphWriteCandidateRepository(store: repository.store)
            self.graphExtractionTraceRepository = AppGraphExtractionTraceRepository(store: repository.store)
            self.admissionHoldQueueRepository = AppGraphAdmissionHoldQueueRepository(store: repository.store)
            self.memoryChangeLogRepository = AppGraphMemoryChangeLogRepository(store: repository.store)
            self.chatSessionRepository = AppChatSessionRepository(store: repository.store)
            self.agentRuntimeFactory = AppGraphAgentRuntimeFactory(store: repository.store, settingsRepository: llmSettingsRepository)
            self.hybridSearchService = SQLiteGraphHybridSearchService(store: repository.store)
            self.backgroundJobRunner = AppGraphBackgroundJobRunner(store: repository.store, settingsRepository: llmSettingsRepository)
        }
        self.llmSettingsRepository = llmSettingsRepository
        self.llmProviderHealthChecker = AppLLMProviderHealthChecker(settingsRepository: llmSettingsRepository)
        self.databasePath = databasePath
        let initialSession = AgentSession(id: "app-session")
        self.legacyChatController = Self.makeLegacyChatController(runtimeFactory: agentRuntimeFactory, settingsRepository: llmSettingsRepository, session: initialSession)
        self.loopChatController = agentRuntimeFactory?.makeAgentLoopChatController(session: initialSession)
        self.searchResults = []
        loadLLMSettings()
        reloadChatSessions()
        reloadSchemaHealthReport()
        reloadGraphExtractionTraces()
        reloadMemoryChangeLog()
    }

    static func live() -> AppViewModel {
        do {
            let paths = try AppStoragePaths.live()
            let repository = try AppGraphRepository.bootstrap(paths: paths)
            var snapshot = try repository.loadSnapshot()
            if snapshot.entities.isEmpty {
                let demo = demoSnapshot()
                for entity in demo.entities { try repository.store.upsert(entity: entity) }
                for statement in demo.statements { try repository.store.upsert(statement: statement) }
                for episode in demo.episodes { try repository.store.upsert(episode: episode) }
                snapshot = try repository.loadSnapshot()
            }
            let viewModel = AppViewModel(
                entities: snapshot.entities,
                statements: snapshot.statements,
                episodes: snapshot.episodes,
                observeLogEntries: snapshot.observeLogEntries,
                repository: repository,
                databasePath: paths.databaseURL.path
            )
            viewModel.reloadPromotionCandidates()
            viewModel.reloadGraphWriteCandidates()
            return viewModel
        } catch {
            let viewModel = AppViewModel.demo()
            viewModel.errorMessage = "已回退到演示数据：\(error)"
            return viewModel
        }
    }

    static func demo() -> AppViewModel {
        let snapshot = demoSnapshot()
        return AppViewModel(entities: snapshot.entities, statements: snapshot.statements, episodes: snapshot.episodes, observeLogEntries: snapshot.observeLogEntries)
    }

    private static func demoSnapshot() -> GraphStoreSnapshot {
        let workObject = GraphEntity(
            id: "work-object-agent-os",
            graphID: "default",
            name: "Agent OS",
            stableKey: "project:work_object:agent-os",
            entityKind: .workObject,
            scope: .project,
            canonicalClassID: "project",
            summary: "A local-first operating system for graph-backed agents."
        )
        let question = GraphEntity(
            id: "question-memory",
            graphID: "default",
            name: "How should memory work?",
            stableKey: "project:entity:question-memory",
            entityKind: .entity,
            scope: .project,
            canonicalClassID: "question",
            summary: "Agent memory should be grounded in graph context."
        )
        let answer = GraphEntity(
            id: "answer-graph-memory",
            graphID: "default",
            name: "Use graph-backed context",
            stableKey: "project:entity:answer-graph-memory",
            entityKind: .entity,
            scope: .project,
            canonicalClassID: "answer",
            summary: "Use a local graph store as the runtime knowledge source of truth."
        )
        let fact = GraphStatement(
            id: "statement-question-memory-answered-by-answer-graph-memory",
            graphID: "default",
            subjectEntityID: question.id,
            predicate: .answeredBy,
            objectEntityID: answer.id,
            statementText: "question-memory is answered by answer-graph-memory",
            validAt: Date(timeIntervalSince1970: 1_700_000_000),
            justifications: [GraphJustification(type: .userStated, source: "demo", strength: 1.0)],
            sourceEpisodeIDs: ["episode-demo"]
        )
        let episode = GraphEpisodeV3(
            id: "episode-demo",
            graphID: "default",
            sourceType: .system,
            title: "Demo seed",
            content: "Graph store is runtime knowledge source of truth.",
            sourceDescription: "Built-in demo seed"
        )
        let observe = ObserveLogEntry(
            id: "observe-demo",
            kind: .insight,
            source: .agent,
            content: "Recent insight: graph store is the runtime knowledge layer.",
            normalizedSummary: "Graph store is runtime knowledge source of truth",
            workObjectID: workObject.id
        )
        return GraphStoreSnapshot(entities: [workObject, question, answer], statements: [fact], episodes: [episode], observeLogEntries: [observe])
    }

    private static func makeLegacyChatController(
        runtimeFactory: AppGraphAgentRuntimeFactory?,
        settingsRepository: AppLLMSettingsRepository,
        session: AgentSession = AgentSession(id: "app-session")
    ) -> AgentChatController<AnyLLMProvider> {
        let provider: AnyLLMProvider
        let contextBuilder: AgentContextBuilder
        if let runtimeFactory {
            provider = runtimeFactory.makeLLMProvider()
            contextBuilder = AgentContextBuilder(
                hybridSearchService: SQLiteGraphHybridSearchService(store: runtimeFactory.store),
                groupID: runtimeFactory.groupID
            )
        } else {
            provider = Self.makeLLMProvider(settingsRepository: settingsRepository)
            contextBuilder = AgentContextBuilder(hybridSearchService: EmptyGraphHybridSearchService(), groupID: "default")
        }
        return AgentChatController(
            agent: GraphAgent(
                session: session,
                contextBuilder: contextBuilder,
                llmProvider: provider
            )
        )
    }

    private static func makeLLMProvider(settingsRepository: AppLLMSettingsRepository) -> AnyLLMProvider {
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

    private func apply(snapshot: GraphStoreSnapshot) {
        entities = snapshot.entities
        statements = snapshot.statements
        episodes = snapshot.episodes
        observeLogEntries = snapshot.observeLogEntries
        let session = activeChatSession
        legacyChatController = Self.makeLegacyChatController(runtimeFactory: agentRuntimeFactory, settingsRepository: llmSettingsRepository, session: session)
        loopChatController = agentRuntimeFactory?.makeAgentLoopChatController(session: session)
        Task { await runSearch() }
        reloadPromotionCandidates()
        reloadGraphWriteCandidates()
    }

    func runBackgroundJobs() async {
        guard let backgroundJobRunner, let repository else { return }
        do {
            _ = try await backgroundJobRunner.runAvailable(limit: 20)
            let snapshot = try repository.loadSnapshot()
            let traces = try graphExtractionTraceRepository?.loadRecentTraces() ?? []
            let holdItems = try admissionHoldQueueRepository?.loadOpenItems() ?? []
            let changeLog = try memoryChangeLogRepository?.loadRecentEntries() ?? []
            await MainActor.run {
                apply(snapshot: snapshot)
                graphExtractionTraces = traces
                admissionHoldQueueItems = holdItems
                memoryChangeLogEntries = changeLog
            }
        } catch {
            await MainActor.run { errorMessage = String(describing: error) }
        }
    }

    func loadLLMSettings() {
        do {
            let settings = try llmSettingsRepository.loadSettings()
            llmProviderMode = settings.providerMode
            llmBaseURLString = settings.baseURLString
            llmModel = settings.model
            llmHasAPIKey = settings.hasAPIKey
            llmAPIKeyInput = ""
            llmSettingsMessage = nil
            llmHealthCheckMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func saveLLMSettings() {
        do {
            let settings = AppLLMSettings(
                baseURLString: llmBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines),
                model: llmModel.trimmingCharacters(in: .whitespacesAndNewlines),
                hasAPIKey: llmHasAPIKey,
                providerMode: llmProviderMode
            )
            let apiKey = llmAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            try llmSettingsRepository.save(settings: settings, apiKey: apiKey.isEmpty ? nil : apiKey)
            loadLLMSettings()
            let session = activeChatSession
            legacyChatController = Self.makeLegacyChatController(runtimeFactory: agentRuntimeFactory, settingsRepository: llmSettingsRepository, session: session)
            loopChatController = agentRuntimeFactory?.makeAgentLoopChatController(session: session)
            llmSettingsMessage = "模型设置已保存。"
            llmHealthCheckMessage = nil
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func clearLLMAPIKey() {
        do {
            try llmSettingsRepository.clearAPIKey()
            loadLLMSettings()
            let session = activeChatSession
            legacyChatController = Self.makeLegacyChatController(runtimeFactory: agentRuntimeFactory, settingsRepository: llmSettingsRepository, session: session)
            loopChatController = agentRuntimeFactory?.makeAgentLoopChatController(session: session)
            llmSettingsMessage = "API Key 已清除。"
            llmHealthCheckMessage = nil
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func testLLMConnection() async {
        isTestingLLMConnection = true
        defer { isTestingLLMConnection = false }
        llmHealthCheckMessage = nil
        let result = await llmProviderHealthChecker.testConnection()
        llmHealthCheckMessage = result.message
        switch result.status {
        case .success:
            errorMessage = nil
        case .notConfigured, .failed:
            errorMessage = result.message
        }
    }

    func reloadChatSessions() {
        guard let chatSessionRepository else {
            transcript = activeChatTranscript
            selectedChatSessionID = activeChatSession.id
            return
        }
        do {
            var sessions = try chatSessionRepository.loadRecentSessions()
            if sessions.isEmpty {
                let session = try chatSessionRepository.createSession()
                sessions = [session]
            }
            chatSessions = sessions
            let selectedID = selectedChatSessionID ?? sessions.first?.id
            selectedChatSessionID = selectedID
            if let selectedID, let session = try chatSessionRepository.loadSession(id: selectedID) {
                legacyChatController = Self.makeLegacyChatController(runtimeFactory: agentRuntimeFactory, settingsRepository: llmSettingsRepository, session: session)
                loopChatController = agentRuntimeFactory?.makeAgentLoopChatController(session: session)
                transcript = session.messages
                agentEventTimeline = []
                latestChatSummary = try chatSessionRepository.loadLatestSummary(sessionID: selectedID)
            } else {
                latestChatSummary = nil
            }
            chatSummaryMessage = nil
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func newChatSession() {
        guard let chatSessionRepository else { return }
        do {
            let session = try chatSessionRepository.createSession()
            selectedChatSessionID = session.id
            legacyChatController = Self.makeLegacyChatController(runtimeFactory: agentRuntimeFactory, settingsRepository: llmSettingsRepository, session: session)
            loopChatController = agentRuntimeFactory?.makeAgentLoopChatController(session: session)
            transcript = []
            agentEventTimeline = []
            latestChatSummary = nil
            chatSummaryMessage = nil
            lastPromptInspection = nil
            reloadChatSessions()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func selectChatSession(_ sessionID: String) {
        guard let chatSessionRepository else { return }
        do {
            guard let session = try chatSessionRepository.loadSession(id: sessionID) else { return }
            selectedChatSessionID = session.id
            legacyChatController = Self.makeLegacyChatController(runtimeFactory: agentRuntimeFactory, settingsRepository: llmSettingsRepository, session: session)
            loopChatController = agentRuntimeFactory?.makeAgentLoopChatController(session: session)
            transcript = session.messages
            agentEventTimeline = []
            latestChatSummary = try chatSessionRepository.loadLatestSummary(sessionID: session.id)
            chatSummaryMessage = nil
            lastContext = nil
            lastPromptInspection = nil
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func reloadPromotionCandidates() {
        do {
            promotionCandidates = try promotionRepository?.loadCandidates() ?? []
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func promote(_ entry: ObserveLogEntry) {
        guard let promotionRepository, let repository else {
            errorMessage = "提升队列不可用。"
            return
        }
        do {
            let result = try promotionRepository.promote(entry)
            let snapshot = try repository.loadSnapshot()
            lastPromotionResultSummary = "已提升 \(entry.id)：\(result.entities.count) 个节点，\(result.statements.count) 条事实"
            apply(snapshot: snapshot)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func dismissPromotionCandidate(_ entry: ObserveLogEntry) {
        do {
            _ = try promotionRepository?.dismiss(entry)
            reloadPromotionCandidates()
            lastPromotionResultSummary = "已忽略 \(entry.id)"
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func pinPromotionCandidate(_ entry: ObserveLogEntry) {
        do {
            _ = try promotionRepository?.pin(entry)
            reloadPromotionCandidates()
            lastPromotionResultSummary = "已置顶 \(entry.id) 30 天"
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func reloadGraphWriteCandidates() {
        do {
            let candidates = try graphWriteCandidateRepository?.loadCandidates() ?? []
            graphWriteCandidates = candidates
            graphWriteCandidateAudits = try graphWriteCandidateRepository?.loadAuditTimelines(for: candidates) ?? [:]
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func reloadSchemaHealthReport() {
        do {
            schemaHealthReport = try repository?.store.schemaHealthReport()
        } catch {
            schemaHealthReport = GraphSchemaHealthReport(
                expectedVersion: SQLiteGraphKernelStore.currentSchemaVersion,
                actualVersion: 0,
                status: .warning,
                missingTables: [],
                missingIndexes: [],
                checkedAt: Date()
            )
            errorMessage = String(describing: error)
        }
    }

    func reloadGraphExtractionTraces() {
        do {
            graphExtractionTraces = try graphExtractionTraceRepository?.loadRecentTraces() ?? []
            admissionHoldQueueItems = try admissionHoldQueueRepository?.loadOpenItems() ?? []
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func reloadMemoryChangeLog() {
        do {
            memoryChangeLogEntries = try memoryChangeLogRepository?.loadRecentEntries() ?? []
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func approveAdmissionHoldQueueItem(_ item: AppGraphAdmissionHoldQueuePresentation) {
        guard let admissionHoldQueueRepository, let repository else {
            errorMessage = "准入诊断队列不可用。"
            return
        }
        do {
            let result = try admissionHoldQueueRepository.approveAndCommit(item.id)
            let snapshot = try repository.loadSnapshot()
            apply(snapshot: snapshot)
            reloadGraphExtractionTraces()
            reloadMemoryChangeLog()
            lastAdmissionHoldQueueActionSummary = "已批准并提交 hold item \(item.id)：实体 +\(result.committedEntityIDs.count)，陈述 +\(result.committedStatementIDs.count)"
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func rejectAdmissionHoldQueueItem(_ item: AppGraphAdmissionHoldQueuePresentation) {
        do {
            try admissionHoldQueueRepository?.reject(item.id)
            reloadGraphExtractionTraces()
            lastAdmissionHoldQueueActionSummary = "已 dismiss hold item \(item.id)"
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func rerunAdmissionHoldQueueItem(_ item: AppGraphAdmissionHoldQueuePresentation) {
        do {
            guard let result = try admissionHoldQueueRepository?.rerunExtraction(item.id) else { return }
            reloadGraphExtractionTraces()
            lastAdmissionHoldQueueActionSummary = "已重新排队 extraction job \(result.jobID)：\(result.status.rawValue)"
            errorMessage = nil
            Task { await runBackgroundJobs() }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func inspectAdmissionHoldQueueItemEvidence(_ item: AppGraphAdmissionHoldQueuePresentation) {
        do {
            guard let inspection = try admissionHoldQueueRepository?.inspectEvidence(item.id) else { return }
            lastAdmissionHoldQueueActionSummary = inspection.summary
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func validateGraphWriteCandidate(_ candidate: GraphWriteCandidate) async {
        do {
            guard let result = try await graphWriteCandidateRepository?.validateGoverned(candidate) else { return }
            reloadGraphWriteCandidates()
            lastGraphWriteCandidateResultSummary = result.validation.isValid ? "候选 \(candidate.id) 验证通过，进入待审阅" : "候选 \(candidate.id) 验证失败：\(result.validation.errors.joined(separator: "; "))"
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func approveGraphWriteCandidate(_ candidate: GraphWriteCandidate) async {
        do {
            _ = try await graphWriteCandidateRepository?.approveGoverned(candidate)
            reloadGraphWriteCandidates()
            lastGraphWriteCandidateResultSummary = "已批准候选 \(candidate.id)，并写入审计日志"
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func rejectGraphWriteCandidate(_ candidate: GraphWriteCandidate) async {
        do {
            _ = try await graphWriteCandidateRepository?.rejectGoverned(candidate, reason: "Rejected by reviewer")
            reloadGraphWriteCandidates()
            lastGraphWriteCandidateResultSummary = "已拒绝候选 \(candidate.id)，并写入审计日志"
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func commitGraphWriteCandidate(_ candidate: GraphWriteCandidate) async {
        guard let graphWriteCandidateRepository, let repository else {
            errorMessage = "写入候选仓储不可用。"
            return
        }
        do {
            let result = try await graphWriteCandidateRepository.commitGoverned(candidate)
            let snapshot = try repository.loadSnapshot()
            apply(snapshot: snapshot)
            reloadGraphWriteCandidates()
            lastGraphWriteCandidateResultSummary = "已通过权限治理提交候选 \(candidate.id)：实体 +\(result.createdEntityIDs.count)，陈述 +\(result.createdStatementIDs.count)，更新陈述 \(result.updatedStatementIDs.count)，附加证据 \(result.attachedEvidenceStatementIDs.count)"
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func runSearch() async {
        guard let hybridSearchService else {
            searchResults = []
            errorMessage = "SQLite hybrid search is unavailable."
            return
        }
        do {
            let response = try await hybridSearchService.search(query: GraphSearchQuery(text: query, graphID: "default"))
            searchResults = response.hits
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func saveBrowserSelectionAsEpisode(_ selection: BrowserSelectionContext) async {
        guard let repository else {
            errorMessage = "当前没有可用的图谱仓储，无法保存网页证据。"
            return
        }
        do {
            let draft = BrowserGraphEvidenceBuilder().makeEpisodeDraft(
                selection: selection,
                groupID: "default",
                sessionID: selectedChatSessionID
            )
            try repository.store.upsert(episode: draft.episode)
            let source = GraphExtractionSource(
                id: draft.episode.id,
                graphID: draft.episode.graphID,
                sourceType: .webpage,
                title: draft.episode.title,
                content: draft.episode.content,
                occurredAt: draft.episode.occurredAt,
                sessionID: draft.episode.sessionID,
                workObjectID: draft.episode.workObjectID,
                metadata: draft.episode.metadata
            )
            try repository.store.enqueueExtractionJob(graphID: source.graphID, source: source)
            let snapshot = try repository.loadSnapshot()
            entities = snapshot.entities
            statements = snapshot.statements
            episodes = snapshot.episodes
            observeLogEntries = snapshot.observeLogEntries
            errorMessage = nil
            lastPromotionResultSummary = "已保存网页证据：\(draft.episode.title)"
            Task { await runBackgroundJobs() }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func submitChat() async {
        let prompt = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        await submitChat(prompt: prompt, clearComposer: true)
    }

    func submitChat(prompt rawPrompt: String, clearComposer: Bool = false) async {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isSubmittingChat else { return }
        if clearComposer { chatInput = "" }
        isSubmittingChat = true
        let optimisticTranscript = transcript
        let optimisticUserMessage = AgentMessage(role: .user, content: prompt)
        transcript = optimisticTranscript + [optimisticUserMessage]
        lastContext = nil
        lastPromptInspection = nil
        defer { isSubmittingChat = false }
        do {
            if var loopController = loopChatController {
                let previousMessageCount = loopController.transcript.count
                let response = try await loopController.submit(prompt)
                if let chatSessionRepository {
                    _ = try chatSessionRepository.saveSession(response.session, previousMessageCount: previousMessageCount)
                }
                loopChatController = loopController
                transcript = loopController.transcript
                agentEventTimeline = loopController.eventPresentations
                selectedChatSessionID = response.session.id
                legacyChatController = Self.makeLegacyChatController(runtimeFactory: agentRuntimeFactory, settingsRepository: llmSettingsRepository, session: response.session)
                if let chatSessionRepository {
                    chatSessions = try chatSessionRepository.loadRecentSessions()
                    latestChatSummary = try chatSessionRepository.loadLatestSummary(sessionID: response.session.id)
                }
                lastContext = nil
                lastPromptInspection = nil
            } else {
                var controller = legacyChatController
                let previousMessageCount = controller.transcript.count
                let sessionSummary: AgentSessionSummary?
                if let chatSessionRepository, let selectedChatSessionID {
                    let candidateSummary = try chatSessionRepository.loadLatestSummary(sessionID: selectedChatSessionID)
                    sessionSummary = AgentSessionSummaryPolicy().summaryForContext(candidateSummary, session: controller.agent.session)
                } else {
                    sessionSummary = nil
                }
                let response = try await controller.submit(prompt, sessionSummary: sessionSummary)
                if let chatSessionRepository {
                    _ = try chatSessionRepository.saveTurn(previousMessageCount: previousMessageCount, response: response)
                }
                legacyChatController = controller
                transcript = controller.transcript
                selectedChatSessionID = response.session.id
                if chatSessionRepository != nil { reloadChatSessions() }
                lastContext = response.context
                lastPromptInspection = response.promptInspection
            }
            errorMessage = nil
            Task { await runBackgroundJobs() }
        } catch {
            transcript = optimisticTranscript + [optimisticUserMessage]
            errorMessage = String(describing: error)
        }
    }

    func summarizeSelectedChatSession() async {
        guard let selectedChatSessionID, let chatSessionRepository else { return }
        isSummarizingChatSession = true
        defer { isSummarizingChatSession = false }
        do {
            let provider = Self.makeLLMProvider(settingsRepository: llmSettingsRepository)
            let summarizer = AgentSessionSummarizer(provider: provider)
            let summary = try await chatSessionRepository.summarizeSession(id: selectedChatSessionID, using: summarizer)
            latestChatSummary = summary
            chatSummaryMessage = latestChatSummaryRefreshState.successMessage
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }
}

struct AppShellView: View {
    @StateObject var viewModel: AppViewModel

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $viewModel.selection) { item in
                Text(item.rawValue).tag(item)
            }
            .navigationTitle("Connor")
        } detail: {
            VStack(spacing: 0) {
                SchemaHealthBanner(viewModel: viewModel)
                Divider()
                Group {
                    switch viewModel.selection ?? .agentChat {
                    case .entities:
                        GraphEntitiesView(entities: viewModel.entities, statements: viewModel.statements, episodes: viewModel.episodes)
                    case .search:
                        SearchView(viewModel: viewModel)
                    case .observeLog:
                        ObserveLogView(entries: viewModel.observeLogEntries)
                    case .agentChat:
                        AgentChatView(viewModel: viewModel)
                    case .promotionQueue:
                        PromotionQueueView(viewModel: viewModel)
                    case .graphWriteCandidates:
                        GraphWriteCandidateReviewView(viewModel: viewModel)
                    case .memoryChangeLog:
                        MemoryChangeLogView(viewModel: viewModel)
                    case .extractionDiagnostics:
                        GraphExtractionDiagnosticsView(viewModel: viewModel)
                    case .llmSettings:
                        LLMSettingsView(viewModel: viewModel)
                    }
                }
            }
            .frame(minWidth: 720, minHeight: 480)
        }
    }
}

struct SchemaHealthBanner: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 10) {
            if let report = viewModel.schemaHealthReport {
                Circle()
                    .fill(statusColor(report.status))
                    .frame(width: 8, height: 8)
                Text("图模型 v\(report.actualVersion)")
                    .font(.caption.weight(.semibold))
                Text(report.status.rawValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if report.status != .healthy {
                    Text(report.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
                Text("图模型版本未加载")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let databasePath = viewModel.databasePath {
                Text(databasePath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button("刷新") { viewModel.reloadSchemaHealthReport() }
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.06))
    }

    private func statusColor(_ status: GraphSchemaHealthReport.Status) -> Color {
        switch status {
        case .healthy: return .green
        case .warning: return .orange
        case .migrationRequired: return .red
        }
    }
}

struct GraphEntitiesView: View {
    let entities: [GraphEntity]
    let statements: [GraphStatement]
    let episodes: [GraphEpisodeV3]

    var body: some View {
        List {
            Section("实体") {
                ForEach(entities) { entity in
                    VStack(alignment: .leading) {
                        Text(entity.name).font(.headline)
                        Text("\(entity.entityKind.rawValue) · \(entity.status.rawValue)").font(.caption).foregroundStyle(.secondary)
                        if !entity.summary.isEmpty { Text(entity.summary).font(.subheadline) }
                    }
                }
            }
            Section("陈述") {
                ForEach(statements) { statement in
                    VStack(alignment: .leading) {
                        Text(statement.predicate.rawValue).font(.headline)
                        Text("\(statement.subjectEntityID) → \(statement.objectEntityID)").font(.caption).foregroundStyle(.secondary)
                        Text(statement.statementText).font(.subheadline)
                    }
                }
            }
            Section("Episodes") {
                ForEach(episodes) { episode in
                    VStack(alignment: .leading) {
                        Text(episode.title).font(.headline)
                        Text("\(episode.sourceType.rawValue) · \(episode.status.rawValue)").font(.caption).foregroundStyle(.secondary)
                        Text(episode.content).font(.subheadline).lineLimit(3)
                    }
                }
            }
        }
        .navigationTitle("图谱")
    }
}

struct SearchView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("搜索图谱和观察日志", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await viewModel.runSearch() } }
                Button("搜索") { Task { await viewModel.runSearch() } }
            }
            List(viewModel.searchResults) { result in
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.id).font(.headline)
                    Text(result.ownerType.rawValue).font(.caption).foregroundStyle(.secondary)
                    Text(result.retrievalMethod).font(.subheadline)
                    Text(result.text).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .navigationTitle("搜索")
    }
}

struct ObserveLogView: View {
    let entries: [ObserveLogEntry]

    var body: some View {
        List(entries) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.content).font(.headline)
                Text("\(entry.kind.rawValue) · \(entry.status.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("过期时间：\(entry.expiresAt.formatted())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("观察日志")
    }
}

struct PromotionQueueView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("刷新") { viewModel.reloadPromotionCandidates() }
                if let summary = viewModel.lastPromotionResultSummary {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
            }

            if viewModel.promotionCandidates.isEmpty {
                Text("暂无可提升候选项。")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(viewModel.promotionCandidates) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(entry.kind.rawValue).font(.headline)
                            Spacer()
                            Text(entry.status.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(entry.content)
                        if !entry.normalizedSummary.isEmpty {
                            Text(entry.normalizedSummary).font(.subheadline).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 12) {
                            if let workObjectID = entry.workObjectID {
                                Text("工作对象：\(workObjectID)")
                            }
                            Text("重要性：\(entry.importance, format: .number.precision(.fractionLength(2)))")
                            Text("置信度：\(entry.confidence, format: .number.precision(.fractionLength(2)))")
                            Text("过期时间：\(entry.expiresAt.formatted())")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        HStack {
                            Button("提升") { viewModel.promote(entry) }
                            Button("忽略") { viewModel.dismissPromotionCandidate(entry) }
                            Button("置顶 30 天") { viewModel.pinPromotionCandidate(entry) }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .padding()
        .navigationTitle("提升队列")
        .onAppear { viewModel.reloadPromotionCandidates() }
    }
}

struct GraphWriteCandidateReviewView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("刷新") { viewModel.reloadGraphWriteCandidates() }
                if let summary = viewModel.lastGraphWriteCandidateResultSummary {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("propose → validate → review → commit → audit")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if viewModel.graphWriteCandidates.isEmpty {
                Text("暂无图谱写入候选。Agent 只能创建候选，不会直接污染长期图谱。")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(viewModel.graphWriteCandidates) { candidate in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(candidate.kind.rawValue)
                                .font(.headline)
                            Text(candidate.status.rawValue)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(statusColor(candidate.status).opacity(0.15), in: Capsule())
                                .foregroundStyle(statusColor(candidate.status))
                            Spacer()
                            Text(candidate.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(candidate.rationale)
                            .font(.subheadline)
                            .textSelection(.enabled)

                        HStack(spacing: 12) {
                            Label("confidence \(candidate.confidence, specifier: "%.2f")", systemImage: "gauge.medium")
                            Label("run \(candidate.proposedByRunID)", systemImage: "play.circle")
                            if let toolCallID = candidate.proposedByToolCallID {
                                Label("tool \(toolCallID)", systemImage: "wrench.and.screwdriver")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        DisclosureGroup("候选 payload JSON") {
                            Text(candidate.payloadJSON)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }

                        if !candidate.validationErrors.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("验证/审阅记录")
                                    .font(.caption.weight(.semibold))
                                ForEach(candidate.validationErrors, id: \.self) { error in
                                    Text("• \(error)")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }

                        let auditItems = viewModel.graphWriteCandidateAudits[candidate.id] ?? []
                        DisclosureGroup("审计时间线（\(auditItems.count)）") {
                            if auditItems.isEmpty {
                                Text("暂无审计事件。执行验证、批准、治理提交或拒绝后会生成审计轨迹。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(auditItems) { item in
                                        HStack(alignment: .top, spacing: 8) {
                                            Circle()
                                                .fill(auditColor(item.severity))
                                                .frame(width: 8, height: 8)
                                                .padding(.top, 5)
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(alignment: .firstTextBaseline) {
                                                    Text(item.title)
                                                        .font(.caption.weight(.semibold))
                                                    Text(item.createdAt.formatted(date: .omitted, time: .standard))
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                    Text(item.actor)
                                                        .font(.caption2.monospaced())
                                                        .foregroundStyle(.secondary)
                                                }
                                                Text(item.detail)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .textSelection(.enabled)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        HStack {
                            Button("验证") { Task { await viewModel.validateGraphWriteCandidate(candidate) } }
                                .disabled(candidate.status == .committed || candidate.status == .rejected)
                            Button("批准") { Task { await viewModel.approveGraphWriteCandidate(candidate) } }
                                .disabled(candidate.status == .approved || candidate.status == .committed || candidate.status == .rejected)
                            Button("治理提交") { Task { await viewModel.commitGraphWriteCandidate(candidate) } }
                                .disabled(candidate.status != .approved)
                            Button("拒绝", role: .destructive) { Task { await viewModel.rejectGraphWriteCandidate(candidate) } }
                                .disabled(candidate.status == .committed || candidate.status == .rejected)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .padding()
        .navigationTitle("写入候选")
        .onAppear { viewModel.reloadGraphWriteCandidates() }
    }

    private func statusColor(_ status: GraphWriteCandidateStatus) -> Color {
        switch status {
        case .pendingValidation, .pendingReview: return .orange
        case .validationFailed, .rejected: return .red
        case .approved: return .blue
        case .committed: return .green
        case .superseded: return .secondary
        }
    }

    private func auditColor(_ severity: GraphWriteCandidateAuditSeverity) -> Color {
        switch severity {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

struct MemoryChangeLogView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("刷新") { viewModel.reloadMemoryChangeLog() }
                Spacer()
                Text("what changed · why · source trace · reversible later")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if viewModel.memoryChangeLogEntries.isEmpty {
                Text("暂无记忆变更记录。后台 extraction/admission 运行后会在这里形成可审计 change log。")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(viewModel.memoryChangeLogEntries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.title)
                                .font(.headline)
                            Text(entry.action.rawValue)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(changeLogColor(entry.action).opacity(0.15), in: Capsule())
                                .foregroundStyle(changeLogColor(entry.action))
                            Spacer()
                            Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(entry.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 6)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .padding()
        .navigationTitle("记忆变更")
        .onAppear { viewModel.reloadMemoryChangeLog() }
    }

    private func changeLogColor(_ action: GraphMemoryChangeLogAction) -> Color {
        switch action {
        case .extractionCommitted: return .green
        case .extractionHeld, .extractionAskUser: return .orange
        case .extractionDiscarded: return .secondary
        case .extractionFailed: return .red
        case .replayDryRun: return .blue
        case .manualInvalidation: return .purple
        }
    }
}

struct GraphExtractionDiagnosticsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("刷新") { viewModel.reloadGraphExtractionTraces() }
                Spacer()
                Text("extract → validate → admit → auto-commit / hold / ask")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if !viewModel.admissionHoldQueueItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("系统待诊断队列")
                        .font(.headline)
                    Text("这些是后台自愈队列，不是默认用户逐条审核。系统可用于 replay、grounding、merge 或必要时询问用户。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let summary = viewModel.lastAdmissionHoldQueueActionSummary {
                        Text(summary)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(8)
                            .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    ForEach(viewModel.admissionHoldQueueItems) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            HStack(spacing: 8) {
                                Button("检查证据") { viewModel.inspectAdmissionHoldQueueItemEvidence(item) }
                                Button("重跑提取") { viewModel.rerunAdmissionHoldQueueItem(item) }
                                Button("批准提交") { viewModel.approveAdmissionHoldQueueItem(item) }
                                Button("Dismiss", role: .destructive) { viewModel.rejectAdmissionHoldQueueItem(item) }
                            }
                            .font(.caption)
                        }
                        .padding(8)
                        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                Divider()
            }

            if viewModel.graphExtractionTraces.isEmpty {
                Text("暂无记忆准入轨迹。后台 extraction job 运行后会记录 auto-commit、hold、ask 或 failed 的原因。")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(viewModel.graphExtractionTraces) { trace in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(trace.title)
                                .font(.headline)
                            Text(trace.admissionAction?.rawValue ?? "no admission")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(traceOutcomeColor(trace.outcome).opacity(0.15), in: Capsule())
                                .foregroundStyle(traceOutcomeColor(trace.outcome))
                            Spacer()
                            Text(trace.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(trace.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        if let payloadText = tracePayloadText(trace) {
                            DisclosureGroup("trace payload") {
                                Text(payloadText)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .padding()
        .navigationTitle("记忆准入")
        .onAppear { viewModel.reloadGraphExtractionTraces() }
    }

    private func tracePayloadText(_ trace: AppGraphExtractionTracePresentation) -> String? {
        var sections: [String] = []
        if let decoderErrorKind = trace.decoderErrorKind {
            sections.append("decoder_error_kind:\n\(decoderErrorKind)")
        }
        if let decoderErrorMessage = trace.decoderErrorMessage {
            sections.append("decoder_error_message:\n\(decoderErrorMessage)")
        }
        if let normalizedJSON = trace.normalizedJSON {
            sections.append("normalized_json:\n\(normalizedJSON)")
        }
        if let rawResponseJSON = trace.rawResponseJSON {
            sections.append("raw_response_json:\n\(rawResponseJSON)")
        }
        if let promptText = trace.promptText {
            sections.append("prompt_text:\n\(promptText)")
        }
        guard !sections.isEmpty else { return nil }
        return sections.joined(separator: "\n\n---\n\n")
    }

    private func traceOutcomeColor(_ outcome: GraphExtractionTraceOutcome) -> Color {
        switch outcome {
        case .committed: return .green
        case .held: return .orange
        case .askUser: return .blue
        case .discarded: return .secondary
        case .failed: return .red
        }
    }
}

struct LLMSettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Picker("模型提供方", selection: $viewModel.llmProviderMode) {
                Text("模拟模式").tag(AppLLMProviderMode.stub)
                Text("OpenAI 兼容").tag(AppLLMProviderMode.openAICompatible)
            }
            .pickerStyle(.segmented)

            TextField("Base URL", text: $viewModel.llmBaseURLString)
                .textFieldStyle(.roundedBorder)
            TextField("模型", text: $viewModel.llmModel)
                .textFieldStyle(.roundedBorder)
            SecureField("API Key", text: $viewModel.llmAPIKeyInput)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("保存设置") { viewModel.saveLLMSettings() }
                Button("清除 API Key") { viewModel.clearLLMAPIKey() }
                Button("重新加载") { viewModel.loadLLMSettings() }
                Button(viewModel.isTestingLLMConnection ? "测试中…" : "测试连接") {
                    Task { await viewModel.testLLMConnection() }
                }
                .disabled(viewModel.isTestingLLMConnection)
            }

            Text(viewModel.llmHasAPIKey ? "API Key：已存入钥匙串" : "API Key：尚未保存")
                .foregroundStyle(viewModel.llmHasAPIKey ? .green : .secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Label("安全提示：API Key 会保存到 macOS 钥匙串", systemImage: "lock.shield")
                        .font(.caption.weight(.semibold))
                    Text("为保证安全，Connor Graph Agent 会将 API Key 存入 macOS 钥匙串，而不是以明文写入应用设置或项目文件。")
                    Text("当 macOS 请求钥匙串访问权限时，请为当前已签名的应用构建选择“始终允许”，以避免重复弹窗。")
                    Text("如果每次 Xcode 重新构建后仍然弹窗，请打开 app target 的 Signing & Capabilities，并确认 Team 设置为 诗闻 段 (Personal Team)。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let message = viewModel.llmSettingsMessage {
                Text(message).foregroundStyle(.secondary)
            }
            if let message = viewModel.llmHealthCheckMessage {
                Text(message).foregroundStyle(message.contains("OK") || message.contains("available") ? .green : .secondary)
            }
            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .padding()
        .navigationTitle("模型设置")
    }
}
