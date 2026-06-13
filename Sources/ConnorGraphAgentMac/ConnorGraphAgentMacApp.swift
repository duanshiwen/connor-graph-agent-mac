import SwiftUI
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
            CommandMenu("Connor") {
                Button("Open Command Palette") {
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

enum SidebarItem: String, CaseIterable, Identifiable {
    case entities = "图谱节点"
    case search = "搜索"
    case observeLog = "观察日志"
    case agentChat = "智能体聊天"
    case promotionQueue = "提升队列"
    case graphWriteCandidates = "写入候选"
    case pendingApprovals = "权限审批"
    case memoryChangeLog = "记忆变更"
    case extractionDiagnostics = "记忆准入"
    case automation = "自动化"
    case productOS = "Product OS"
    case sources = "Sources"
    case skills = "Skills"
    case llmSettings = "模型设置"

    var id: String { rawValue }
}

enum ConnorSettingsSection: String, CaseIterable, Identifiable {
    case app
    case ai
    case appearance
    case input
    case permissions
    case labels
    case shortcuts
    case preferences

    var id: String { rawValue }

    var title: String {
        switch self {
        case .app: "应用"
        case .ai: "AI"
        case .appearance: "外观"
        case .input: "输入"
        case .permissions: "权限"
        case .labels: "标签"
        case .shortcuts: "快捷键"
        case .preferences: "偏好"
        }
    }

    var subtitle: String {
        switch self {
        case .app: "通知和更新"
        case .ai: "模型、思考、连接"
        case .appearance: "主题、字体、工具图标"
        case .input: "发送键、拼写检查"
        case .permissions: "默认权限和审批"
        case .labels: "管理会话标签"
        case .shortcuts: "键盘快捷键"
        case .preferences: "用户偏好"
        }
    }

    var systemImage: String {
        switch self {
        case .app: "app.badge"
        case .ai: "sparkles"
        case .appearance: "paintpalette"
        case .input: "keyboard"
        case .permissions: "shield"
        case .labels: "tag"
        case .shortcuts: "command"
        case .preferences: "person.crop.circle"
        }
    }
}

enum AppChatRuntimeUnavailableError: Error, LocalizedError {
    case nativeSessionManagerUnavailable

    var errorDescription: String? {
        switch self {
        case .nativeSessionManagerUnavailable:
            return "Native chat runtime is unavailable. Configure storage/runtime before sending messages."
        }
    }
}

enum ConnorAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "display"
        case .light: "sun.max"
        case .dark: "moon"
        }
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
    private var agentEventTimelinesBySessionID: [String: [AgentEventPresentation]] = [:]
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

    func showBrowserWorkspace() {
        let sessionID = selectedChatSessionID ?? activeChatSession.id
        browserWorkspaceSessionBinding.bindBrowserWorkspace(to: sessionID)
        browserWorkspaceSessionID = browserWorkspaceSessionBinding.boundSessionID
        isBrowserVisible = true
        selection = .agentChat
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
            errorMessage = "Unsupported Connor link: \(url.absoluteString)"
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
            self.agentRuntimeFactory = AppGraphAgentRuntimeFactory(store: repository.store, settingsRepository: llmSettingsRepository)
            self.hybridSearchService = SQLiteGraphHybridSearchService(store: repository.store)
            self.backgroundJobRunner = AppGraphBackgroundJobRunner(store: repository.store, settingsRepository: llmSettingsRepository)
        }
        self.llmSettingsRepository = llmSettingsRepository
        self.llmProviderHealthChecker = AppLLMProviderHealthChecker(settingsRepository: llmSettingsRepository)
        self.databasePath = databasePath
        let initialSession = AgentSession(id: "app-session")
        self.fallbackChatSession = initialSession
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
        nativeSessionManager = agentRuntimeFactory?.makeNativeSessionManager(session: session)
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
                productOSRegistryMessage = "Product OS registry loaded from Connor Home."
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
            productOSRegistryMessage = "Source \(id) is now \(status.rawValue). Connor still owns credentials, permissions, audit, and graph ingestion."
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
            nativeSessionManager = agentRuntimeFactory?.makeNativeSessionManager(session: session)
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
            nativeSessionManager = agentRuntimeFactory?.makeNativeSessionManager(session: session)
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
                fallbackChatSession = session
                nativeSessionManager = agentRuntimeFactory?.makeNativeSessionManager(session: session)
                transcript = session.messages
                isSubmittingChat = submittingChatSessionID == selectedID
                if let cachedTimeline = agentEventTimelinesBySessionID[selectedID] {
                    agentEventTimeline = cachedTimeline
                } else {
                    try restoreLatestAgentEventTimeline(sessionID: selectedID)
                }
                latestChatSummary = try chatSessionRepository.loadLatestSummary(sessionID: selectedID)
                selectedSessionArtifactDirectories = try chatSessionRepository.artifactDirectories(sessionID: selectedID)
                try loadSessionCapsule(sessionID: selectedID)
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
            isBrowserVisible = false
            browserWorkspaceSessionID = nil
            rememberWorkspaceMode(.conversation, for: session.id)
            fallbackChatSession = session
            nativeSessionManager = agentRuntimeFactory?.makeNativeSessionManager(session: session)
            transcript = []
            isSubmittingChat = false
            agentEventTimeline = []
            agentEventTimelinesBySessionID[session.id] = []
            latestChatSummary = nil
            chatSummaryMessage = nil
            lastPromptInspection = nil
            selectedSessionArtifactDirectories = try chatSessionRepository.artifactDirectories(sessionID: session.id)
            try loadSessionCapsule(sessionID: session.id)
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
            if let mode = ChatSessionWorkspaceMode(rawValue: state.selectedPane ?? "") {
                chatSessionWorkspaceModes.setMode(mode, for: sessionID)
            }
        } else {
            let state = AppSessionStateSnapshot(sessionID: sessionID, updatedAt: Date())
            sessionStateSnapshotsBySessionID[sessionID] = state
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

        let replayer = AgentEventReplayer()
        let presenter = AgentEventPresenter()

        func presentations(from persistedEvents: [PersistedAgentEvent]) -> [AgentEventPresentation] {
            let sequencedEvents = persistedEvents.filter { $0.sequence != nil }
            let replaySource = sequencedEvents.isEmpty ? persistedEvents : sequencedEvents
            return replaySource.compactMap { persistedEvent in
                try? replayer.replay(persistedEvent)
            }.map { event in
                presenter.presentation(for: event)
            }
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
            fallbackChatSession = session
            nativeSessionManager = agentRuntimeFactory?.makeNativeSessionManager(session: session)
            transcript = session.messages
            isSubmittingChat = submittingChatSessionID == session.id
            if let cachedTimeline = agentEventTimelinesBySessionID[session.id] {
                agentEventTimeline = cachedTimeline
            } else {
                try restoreLatestAgentEventTimeline(sessionID: session.id)
            }
            latestChatSummary = try chatSessionRepository.loadLatestSummary(sessionID: session.id)
            selectedSessionArtifactDirectories = try chatSessionRepository.artifactDirectories(sessionID: session.id)
            try loadSessionCapsule(sessionID: session.id)
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
              selectedChatSessionID == submittingSessionID,
              let runID = activeChatRunID
        else { return }
        if var manager = nativeSessionManager {
            manager.cancel(runID: runID, reason: "cancelled by user")
            nativeSessionManager = manager
        }
        let cancellation = AgentEventPresentation(
            kind: "run_cancelled",
            title: "Run cancelled",
            detail: "已手动终止本轮 agent loop。",
            severity: .warning,
            runID: runID,
            sessionID: submittingSessionID
        )
        var timeline = agentEventTimelinesBySessionID[submittingSessionID] ?? agentEventTimeline
        timeline.append(cancellation)
        agentEventTimelinesBySessionID[submittingSessionID] = timeline
        try? chatSessionRepository?.saveActivityTimelineCache(sessionID: submittingSessionID, timeline: timeline)
        agentEventTimeline = timeline
        submittingChatSessionID = nil
        activeChatRunID = nil
        isSubmittingChat = false
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
            if selectedChatSessionID == submittingSessionID {
                transcript = optimisticTranscript + [optimisticUserMessage]
            }
            reloadPendingApprovals()
            errorMessage = String(describing: error)
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

struct AppShellView: View {
    @StateObject var viewModel: AppViewModel
    @State private var sidebarSelection: SidebarItem? = .agentChat

    var body: some View {
        HStack(spacing: 0) {
            CraftPrimarySidebarView(viewModel: viewModel, selection: $sidebarSelection)
                .frame(width: 264)
                .background(.bar)

            Divider()

            CraftListPaneView(viewModel: viewModel, selection: $sidebarSelection)
                .frame(width: 314)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.84))

            Divider()

            CraftDetailPaneView(viewModel: viewModel, selection: sidebarSelection ?? .agentChat)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.12))
        }
        .frame(minWidth: 1120, minHeight: 680)
        .controlSize(.small)
        .onAppear {
            sidebarSelection = viewModel.selection ?? .agentChat
            viewModel.reloadChatSessions()
        }
        .onChange(of: sidebarSelection) { _, newSelection in
            viewModel.deferViewUpdate {
                viewModel.selection = newSelection
            }
        }
        .onChange(of: viewModel.selection) { _, newSelection in
            if sidebarSelection != newSelection {
                sidebarSelection = newSelection
            }
        }
        .sheet(isPresented: $viewModel.isCommandPalettePresented) {
            ConnorCommandPaletteView(viewModel: viewModel)
        }
    }
}

