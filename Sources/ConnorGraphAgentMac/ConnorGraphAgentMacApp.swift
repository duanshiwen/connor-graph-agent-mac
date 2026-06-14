import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

@main
struct ConnorGraphAgentMacApp: App {
    @StateObject private var viewModel = AppViewModel.live()

    var body: some Scene {
        WindowGroup {
            AppShellView(viewModel: viewModel)
        }
        .commands {
            CommandMenu("康纳同学") {
                Button("打开命令面板") {
                    viewModel.isCommandPalettePresented = true
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                ForEach(ConnorNativeShellPresentation.default.commands) { command in
                    Button(command.title) {
                        viewModel.performShellCommand(command.id)
                    }
                    .keyboardShortcut(keyEquivalent(for: command), modifiers: .command)
                }
            }
        }
    }
}

private func keyEquivalent(for command: ConnorNativeShellCommand) -> KeyEquivalent {
    switch command.id {
    case .newSession: "n"
    case .toggleBrowser: "b"
    case .openGraphMemoryReview: "2"
    case .openApprovals: "3"
    case .openSources: "4"
    case .openSkills: "5"
    case .openAutomation: "6"
    case .openLocalAutomationSurface: "7"
    case .checkCommercialReadiness: "r"
    case .openSettings: ","
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var selection: SidebarItem? = .agentChat
    @Published var query: String = "记忆"
    @Published var searchResults: [GraphSearchHit] = []
    @Published var chatInput: String = ""
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
    @Published var pendingApprovals: [AgentPendingApproval] = []
    @Published var graphExtractionTraces: [AppGraphExtractionTracePresentation] = []
    @Published var admissionHoldQueueItems: [AppGraphAdmissionHoldQueuePresentation] = []
    @Published var memoryChangeLogEntries: [AppGraphMemoryChangeLogPresentation] = []
    @Published var lastPromotionResultSummary: String?
    @Published var lastGraphWriteCandidateResultSummary: String?
    @Published var lastPendingApprovalResultSummary: String?
    @Published var lastAdmissionHoldQueueActionSummary: String?
    @Published var llmProviderMode: AppLLMProviderMode = .openAICompatible
    @Published var llmBaseURLString: String = AppLLMSettings.default.baseURLString
    @Published var llmModel: String = AppLLMSettings.default.model
    @Published var llmSelectedModel: String = AppLLMSettings.default.effectiveModel
    @Published var llmAPIKeyInput: String = ""
    @Published var llmHasAPIKey: Bool = false
    @Published var sidecarExecutablePath: String = ""
    @Published var sidecarArguments: String = ""
    @Published var sidecarWorkingDirectoryPath: String = ""
    @Published var sidecarPermissionMode: AgentPermissionMode = .readOnly
    @Published var llmSettingsMessage: String?
    @Published var llmHealthCheckMessage: String?
    @Published var isTestingLLMConnection: Bool = false
    @Published var llmModelConnections: [AppLLMModelConnection] = []
    @Published var isLoadingLLMModelConnections: Bool = false
    @Published var chatSessions: [AgentSession] = []
    @Published var selectedChatSessionID: String?
    @Published var sessionListFilter: AgentSessionListFilter = .all
    @Published var sessionSearchQuery: String = ""
    @Published var governanceConfig: AppSessionGovernanceConfig = .default
    @Published var productOSRegistry: ProductOSRegistrySnapshot = .default
    @Published var automationConfig: ProductOSAutomationConfig = .default
    @Published var automationTriggerRecords: [ProductOSAutomationTriggerRecord] = []
    @Published var automationExecutionHistory: [ProductOSAutomationExecutionHistoryRecord] = []
    @Published var sourceRuntimeConfigurations: [MCPSourceRuntimeConfiguration] = []
    @Published var skillRuntimeDefinitions: [SkillRuntimeDefinition] = []
    @Published var sidecarRuntimeDiagnostics: [ClaudeSDKSidecarRuntimeDiagnostics] = []
    @Published var commercialReleaseGateResult: CommercialReadinessReleaseGateResult?
    @Published var productOSRegistryMessage: String?
    @Published var selectedSessionArtifactDirectories: AgentSessionArtifactDirectories?
    @Published var latestChatSummary: AgentSessionSummary?
    @Published var isSummarizingChatSession: Bool = false
    @Published var chatSummaryMessage: String?
    @Published var isSubmittingChat: Bool = false
    @Published var agentEventTimeline: [AgentEventPresentation] = []
    @Published var isBrowserVisible: Bool = false
    @Published var browserWorkspaceSessionID: String?
    @Published var browserTargetURLString: String = BrowserBuiltInPage.blankURLString
    @Published var sessionStateSnapshotsBySessionID: [String: AppSessionStateSnapshot] = [:]
    @Published var sessionRecordsBySessionID: [String: [AppSessionRecord]] = [:]
    @Published var browserWorkspaceSnapshotsBySessionID: [String: AppBrowserStateSnapshot] = [:]
    @Published var browserAssistedTasksByID: [UUID: BrowserAssistedTaskState] = [:]
    @Published var isCommandPalettePresented: Bool = false
    @Published var selectedSettingsSection: ConnorSettingsSection = .app
    @Published var desktopNotificationsEnabled: Bool = true
    @Published var keepScreenAwake: Bool = false
    @Published var internalBrowserEnabled: Bool = true
    @Published var httpProxyEnabled: Bool = false
    @Published var httpProxyURLString: String = ""
    @Published var appearanceMode: ConnorAppearanceMode = .system
    @Published var showProviderIcons: Bool = true
    @Published var richToolDescriptionsEnabled: Bool = true
    @Published var composerSendShortcut: String = "return"
    @Published var spellCheckEnabled: Bool = true
    @Published var autoSaveDraftsEnabled: Bool = true
    @Published var defaultPermissionMode: AgentPermissionMode = .askToWrite
    @Published var requireApprovalForNetwork: Bool = true
    @Published var requireApprovalForShell: Bool = true
    @Published var defaultWorkingDirectoryPath: String = ""
    @Published var workspaceRoots: [WorkspaceRootDraft] = []
    @Published var workspaceRootPathInput: String = ""
    @Published var userDisplayName: String = "诗闻"
    @Published var userTimezone: String = "Asia/Shanghai"
    @Published var userCity: String = "杭州"
    @Published var userCountry: String = "中国"
    @Published var userPreferenceNotes: String = ""
    @Published var appSettingsMessage: String?

    private var repository: AppGraphRepository?
    private var promotionRepository: AppPromotionQueueRepository?
    private var graphWriteCandidateRepository: AppGraphWriteCandidateRepository?
    private var pendingApprovalRepository: AppAgentPendingApprovalRepository?
    private var graphExtractionTraceRepository: AppGraphExtractionTraceRepository?
    private var admissionHoldQueueRepository: AppGraphAdmissionHoldQueueRepository?
    private var memoryChangeLogRepository: AppGraphMemoryChangeLogRepository?
    private var chatSessionRepository: AppChatSessionRepository?
    private var productOSRegistryRepository: AppProductOSRegistryRepository?
    private var automationRepository: AppProductOSAutomationRepository?
    private var sourceRuntimeRepository: AppMCPSourceRuntimeRepository?
    private var skillRuntimeRepository: AppSkillRuntimeRepository?
    private var storagePaths: AppStoragePaths?
    private var runtimeSettingsRepository: AppRuntimeSettingsRepository?
    private var llmSettingsRepository: AppLLMSettingsRepository
    private var llmProviderHealthChecker: AppLLMProviderHealthChecker
    private var agentRuntimeFactory: AppGraphAgentRuntimeFactory?
    private var hybridSearchService: (any GraphHybridSearchService)?
    private var backgroundJobRunner: AppGraphBackgroundJobRunner?
    private var isRunningBackgroundJobs: Bool = false
    // Product chat path: NativeSessionManager owns Connor session state and talks to replaceable AgentBackend implementations.
    // fallbackChatSession is UI-only for demo/no-runtime states.
    private var fallbackChatSession: AgentSession
    private var nativeSessionManager: NativeSessionManager?
    private var submittingChatSessionID: String?
    private var activeChatRunID: String?
    private var pendingChatCancellationReasonsBySessionID: [String: String] = [:]
    private var agentEventTimelinesBySessionID: [String: [AgentEventPresentation]] = [:]
    private var agentEventTimelinesByProcessKey: [String: [AgentEventPresentation]] = [:]
    private var browserWorkspaceSessionBinding = BrowserWorkspaceSessionBinding()
    private var chatSessionWorkspaceModes = ChatSessionWorkspaceModeStore()

    private var activeChatSession: AgentSession {
        nativeSessionManager?.session ?? fallbackChatSession
    }

    private var activeChatTranscript: [AgentMessage] {
        nativeSessionManager?.session.messages ?? fallbackChatSession.messages
    }

    var activeChatPendingApprovals: [AgentPendingApproval] {
        let activeSessionID = activeChatSession.id
        return pendingApprovals.filter { $0.sessionID == activeSessionID }
    }

    func deferViewUpdate(_ operation: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000)
            operation()
        }
    }