struct SidebarActionButtonLabel: View {
    var title: String
    var systemImage: String
    var fillsWidth: Bool = true
    var titleFont: Font = .system(size: 12, weight: .regular)
    var iconFont: Font = .system(size: 13, weight: .medium)
    var minHeight: CGFloat = 24

    var body: some View {
        Label {
            Text(title)
                .font(titleFont)
                .lineLimit(1)
        } icon: {
            Image(systemName: systemImage)
                .font(iconFont)
                .symbolRenderingMode(.monochrome)
                .frame(width: 15, alignment: .center)
        }
        .foregroundStyle(Color.primary)
        .labelStyle(.titleAndIcon)
        .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: minHeight, alignment: .leading)
        .padding(.horizontal, 7)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct SidebarActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(backgroundColor(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(borderColor(isPressed: configuration.isPressed), lineWidth: 1)
            )
            .shadow(color: shadowColor(isPressed: configuration.isPressed), radius: configuration.isPressed ? 0 : 0.5, x: 0, y: configuration.isPressed ? 0 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.992 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        Color(nsColor: .controlBackgroundColor)
            .opacity(isPressed ? 0.78 : 0.96)
    }

    private func borderColor(isPressed: Bool) -> Color {
        Color(nsColor: .separatorColor)
            .opacity(isPressed ? 0.42 : 0.28)
    }

    private func shadowColor(isPressed: Bool) -> Color {
        Color.black.opacity(isPressed ? 0.04 : 0.08)
    }
}

private struct CraftPrimarySidebarView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var selection: SidebarItem?
    @State private var sessionsExpanded = true
    @State private var labelsExpanded = true
    @State private var sourcesExpanded = true
    @State private var automationExpanded = true

    var body: some View {
        VStack(spacing: 10) {
            Button {
                viewModel.newChatSession()
                select(.agentChat)
            } label: {
                SidebarActionButtonLabel(title: "新建会话", systemImage: "square.and.pencil", minHeight: 32)
            }
            .buttonStyle(SidebarActionButtonStyle())
            .padding(.horizontal, 10)
            .padding(.top, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    SidebarDisclosure(title: "所有会话", systemImage: "tray", isExpanded: $sessionsExpanded) {
                        SidebarRow(title: "全部", systemImage: "bubble.left.and.bubble.right", count: viewModel.chatSessions.count, isSelected: selection == .agentChat && viewModel.sessionListFilter == .all) {
                            viewModel.setSessionListFilter(.all)
                            select(.agentChat)
                        }
                        SidebarRow(title: "收件箱", systemImage: "tray.full", count: inboxCount, isSelected: selection == .agentChat && viewModel.sessionListFilter == .inbox) {
                            viewModel.setSessionListFilter(.inbox)
                            select(.agentChat)
                        }
                        ForEach(viewModel.governanceConfig.statuses.sorted { $0.sortOrder < $1.sortOrder }) { status in
                            if let sessionStatus = AgentSessionStatus(rawValue: status.id) {
                                SidebarRow(title: status.name, systemImage: status.systemImage, count: count(for: sessionStatus), isSelected: selection == .agentChat && viewModel.sessionListFilter == .status(sessionStatus)) {
                                    viewModel.setSessionListFilter(.status(sessionStatus))
                                    select(.agentChat)
                                }
                            }
                        }
                    }

                    SidebarDisclosure(title: "标签", systemImage: "tag", isExpanded: $labelsExpanded) {
                        if viewModel.governanceConfig.labels.isEmpty {
                            SidebarMutedText("暂无标签")
                        } else {
                            ForEach(viewModel.governanceConfig.labels) { label in
                                SidebarRow(title: label.name, systemImage: "tag", count: count(forLabel: label.id), isSelected: selection == .agentChat && viewModel.sessionListFilter == .label(label.id)) {
                                    viewModel.setSessionListFilter(.label(label.id))
                                    select(.agentChat)
                                }
                            }
                        }
                    }

                    SidebarRow(title: "数据源", systemImage: "externaldrive.connected.to.line.below", count: viewModel.sourceRuntimeConfigurations.count, isSelected: selection == .sources) { select(.sources) }

                    SidebarRow(title: "技能", systemImage: "bolt", count: viewModel.skillRuntimeDefinitions.count, isSelected: selection == .skills) { select(.skills) }

                    SidebarDisclosure(title: "自动化", systemImage: "wand.and.stars", isExpanded: $automationExpanded) {
                        SidebarRow(title: "定时任务", systemImage: "clock", count: viewModel.automationConfig.rules.count, isSelected: selection == .automation) { select(.automation) }
                        SidebarRow(title: "事件触发", systemImage: "dot.radiowaves.left.and.right", count: viewModel.automationTriggerRecords.count, isSelected: selection == .automation) { select(.automation) }
                        SidebarRow(title: "智能体", systemImage: "shippingbox", count: viewModel.productOSRegistry.skills.count, isSelected: selection == .productOS) { select(.productOS) }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                SidebarRow(title: "设置", systemImage: "gearshape", count: nil, isSelected: selection == .llmSettings) { select(.llmSettings) }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
    }

    private var inboxCount: Int {
        viewModel.chatSessions.filter { !$0.governance.isArchived }.count
    }

    private func count(for status: AgentSessionStatus) -> Int {
        viewModel.chatSessions.filter { $0.governance.status == status }.count
    }

    private func count(forLabel labelID: String) -> Int {
        viewModel.chatSessions.filter { session in
            session.governance.labels.contains { $0.id == labelID }
        }.count
    }

    private func select(_ item: SidebarItem) {
        selection = item
        viewModel.selection = item
    }
}

private struct CraftListPaneView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var selection: SidebarItem?

    var body: some View {
        VStack(spacing: 0) {
            switch selection ?? .agentChat {
            case .agentChat:
                CraftSessionListPane(viewModel: viewModel)
            case .llmSettings:
                CraftSettingsListPane(viewModel: viewModel, selection: $selection)
            case .sources:
                CraftSimpleListPane(title: "数据源", subtitle: "MCP Source Runtime", rows: viewModel.sourceRuntimeConfigurations.map(\.displayName))
            case .skills:
                CraftSimpleListPane(title: "技能", subtitle: "Skill Runtime", rows: viewModel.skillRuntimeDefinitions.map { $0.manifest.name })
            case .automation:
                CraftSimpleListPane(title: "自动化", subtitle: "事件触发与执行历史", rows: viewModel.automationConfig.rules.map(\.name))
            case .productOS:
                CraftSimpleListPane(title: "Product OS", subtitle: "本地控制面模块", rows: viewModel.productOSRegistry.sources.map(\.displayName) + viewModel.productOSRegistry.skills.map(\.displayName))
            default:
                CraftSimpleListPane(title: (selection ?? .agentChat).rawValue, subtitle: "Connor 工作区", rows: [])
            }
        }
    }
}

private struct CraftSessionListPane: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(sessionListTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack {
                    Spacer()
                    Button(action: { viewModel.reloadChatSessions() }) {
                        Image(systemName: "line.3.horizontal.decrease")
                    }
                    .buttonStyle(.borderless)
                    .help("刷新/过滤")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.chatSessions) { session in
                        CraftSessionRow(row: AgentChatSessionPresentation(session: session), isSelected: session.id == viewModel.selectedChatSessionID) {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                viewModel.selectChatSession(session.id)
                            }
                        }
                    }
                    if viewModel.chatSessions.isEmpty {
                        ContentUnavailableView("暂无会话", systemImage: "bubble.left", description: Text("点击左上角新建会话开始。"))
                            .padding(.top, 80)
                    }
                }
                .padding(8)
            }
        }
        .task { viewModel.reloadChatSessions() }
    }

    private var sessionListTitle: String {
        switch viewModel.sessionListFilter {
        case .inbox: "所有会话"
        case .archived: "已归档"
        case .all: "全部会话"
        case .status(let status): status.displayName
        case .label(let labelID): viewModel.governanceConfig.labels.first(where: { $0.id == labelID })?.name ?? labelID
        }
    }
}