    func navigate(to item: ConnorNativeShellItem) {
        deferViewUpdate { [weak self] in
            self?.applyNavigation(to: item)
        }
    }

    private func applyNavigation(to item: ConnorNativeShellItem) {
        switch item {
        case .home:
            isBrowserVisible = false
            selection = .agentChat
        case .agentChat:
            isBrowserVisible = false
            selection = .agentChat
        case .browserWorkspace:
            showBrowserWorkspace()
        case .graphMemory:
            selection = .graphWriteCandidates
        case .search:
            selection = .search
        case .graphEntities:
            selection = .entities
        case .approvals:
            selection = .pendingApprovals
        case .automation, .localAutomationSurface:
            selection = .automation
        case .productOS:
            selection = .productOS
        case .sources:
            selection = .sources
        case .skills:
            selection = .skills
        case .settings:
            selection = .llmSettings
        }
    }

    func performShellCommand(_ commandID: ConnorNativeShellCommandID) {
        switch commandID {
        case .newSession:
            newChatSession()
            navigate(to: .agentChat)
        case .toggleBrowser:
            toggleBrowserWorkspaceVisibility()
        case .checkCommercialReadiness:
            runCommercialReadinessReleaseGate()
        case .openGraphMemoryReview, .openApprovals, .openSources, .openSkills, .openAutomation, .openLocalAutomationSurface, .openSettings:
            if let command = ConnorNativeShellPresentation.default.command(for: commandID) {
                navigate(to: command.target)
            }
        }
    }

    func openURLInCurrentChatBrowser(_ url: URL) {
        let sessionID = selectedChatSessionID ?? activeChatSession.id
        let urlString = url.absoluteString
        let currentSnapshot = browserWorkspaceSnapshotsBySessionID[sessionID] ?? AppBrowserStateSnapshot()
        let plannedSnapshot = BrowserExternalOpenPlanner().open(urlString: urlString, in: currentSnapshot)
        browserTargetURLString = urlString
        saveBrowserWorkspaceSnapshot(plannedSnapshot, for: sessionID)
        showBrowserWorkspace()
    }

    func openProjectGitHubHelp() {
        guard let url = URL(string: "https://github.com/duanshiwen/connor-graph-agent-mac") else { return }
        openURLInCurrentChatBrowser(url)
    }

    @discardableResult
    func startBrowserAssistedSearch(urlString: String, title: String, revealImmediately: Bool = false) -> BrowserAssistedTaskState {
        let sessionID = selectedChatSessionID ?? activeChatSession.id
        let currentSnapshot = browserWorkspaceSnapshotsBySessionID[sessionID] ?? AppBrowserStateSnapshot()
        let request = BrowserAssistedTaskRequest(
            kind: .search,
            sessionID: sessionID,
            urlString: urlString,
            title: title,
            visibility: revealImmediately ? .foreground : .background
        )
        let plan = BrowserAssistedTaskPlanner().start(request, in: currentSnapshot)
        browserAssistedTasksByID[plan.task.id] = plan.task
        browserTargetURLString = urlString
        saveBrowserWorkspaceSnapshot(plan.snapshot, for: sessionID)
        if plan.shouldRevealBrowser { showBrowserWorkspace(for: sessionID) }
        return plan.task
    }

    func revealBrowserAssistedTask(_ taskID: UUID, reason: String) {
        guard let task = browserAssistedTasksByID[taskID] else { return }
        let updated = BrowserAssistedTaskPlanner().requireUserIntervention(task, reason: reason)
        browserAssistedTasksByID[taskID] = updated
        focusBrowserTab(updated.tabID, in: updated.sessionID, urlString: updated.urlString)
        showBrowserWorkspace(for: updated.sessionID)
    }

    func completeBrowserAssistedTask(_ taskID: UUID, message: String) {
        guard let task = browserAssistedTasksByID[taskID] else { return }
        browserAssistedTasksByID[taskID] = BrowserAssistedTaskPlanner().complete(task, message: message)
    }

    func failBrowserAssistedTask(_ taskID: UUID, message: String) {
        guard let task = browserAssistedTasksByID[taskID] else { return }
        browserAssistedTasksByID[taskID] = BrowserAssistedTaskPlanner().fail(task, message: message)
    }

    private func focusBrowserTab(_ tabID: UUID, in sessionID: String, urlString: String) {
        var snapshot = browserWorkspaceSnapshotsBySessionID[sessionID] ?? AppBrowserStateSnapshot()
        if snapshot.tabs.contains(where: { $0.id == tabID }) {
            snapshot.selectedTabID = tabID
        } else {
            snapshot = BrowserExternalOpenPlanner().open(urlString: urlString, in: snapshot)
        }
        browserTargetURLString = urlString
        saveBrowserWorkspaceSnapshot(snapshot, for: sessionID)
    }

    func showBrowserWorkspace() {
        let sessionID = selectedChatSessionID ?? activeChatSession.id
        showBrowserWorkspace(for: sessionID)
    }

    private func showBrowserWorkspace(for sessionID: String) {
        browserWorkspaceSessionBinding.bindBrowserWorkspace(to: sessionID)
        browserWorkspaceSessionID = browserWorkspaceSessionBinding.boundSessionID
        isBrowserVisible = true
        selection = .agentChat
        if selectedChatSessionID != sessionID {
            selectChatSession(sessionID)
        }
        rememberWorkspaceMode(.browser, for: sessionID)
    }

    func returnFromBrowserWorkspace() {
        let targetSessionID = browserWorkspaceSessionBinding.sessionIDForReturningFromBrowser(
            currentSelectedSessionID: selectedChatSessionID ?? activeChatSession.id
        )
        if let targetSessionID, targetSessionID != selectedChatSessionID {
            selectChatSession(targetSessionID)
        }
        browserWorkspaceSessionID = targetSessionID
        isBrowserVisible = false
        selection = .agentChat
        rememberWorkspaceMode(.conversation, for: targetSessionID)
    }

    func toggleBrowserWorkspaceVisibility() {
        if isBrowserVisible {
            returnFromBrowserWorkspace()
        } else {
            showBrowserWorkspace()
        }
    }

    func openDeepLink(_ url: URL) {
        do {
            let resolution = try ConnorDeepLinkNavigator().resolve(url)
            navigate(to: resolution.item)
            errorMessage = nil
        } catch {
            errorMessage = "不支持的康纳同学链接：\(url.absoluteString)"
        }
    }

    var commercialReadinessDashboard: CommercialReadinessDashboard {
        let input = CommercialReadinessSnapshotBuilder().build(
            sessions: chatSessions.isEmpty ? [activeChatSession] : chatSessions,
            governanceConfig: governanceConfig,
            artifactDirectoriesReady: storagePaths != nil,
            sidecarRecord: selectedSidecarRuntimeDiagnostics?.record,
            sidecarHealthStatus: selectedSidecarRuntimeDiagnostics?.health.rawValue,
            sources: sourceRuntimeConfigurations,
            skills: skillRuntimeDefinitions,
            automationConfig: automationConfig,
            graphMemoryDashboard: graphMemoryDashboardPresentation,
            shell: .default,
            settingsPanelsReady: true
        )
        return CommercialReadinessGate().evaluate(input)
    }

    private var selectedSidecarRuntimeDiagnostics: ClaudeSDKSidecarRuntimeDiagnostics? {
        let activeID = activeChatSession.id
        return sidecarRuntimeDiagnostics.first { $0.record.connorSessionID == activeID } ?? sidecarRuntimeDiagnostics.first
    }

    private var graphMemoryDashboardPresentation: GraphMemoryDashboard {
        let pendingCandidates = graphWriteCandidates.filter { $0.status == .pendingReview || $0.status == .validationFailed }
        let memoryCards: [GraphMemoryProductCard] = admissionHoldQueueItems.map { item in
            GraphMemoryProductCard(
                id: item.id,
                kind: .admissionHold,
                title: item.title,
                detail: item.detail,
                severity: .needsReview,
                recommendedActions: item.recommendedActions.map(\.rawValue),
                createdAt: item.createdAt
            )
        } + pendingCandidates.map { candidate in
            GraphMemoryProductCard(
                id: candidate.id,
                kind: .writeCandidate,
                title: "\(candidate.kind.rawValue) · \(candidate.status.rawValue)",
                detail: candidate.rationale,
                severity: candidate.status == .validationFailed ? .error : .needsReview,
                sourceIDs: candidate.sourceEpisodeIDs,
                createdAt: candidate.createdAt
            )
        } + memoryChangeLogEntries.prefix(5).map { entry in
            GraphMemoryProductCard(
                id: entry.id,
                kind: .changeLog,
                title: entry.title,
                detail: entry.detail,
                severity: entry.action == .extractionCommitted ? .success : .info,
                createdAt: entry.createdAt
            )
        }
        return GraphMemoryDashboard(
            summary: GraphMemoryDashboardSummary(
                pendingCandidateCount: pendingCandidates.count,
                openHoldCount: admissionHoldQueueItems.count,
                recentChangeCount: memoryChangeLogEntries.count
            ),
            cards: memoryCards
        )
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
        storagePaths: AppStoragePaths? = nil,
        governanceConfig: AppSessionGovernanceConfig = .default,
        productOSRegistry: ProductOSRegistrySnapshot = .default,
        automationConfig: ProductOSAutomationConfig = .default,
        llmSettingsRepository: AppLLMSettingsRepository = AppLLMSettingsRepository()
    ) {
        self.entities = entities
        self.statements = statements
        self.episodes = episodes
        self.observeLogEntries = observeLogEntries
        self.repository = repository
        self.storagePaths = storagePaths
        self.governanceConfig = governanceConfig
        self.productOSRegistry = productOSRegistry
        self.automationConfig = automationConfig
        self.llmSettingsRepository = llmSettingsRepository
        self.llmProviderHealthChecker = AppLLMProviderHealthChecker(settingsRepository: llmSettingsRepository)
        if let storagePaths {
            self.productOSRegistryRepository = AppProductOSRegistryRepository(storagePaths: storagePaths)
            self.automationRepository = AppProductOSAutomationRepository(storagePaths: storagePaths)
            self.sourceRuntimeRepository = AppMCPSourceRuntimeRepository(storagePaths: storagePaths)
            self.skillRuntimeRepository = AppSkillRuntimeRepository(storagePaths: storagePaths)
        }
        if let repository {
            self.promotionRepository = AppPromotionQueueRepository(store: repository.store)
            self.graphWriteCandidateRepository = AppGraphWriteCandidateRepository(store: repository.store)
            self.pendingApprovalRepository = AppAgentPendingApprovalRepository(store: repository.store)
            self.graphExtractionTraceRepository = AppGraphExtractionTraceRepository(store: repository.store)
            self.admissionHoldQueueRepository = AppGraphAdmissionHoldQueueRepository(store: repository.store)
            self.memoryChangeLogRepository = AppGraphMemoryChangeLogRepository(store: repository.store)
            self.chatSessionRepository = AppChatSessionRepository(store: repository.store, storagePaths: storagePaths, governanceConfig: governanceConfig)
            if let storagePaths {
                self.runtimeSettingsRepository = AppRuntimeSettingsRepository(configDirectory: storagePaths.configDirectory)
            }
            self.hybridSearchService = SQLiteGraphHybridSearchService(store: repository.store)
            self.backgroundJobRunner = AppGraphBackgroundJobRunner(store: repository.store, settingsRepository: llmSettingsRepository)
        }
        self.databasePath = databasePath
        let initialSession = AgentSession(id: "app-session")
        self.fallbackChatSession = initialSession
        if let repository {
            self.agentRuntimeFactory = AppGraphAgentRuntimeFactory(
                store: repository.store,
                settingsRepository: llmSettingsRepository,
                browserAssistedSearchHandler: { [weak self] request in
                    await MainActor.run {
                        guard let self else { return nil }
                        let state = self.startBrowserAssistedSearch(
                            urlString: request.urlString,
                            title: request.title,
                            revealImmediately: request.revealImmediately
                        )
                        return BrowserAssistedSearchResult(
                            taskID: state.id.uuidString,
                            sessionID: state.sessionID,
                            tabID: state.tabID.uuidString,
                            urlString: state.urlString,
                            status: state.status.rawValue
                        )
                    }
                }
            )
        }
        self.nativeSessionManager = agentRuntimeFactory?.makeNativeSessionManager(session: initialSession)
        self.searchResults = []
        loadLLMSettings()
        Task { await reloadLLMModelConnections() }
        loadRuntimeSettings()
        reloadProductOSRegistry()
        reloadAutomationConfig()
        reloadAutomationExecutionHistory()
        reloadSourceRuntimeConfigurations()
        reloadSkillRuntimeDefinitions()
        reloadSidecarRuntimeDiagnostics()
        reloadChatSessions()
        reloadSchemaHealthReport()
        reloadGraphExtractionTraces()
        reloadMemoryChangeLog()
    }