private struct CraftDetailPaneView: View {
    @ObservedObject var viewModel: AppViewModel
    var selection: SidebarItem

    var body: some View {
        Group {
            switch selection {
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
            case .pendingApprovals:
                AgentPendingApprovalReviewView(viewModel: viewModel)
            case .memoryChangeLog:
                MemoryChangeLogView(viewModel: viewModel)
            case .extractionDiagnostics:
                GraphExtractionDiagnosticsView(viewModel: viewModel)
            case .automation:
                AutomationRuntimePanelView(viewModel: viewModel)
            case .productOS:
                ProductOSRegistryView(viewModel: viewModel)
            case .sources:
                SourceRuntimePanelView(viewModel: viewModel)
            case .skills:
                SkillRuntimePanelView(viewModel: viewModel)
            case .llmSettings:
                ConnorSettingsDetailView(viewModel: viewModel)
            }
        }
    }
}


private struct CraftSessionRow: View {
    var row: AgentChatSessionPresentation
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: row.isFlagged ? "pin.fill" : icon(for: row.status))
                    .foregroundStyle(row.isFlagged ? .orange : (isSelected ? .accentColor : .secondary))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(row.title)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(row.relativeUpdatedTime)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Text(row.statusText)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusColor(row.status).opacity(0.14), in: Capsule())
                        Text("\(row.messageCount) msgs")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !row.labels.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(Array(row.labels.prefix(3)), id: \.stableID) { label in
                                Text(label.displayText)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.purple.opacity(0.10), in: Capsule())
                            }
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func icon(for status: AgentSessionStatus) -> String {
        switch status {
        case .todo: "circle"
        case .inProgress: "play.circle"
        case .waiting: "clock"
        case .needsReview: "exclamationmark.bubble"
        case .done: "checkmark.circle.fill"
        case .blocked: "nosign"
        case .archived: "archivebox"
        }
    }

    private func statusColor(_ status: AgentSessionStatus) -> Color {
        switch status {
        case .todo: .secondary
        case .inProgress: .blue
        case .waiting: .orange
        case .needsReview: .purple
        case .done: .green
        case .blocked: .red
        case .archived: .gray
        }
    }
}

private struct CraftSettingsListPane: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var selection: SidebarItem?

    var body: some View {
        VStack(spacing: 0) {
            Text("设置")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            Divider()
            VStack(spacing: 0) {
                ForEach(ConnorSettingsSection.allCases) { section in
                    SettingsCategoryRow(
                        title: section.title,
                        subtitle: section.subtitle,
                        systemImage: section.systemImage,
                        isSelected: viewModel.selectedSettingsSection == section
                    ) {
                        selection = .llmSettings
                        viewModel.selectSettingsSection(section)
                    }
                }
            }
            .padding(10)
            Spacer()
        }
    }
}

private struct SettingsCategoryRow: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.medium))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct CraftSimpleListPane: View {
    var title: String
    var subtitle: String
    var rows: [String]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(rows.isEmpty ? ["在右侧查看详情"] : rows, id: \.self) { row in
                        Text(row)
                            .font(.subheadline)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(10)
            }
        }
    }
}

private struct SidebarDisclosure<Content: View>: View {
    var title: String
    var systemImage: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: Content

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 2) {
                content
            }
            .padding(.leading, 12)
            .padding(.top, 3)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
        }
        .disclosureGroupStyle(.automatic)
    }
}

private struct SidebarRow: View {
    var title: String
    var systemImage: String
    var count: Int?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarMutedText: View {
    var text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
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
        .task {
            viewModel.deferViewUpdate {
                viewModel.reloadPromotionCandidates()
            }
        }
    }
}

struct AgentPendingApprovalReviewView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("刷新") { viewModel.reloadPendingApprovals() }
                if let summary = viewModel.lastPendingApprovalResultSummary {
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("request → review → decision → audit → timeline")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if viewModel.pendingApprovals.isEmpty {
                Text("暂无待审批权限请求。Sidecar 只能请求权限，Connor 负责审批、审计和 timeline。")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(viewModel.pendingApprovals) { approval in
                    let row = AppAgentPendingApprovalPresentation(approval)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.title)
                                .font(.headline)
                            Text(row.statusLabel)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(severityColor(row.severity).opacity(0.15), in: Capsule())
                                .foregroundStyle(severityColor(row.severity))
                            Spacer()
                            Text(row.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(row.detail)
                            .font(.subheadline)
                            .textSelection(.enabled)

                        HStack(spacing: 12) {
                            Label("run \(approval.runID)", systemImage: "play.circle")
                            Label("session \(approval.sessionID)", systemImage: "bubble.left.and.bubble.right")
                            if let toolName = approval.toolName {
                                Label(toolName, systemImage: "wrench.and.screwdriver")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        DisclosureGroup("Payload JSON") {
                            Text(approval.payloadJSON)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }

                        HStack {
                            Button("批准") { viewModel.approvePendingApproval(approval) }
                            Button("拒绝", role: .destructive) { viewModel.denyPendingApproval(approval) }
                            Button("取消") { viewModel.cancelPendingApproval(approval) }
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
        .navigationTitle("权限审批")
        .task {
            viewModel.deferViewUpdate {
                viewModel.reloadPendingApprovals()
            }
        }
    }

    private func severityColor(_ severity: AppAgentPendingApprovalSeverity) -> Color {
        switch severity {
        case .warning: .orange
        case .success: .green
        case .error: .red
        case .cancelled: .secondary
        }
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
        .task {
            viewModel.deferViewUpdate {
                viewModel.reloadGraphWriteCandidates()
            }
        }
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
        .task {
            viewModel.deferViewUpdate {
                viewModel.reloadMemoryChangeLog()
            }
        }
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
        .task {
            viewModel.deferViewUpdate {
                viewModel.reloadGraphExtractionTraces()
            }
        }
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

struct ProductOSRegistryView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Product OS Registry")
                            .font(.largeTitle.bold())
                        Text("Phase 5 将 Automation / Labels / Statuses 纳入 Connor-owned 控制平面：自动化只能记录和建议，不能绕过权限、审计和图谱准入。")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("重新加载") {
                        viewModel.reloadProductOSRegistry()
                        viewModel.reloadAutomationConfig()
                        viewModel.reloadSidecarRuntimeDiagnostics()
                    }
                }

                if let message = viewModel.productOSRegistryMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ProductOSRegistrySummary(snapshot: viewModel.productOSRegistry, automationConfig: viewModel.automationConfig, triggerRecords: viewModel.automationTriggerRecords)

                CommercialReadinessProductOSSection(
                    dashboard: viewModel.commercialReadinessDashboard,
                    releaseGateResult: viewModel.commercialReleaseGateResult,
                    onCheck: { viewModel.runCommercialReadinessReleaseGate() }
                )

                GroupBox("Statuses") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.governanceConfig.statuses) { status in
                            HStack {
                                Label(status.name, systemImage: status.systemImage)
                                Spacer()
                                ProductOSRegistryChip("id: \(status.id)")
                                ProductOSRegistryChip(status.isTerminal ? "terminal" : "open")
                                ProductOSRegistryChip("sort: \(status.sortOrder)")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Labels") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.governanceConfig.labels) { label in
                            HStack {
                                Text(label.name).font(.headline)
                                Text(label.id).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                ProductOSRegistryChip(label.valueType.rawValue)
                                ProductOSRegistryChip(label.colorName)
                                if let binding = label.graphBindingKind { ProductOSRegistryChip("graph: \(binding)") }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Automations") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.automationConfig.rules) { rule in
                            ProductOSAutomationRuleRow(rule: rule) { enabled in
                                viewModel.setAutomationRuleEnabled(id: rule.id, isEnabled: enabled)
                            }
                            Divider()
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Automation Trigger Log") {
                    VStack(alignment: .leading, spacing: 10) {
                        if viewModel.automationTriggerRecords.isEmpty {
                            Text("暂无触发记录。状态/标签/Source/Skill 变更后会在这里留下可审计记录。")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.automationTriggerRecords.prefix(8)) { record in
                                ProductOSAutomationRecordRow(record: record)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Sources") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.productOSRegistry.sources) { source in
                            ProductOSSourceRow(source: source) { status in
                                viewModel.setSourceRegistryStatus(id: source.id, status: status)
                            }
                            Divider()
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Skills") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.productOSRegistry.skills) { skill in
                            ProductOSSkillRow(skill: skill) { status in
                                viewModel.setSkillRegistryStatus(id: skill.id, status: status)
                            }
                            Divider()
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Phase 5 Guardrails") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Single Home Root: no multi-workspace abstraction is introduced.", systemImage: "house")
                        Label("Source credentials and connector execution remain governed by Connor.", systemImage: "lock.shield")
                        Label("Skills are instruction profiles; they cannot bypass graph admission or audit.", systemImage: "checkmark.seal")
                        Label("Graph memory stays a kernel, not a normal RAG/source plugin.", systemImage: "brain.head.profile")
                        Label("Automation execution is audit-first: actions are recorded for review before becoming background execution.", systemImage: "bolt.badge.clock")
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Product OS")
    }
}

struct CommercialReadinessProductOSSection: View {
    var dashboard: CommercialReadinessDashboard
    var releaseGateResult: CommercialReadinessReleaseGateResult?
    var onCheck: () -> Void

    var body: some View {
        GroupBox("Commercial Readiness") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dashboard.summary)
                            .font(.headline)
                        if let releaseGateResult {
                            Text(releaseGateResult.summary)
                                .font(.caption)
                                .foregroundStyle(releaseGateResult.status == .ready ? .green : .orange)
                        } else {
                            Text("Run the release gate to verify whether this build is commercial-ready.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Check Commercial Readiness", action: onCheck)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(dashboard.cards) { card in
                        CommercialReadinessProductOSCard(card: card)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct CommercialReadinessProductOSCard: View {
    var card: CommercialReadinessCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.title)
                    .font(.headline)
                Spacer()
                ProductOSRegistryChip(card.status.rawValue)
            }
            Text(card.evidence)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            if !card.metrics.isEmpty {
                HStack(spacing: 6) {
                    ForEach(card.metrics.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        ProductOSRegistryChip("\(key): \(value)")
                    }
                }
            }
            if !card.blockingReasons.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(card.blockingReasons, id: \.self) { reason in
                        Label(reason, systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                    }
                }
                .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(card.status == .ready ? Color.green.opacity(0.08) : Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ProductOSRegistrySummary: View {
    var snapshot: ProductOSRegistrySnapshot
    var automationConfig: ProductOSAutomationConfig
    var triggerRecords: [ProductOSAutomationTriggerRecord]

    var body: some View {
        HStack(spacing: 12) {
            ProductOSMetricCard(title: "Sources", value: "\(snapshot.sources.count)", detail: "\(snapshot.sources.filter { $0.status == .enabled }.count) enabled")
            ProductOSMetricCard(title: "Skills", value: "\(snapshot.skills.count)", detail: "\(snapshot.skills.filter { $0.status == .enabled }.count) enabled")
            ProductOSMetricCard(title: "Automations", value: "\(automationConfig.rules.count)", detail: "\(automationConfig.rules.filter(\.isEnabled).count) enabled")
            ProductOSMetricCard(title: "Triggers", value: "\(triggerRecords.count)", detail: "recent audit log")
        }
    }
}

struct ProductOSMetricCard: View {
    var title: String
    var value: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold())
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ProductOSAutomationRuleRow: View {
    var rule: ProductOSAutomationRule
    var onEnabledChange: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(rule.name).font(.headline)
                    Text(rule.id).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(
                    "Enabled",
                    isOn: Binding(
                        get: { rule.isEnabled },
                        set: { newValue in
                            Task { @MainActor in
                                await Task.yield()
                                onEnabledChange(newValue)
                            }
                        }
                    )
                )
                .toggleStyle(.switch)
                .labelsHidden()
            }
            HStack(spacing: 8) {
                ProductOSRegistryChip("trigger: \(rule.trigger.kind.rawValue)")
                if let status = rule.trigger.status { ProductOSRegistryChip("status: \(status.rawValue)") }
                if let labelID = rule.trigger.labelID { ProductOSRegistryChip("label: \(labelID)") }
                ProductOSRegistryChip(rule.requiresReview ? "review required" : "audit only")
            }
            ForEach(rule.actions) { action in
                Text("• \(action.kind.rawValue): \(action.message)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ProductOSAutomationRecordRow: View {
    var record: ProductOSAutomationTriggerRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.ruleName).font(.headline)
                Spacer()
                ProductOSRegistryChip(record.trigger.rawValue)
            }
            Text("Session: \(record.sessionID)")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(record.actionSummaries, id: \.self) { summary in
                Text("• \(summary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ProductOSSourceRow: View {
    var source: ProductOSSourceDefinition
    var onStatusChange: (ProductOSRegistryEntryStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.displayName).font(.headline)
                    Text(source.id).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                ProductOSRegistryStatusPicker(status: source.status, onChange: onStatusChange)
            }
            HStack(spacing: 8) {
                ProductOSRegistryChip(source.kind.rawValue)
                ProductOSRegistryChip(source.credentialRequirement.rawValue)
                ProductOSRegistryChip("graph: \(source.graphIngestionEnabled ? "on" : "off")")
                ProductOSRegistryChip("write: \(source.graphWritePolicy.rawValue)")
            }
            Text(source.notes).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ProductOSSkillRow: View {
    var skill: ProductOSSkillDefinition
    var onStatusChange: (ProductOSRegistryEntryStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(skill.displayName).font(.headline)
                    Text(skill.id).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                ProductOSRegistryStatusPicker(status: skill.status, onChange: onStatusChange)
            }
            HStack(spacing: 8) {
                ProductOSRegistryChip(skill.scope.rawValue)
                ProductOSRegistryChip("triggers: \(skill.triggers.map(\.rawValue).joined(separator: ", "))")
                ProductOSRegistryChip("graph: \(skill.graphContextPolicy.rawValue)")
            }
            Text(skill.notes).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ProductOSRegistryStatusPicker: View {
    var status: ProductOSRegistryEntryStatus
    var onChange: (ProductOSRegistryEntryStatus) -> Void

    var body: some View {
        Picker(
            "Status",
            selection: Binding(
                get: { status },
                set: { newValue in
                    Task { @MainActor in
                        await Task.yield()
                        onChange(newValue)
                    }
                }
            )
        ) {
            ForEach(ProductOSRegistryEntryStatus.allCases, id: \.self) { value in
                Text(value.rawValue).tag(value)
            }
        }
        .labelsHidden()
        .frame(width: 150)
    }
}

struct ProductOSRegistryChip: View {
    var text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
    }
}

struct LLMSettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Picker("模型提供方", selection: $viewModel.llmProviderMode) {
                Text("OpenAI 兼容").tag(AppLLMProviderMode.openAICompatible)
                Text("Claude Sidecar").tag(AppLLMProviderMode.governedClaudeSidecar)
            }
            .pickerStyle(.segmented)

            if viewModel.llmProviderMode == .governedClaudeSidecar {
                GroupBox("Governed Claude SDK Sidecar") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Sidecar executable path，例如 /usr/local/bin/node", text: $viewModel.sidecarExecutablePath)
                            .textFieldStyle(.roundedBorder)
                        TextField("Sidecar arguments，例如 sidecars/claude-agent-engine/claude-sidecar.mjs", text: $viewModel.sidecarArguments)
                            .textFieldStyle(.roundedBorder)
                        TextField("Working directory", text: $viewModel.sidecarWorkingDirectoryPath)
                            .textFieldStyle(.roundedBorder)
                        Picker("Connor 权限模式", selection: $viewModel.sidecarPermissionMode) {
                            Text("只读").tag(AgentPermissionMode.readOnly)
                            Text("写入需审批").tag(AgentPermissionMode.askToWrite)
                            Text("受信写入").tag(AgentPermissionMode.trustedWrite)
                        }
                        .pickerStyle(.segmented)
                        Text("安全边界：SDK permissionMode 固定为 bypassPermissions；Connor 保留 session、pending approval、audit、graph memory 和 product state 主权。Sidecar 模式不允许 allowAll。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                TextField("Base URL", text: $viewModel.llmBaseURLString)
                    .textFieldStyle(.roundedBorder)
                TextField("模型列表（逗号分隔）", text: $viewModel.llmModel)
                    .textFieldStyle(.roundedBorder)
                SecureField("API Key", text: $viewModel.llmAPIKeyInput)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("保存设置") { viewModel.saveLLMSettings() }
                Button("清除 API Key") { viewModel.clearLLMAPIKey() }
                Button("重新加载") { viewModel.loadLLMSettings() }
                Button(viewModel.isTestingLLMConnection ? "测试中…" : "测试连接") {
                    Task { await viewModel.testLLMConnection() }
                }
                .disabled(viewModel.isTestingLLMConnection)
            }

            Text(viewModel.llmHasAPIKey ? "API Key：已本地加密保存" : "API Key：尚未保存")
                .foregroundStyle(viewModel.llmHasAPIKey ? .green : .secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Label("安全提示：API Key 会保存到 Connor Home 的本地加密凭据文件", systemImage: "lock.shield")
                        .font(.caption.weight(.semibold))
                    Text("为减少钥匙串弹窗，Connor Graph Agent 会使用本机生成的 master key 对 API Key 进行 AES-GCM 加密，并写入 Application Support/Connor/config/credentials。")
                    Text("API Key 不会以明文写入应用设置、项目文件或 Git 仓库；删除 API Key 会移除对应加密凭据文件。")
                    Text("这是本机本地加密存储，不依赖 macOS 钥匙串授权弹窗。")
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

struct ConnorSettingsDetailView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    Text(viewModel.selectedSettingsSection.title)
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Button(action: { viewModel.resetRuntimeSettings() }) {
                        Image(systemName: "ellipsis")
                    }
                    .buttonStyle(.borderless)
                    .help("更多")
                }

                Group {
                    switch viewModel.selectedSettingsSection {
                    case .app:
                        SettingsAppSection(viewModel: viewModel)
                    case .ai:
                        SettingsAISection(viewModel: viewModel)
                    case .appearance:
                        SettingsAppearanceSection(viewModel: viewModel)
                    case .input:
                        SettingsInputSection(viewModel: viewModel)
                    case .permissions:
                        SettingsPermissionsSection(viewModel: viewModel)
                    case .labels:
                        SettingsLabelsSection(viewModel: viewModel)
                    case .shortcuts:
                        SettingsShortcutsSection()
                    case .preferences:
                        SettingsPreferencesSection(viewModel: viewModel)
                    }
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .center)

                if let message = viewModel.appSettingsMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 760, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: 760, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 18)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.12))
        .task {
            viewModel.loadRuntimeSettings()
        }
    }
}

private struct SettingsAppSection: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: "通知") {
                SettingsToggleRow(title: "桌面通知", subtitle: "AI 在聊天中完成工作时发送通知。", isOn: $viewModel.desktopNotificationsEnabled)
            }
            SettingsGroup(title: "电源") {
                SettingsToggleRow(title: "保持屏幕常亮", subtitle: "会话运行时防止屏幕关闭。", isOn: $viewModel.keepScreenAwake)
            }
            SettingsGroup(title: "工具") {
                SettingsToggleRow(title: "内置浏览器", subtitle: "如果使用外部浏览器工具，则禁用。", isOn: $viewModel.internalBrowserEnabled)
            }
            SettingsGroup(title: "网络") {
                SettingsToggleRow(title: "HTTP 代理", subtitle: "通过代理服务器路由网络流量。", isOn: $viewModel.httpProxyEnabled)
                if viewModel.httpProxyEnabled {
                    Divider()
                    SettingsTextFieldRow(title: "代理地址", subtitle: "例如 http://127.0.0.1:7890", text: $viewModel.httpProxyURLString)
                }
            }
            SettingsGroup(title: "关于") {
                SettingsValueRow(title: "版本", value: "0.1.0")
                Divider()
                HStack {
                    Text("检查更新")
                    Spacer()
                    Button("立即检查") { viewModel.appSettingsMessage = "当前为本地开发版本。" }
                }
                .font(.subheadline)
            }
            SettingsSaveBar(viewModel: viewModel)
        }
    }
}

private struct SettingsAISection: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: "默认") {
                SettingsPickerRow(title: "连接", subtitle: "新聊天的 API 连接", selection: $viewModel.llmProviderMode) {
                    Text("OpenAI 兼容").tag(AppLLMProviderMode.openAICompatible)
                    Text("Claude Sidecar").tag(AppLLMProviderMode.governedClaudeSidecar)
                }
                Divider()
                SettingsTextFieldRow(title: "模型列表", subtitle: "逗号分隔多个候选模型；聊天输入区每次只选择其中一个实际模型", text: $viewModel.llmModel)
                Divider()
                SettingsPickerRow(title: "权限", subtitle: "新聊天默认权限", selection: $viewModel.defaultPermissionMode) {
                    ForEach(AgentPermissionMode.allCases.filter { $0 != .allowAll }, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            SettingsGroup(title: "连接") {
                SettingsTextFieldRow(title: "Base URL", subtitle: "OpenAI-compatible endpoint", text: $viewModel.llmBaseURLString)
                Divider()
                SecureField("API Key", text: $viewModel.llmAPIKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .padding(.vertical, 6)
                Divider()
                SettingsValueRow(title: "API Key", value: viewModel.llmHasAPIKey ? "已本地加密保存" : "尚未保存")
                Divider()
                HStack(spacing: 10) {
                    Button("保存 AI 设置") {
                        viewModel.saveLLMSettings()
                        viewModel.saveRuntimeSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("清除 API Key") { viewModel.clearLLMAPIKey() }
                    Button(viewModel.isTestingLLMConnection ? "测试中…" : "测试连接") {
                        Task { await viewModel.testLLMConnection() }
                    }
                    .disabled(viewModel.isTestingLLMConnection)
                }
                .controlSize(.regular)
            }

            if viewModel.llmProviderMode == .governedClaudeSidecar {
                SettingsGroup(title: "Claude Sidecar") {
                    SettingsTextFieldRow(title: "可执行文件", subtitle: "例如 /usr/local/bin/node", text: $viewModel.sidecarExecutablePath)
                    Divider()
                    SettingsTextFieldRow(title: "参数", subtitle: "sidecars/claude-agent-engine/claude-sidecar.mjs", text: $viewModel.sidecarArguments)
                    Divider()
                    SettingsTextFieldRow(title: "工作目录", subtitle: "Sidecar 运行目录", text: $viewModel.sidecarWorkingDirectoryPath)
                }
            }

            if let message = viewModel.llmSettingsMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if let message = viewModel.llmHealthCheckMessage {
                Text(message).font(.caption).foregroundStyle(message.contains("OK") || message.contains("available") ? .green : .secondary)
            }
        }
    }
}

private struct SettingsAppearanceSection: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: "默认主题") {
                HStack {
                    Text("模式")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Picker("模式", selection: $viewModel.appearanceMode) {
                        ForEach(ConnorAppearanceMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }
                Divider()
                SettingsValueRow(title: "颜色主题", value: "使用默认")
                Divider()
                SettingsValueRow(title: "字体", value: "系统")
                Divider()
                SettingsValueRow(title: "语言", value: "简体中文")
            }
            SettingsGroup(title: "界面") {
                SettingsToggleRow(title: "连接图标", subtitle: "在会话列表和模型选择器中显示提供商图标。", isOn: $viewModel.showProviderIcons)
                Divider()
                SettingsToggleRow(title: "丰富的工具描述", subtitle: "为工具调用添加操作名称和意图描述。", isOn: $viewModel.richToolDescriptionsEnabled)
            }
            SettingsSaveBar(viewModel: viewModel)
        }
    }
}

private struct SettingsInputSection: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: "发送") {
                SettingsPickerRow(title: "发送消息", subtitle: "选择默认发送快捷键", selection: $viewModel.composerSendShortcut) {
                    Text("Return").tag("return")
                    Text("⌘ Return").tag("cmd-return")
                }
                Divider()
                SettingsToggleRow(title: "自动保存草稿", subtitle: "切换会话时保留未发送输入。", isOn: $viewModel.autoSaveDraftsEnabled)
                Divider()
                SettingsToggleRow(title: "拼写检查", subtitle: "使用系统拼写检查。", isOn: $viewModel.spellCheckEnabled)
            }
            SettingsSaveBar(viewModel: viewModel)
        }
    }
}