    static func live() -> AppViewModel {
        do {
            let paths = try AppStoragePaths.live()
            let repository = try AppGraphRepository.bootstrap(paths: paths)
            let governanceConfig = try AppSessionGovernanceConfigRepository(configDirectory: paths.configDirectory).loadOrCreateDefault()
            let productOSRegistry = try AppProductOSRegistryRepository(storagePaths: paths).loadOrCreateDefault()
            let automationConfig = try AppProductOSAutomationRepository(storagePaths: paths).loadOrCreateDefault(governanceConfig: governanceConfig)
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
                databasePath: paths.databaseURL.path,
                storagePaths: paths,
                governanceConfig: governanceConfig,
                productOSRegistry: productOSRegistry,
                automationConfig: automationConfig
            )
            viewModel.reloadPromotionCandidates()
            viewModel.reloadGraphWriteCandidates()
            viewModel.reloadPendingApprovals()
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
            name: "康纳同学",
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

    private static func makeLLMProvider(settingsRepository: AppLLMSettingsRepository) -> AnyLLMProvider {
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

    private func apply(snapshot: GraphStoreSnapshot) {
        entities = snapshot.entities
        statements = snapshot.statements
        episodes = snapshot.episodes
        observeLogEntries = snapshot.observeLogEntries
        let session = activeChatSession
        fallbackChatSession = session
        nativeSessionManager = makeNativeSessionManager(for: session)
        Task { await runSearch() }
        reloadPromotionCandidates()
        reloadGraphWriteCandidates()
        reloadPendingApprovals()
    }

    func runBackgroundJobs() async {
        guard !isRunningBackgroundJobs else { return }
        guard let backgroundJobRunner, let repository else { return }
        isRunningBackgroundJobs = true
        defer { isRunningBackgroundJobs = false }
        do {
            _ = try await backgroundJobRunner.runAvailable(limit: 5)
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

    func reloadProductOSRegistry() {
        do {
            if let productOSRegistryRepository {
                productOSRegistry = try productOSRegistryRepository.loadOrCreateDefault()
                productOSRegistryMessage = "Product OS 注册表已从康纳同学 Home 加载。"
            }
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func reloadAutomationConfig() {
        do {
            if let automationRepository {
                automationConfig = try automationRepository.loadOrCreateDefault(governanceConfig: governanceConfig)
                automationTriggerRecords = try automationRepository.loadRecentTriggerRecords()
            }
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func reloadAutomationExecutionHistory() {
        do {
            automationExecutionHistory = try automationRepository?.loadRecentExecutionHistory() ?? []
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func reloadSourceRuntimeConfigurations() {
        do {
            sourceRuntimeConfigurations = try sourceRuntimeRepository?.list() ?? []
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func reloadSkillRuntimeDefinitions() {
        do {
            skillRuntimeDefinitions = try skillRuntimeRepository?.list() ?? []
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func reloadSidecarRuntimeDiagnostics() {
        do {
            if let storagePaths {
                sidecarRuntimeDiagnostics = try AppClaudeSDKSidecarRuntimeStore(configDirectory: storagePaths.configDirectory).loadDiagnostics()
            } else {
                sidecarRuntimeDiagnostics = []
            }
            errorMessage = nil
        } catch {
            sidecarRuntimeDiagnostics = []
            errorMessage = String(describing: error)
        }
    }

    func runCommercialReadinessReleaseGate() {
        reloadSidecarRuntimeDiagnostics()
        let result = CommercialReadinessReleaseGate().evaluate(commercialReadinessDashboard)
        commercialReleaseGateResult = result
        productOSRegistryMessage = result.summary
        navigate(to: .productOS)
    }

    func setAutomationRuleEnabled(id: String, isEnabled: Bool) {
        do {
            guard let automationRepository else { return }
            automationConfig = try automationRepository.setRuleEnabled(id: id, isEnabled: isEnabled, governanceConfig: governanceConfig)
            automationTriggerRecords = try automationRepository.loadRecentTriggerRecords()
            productOSRegistryMessage = "Automation rule \(id) is now \(isEnabled ? "enabled" : "disabled")."
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func evaluateAutomation(_ context: ProductOSAutomationEventContext) {
        do {
            guard let automationRepository else { return }
            let records = try automationRepository.evaluate(context: context, governanceConfig: governanceConfig)
            guard !records.isEmpty else { return }
            automationTriggerRecords = try automationRepository.loadRecentTriggerRecords()
            for record in records {
                let payload = AgentAutomationPlaceholderEvent(
                    sessionID: record.sessionID,
                    trigger: record.trigger.rawValue,
                    message: "Automation \(record.ruleName) matched. Actions are recorded for governed review: \(record.actionSummaries.joined(separator: "; "))"
                )
                agentEventTimeline.insert(AgentEventPresenter().presentation(for: .automationTriggered(payload)), at: 0)
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func setSourceRegistryStatus(id: String, status: ProductOSRegistryEntryStatus) {
        do {
            guard let productOSRegistryRepository else { return }
            productOSRegistry = try productOSRegistryRepository.setSourceStatus(id: id, status: status)
            productOSRegistryMessage = "Source \(id) 当前状态为 \(status.rawValue)。康纳同学仍负责凭据、权限、审计和图谱摄取治理。"
            appendProductOSRegistryEvent(kind: "source", entryID: id, status: status, message: productOSRegistryMessage ?? "Source registry changed")
            evaluateAutomation(ProductOSAutomationEventContext(triggerKind: .sourceRegistryChanged, sessionID: selectedChatSessionID ?? activeChatSession.id, registryEntryID: id))
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func setSkillRegistryStatus(id: String, status: ProductOSRegistryEntryStatus) {
        do {
            guard let productOSRegistryRepository else { return }
            productOSRegistry = try productOSRegistryRepository.setSkillStatus(id: id, status: status)
            productOSRegistryMessage = "Skill \(id) is now \(status.rawValue). Skills are instruction profiles; graph memory writes remain governed."
            appendProductOSRegistryEvent(kind: "skill", entryID: id, status: status, message: productOSRegistryMessage ?? "Skill registry changed")
            evaluateAutomation(ProductOSAutomationEventContext(triggerKind: .skillRegistryChanged, sessionID: selectedChatSessionID ?? activeChatSession.id, registryEntryID: id))
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func appendProductOSRegistryEvent(kind: String, entryID: String, status: ProductOSRegistryEntryStatus, message: String) {
        let sessionID = selectedChatSessionID ?? activeChatSession.id
        let payload = AgentProductOSRegistryEvent(
            sessionID: sessionID,
            registryKind: kind,
            entryID: entryID,
            status: status,
            message: message
        )
        let event: AgentEvent = kind == "source" ? .sourceRegistryChanged(payload) : .skillRegistryChanged(payload)
        agentEventTimeline.insert(AgentEventPresenter().presentation(for: event), at: 0)
    }

    func loadLLMSettings() {
        do {
            let settings = try llmSettingsRepository.loadSettings()
            llmProviderMode = settings.providerMode
            llmBaseURLString = settings.baseURLString
            llmModel = settings.model
            llmSelectedModel = settings.effectiveModel
            llmHasAPIKey = settings.hasAPIKey
            llmAPIKeyInput = ""
            sidecarExecutablePath = settings.sidecarExecutablePath
            sidecarArguments = settings.sidecarArguments
            sidecarWorkingDirectoryPath = settings.sidecarWorkingDirectoryPath
            sidecarPermissionMode = settings.sidecarPermissionMode
            llmSettingsMessage = nil
            llmHealthCheckMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func reloadLLMModelConnections() async {
        isLoadingLLMModelConnections = true
        defer { isLoadingLLMModelConnections = false }
        let catalog = AppLLMModelCatalog(settingsRepository: llmSettingsRepository, httpClient: URLSessionAgentHTTPClient())
        llmModelConnections = await catalog.loadConnections()
    }

    func selectLLMModel(_ modelID: String, providerMode: AppLLMProviderMode) {
        guard !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        llmProviderMode = providerMode
        llmSelectedModel = modelID
        saveLLMSettings()
    }

    func saveLLMSettings() {
        do {
            let settings = AppLLMSettings(
                baseURLString: llmBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines),
                model: llmModel.trimmingCharacters(in: .whitespacesAndNewlines),
                selectedModel: llmSelectedModel.trimmingCharacters(in: .whitespacesAndNewlines),
                hasAPIKey: llmHasAPIKey,
                providerMode: llmProviderMode,
                sidecarExecutablePath: sidecarExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines),
                sidecarArguments: sidecarArguments.trimmingCharacters(in: .whitespacesAndNewlines),
                sidecarWorkingDirectoryPath: sidecarWorkingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines),
                sidecarPermissionMode: sidecarPermissionMode
            )
            let apiKey = llmAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            try llmSettingsRepository.save(settings: settings, apiKey: apiKey.isEmpty ? nil : apiKey)
            loadLLMSettings()
            let session = activeChatSession
            fallbackChatSession = session
            nativeSessionManager = makeNativeSessionManager(for: session)
            llmSettingsMessage = "模型设置已保存。"
            llmHealthCheckMessage = nil
            errorMessage = nil
            Task { await reloadLLMModelConnections() }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func clearLLMAPIKey() {
        do {
            try llmSettingsRepository.clearAPIKey()
            loadLLMSettings()
            let session = activeChatSession
            fallbackChatSession = session
            nativeSessionManager = makeNativeSessionManager(for: session)
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

    func selectSettingsSection(_ section: ConnorSettingsSection) {
        selectedSettingsSection = section
        selection = .llmSettings
    }

    private func makeNativeSessionManager(for session: AgentSession) -> NativeSessionManager? {
        agentRuntimeFactory?.makeNativeSessionManager(
            session: session,
            sessionWorkspace: sessionStateSnapshotsBySessionID[session.id]?.workspace
        )
    }

    private func rebuildNativeSessionManagerForActiveSession() {
        let session = activeChatSession
        fallbackChatSession = session
        nativeSessionManager = makeNativeSessionManager(for: session)
    }

    private func syncWorkspaceDraftsFromSession(_ state: AppSessionStateSnapshot?) {
        if let workspace = state?.workspace {
            workspaceRoots = Self.workspaceRootDrafts(from: workspace)
            defaultWorkingDirectoryPath = workspace.workingDirectoryPath
            return
        }
        workspaceRoots = []
        defaultWorkingDirectoryPath = ""
    }

    private func currentSessionIDForWorkspaceDrafts() -> String? {
        selectedChatSessionID ?? activeChatSession.id
    }

    private func sessionWorkspaceReferenceFromDrafts(source: String = "session") -> AppSessionWorkspaceReference? {
        let roots = sessionWorkspaceRootsFromDrafts()
        let primary = roots.first(where: \.isPrimary) ?? roots.first
        let workingDirectoryPath = primary?.path ?? defaultWorkingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workingDirectoryPath.isEmpty || !roots.isEmpty else { return nil }
        return AppSessionWorkspaceReference(
            workingDirectoryPath: workingDirectoryPath,
            source: source,
            roots: roots
        )
    }

    private func sessionWorkspaceRootsFromDrafts() -> [AppSessionWorkspaceRootReference] {
        let primaryID = workspaceRoots.first(where: \.isPrimary)?.id ?? workspaceRoots.first?.id
        return workspaceRoots
            .map { draft in
                AppSessionWorkspaceRootReference(
                    id: draft.id,
                    displayName: draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? URL(fileURLWithPath: draft.path).lastPathComponent : draft.displayName,
                    path: draft.path.trimmingCharacters(in: .whitespacesAndNewlines),
                    role: draft.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "project" : draft.role,
                    isPrimary: draft.id == primaryID
                )
            }
            .filter { !$0.path.isEmpty }
    }

    private func saveWorkspaceDraftsToCurrentSession() {
        guard let sessionID = currentSessionIDForWorkspaceDrafts() else { return }
        do {
            var state = try chatSessionRepository?.loadSessionState(sessionID: sessionID) ?? AppSessionStateSnapshot(sessionID: sessionID)
            state.workspace = sessionWorkspaceReferenceFromDrafts()
            state.updatedAt = Date()
            sessionStateSnapshotsBySessionID[sessionID] = state
            try chatSessionRepository?.saveSessionState(state, sessionID: sessionID)
            if activeChatSession.id == sessionID || selectedChatSessionID == sessionID {
                rebuildNativeSessionManagerForActiveSession()
            }
            appSettingsMessage = "当前会话 Workspace 已保存。"
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func loadRuntimeSettings() {
        do {
            let settings = try runtimeSettingsRepository?.loadOrCreateDefault() ?? .default
            defaultPermissionMode = settings.loop.permissionMode == .allowAll ? .askToWrite : settings.loop.permissionMode
            showProviderIcons = settings.ui.showProviderIcons
            richToolDescriptionsEnabled = settings.ui.richToolDescriptionsEnabled
            desktopNotificationsEnabled = settings.app.desktopNotificationsEnabled
            keepScreenAwake = settings.app.keepScreenAwake
            internalBrowserEnabled = settings.app.internalBrowserEnabled
            httpProxyEnabled = settings.app.httpProxyEnabled
            httpProxyURLString = settings.app.httpProxyURLString
            appearanceMode = ConnorAppearanceMode(rawValue: settings.appearance.mode) ?? .system
            spellCheckEnabled = settings.input.spellCheckEnabled
            autoSaveDraftsEnabled = settings.input.autoSaveDraftsEnabled
            composerSendShortcut = settings.input.composerSendShortcut
            requireApprovalForNetwork = settings.permissions.requireApprovalForNetwork
            requireApprovalForShell = settings.permissions.requireApprovalForShell
            if let sessionID = currentSessionIDForWorkspaceDrafts() {
                syncWorkspaceDraftsFromSession(sessionStateSnapshotsBySessionID[sessionID])
            } else {
                defaultWorkingDirectoryPath = ""
                workspaceRoots = []
            }
            userDisplayName = settings.preferences.displayName
            userTimezone = settings.preferences.timezone
            userCity = settings.preferences.city
            userCountry = settings.preferences.country
            userPreferenceNotes = settings.preferences.notes
            appSettingsMessage = nil
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func saveRuntimeSettings() {
        do {
            var settings = try runtimeSettingsRepository?.loadOrCreateDefault() ?? .default
            settings.loop.permissionMode = defaultPermissionMode == .allowAll ? .askToWrite : defaultPermissionMode
            settings.ui.showProviderIcons = showProviderIcons
            settings.ui.richToolDescriptionsEnabled = richToolDescriptionsEnabled
            settings.app.desktopNotificationsEnabled = desktopNotificationsEnabled
            settings.app.keepScreenAwake = keepScreenAwake
            settings.app.internalBrowserEnabled = internalBrowserEnabled
            settings.app.httpProxyEnabled = httpProxyEnabled
            settings.app.httpProxyURLString = httpProxyURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.appearance.mode = appearanceMode.rawValue
            settings.input.spellCheckEnabled = spellCheckEnabled
            settings.input.autoSaveDraftsEnabled = autoSaveDraftsEnabled
            settings.input.composerSendShortcut = composerSendShortcut
            settings.permissions.requireApprovalForNetwork = requireApprovalForNetwork
            settings.permissions.requireApprovalForShell = requireApprovalForShell
            // Workspace roots are session-scoped and saved into Session Capsule.
            // Keep runtime-settings.workspace as a legacy fallback/template only.
            settings.preferences.displayName = userDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.preferences.timezone = userTimezone.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.preferences.city = userCity.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.preferences.country = userCountry.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.preferences.notes = userPreferenceNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            try runtimeSettingsRepository?.save(settings)
            appSettingsMessage = "设置已保存。"
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    var primaryWorkspaceRootDraft: WorkspaceRootDraft? {
        workspaceRoots.first(where: \.isPrimary) ?? workspaceRoots.first
    }

    func addWorkspaceRoot(path rawPath: String) {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        guard !workspaceRoots.contains(where: { $0.path == path }) else {
            workspaceRootPathInput = ""
            return
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        workspaceRoots.append(WorkspaceRootDraft(
            displayName: url.lastPathComponent.isEmpty ? path : url.lastPathComponent,
            path: path,
            role: workspaceRoots.isEmpty ? "project" : "additional",
            isPrimary: workspaceRoots.isEmpty
        ))
        normalizeWorkspaceRootsPrimary()
        defaultWorkingDirectoryPath = workspaceRoots.first(where: \.isPrimary)?.path ?? ""
        workspaceRootPathInput = ""
        saveWorkspaceDraftsToCurrentSession()
    }

    func addWorkspaceRootAndSetPrimary(path rawPath: String) {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        if let existing = workspaceRoots.first(where: { $0.path == path }) {
            setPrimaryWorkspaceRoot(id: existing.id)
            workspaceRootPathInput = ""
            return
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        for index in workspaceRoots.indices {
            workspaceRoots[index].isPrimary = false
        }
        workspaceRoots.append(WorkspaceRootDraft(
            displayName: url.lastPathComponent.isEmpty ? path : url.lastPathComponent,
            path: path,
            role: workspaceRoots.isEmpty ? "project" : "additional",
            isPrimary: true
        ))
        normalizeWorkspaceRootsPrimary()
        defaultWorkingDirectoryPath = path
        workspaceRootPathInput = ""
        saveWorkspaceDraftsToCurrentSession()
    }

    func addWorkspaceRoots(paths: [String]) {
        for path in paths { addWorkspaceRoot(path: path) }
    }

    func resetWorkspaceRootsForCurrentSession() {
        workspaceRoots = []
        defaultWorkingDirectoryPath = ""
        workspaceRootPathInput = ""
        saveWorkspaceDraftsToCurrentSession()
    }

    func removeWorkspaceRoot(id: String) {
        let removedWasPrimary = workspaceRoots.first(where: { $0.id == id })?.isPrimary == true
        workspaceRoots.removeAll { $0.id == id }
        if removedWasPrimary, !workspaceRoots.isEmpty {
            workspaceRoots[0].isPrimary = true
        }
        normalizeWorkspaceRootsPrimary()
        defaultWorkingDirectoryPath = workspaceRoots.first(where: \.isPrimary)?.path ?? ""
        saveWorkspaceDraftsToCurrentSession()
    }

    func setPrimaryWorkspaceRoot(id: String) {
        for index in workspaceRoots.indices {
            workspaceRoots[index].isPrimary = workspaceRoots[index].id == id
        }
        defaultWorkingDirectoryPath = workspaceRoots.first(where: \.isPrimary)?.path ?? ""
        saveWorkspaceDraftsToCurrentSession()
    }

    private func normalizeWorkspaceRootsPrimary() {
        guard !workspaceRoots.isEmpty else { return }
        let primaryIDs = workspaceRoots.filter(\.isPrimary).map(\.id)
        let primaryID = primaryIDs.first ?? workspaceRoots[0].id
        for index in workspaceRoots.indices {
            workspaceRoots[index].isPrimary = workspaceRoots[index].id == primaryID
        }
    }

    private func runtimeWorkspaceRootsFromDrafts() -> [AgentRuntimeWorkspaceRoot] {
        var drafts = workspaceRoots
        if drafts.isEmpty {
            let path = defaultWorkingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                let url = URL(fileURLWithPath: path, isDirectory: true)
                drafts = [WorkspaceRootDraft(displayName: url.lastPathComponent, path: path, role: "project", isPrimary: true)]
            }
        }
        let primaryID = drafts.first(where: \.isPrimary)?.id ?? drafts.first?.id
        return drafts
            .map { draft in
                AgentRuntimeWorkspaceRoot(
                    id: draft.id,
                    displayName: draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? URL(fileURLWithPath: draft.path).lastPathComponent : draft.displayName,
                    path: draft.path.trimmingCharacters(in: .whitespacesAndNewlines),
                    role: draft.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "project" : draft.role,
                    isPrimary: draft.id == primaryID
                )
            }
            .filter { !$0.path.isEmpty }
    }

    private static func workspaceRootDrafts(from settings: AgentRuntimeWorkspaceSettings) -> [WorkspaceRootDraft] {
        let roots = settings.effectiveRoots()
        let primaryID = roots.first(where: \.isPrimary)?.id ?? roots.first?.id
        return roots.map { root in
            WorkspaceRootDraft(
                id: root.id,
                displayName: root.displayName,
                path: root.path,
                role: root.role,
                isPrimary: root.id == primaryID
            )
        }
    }

    private static func workspaceRootDrafts(from workspace: AppSessionWorkspaceReference) -> [WorkspaceRootDraft] {
        let primaryID = workspace.roots.first(where: \.isPrimary)?.id ?? workspace.roots.first?.id
        if workspace.roots.isEmpty, !workspace.workingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let path = workspace.workingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
            return [WorkspaceRootDraft(
                displayName: URL(fileURLWithPath: path).lastPathComponent,
                path: path,
                role: "project",
                isPrimary: true
            )]
        }
        return workspace.roots.map { root in
            WorkspaceRootDraft(
                id: root.id,
                displayName: root.displayName,
                path: root.path,
                role: root.role,
                isPrimary: root.id == primaryID
            )
        }
    }

    func resetRuntimeSettings() {
        do {
            try runtimeSettingsRepository?.save(.default)
            loadRuntimeSettings()
            appSettingsMessage = "设置已恢复默认值。"
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func reloadChatSessions() {
        guard let chatSessionRepository else {
            transcript = activeChatTranscript
            selectedChatSessionID = activeChatSession.id
            return
        }
        do {
            var sessions = try chatSessionRepository.loadSessions(filter: sessionListFilter)
            if sessions.isEmpty, sessionListFilter == .inbox || sessionListFilter == .all {
                let session = try chatSessionRepository.createSession()
                sessions = [session]
            }
            chatSessions = sessions
            let selectedID = selectedChatSessionID ?? sessions.first?.id
            selectedChatSessionID = selectedID
            if let selectedID, let session = try chatSessionRepository.loadSession(id: selectedID) {
                try loadSessionCapsule(sessionID: selectedID)
                fallbackChatSession = session
                nativeSessionManager = makeNativeSessionManager(for: session)
                transcript = session.messages
                isSubmittingChat = submittingChatSessionID == selectedID
                if let cachedTimeline = agentEventTimelinesBySessionID[selectedID] {
                    agentEventTimeline = cachedTimeline
                } else {
                    try restoreLatestAgentEventTimeline(sessionID: selectedID)
                }
                latestChatSummary = try chatSessionRepository.loadLatestSummary(sessionID: selectedID)
                selectedSessionArtifactDirectories = try chatSessionRepository.artifactDirectories(sessionID: selectedID)
                restoreWorkspaceMode(for: selectedID)
            } else {
                selectedSessionArtifactDirectories = nil
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
        rememberCurrentWorkspaceMode()
        do {
            let session = try chatSessionRepository.createSession()
            selectedChatSessionID = session.id
            agentEventTimelinesByProcessKey.removeAll(keepingCapacity: true)
            isBrowserVisible = false
            browserWorkspaceSessionID = nil
            rememberWorkspaceMode(.conversation, for: session.id)
            selectedSessionArtifactDirectories = try chatSessionRepository.artifactDirectories(sessionID: session.id)
            try loadSessionCapsule(sessionID: session.id)
            fallbackChatSession = session
            nativeSessionManager = makeNativeSessionManager(for: session)
            transcript = []
            isSubmittingChat = false
            agentEventTimeline = []
            agentEventTimelinesBySessionID[session.id] = []
            latestChatSummary = nil
            chatSummaryMessage = nil
            lastPromptInspection = nil
            reloadChatSessions()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func loadSessionCapsule(sessionID: String) throws {
        guard let chatSessionRepository else { return }
        _ = try chatSessionRepository.artifactDirectories(sessionID: sessionID)
        if let state = try chatSessionRepository.loadSessionState(sessionID: sessionID) {
            sessionStateSnapshotsBySessionID[sessionID] = state
            if selectedChatSessionID == sessionID { syncWorkspaceDraftsFromSession(state) }
            if let mode = ChatSessionWorkspaceMode(rawValue: state.selectedPane ?? "") {
                chatSessionWorkspaceModes.setMode(mode, for: sessionID)
            }
        } else {
            let state = AppSessionStateSnapshot(sessionID: sessionID, updatedAt: Date())
            sessionStateSnapshotsBySessionID[sessionID] = state
            if selectedChatSessionID == sessionID { syncWorkspaceDraftsFromSession(state) }
            try chatSessionRepository.saveSessionState(state, sessionID: sessionID)
        }
        sessionRecordsBySessionID[sessionID] = try chatSessionRepository.loadSessionRecords(sessionID: sessionID, limit: nil)
        if let browserState = try chatSessionRepository.loadBrowserState(sessionID: sessionID) {
            browserWorkspaceSnapshotsBySessionID[sessionID] = browserState
        }
        _ = try chatSessionRepository.refreshSessionManifest(sessionID: sessionID)
    }

    func saveBrowserWorkspaceSnapshot(_ snapshot: AppBrowserStateSnapshot, for sessionID: String) {
        var normalized = snapshot
        normalized.updatedAt = Date()
        browserWorkspaceSnapshotsBySessionID[sessionID] = normalized
        do {
            try chatSessionRepository?.saveBrowserState(normalized, sessionID: sessionID)
            if let state = try chatSessionRepository?.loadSessionState(sessionID: sessionID) {
                sessionStateSnapshotsBySessionID[sessionID] = state
            }
            _ = try chatSessionRepository?.refreshSessionManifest(sessionID: sessionID)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func rememberCurrentWorkspaceMode() {
        rememberWorkspaceMode(isBrowserVisible ? .browser : .conversation, for: selectedChatSessionID ?? activeChatSession.id)
    }

    private func rememberWorkspaceMode(_ mode: ChatSessionWorkspaceMode, for sessionID: String?) {
        chatSessionWorkspaceModes.setMode(mode, for: sessionID)
        guard let sessionID else { return }
        do {
            var state = try chatSessionRepository?.loadSessionState(sessionID: sessionID) ?? AppSessionStateSnapshot(sessionID: sessionID)
            state.selectedPane = mode.rawValue
            state.updatedAt = Date()
            sessionStateSnapshotsBySessionID[sessionID] = state
            try chatSessionRepository?.saveSessionState(state, sessionID: sessionID)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func restoreWorkspaceMode(for sessionID: String) {
        let mode = chatSessionWorkspaceModes.mode(for: sessionID)
        isBrowserVisible = mode == .browser
        browserWorkspaceSessionID = mode == .browser ? sessionID : nil
        if mode == .browser {
            browserWorkspaceSessionBinding.bindBrowserWorkspace(to: sessionID)
        }
        selection = .agentChat
    }

    func appendSessionRecord(kind: String, title: String? = nil, body: String? = nil, metadata: [String: String] = [:], sessionID: String? = nil) {
        let targetSessionID = sessionID ?? selectedChatSessionID ?? activeChatSession.id
        let record = AppSessionRecord(sessionID: targetSessionID, kind: kind, title: title, body: body, metadata: metadata)
        do {
            try chatSessionRepository?.appendSessionRecord(record, sessionID: targetSessionID)
            sessionRecordsBySessionID[targetSessionID] = try chatSessionRepository?.loadSessionRecords(sessionID: targetSessionID, limit: nil) ?? []
            if let state = try chatSessionRepository?.loadSessionState(sessionID: targetSessionID) {
                sessionStateSnapshotsBySessionID[targetSessionID] = state
            }
            _ = try chatSessionRepository?.refreshSessionManifest(sessionID: targetSessionID)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func restoredAgentEventTimeline(for process: AgentChatTurnProcessPresentation) -> [AgentEventPresentation] {
        guard process.state == .completed,
              let chatSessionRepository,
              let sessionID = selectedChatSessionID
        else { return [] }
        let cacheKey = "\(sessionID):\(process.id)"
        if let cached = agentEventTimelinesByProcessKey[cacheKey] { return cached }
        guard let sourceUserMessageID = process.sourceUserMessageID else {
            agentEventTimelinesByProcessKey[cacheKey] = []
            return []
        }
        do {
            let runs = try chatSessionRepository.loadRuns(sessionID: sessionID, statuses: nil, limit: 200)
            guard let run = runs.first(where: { $0.metadata["user_message_id"] == sourceUserMessageID }) else {
                agentEventTimelinesByProcessKey[cacheKey] = []
                return []
            }
            let restored = try restoreAgentEventTimeline(runID: run.id, sessionID: sessionID)
            agentEventTimelinesByProcessKey[cacheKey] = restored
            return restored
        } catch {
            agentEventTimelinesByProcessKey[cacheKey] = []
            return []
        }
    }

    private func restoreAgentEventTimeline(runID: String, sessionID: String) throws -> [AgentEventPresentation] {
        guard let chatSessionRepository else { return [] }
        let restored = presentations(from: try chatSessionRepository.loadRunEvents(runID: runID, limit: 300))
        if !restored.isEmpty { return restored }
        return presentations(
            from: try chatSessionRepository.loadRecentJournalEvents(sessionID: sessionID, limit: 500)
                .filter { $0.runID == runID }
                .sorted { lhs, rhs in
                    switch (lhs.sequence, rhs.sequence) {
                    case let (left?, right?): return left < right
                    case (.some, .none): return true
                    case (.none, .some): return false
                    case (.none, .none): return lhs.createdAt < rhs.createdAt
                    }
                }
        )
    }

    private func presentations(from persistedEvents: [PersistedAgentEvent]) -> [AgentEventPresentation] {
        AgentEventPresentationRestorer().presentations(from: persistedEvents)
    }

    private func restoreLatestAgentEventTimeline(sessionID: String) throws {
        guard let chatSessionRepository else {
            agentEventTimelinesBySessionID[sessionID] = []
            agentEventTimeline = []
            return
        }

        let cachedTimeline = try chatSessionRepository.loadActivityTimelineCache(sessionID: sessionID)
        if !cachedTimeline.isEmpty {
            agentEventTimelinesBySessionID[sessionID] = cachedTimeline
            agentEventTimeline = cachedTimeline
            return
        }

        let runs = try chatSessionRepository.loadRuns(
            sessionID: sessionID,
            statuses: [.completed, .failed, .cancelled],
            limit: 10
        )
        for run in runs {
            let restored = presentations(from: try chatSessionRepository.loadRunEvents(runID: run.id, limit: 300))
            if !restored.isEmpty {
                agentEventTimelinesBySessionID[sessionID] = restored
                try? chatSessionRepository.saveActivityTimelineCache(sessionID: sessionID, timeline: restored)
                agentEventTimeline = restored
                return
            }
        }

        let recentEvents = try chatSessionRepository.loadRecentJournalEvents(sessionID: sessionID, limit: 300)
        var seenRunIDs: [String] = []
        for event in recentEvents where !seenRunIDs.contains(event.runID) {
            seenRunIDs.append(event.runID)
        }
        for runID in seenRunIDs {
            let runEvents = recentEvents
                .filter { $0.runID == runID }
                .sorted { lhs, rhs in
                    switch (lhs.sequence, rhs.sequence) {
                    case let (left?, right?): return left < right
                    case (.some, .none): return true
                    case (.none, .some): return false
                    case (.none, .none): return lhs.createdAt < rhs.createdAt
                    }
                }
            let restored = presentations(from: runEvents)
            if !restored.isEmpty {
                agentEventTimelinesBySessionID[sessionID] = restored
                try? chatSessionRepository.saveActivityTimelineCache(sessionID: sessionID, timeline: restored)
                agentEventTimeline = restored
                return
            }
        }

        agentEventTimelinesBySessionID[sessionID] = []
        agentEventTimeline = []
    }

    func selectChatSession(_ sessionID: String) {
        guard let chatSessionRepository else { return }
        rememberCurrentWorkspaceMode()
        do {
            guard let session = try chatSessionRepository.loadSession(id: sessionID) else { return }
            selectedChatSessionID = session.id
            agentEventTimelinesByProcessKey.removeAll(keepingCapacity: true)
            try loadSessionCapsule(sessionID: session.id)
            fallbackChatSession = session
            nativeSessionManager = makeNativeSessionManager(for: session)
            transcript = session.messages
            isSubmittingChat = submittingChatSessionID == session.id
            if let cachedTimeline = agentEventTimelinesBySessionID[session.id] {
                agentEventTimeline = cachedTimeline
            } else {
                try restoreLatestAgentEventTimeline(sessionID: session.id)
            }
            latestChatSummary = try chatSessionRepository.loadLatestSummary(sessionID: session.id)
            selectedSessionArtifactDirectories = try chatSessionRepository.artifactDirectories(sessionID: session.id)
            restoreWorkspaceMode(for: session.id)
            chatSummaryMessage = nil
            lastContext = nil
            lastPromptInspection = nil
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func setSessionListFilter(_ filter: AgentSessionListFilter) {
        sessionListFilter = filter
        reloadChatSessions()
    }

    func setSelectedSessionStatus(_ status: AgentSessionStatus) {
        guard let selectedChatSessionID, let chatSessionRepository else { return }
        do {
            let session = try chatSessionRepository.setStatus(sessionID: selectedChatSessionID, status: status)
            self.selectedChatSessionID = session.id
            reloadChatSessions()
            appendGovernanceEvent(.sessionStatusChanged(AgentSessionGovernanceEvent(sessionID: session.id, message: "状态已更新为 \(status.displayName)", status: status)))
            evaluateAutomation(ProductOSAutomationEventContext(triggerKind: .sessionStatusChanged, sessionID: session.id, status: status))
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func toggleSelectedSessionFlag() {
        guard let selectedChatSessionID, let chatSessionRepository else { return }
        do {
            let session = try chatSessionRepository.toggleFlag(sessionID: selectedChatSessionID)
            reloadChatSessions()
            appendGovernanceEvent(.sessionLabelsChanged(AgentSessionGovernanceEvent(sessionID: session.id, message: session.governance.isFlagged ? "已标记重点会话" : "已取消重点标记", labels: session.governance.labels)))
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func toggleSelectedSessionLabel(_ labelID: String) {
        guard let selectedChatSessionID, let chatSessionRepository else { return }
        do {
            guard let session = try chatSessionRepository.loadSession(id: selectedChatSessionID) else { return }
            var labels = session.governance.labels
            let didRemove: Bool
            if labels.contains(where: { $0.id == labelID }) {
                labels.removeAll { $0.id == labelID }
                didRemove = true
            } else {
                labels.append(AgentSessionLabel(id: labelID))
                didRemove = false
            }
            let updated = try chatSessionRepository.setLabels(sessionID: selectedChatSessionID, labels: labels)
            reloadChatSessions()
            appendGovernanceEvent(.sessionLabelsChanged(AgentSessionGovernanceEvent(sessionID: updated.id, message: "标签已更新：\(updated.governance.labels.map(\.displayText).joined(separator: ", "))", labels: updated.governance.labels)))
            evaluateAutomation(ProductOSAutomationEventContext(triggerKind: didRemove ? .sessionLabelRemoved : .sessionLabelAdded, sessionID: updated.id, labelID: labelID))
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func archiveSelectedSession() {
        guard let selectedChatSessionID, let chatSessionRepository else { return }
        do {
            let session = try chatSessionRepository.archive(sessionID: selectedChatSessionID)
            appendGovernanceEvent(.sessionArchived(AgentSessionGovernanceEvent(sessionID: session.id, message: "会话已归档", status: session.governance.status)))
            evaluateAutomation(ProductOSAutomationEventContext(triggerKind: .sessionArchived, sessionID: session.id, status: session.governance.status))
            self.selectedChatSessionID = nil
            reloadChatSessions()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func restoreSelectedSession() {
        guard let selectedChatSessionID, let chatSessionRepository else { return }
        do {
            let session = try chatSessionRepository.restore(sessionID: selectedChatSessionID)
            appendGovernanceEvent(.sessionRestored(AgentSessionGovernanceEvent(sessionID: session.id, message: "会话已恢复", status: session.governance.status)))
            evaluateAutomation(ProductOSAutomationEventContext(triggerKind: .sessionRestored, sessionID: session.id, status: session.governance.status))
            setSessionListFilter(.inbox)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func appendGovernanceEvent(_ event: AgentEvent) {
        agentEventTimeline.insert(AgentEventPresenter().presentation(for: event), at: 0)
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

    func reloadPendingApprovals() {
        do {
            pendingApprovals = try pendingApprovalRepository?.loadPending() ?? []
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func approvePendingApproval(_ approval: AgentPendingApproval) {
        Task { await resolvePendingApproval(approval, status: .approved, reason: "Approved by reviewer", actor: "human-reviewer") }
    }

    func denyPendingApproval(_ approval: AgentPendingApproval) {
        Task { await resolvePendingApproval(approval, status: .denied, reason: "Denied by reviewer", actor: "human-reviewer") }
    }

    func cancelPendingApproval(_ approval: AgentPendingApproval) {
        Task { await resolvePendingApproval(approval, status: .cancelled, reason: "Cancelled by system", actor: "system") }
    }

    func alwaysAllowPendingApproval(_ approval: AgentPendingApproval) {
        sidecarPermissionMode = .trustedWrite
        saveLLMSettings()
        Task { await resolvePendingApproval(approval, status: .approved, reason: "Always allowed by reviewer for this trusted session", actor: "human-reviewer") }
    }

    private func resolvePendingApproval(_ approval: AgentPendingApproval, status: AgentPendingApprovalStatus, reason: String, actor: String) async {
        do {
            let resolved: AgentPendingApproval?
            switch status {
            case .approved:
                resolved = try pendingApprovalRepository?.approve(requestID: approval.requestID, reason: reason, actor: actor)
            case .denied:
                resolved = try pendingApprovalRepository?.deny(requestID: approval.requestID, reason: reason, actor: actor)
            case .cancelled:
                resolved = try pendingApprovalRepository?.cancel(requestID: approval.requestID, reason: reason, actor: actor)
            case .pending:
                resolved = approval
            }
            if let resolved {
                try await nativeSessionManager?.backend.resolveApproval(resolved, status: status, reason: reason, actor: actor)
            }
            reloadPendingApprovals()
            switch status {
            case .approved:
                lastPendingApprovalResultSummary = "已批准权限请求 \(approval.requestID)，并写入审计、timeline，且已向 sidecar 发送 resume。"
            case .denied:
                lastPendingApprovalResultSummary = "已拒绝权限请求 \(approval.requestID)，并写入审计、timeline，且已向 sidecar 发送 deny。"
            case .cancelled:
                lastPendingApprovalResultSummary = "已取消权限请求 \(approval.requestID)，并写入审计、timeline，且已向 sidecar 发送 cancel/deny。"
            case .pending:
                lastPendingApprovalResultSummary = "权限请求 \(approval.requestID) 仍为 pending。"
            }
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

    func cancelActiveChatRun() {
        guard let submittingSessionID = submittingChatSessionID,
              selectedChatSessionID == submittingSessionID
        else { return }
        let reason = "cancelled by user"
        guard let runID = activeChatRunID else {
            if pendingChatCancellationReasonsBySessionID[submittingSessionID] == nil {
                pendingChatCancellationReasonsBySessionID[submittingSessionID] = reason
                appendChatCancellationPresentation(
                    sessionID: submittingSessionID,
                    runID: nil,
                    title: "Run cancellation requested",
                    detail: "已请求终止本轮 agent loop，正在等待 runtime run ID。"
                )
            }
            return
        }
        cancelRunningChatRun(sessionID: submittingSessionID, runID: runID, reason: reason)
    }

    private func cancelRunningChatRun(sessionID: String, runID: String, reason: String) {
        if var manager = nativeSessionManager {
            manager.cancel(runID: runID, reason: reason)
            nativeSessionManager = manager
        }
        appendChatCancellationPresentation(
            sessionID: sessionID,
            runID: runID,
            title: "Run cancelled",
            detail: "已手动终止本轮 agent loop。"
        )
        pendingChatCancellationReasonsBySessionID.removeValue(forKey: sessionID)
        submittingChatSessionID = nil
        activeChatRunID = nil
        isSubmittingChat = false
    }

    private func appendChatCancellationPresentation(sessionID: String, runID: String?, title: String, detail: String) {
        let cancellation = AgentEventPresentation(
            kind: "run_cancelled",
            title: title,
            detail: detail,
            severity: .warning,
            runID: runID,
            sessionID: sessionID
        )
        var timeline = agentEventTimelinesBySessionID[sessionID] ?? agentEventTimeline
        timeline.append(cancellation)
        agentEventTimelinesBySessionID[sessionID] = timeline
        try? chatSessionRepository?.saveActivityTimelineCache(sessionID: sessionID, timeline: timeline)
        if selectedChatSessionID == sessionID {
            agentEventTimeline = timeline
        }
    }

    @discardableResult
    func submitChat(prompt rawPrompt: String, clearComposer: Bool = false, displayPrompt rawDisplayPrompt: String? = nil) async -> String? {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayPrompt = rawDisplayPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, submittingChatSessionID == nil else { return nil }
        guard var manager = nativeSessionManager else {
            errorMessage = String(describing: AppChatRuntimeUnavailableError.nativeSessionManagerUnavailable)
            return nil
        }
        let submittingSessionID = manager.session.id
        if clearComposer { chatInput = "" }
        agentEventTimelinesBySessionID[submittingSessionID] = []
        agentEventTimelinesByProcessKey = agentEventTimelinesByProcessKey.filter { key, _ in !key.hasPrefix("\(submittingSessionID):") }
        agentEventTimeline = []
        submittingChatSessionID = submittingSessionID
        activeChatRunID = nil
        isSubmittingChat = selectedChatSessionID == submittingSessionID
        let optimisticTranscript = transcript
        let baselineMessageCount = manager.session.messages.count
        let optimisticUserMessage = AgentMessage(role: .user, content: displayPrompt?.isEmpty == false ? displayPrompt! : prompt)
        if selectedChatSessionID == submittingSessionID {
            transcript = optimisticTranscript + [optimisticUserMessage]
        }
        lastContext = nil
        lastPromptInspection = nil
        defer {
            if submittingChatSessionID == submittingSessionID {
                submittingChatSessionID = nil
                activeChatRunID = nil
            }
            isSubmittingChat = selectedChatSessionID == submittingSessionID ? false : (submittingChatSessionID == selectedChatSessionID)
        }
        do {
            let sessionSummary: AgentSessionSummary?
            if let chatSessionRepository {
                let candidateSummary = try chatSessionRepository.loadLatestSummary(sessionID: submittingSessionID)
                sessionSummary = AgentSessionSummaryPolicy().summaryForContext(candidateSummary, session: manager.session)
            } else {
                sessionSummary = nil
            }
            let response = try await manager.submit(
                prompt,
                sessionSummary: sessionSummary,
                displayPrompt: displayPrompt?.isEmpty == false ? displayPrompt : nil,
                onRunStarted: { [weak self] runID in
                    guard let self else { return }
                    if self.submittingChatSessionID == submittingSessionID {
                        self.activeChatRunID = runID
                        if let reason = self.pendingChatCancellationReasonsBySessionID[submittingSessionID] {
                            self.cancelRunningChatRun(sessionID: submittingSessionID, runID: runID, reason: reason)
                        }
                    }
                },
                onEventPresentation: { [weak self] presentation in
                    guard let self else { return }
                    var timeline = self.agentEventTimelinesBySessionID[submittingSessionID] ?? []
                    timeline.append(presentation)
                    self.agentEventTimelinesBySessionID[submittingSessionID] = timeline
                    try? self.chatSessionRepository?.saveActivityTimelineCache(sessionID: submittingSessionID, timeline: timeline)
                    if self.selectedChatSessionID == submittingSessionID {
                        self.agentEventTimeline = timeline
                    }
                    if presentation.kind == AgentEventKind.permissionRequested.rawValue {
                        self.reloadPendingApprovals()
                    }
                }
            )
            agentEventTimelinesBySessionID[submittingSessionID] = manager.eventPresentations
            try? chatSessionRepository?.saveActivityTimelineCache(sessionID: submittingSessionID, timeline: manager.eventPresentations)
            if selectedChatSessionID == submittingSessionID {
                nativeSessionManager = manager
                fallbackChatSession = response.session
                transcript = manager.session.messages
                agentEventTimeline = manager.eventPresentations
                selectedChatSessionID = response.session.id
                latestChatSummary = try chatSessionRepository?.loadLatestSummary(sessionID: response.session.id)
                lastContext = nil
                lastPromptInspection = nil
            }
            reloadPendingApprovals()
            if let chatSessionRepository {
                chatSessions = try chatSessionRepository.loadSessions(filter: sessionListFilter)
            }
            errorMessage = nil
            Task { await runBackgroundJobs() }
            return response.session.messages
                .dropFirst(baselineMessageCount)
                .last(where: { $0.role == .assistant })?
                .content
        } catch {
            let recoveredSession = (try? chatSessionRepository?.loadSession(id: submittingSessionID)) ?? manager.session
            if selectedChatSessionID == submittingSessionID {
                nativeSessionManager = manager
                fallbackChatSession = recoveredSession
                transcript = recoveredSession.messages.isEmpty ? optimisticTranscript + [optimisticUserMessage] : recoveredSession.messages
            }
            reloadPendingApprovals()
            pendingChatCancellationReasonsBySessionID.removeValue(forKey: submittingSessionID)
            if case NativeSessionManagerError.runCancelled = error {
                errorMessage = nil
            } else {
                errorMessage = String(describing: error)
            }
            return nil
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