private struct SettingsPermissionsSection: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: "默认权限") {
                SettingsPickerRow(title: "新会话权限", subtitle: "控制工具调用和写入操作", selection: $viewModel.defaultPermissionMode) {
                    ForEach(AgentPermissionMode.allCases.filter { $0 != .allowAll }, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Divider()
                SettingsToggleRow(title: "网络访问需要审批", subtitle: "外部网络请求默认进入审批流程。", isOn: $viewModel.requireApprovalForNetwork)
                Divider()
                SettingsToggleRow(title: "Shell 写入需要审批", subtitle: "本地命令涉及写入时默认要求确认。", isOn: $viewModel.requireApprovalForShell)
            }
            SettingsSaveBar(viewModel: viewModel)
        }
    }
}

private struct SettingsLabelsSection: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: "关于标签") {
                Text("标签帮助你用彩色标记整理会话。布尔标签用于筛选，带值标签可表达优先级、截止日期或项目引用。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            SettingsGroup(title: "标签层级") {
                if viewModel.governanceConfig.labels.isEmpty {
                    Text("尚未配置标签。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.governanceConfig.labels) { label in
                        HStack {
                            Circle().fill(color(named: label.colorName)).frame(width: 7, height: 7)
                            Text(label.name).frame(width: 180, alignment: .leading)
                            Text(label.valueType.rawValue).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .font(.subheadline)
                        .padding(.vertical, 7)
                        if label.id != viewModel.governanceConfig.labels.last?.id { Divider() }
                    }
                }
            }
            SettingsGroup(title: "自动应用规则") {
                Text("自动应用规则将在后续版本接入。当前标签定义来自会话治理配置。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func color(named name: String) -> Color {
        switch name {
        case "orange": .orange
        case "purple": .purple
        case "teal": .teal
        case "red": .red
        case "yellow": .yellow
        case "green": .green
        default: .blue
        }
    }
}

private struct SettingsShortcutsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: "通用") {
                ShortcutRow(title: "新建聊天", keys: ["⌘", "N"])
                ShortcutRow(title: "设置", keys: ["⌘", ","])
                ShortcutRow(title: "搜索", keys: ["⌘", "F"])
                ShortcutRow(title: "命令面板", keys: ["⌘", "/"])
            }
            SettingsGroup(title: "导航") {
                ShortcutRow(title: "聚焦侧栏", keys: ["⌘", "1"])
                ShortcutRow(title: "聚焦会话列表", keys: ["⌘", "2"])
                ShortcutRow(title: "聚焦聊天", keys: ["⌘", "3"])
                ShortcutRow(title: "聚焦下一块区域", keys: ["Tab"])
            }
        }
    }
}

private struct SettingsPreferencesSection: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: "基本信息") {
                SettingsTextFieldRow(title: "名称", subtitle: "Connor 如何称呼你。", text: $viewModel.userDisplayName)
                Divider()
                SettingsTextFieldRow(title: "时区", subtitle: "用于相对日期和日程上下文。", text: $viewModel.userTimezone)
            }
            SettingsGroup(title: "位置") {
                SettingsTextFieldRow(title: "城市", subtitle: "用于本地信息和上下文。", text: $viewModel.userCity)
                Divider()
                SettingsTextFieldRow(title: "国家", subtitle: "用于区域格式和上下文。", text: $viewModel.userCountry)
            }
            SettingsGroup(title: "备注") {
                TextEditor(text: $viewModel.userPreferenceNotes)
                    .font(.subheadline)
                    .frame(minHeight: 150)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            SettingsSaveBar(viewModel: viewModel)
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            VStack(spacing: 0) {
                content
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
            )
        }
    }
}

private struct SettingsToggleRow: View {
    var title: String
    var subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .frame(minHeight: 42)
    }
}

private struct SettingsValueRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack {
            Text(title).font(.subheadline.weight(.medium))
            Spacer()
            Text(value).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(minHeight: 42)
    }
}

private struct SettingsTextFieldRow: View {
    var title: String
    var subtitle: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

private struct SettingsPickerRow<Selection: Hashable, Content: View>: View {
    var title: String
    var subtitle: String
    @Binding var selection: Selection
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker(title, selection: $selection) { content }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
        }
        .frame(minHeight: 46)
    }
}

private struct SettingsSaveBar: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack {
            Spacer()
            Button("重新加载") { viewModel.loadRuntimeSettings() }
            Button("保存设置") { viewModel.saveRuntimeSettings() }
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.regular)
    }
}

private struct ShortcutRow: View {
    var title: String
    var keys: [String]

    var body: some View {
        HStack {
            Text(title).font(.subheadline.weight(.medium))
            Spacer()
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.30), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
        }
        .frame(minHeight: 38)
    }
}
