import SwiftUI
import AppKit
import CoreLocation
import IOKit.pwr_mgt
import UserNotifications
import WebKit
import UniformTypeIdentifiers
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

struct AgentChatToast: Identifiable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var message: String
    var systemImage: String
}

enum AppViewModelStartupMode: Equatable {
    case immediate
    case deferred
}

@MainActor
final class AppViewModel: NSObject, ObservableObject {
    let maintenanceCoordinator = AppMaintenanceCoordinator()
    private let chatSessionListRefreshCoordinator = ChatSessionListRefreshCoordinator()
    private lazy var chatSessionCoordinator = ChatSessionCoordinator(
        model: chatFeatureModel.sessions,
        repository: chatSessionRepository
    )
    lazy var chatAttentionCoordinator = ChatAttentionCoordinator(
        model: chatFeatureModel.sessions,
        repository: chatSessionRepository
    )
    lazy var chatBackgroundTaskCoordinator = ChatBackgroundTaskCoordinator(
        model: chatFeatureModel.sessions,
        repository: chatSessionRepository
    )
    lazy var chatApprovalCoordinator = ChatApprovalCoordinator(
        model: chatFeatureModel.approvals,
        repository: repository.map { AppAgentPendingApprovalRepository(store: $0.store) }
    )
    lazy var chatComposerCoordinator = ChatComposerCoordinator(
        model: chatFeatureModel.composer,
        storagePaths: storagePaths
    )
    lazy var chatRunCoordinator = ChatRunCoordinator(
        model: chatFeatureModel.run,
        fallbackSession: fallbackChatSessionStorage
    )

    private static let birthDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let customGenderIdentitySelection = "__custom_gender_identity__"
    static let genderIdentityPresetValues: Set<String> = ["女性", "男性", "非二元", "性别流动", "无性别", "酷儿 / 性别酷儿", "不愿透露"]

    let shellFeatureModel: AppShellFeatureModel
    var selection: SidebarItem? {
        get { shellFeatureModel.selection }
        set { shellFeatureModel.selection = newValue }
    }
    let graphDiagnosticsModel: GraphDiagnosticsModel
    let chatFeatureModel: ChatFeatureModel
    @Published var errorMessage: String?
    @Published var databasePath: String?
    let aiConnectionsModel: AIConnectionsFeatureModel
    var llmConnectionConfigs: [AppLLMConnectionConfig] {
        get { aiConnectionsModel.connectionConfigs }
        set { aiConnectionsModel.connectionConfigs = newValue }
    }
    var llmDefaultConnectionID: String {
        get { aiConnectionsModel.defaultConnectionID }
        set { aiConnectionsModel.defaultConnectionID = newValue }
    }
    var llmConnectionName: String {
        get { aiConnectionsModel.connectionName }
        set { aiConnectionsModel.connectionName = newValue }
    }
    var llmProviderMode: AppLLMProviderMode {
        get { aiConnectionsModel.providerMode }
        set { aiConnectionsModel.providerMode = newValue }
    }
    var llmBaseURLString: String {
        get { aiConnectionsModel.baseURLString }
        set { aiConnectionsModel.baseURLString = newValue }
    }
    var llmModel: String {
        get { aiConnectionsModel.model }
        set { aiConnectionsModel.model = newValue }
    }
    var llmSelectedModel: String {
        get { aiConnectionsModel.selectedModel }
        set { aiConnectionsModel.selectedModel = newValue }
    }
    var llmShouldFetchModelsList: Bool {
        get { aiConnectionsModel.shouldFetchModelsList }
        set { aiConnectionsModel.shouldFetchModelsList = newValue }
    }
    var llmThinkingLevel: AppLLMThinkingLevel {
        get { aiConnectionsModel.thinkingLevel }
        set { aiConnectionsModel.thinkingLevel = newValue }
    }
    var llmAPIKeyInput: String {
        get { aiConnectionsModel.apiKeyInput }
        set { aiConnectionsModel.apiKeyInput = newValue }
    }
    var llmHasAPIKey: Bool {
        get { aiConnectionsModel.hasAPIKey }
        set { aiConnectionsModel.hasAPIKey = newValue }
    }
    @Published var agentPermissionMode: AgentPermissionMode = .readOnly
    var llmSettingsMessage: String? {
        get { aiConnectionsModel.settingsMessage }
        set { aiConnectionsModel.settingsMessage = newValue }
    }
    var llmHealthCheckMessage: String? {
        get { aiConnectionsModel.healthCheckMessage }
        set { aiConnectionsModel.healthCheckMessage = newValue }
    }
    var isTestingLLMConnection: Bool { aiConnectionsModel.isTestingConnection }
    var lastAddedLLMConnectionID: String? { aiConnectionsModel.lastAddedConnectionID }
    var lastAddedLLMCapabilityEvidence: [AppProviderCapabilityEvidence] { aiConnectionsModel.lastAddedCapabilityEvidence }
    var isAddingLLMConnection: Bool { aiConnectionsModel.isAddingConnection }
    var llmModelConnections: [AppLLMModelConnection] { aiConnectionsModel.modelConnections }
    var isLoadingLLMModelConnections: Bool { aiConnectionsModel.isLoadingModelConnections }
    var showWelcomePlaceholder: Bool {
        get { aiConnectionsModel.showsWelcome }
        set { aiConnectionsModel.showsWelcome = newValue }
    }
    let governanceModel: GovernanceFeatureModel
    var governanceConfig: AppSessionGovernanceConfig { governanceModel.config }
    let productOSControlModel: ProductOSControlFeatureModel
    let taskAutomationModel: TaskAutomationFeatureModel
    let sourceRuntimeModel: SourceRuntimeFeatureModel
    let calendarFeatureModel: CalendarFeatureModel
    let contactsFeatureModel: ContactsFeatureModel
    let mailFeatureModel: MailFeatureModel
    let browserFeatureModel: BrowserFeatureModel
    let globalSearchFeatureModel: GlobalSearchFeatureModel
    let rssFeatureModel: RSSFeatureModel
    let skillRuntimeModel: SkillRuntimeFeatureModel
    let chatWorkspaceCoordinator = ChatWorkspaceCoordinator()
    var sessionStateSnapshotsBySessionID: [String: AppSessionStateSnapshot] {
        get { chatWorkspaceCoordinator.stateSnapshotsBySessionID }
        set { chatWorkspaceCoordinator.stateSnapshotsBySessionID = newValue }
    }
    var sessionRecordsBySessionID: [String: [AppSessionRecord]] {
        get { chatWorkspaceCoordinator.recordsBySessionID }
        set { chatWorkspaceCoordinator.recordsBySessionID = newValue }
    }
    var selectedSettingsSection: ConnorSettingsSection {
        get { shellFeatureModel.selectedSettingsSection }
        set { shellFeatureModel.selectedSettingsSection = newValue }
    }
    let appSettingsModel: AppSettingsFeatureModel
    let inputSettingsModel: InputSettingsFeatureModel
    let userPreferencesModel: UserPreferencesFeatureModel
    let workspaceSettingsModel: WorkspaceSettingsFeatureModel
    let permissionSettingsModel: PermissionSettingsFeatureModel
    var focusTopSearchRequestID: UUID? { shellFeatureModel.focusTopSearchRequestID }
    var settingsSectionMessageStore: SettingsSectionMessageStore { shellFeatureModel.settingsSectionMessageStore }
    @Published var memoryOSSearchHealthSummary: String?
    @Published private(set) var isMemoryOSSearchIndexRepairing = false

    private var repository: AppGraphRepository?
    private var memoryOSStore: SQLiteMemoryOSStore?
    private var memoryOSFacade: AppMemoryOSFacade?
    private var chatSessionRepository: AppChatSessionRepository?
    private var activityTimelineCacheWriter: ActivityTimelineCacheWriter?
    private var storagePaths: AppStoragePaths?
    private let runtimeSettingsCoordinator: RuntimeSettingsPersistenceCoordinator
    private var loadedLoopConfiguration = AgentLoopConfiguration()
    private var llmSettingsRepository: AppLLMSettingsRepository { aiConnectionsModel.settingsRepository }
    private var nativeSourceSearchBackend: (any NativeSourceSearchBackend)?

    private var backgroundAIExecutorProvider: BackgroundAIExecutorProvider? {
        guard let factory = chatRunCoordinator.runtimeFactory, let memoryOSFacade else { return nil }
        let store = memoryOSFacade.store
        return BackgroundAIExecutorProvider { facade in
            let model = AgentModelBackgroundToolLoopModel(provider: factory.makeAgentModelProvider())
            let executor = MemoryOSHeadlessKnowledgeLoopExecutor(
                model: model,
                toolExecutor: MemoryOSBackgroundToolExecutor(facade: facade),
                store: store
            )
            let runs = try facade.runBackgroundAIQueueOnce(executor: executor, limit: 3)
            return runs.count
        }
    }
    // Product chat path: ChatRunCoordinator owns NativeSessionManager, backends, run IDs and timelines.
    private var fallbackChatSessionStorage: AgentSession
    private var isLoadingRuntimeSettings = false
    private var hasActivatedRuntimeSettingsSideEffects = false

    private var activeChatSession: AgentSession { chatRunCoordinator.activeSession }

    private var activeChatTranscript: [AgentMessage] { chatRunCoordinator.activeTranscript }

    var isLoadingSelectedChatSessionDetail: Bool { chatSessionCoordinator.isLoadingSelectedDetail }

    func performShortcutAction(_ action: AgentRuntimeShortcutAction) {
        switch action {
        case .newSession:
            performShellCommand(.newSession)
        case .toggleBrowser:
            performShellCommand(.toggleBrowser)
        case .focusTopSearch:
            shellFeatureModel.requestTopSearchFocus()
        case .openSettings:
            performShellCommand(.openSettings)
        case .focusBrowserAddress, .newBrowserTab, .closeBrowserTab, .browserBack, .browserForward, .toggleBrowserBookmarks, .toggleBrowserHistory:
            break
        }
    }

    func setAgentPermissionMode(_ mode: AgentPermissionMode) {
        guard mode != .allowAll else { return }
        agentPermissionMode = mode
        chatRunCoordinator.mutateManager { $0.permissionMode = mode }
        persistLLMSettings(rebuildRuntime: chatFeatureModel.run.submittingSessionIDs.isEmpty)
        chatApprovalCoordinator.permissionModeDidChange()
    }

    func isChatSessionSubmitting(_ sessionID: String) -> Bool {
        chatFeatureModel.run.submittingSessionIDs.contains(sessionID)
    }

    private func restoreChatInputDraft(for sessionID: String?) { chatComposerCoordinator.restore(sessionID: sessionID) }

    func markdownPersistentCacheContext(messageID: String) -> AgentMarkdownPersistentCacheContext? {
        guard let selectedChatSessionID = chatFeatureModel.sessions.selectedSessionID, let storagePaths else { return nil }
        return AgentMarkdownPersistentCacheContext(
            store: AgentMarkdownRenderCacheStore(storagePaths: storagePaths),
            sessionID: selectedChatSessionID,
            messageID: messageID
        )
    }

    func copyAssistantMessageToPasteboard(_ message: AgentChatMessagePresentation) {
        let content = message.message.content
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
        chatComposerCoordinator.showToast(
            title: "已复制回复",
            message: "已复制原始 Markdown 文本。",
            systemImage: "doc.on.doc"
        )
    }

    func exportAssistantMessageToFile(_ message: AgentChatMessagePresentation, now: Date = Date()) {
        let content = message.message.content
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let panel = NSSavePanel()
        panel.title = "导出助理回复"
        panel.message = "选择保存位置和文件名。"
        panel.prompt = "导出"
        panel.nameFieldLabel = "文件名："
        panel.nameFieldStringValue = AssistantMessageExportFormatter.filename(for: message, date: now)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.directoryURL = chatFeatureModel.sessions.selectedArtifactDirectories?.exports

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            chatComposerCoordinator.showToast(
                title: "已导出回复",
                message: url.path,
                systemImage: "square.and.arrow.down"
            )
        } catch {
            chatComposerCoordinator.showToast(
                title: "导出回复失败",
                message: String(describing: error),
                systemImage: "xmark.circle"
            )
        }
    }

    func downloadPreviewImage(_ model: AttachmentPreviewModel) {
        let service = AttachmentImageExportService()
        guard let filename = service.defaultFilename(for: model), let sourceURL = model.sourceFileURL else {
            chatComposerCoordinator.showToast(
                title: "图片下载失败",
                message: AttachmentImageExportError.sourceUnavailable.localizedDescription,
                systemImage: "xmark.circle"
            )
            return
        }

        let panel = NSSavePanel()
        panel.title = "下载图片"
        panel.message = "选择图片保存位置和文件名。"
        panel.prompt = "下载"
        panel.nameFieldLabel = "文件名："
        panel.nameFieldStringValue = filename
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let contentType = UTType(filenameExtension: sourceURL.pathExtension) {
            panel.allowedContentTypes = [contentType]
        }
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        do {
            try service.export(model: model, to: destinationURL)
            chatComposerCoordinator.showToast(
                title: "图片已下载",
                message: destinationURL.path,
                systemImage: "square.and.arrow.down"
            )
        } catch {
            chatComposerCoordinator.showToast(
                title: "图片下载失败",
                message: error.localizedDescription,
                systemImage: "xmark.circle"
            )
        }
    }

    private func buildAttachmentContextPlan(
        sessionID: String,
        attachments: [AgentMessageAttachmentRef],
        perAttachmentCharacterLimit: Int = 20_000,
        totalCharacterLimit: Int = 60_000
    ) -> AttachmentContextPlan {
        AgentAttachmentContextPlanBuilder(
            storagePaths: storagePaths,
            perAttachmentCharacterLimit: perAttachmentCharacterLimit,
            totalCharacterLimit: totalCharacterLimit
        ).build(sessionID: sessionID, attachments: attachments)
    }

    private func buildAttachmentContextPlanOffMain(
        sessionID: String,
        attachments: [AgentMessageAttachmentRef],
        perAttachmentCharacterLimit: Int = 20_000,
        totalCharacterLimit: Int = 60_000
    ) async -> AttachmentContextPlan {
        let builder = AgentAttachmentContextPlanBuilder(
            storagePaths: storagePaths,
            perAttachmentCharacterLimit: perAttachmentCharacterLimit,
            totalCharacterLimit: totalCharacterLimit
        )
        return await Task.detached(priority: .utility) {
            builder.build(sessionID: sessionID, attachments: attachments)
        }.value
    }

    private func refreshSelectedSubmittingState() { chatRunCoordinator.refreshSelectedSubmittingState() }

    func navigate(to item: ConnorNativeShellItem) {
        DispatchQueue.main.async { [weak self] in
            self?.applyNavigation(to: item)
        }
    }

    private func applyNavigation(to item: ConnorNativeShellItem) {
        switch item {
        case .home, .agentChat, .graphMemory:
            browserFeatureModel.isVisible = false
        case .browserWorkspace:
            browserFeatureModel.showWorkspace()
        default:
            break
        }
        shellFeatureModel.applyNavigation(item)
    }

    func performShellCommand(_ commandID: ConnorNativeShellCommandID) {
        switch commandID {
        case .newSession:
            newChatSession()
            navigate(to: .agentChat)
        case .toggleBrowser:
            browserFeatureModel.toggleWorkspaceVisibility()
        case .checkCommercialReadiness:
            runCommercialReadinessReleaseGate()
        case .openGraphMemoryReview, .openApprovals, .openSources, .openSkills, .openAutomation, .openLocalAutomationSurface, .openCalendarSources, .openContactsSources, .openMailSources, .openRSSSources, .openSettings:
            if let command = ConnorNativeShellPresentation.default.command(for: commandID) {
                navigate(to: command.target)
            }
        }
    }

    func openURLInCurrentChatBrowser(_ url: URL) {
        browserFeatureModel.openURL(url)
    }

    private func fallbackNativeSearchResults(kind: NativeSearchSourceKind, query: String, limit: Int) -> [NativeSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        switch kind {
        case .calendar:
            return presentationFallbackCalendarResults(query: trimmed, now: now, limit: limit)
        case .rss:
            return presentationFallbackRSSResults(query: trimmed, now: now, limit: limit)
        case .mail:
            return presentationFallbackMailResults(query: trimmed, now: now, limit: limit)
        case .browserHistory:
            return presentationFallbackBrowserHistoryResults(query: trimmed, now: now, limit: limit)
        }
    }

    private func presentationFallbackCalendarResults(query: String, now: Date, limit: Int) -> [NativeSearchResult] {
        let normalized = query.lowercased()
        return calendarFeatureModel.events
            .filter { event in
                guard !normalized.isEmpty else { return true }
                return event.title.lowercased().contains(normalized)
                    || (event.location?.lowercased().contains(normalized) ?? false)
                    || (event.notes?.lowercased().contains(normalized) ?? false)
                    || event.attendees.contains { attendee in
                        (attendee.name?.lowercased().contains(normalized) ?? false) || (attendee.email?.lowercased().contains(normalized) ?? false)
                    }
            }
            .sorted { $0.start.date < $1.start.date }
            .prefix(limit)
            .map { event in
                NativeSearchResult(
                    id: "calendar:\(event.id.rawValue)",
                    sourceKind: .calendar,
                    externalID: event.id.rawValue,
                    sourceInstanceID: event.calendarID.rawValue,
                    title: event.title,
                    snippet: [event.location, event.notes].compactMap { $0 }.joined(separator: " · "),
                    score: 1,
                    lexicalScore: 1,
                    freshnessScore: 0,
                    fieldScore: 0,
                    temporal: NativeSearchTemporalMetadata(primaryTime: event.start.date, primaryTimeKind: .eventStartAt, eventStartAt: event.start.date, eventEndAt: event.end.date, indexedAt: now),
                    resultTimeLabel: event.start.date.connorLocalFormatted(date: .medium, time: .short)
                )
            }
    }

    private func presentationFallbackRSSResults(query: String, now: Date, limit: Int) -> [NativeSearchResult] {
        rssFeatureModel.presentation.items(sourceID: nil, query: query).prefix(limit).map { item in
            NativeSearchResult(
                id: "rss:\(item.id.rawValue)",
                sourceKind: .rss,
                externalID: item.id.rawValue,
                sourceInstanceID: item.sourceID.rawValue,
                title: item.title,
                snippet: item.snippet,
                score: 1,
                lexicalScore: 1,
                freshnessScore: 0,
                fieldScore: 0,
                temporal: NativeSearchTemporalMetadata(primaryTime: item.publishedAt, primaryTimeKind: .publishedAt, publishedAt: item.publishedAt, fetchedAt: item.fetchedAt, indexedAt: now),
                resultTimeLabel: item.publishedAt.connorLocalFormatted(date: .medium, time: .short)
            )
        }
    }

    private func presentationFallbackMailResults(query: String, now: Date, limit: Int) -> [NativeSearchResult] {
        let normalized = query.lowercased()
        return mailFeatureModel.presentation.messages
            .filter { message in
                guard !normalized.isEmpty else { return true }
                return message.subject.lowercased().contains(normalized)
                    || message.snippet.lowercased().contains(normalized)
                    || message.from.email.lowercased().contains(normalized)
                    || (message.from.name?.lowercased().contains(normalized) ?? false)
                    || message.to.contains { $0.email.lowercased().contains(normalized) || ($0.name?.lowercased().contains(normalized) ?? false) }
            }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { message in
                NativeSearchResult(
                    id: "mail:\(message.id.rawValue)",
                    sourceKind: .mail,
                    externalID: message.id.rawValue,
                    sourceInstanceID: message.accountID.rawValue,
                    title: message.subject.isEmpty ? "(No subject)" : message.subject,
                    snippet: [message.from.name ?? message.from.email, message.snippet].filter { !$0.isEmpty }.joined(separator: " · "),
                    score: 1,
                    lexicalScore: 1,
                    freshnessScore: 0,
                    fieldScore: 0,
                    temporal: NativeSearchTemporalMetadata(primaryTime: message.date, primaryTimeKind: .sentAt, receivedAt: message.date, sentAt: message.date, indexedAt: now),
                    resultTimeLabel: message.date.connorLocalFormatted(date: .medium, time: .short)
                )
            }
    }

    private func presentationFallbackBrowserHistoryResults(query: String, now: Date, limit: Int) -> [NativeSearchResult] {
        browserFeatureModel.fallbackSearchResults(query: query, now: now, limit: limit)
    }

    private func handleGlobalSearchDestination(_ destination: GlobalSearchFeatureModel.Destination) {
        switch destination {
        case .newChat(let prompt):
            newChatSession()
            selection = .agentChat
            Task { @MainActor in
                _ = await submitChat(prompt: prompt, clearComposer: false, displayPrompt: prompt)
            }
        case .webSearch(let url):
            openURLInCurrentChatBrowser(url)
        case .chatSession(let sessionID):
            selection = .agentChat
            selectChatSession(sessionID)
        case .nativeResult(let result):
            openGlobalSearchNativeResult(result)
        case .browserHistoryRecord(let record):
            browserFeatureModel.navigateToHistoryRecord(record)
        case .showAll(let kind, let query):
            switch kind {
            case .chatSessions:
                chatFeatureModel.sessions.searchQuery = query
                browserFeatureModel.isVisible = false
                selection = .agentChat
            case .calendar:
                calendarFeatureModel.searchQuery = query
                selection = .calendar
            case .rss:
                rssFeatureModel.searchQuery = query
                selection = .rss
            case .mail:
                mailFeatureModel.searchQuery = query
                selection = .mail
            case .browserHistory:
                browserFeatureModel.openHistorySearch(query: query)
            }
        }
    }

    private func openGlobalSearchNativeResult(_ result: NativeSearchResult) {
        switch result.sourceKind {
        case .calendar:
            selection = .calendar
            calendarFeatureModel.selectEvent(id: CalendarEventID(rawValue: result.externalID))
        case .rss:
            selection = .rss
            rssFeatureModel.selectItem(id: RSSItemID(rawValue: result.externalID))
        case .mail:
            selection = .mail
            mailFeatureModel.openSearchResult(result)
        case .browserHistory:
            if let id = UUID(uuidString: result.externalID), let record = browserFeatureModel.historyRecord(id: id) {
                browserFeatureModel.navigateToHistoryRecord(record)
            } else {
                browserFeatureModel.openHistorySearch(query: "")
            }
        }
    }

    private func rebuildCalendarSearchIndexIfNeeded(events: [CalendarEvent]) async throws {
        guard let nativeSourceSearchBackend else { return }
        try await nativeSourceSearchBackend.rebuildSource(
            kind: .calendar,
            sourceInstanceID: nil,
            documents: events.map(NativeSourceSearchAdapters.calendarDocument(from:))
        )
    }

    private func scheduleCalendarSearchIndexRefresh(events: [CalendarEvent]) {
        guard nativeSourceSearchBackend != nil else { return }
        Task { @MainActor in
            try? await rebuildCalendarSearchIndexIfNeeded(events: events)
        }
    }

    func openURLInSystemDefaultBrowser(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func openProjectGitHubHelp() {
        guard let url = URL(string: "https://github.com/duanshiwen/connor-graph-agent-mac") else { return }
        openURLInCurrentChatBrowser(url)
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
        AppCommercialReadinessDashboardBuilder().build(
            chatSessions: chatFeatureModel.sessions.sessions,
            activeChatSession: activeChatSession,
            governanceConfig: governanceConfig,
            artifactDirectoriesReady: storagePaths != nil,
            sourceRuntimeConfigurations: sourceRuntimeModel.configurations,
            skillRuntimeDefinitions: skillRuntimeModel.definitions,
            automationConfig: productOSControlModel.automationConfig,
            graphMemoryDashboard: graphMemoryDashboardPresentation
        )
    }


    private var graphMemoryDashboardPresentation: GraphMemoryDashboard {
        GraphMemoryDashboard(summary: GraphMemoryDashboardSummary(pendingCandidateCount: 0, openHoldCount: 0, recentChangeCount: 0), cards: [])
    }

    private var chatSummaryPresentation: AppChatSummaryPresentation {
        AppChatSummaryPresentationBuilder().build(
            latestSummary: chatFeatureModel.run.latestSummary,
            activeSession: activeChatSession,
            isSummarizing: chatFeatureModel.run.isSummarizing,
            hasTranscriptMessages: !chatFeatureModel.run.transcript.isEmpty
        )
    }

    var latestChatSummaryFreshness: AgentSessionSummaryFreshness? {
        chatSummaryPresentation.freshness
    }

    var latestChatSummaryContextMessage: String {
        chatSummaryPresentation.contextMessage
    }

    var latestChatSummaryRefreshState: AgentSessionSummaryRefreshState {
        chatSummaryPresentation.refreshState
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
        rssRuntime: RSSRuntime? = nil,
        calendarLegacyStore: FileBackedCalendarSourceStore? = nil,
        calendarRuntimeStore: FileBackedCalendarSourceRuntimeStore? = nil,
        calendarCredentialStore: AppCalendarCredentialStore = AppCalendarCredentialStore(),
        calendarSystemSnapshotLoader: @escaping CalendarFeatureModel.SystemSnapshotLoader = {
            try await CalendarEventKitAdapter.fetchSystemSnapshot()
        },
        contactsProfileStore: (any PersonProfileStore)? = nil,
        contactsRelationshipStore: (any PersonRelationshipStore)? = nil,
        contactsSystemLoader: @escaping ContactsFeatureModel.SystemContactsLoader = {
            try await ContactsSystemAdapter.fetchSystemContacts()
        },
        injectedMailStore: FileBackedMailSourceStore? = nil,
        injectedMailPreferencesStore: (any MailPreferencesStore)? = nil,
        mailCredentialStore: AppMailCredentialStore = AppMailCredentialStore(),
        injectedNativeSourceSearchBackend: (any NativeSourceSearchBackend)? = nil,
        injectedSessionSearchIndexService: SessionSearchIndexService? = nil,
        injectedMemoryOSStore: SQLiteMemoryOSStore? = nil,
        injectedMemoryOSFacade: AppMemoryOSFacade? = nil,
        injectedMemoryOSSearchHealthSummary: String? = nil,
        injectedMemoryOSInitializationError: String? = nil,
        startupMode: AppViewModelStartupMode = .immediate,
        calendarRemoteAccountSynchronizer: @escaping CalendarFeatureModel.RemoteAccountSynchronizer = { account, credential, runID, runtimeStore in
            let engine = CalendarSourceSyncEngine(
                connectors: [
                    CalendarICSSubscriptionConnector(),
                    CalendarCalDAVConnector(kind: .genericCalDAV),
                    CalendarCalDAVConnector(kind: .appleICloudCalDAV),
                    CalendarCalDAVConnector(kind: .fastmailCalDAV),
                    CalendarCalDAVConnector(kind: .nextcloudCalDAV)
                ],
                runtimeStore: runtimeStore
            )
            return try await engine.sync(request: CalendarSourceSyncRequest(account: account, credential: credential, runID: runID))
        },
        llmSettingsRepository: AppLLMSettingsRepository = AppLLMSettingsRepository(),
        llmConnectionSetupServiceFactory: (@MainActor (AppLLMSettingsRepository) -> AppLLMConnectionSetupService)? = nil
    ) {
        self.shellFeatureModel = AppShellFeatureModel()
        self.aiConnectionsModel = AIConnectionsFeatureModel(
            settingsRepository: llmSettingsRepository,
            setupServiceFactory: llmConnectionSetupServiceFactory
        )
        self.chatFeatureModel = ChatFeatureModel()
        self.appSettingsModel = AppSettingsFeatureModel()
        self.inputSettingsModel = InputSettingsFeatureModel()
        self.userPreferencesModel = UserPreferencesFeatureModel()
        self.workspaceSettingsModel = WorkspaceSettingsFeatureModel()
        self.permissionSettingsModel = PermissionSettingsFeatureModel()
        self.runtimeSettingsCoordinator = RuntimeSettingsPersistenceCoordinator(
            repository: storagePaths.map { AppRuntimeSettingsRepository(configDirectory: $0.configDirectory) }
        )
        self.governanceModel = GovernanceFeatureModel(
            config: governanceConfig,
            repository: storagePaths.map { AppSessionGovernanceConfigRepository(configDirectory: $0.configDirectory) }
        )
        self.graphDiagnosticsModel = GraphDiagnosticsModel(
            entities: entities,
            statements: statements,
            episodes: episodes,
            observeLogEntries: observeLogEntries,
            databasePath: databasePath,
            repository: repository
        )
        self.repository = repository
        self.productOSControlModel = ProductOSControlFeatureModel(
            registry: productOSRegistry,
            automationConfig: automationConfig,
            registryRepository: storagePaths.map { AppProductOSRegistryRepository(storagePaths: $0) },
            automationRepository: storagePaths.map { AppProductOSAutomationRepository(storagePaths: $0) }
        )
        self.taskAutomationModel = TaskAutomationFeatureModel(
            repository: storagePaths.map { AppTaskManagementRepository(storagePaths: $0) }
        )
        self.sourceRuntimeModel = SourceRuntimeFeatureModel(
            repository: storagePaths.map { AppMCPSourceRuntimeRepository(storagePaths: $0) }
        )
        let resolvedCalendarLegacyStore = calendarLegacyStore ?? storagePaths.map { paths in
            FileBackedCalendarSourceStore(storagePaths: paths)
        }
        let resolvedCalendarRuntimeStore = calendarRuntimeStore ?? storagePaths.map { paths in
            FileBackedCalendarSourceRuntimeStore(storagePaths: paths)
        }
        self.calendarFeatureModel = CalendarFeatureModel(
            legacyStore: resolvedCalendarLegacyStore,
            runtimeStore: resolvedCalendarRuntimeStore,
            credentialStore: calendarCredentialStore,
            systemSnapshotLoader: calendarSystemSnapshotLoader,
            remoteAccountSynchronizer: calendarRemoteAccountSynchronizer
        )
        let contactsDatabaseURL = storagePaths?.applicationSupportDirectory
            .appendingPathComponent("contacts", isDirectory: true)
            .appendingPathComponent("person-profiles.sqlite")
        let resolvedContactsProfileStore = contactsProfileStore ?? (startupMode == .immediate ? contactsDatabaseURL.flatMap {
            try? SQLitePersonProfileStore(databaseURL: $0)
        } : nil)
        let resolvedContactsRelationshipStore = contactsRelationshipStore ?? (startupMode == .immediate ? contactsDatabaseURL.flatMap {
            try? SQLitePersonRelationshipStore(databaseURL: $0)
        } : nil)
        self.contactsFeatureModel = ContactsFeatureModel(
            profileStore: resolvedContactsProfileStore,
            relationshipStore: resolvedContactsRelationshipStore,
            systemContactsLoader: contactsSystemLoader
        )
        let nativeSourceSearchBackend: (any NativeSourceSearchBackend)? = injectedNativeSourceSearchBackend ?? {
            guard startupMode == .immediate, let storagePaths else { return nil }
            if let sqliteBackend = try? SQLiteNativeSourceSearchBackend(
                databaseURL: storagePaths.nativeSourceSearchDatabaseURL
            ) {
                return sqliteBackend
            }
            return NativeSourceSearchService(storagePaths: storagePaths)
        }()
        let resolvedMailStore = injectedMailStore ?? (startupMode == .immediate ? storagePaths.map { FileBackedMailSourceStore(storagePaths: $0, searchService: nativeSourceSearchBackend) } : nil)
        let resolvedMailPreferencesStore = injectedMailPreferencesStore ?? storagePaths.map { FileBackedMailPreferencesStore(storagePaths: $0) }
        self.mailFeatureModel = MailFeatureModel(store: resolvedMailStore, preferencesStore: resolvedMailPreferencesStore, credentialStore: mailCredentialStore)
        self.browserFeatureModel = BrowserFeatureModel(
            historyStore: storagePaths.map { BrowserHistoryStore(historyURL: $0.browserHistoryURL) },
            bookmarkStore: storagePaths.map { BrowserBookmarkStore(bookmarksURL: $0.browserBookmarksURL) },
            nativeSourceSearchBackend: nativeSourceSearchBackend
        )
        let resolvedSessionSearchIndexService = injectedSessionSearchIndexService ?? (startupMode == .immediate ? storagePaths.flatMap { try? SessionSearchIndexService(databaseURL: $0.sessionSearchDatabaseURL) } : nil)
        let resolvedGlobalSearchHistoryRepository = storagePaths.map { AppGlobalSearchHistoryRepository(historyURL: $0.globalSearchHistoryURL) }
        self.globalSearchFeatureModel = GlobalSearchFeatureModel(
            nativeSourceSearchBackend: nativeSourceSearchBackend,
            sessionSearchIndexService: resolvedSessionSearchIndexService,
            historyRepository: resolvedGlobalSearchHistoryRepository
        )
        let resolvedRSSRuntime = rssRuntime ?? storagePaths.map { paths in
            RSSRuntime(
                repository: FileBackedRSSSourceRepository(storagePaths: paths),
                cache: FileBackedRSSSourceCache(storagePaths: paths, searchService: nativeSourceSearchBackend)
            )
        } ?? RSSRuntime(repository: InMemoryRSSSourceRepository(), cache: InMemoryRSSSourceCache())
        self.rssFeatureModel = RSSFeatureModel(runtime: resolvedRSSRuntime)
        self.skillRuntimeModel = SkillRuntimeFeatureModel(
            repository: storagePaths.map { AppSkillRuntimeRepository(storagePaths: $0) },
            storagePaths: storagePaths
        )
        self.storagePaths = storagePaths
        if storagePaths != nil {
            self.nativeSourceSearchBackend = nativeSourceSearchBackend
        }
        if let repository {
            let chatSessionRepository = AppChatSessionRepository(store: repository.store, storagePaths: storagePaths, governanceConfig: governanceConfig)
            self.chatSessionRepository = chatSessionRepository
            self.activityTimelineCacheWriter = ActivityTimelineCacheWriter(persistor: chatSessionRepository)
        }
        if startupMode == .deferred || injectedMemoryOSStore != nil || injectedMemoryOSFacade != nil || injectedMemoryOSInitializationError != nil {
            self.memoryOSStore = injectedMemoryOSStore
            self.memoryOSFacade = injectedMemoryOSFacade
            self.memoryOSSearchHealthSummary = injectedMemoryOSSearchHealthSummary
            self.errorMessage = injectedMemoryOSInitializationError
        } else if let storagePaths {
            do {
                let store = try SQLiteMemoryOSStore(path: storagePaths.memoryOSDatabaseURL.path)
                try store.migrate()
                self.memoryOSStore = store
                let initialSearchHealth = AppMemoryOSSearchKernelFactory.healthReport(paths: storagePaths)
                let searchKernel = try AppMemoryOSSearchKernelFactory.makeLiveIfHealthy(paths: storagePaths)
                self.memoryOSSearchHealthSummary = initialSearchHealth.status == .healthy
                    ? "Memory OS SearchKernel 正常：索引已验证。"
                    : "Memory OS SearchKernel 降级启动，后台将修复索引：\(initialSearchHealth.messages.joined(separator: ", "))"
                self.memoryOSFacade = AppMemoryOSFacade(store: store, searchKernel: searchKernel)
            } catch {
                self.errorMessage = "Memory OS 初始化失败：\(error)"
            }
        }
        self.databasePath = databasePath
        let initialSession = AgentSession(id: "app-session")
        self.fallbackChatSessionStorage = initialSession
        super.init()
        aiConnectionsModel.onRuntimeSettingsChanged = { [weak self] rebuildRuntime in
            guard let self else { return }
            if rebuildRuntime {
                self.rebuildNativeSessionManagerForActiveSession()
            } else {
                self.chatRunCoordinator.mutateManager { $0.permissionMode = self.agentPermissionMode }
            }
        }
        aiConnectionsModel.onConnectionSetup = { [weak self] connection in
            self?.syncActiveSessionLLMOverride(to: connection)
        }
        governanceModel.sessionsProvider = { [weak self] in
            guard let self else { return [] }
            return try self.chatSessionRepository?.loadSessions(filter: .all)
                ?? self.chatFeatureModel.sessions.allSessions
        }
        governanceModel.removeLabelFromSessions = { [weak self] labelID in
            guard let self, let repository = self.chatSessionRepository else { return 0 }
            let sessions = try repository.loadSessions(filter: .all)
            var removedCount = 0
            for session in sessions where session.governance.labels.contains(where: { $0.id == labelID }) {
                let labels = session.governance.labels.filter { $0.id != labelID }
                _ = try repository.setLabels(sessionID: session.id, labels: labels)
                removedCount += 1
            }
            return removedCount
        }
        governanceModel.onConfigSaved = { [weak self] config in
            guard let self else { return }
            self.chatSessionRepository?.governanceConfig = config
            try self.productOSControlModel.reloadAutomationAfterGovernanceChange(governanceConfig: config)
        }
        governanceModel.onSettingsMessage = { [weak self] message, section in
            self?.shellFeatureModel.setSettingsMessage(message, for: section)
        }
        governanceModel.onError = { [weak self] message in
            self?.errorMessage = message
        }
        governanceModel.onDefinitionDeleted = { [weak self] deletion in
            guard let self else { return }
            switch deletion {
            case .status(let id):
                if case .status(let selected) = self.chatFeatureModel.sessions.filter, selected.rawValue == id {
                    self.setSessionListFilter(.all, restoreWorkspaceMode: false)
                } else {
                    self.reloadChatSessions(restoreWorkspaceMode: false)
                }
            case .label(let id):
                if case .label(let selected) = self.chatFeatureModel.sessions.filter, selected == id {
                    self.setSessionListFilter(.all, restoreWorkspaceMode: false)
                } else {
                    self.reloadChatSessions(restoreWorkspaceMode: false)
                }
            }
        }
        if startupMode == .immediate {
            maintenanceCoordinator.startObservers()
        }
        if let repository {
            self.chatRunCoordinator.installRuntimeFactory(AppGraphAgentRuntimeFactory(
                store: repository.store,
                settingsRepository: llmSettingsRepository,
                storagePaths: storagePaths,
                calendarRuntimeStore: calendarFeatureModel.agentRuntimeStore,
                calendarCredentialStore: calendarCredentialStore,
                personProfileStore: contactsFeatureModel.agentProfileStore,
                mailRuntime: mailFeatureModel.agentRuntime,
                rssRuntime: rssFeatureModel.agentRuntime,
                browserAssistedSearchHandler: { [weak self] request in
                    await MainActor.run {
                        guard let self else { return nil }
                        let state = self.browserFeatureModel.startAssistedSearch(
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
                },
                browserAssistedWebFetchHandler: { [weak self] request in
                    guard let self else { return nil }
                    return await self.browserFeatureModel.performAssistedWebFetch(request)
                }
            ))
        }
        graphDiagnosticsModel.onPromotedSnapshot = { [weak self] snapshot in
            self?.applyPromotedGraphSnapshot(snapshot)
        }
        productOSControlModel.sessionIDProvider = { [weak self] in
            guard let self else { return "" }
            return self.chatFeatureModel.sessions.selectedSessionID ?? self.activeChatSession.id
        }
        productOSControlModel.onEvent = { [weak self] event in
            guard let self else { return }
            self.objectWillChange.send()
            switch event {
            case .operationSucceeded:
                break
            case .operationFailed(let message):
                self.errorMessage = message
            case .registryChanged(let kind, let entryID, let status, let message, let automationContext):
                self.appendProductOSRegistryEvent(
                    kind: kind.rawValue,
                    entryID: entryID,
                    status: status,
                    message: message
                )
                self.productOSControlModel.evaluateAutomation(
                    automationContext,
                    governanceConfig: self.governanceConfig
                )
            case .automationMatched(let records):
                self.appendAutomationMatchedEvents(records)
            case .releaseGateChecked:
                self.navigate(to: .productOS)
            }
        }
        appSettingsModel.onChanged = { [weak self] in self?.scheduleRuntimeSettingsAutosave() }
        permissionSettingsModel.onChanged = { [weak self] in self?.scheduleRuntimeSettingsAutosave() }
        inputSettingsModel.onSpeechTranscriptionDisabled = { [weak self] in
            self?.stopSpeechTranscriptionForDisabledSetting()
        }
        inputSettingsModel.onChanged = { [weak self] in self?.scheduleRuntimeSettingsAutosave() }
        userPreferencesModel.onChanged = { [weak self] in self?.scheduleRuntimeSettingsAutosave() }
        workspaceSettingsModel.onSaveSessionWorkspace = { [weak self] roots, defaultPath in
            self?.saveWorkspaceDraftsToCurrentSession(roots: roots, defaultWorkingDirectoryPath: defaultPath)
        }
        workspaceSettingsModel.onChanged = { [weak self] in
            self?.objectWillChange.send()
            self?.scheduleRuntimeSettingsAutosave()
        }
        runtimeSettingsCoordinator.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .loaded:
                break
            case .saved(let settings):
                self.handleRuntimeSettingsSaved(settings)
            case .failed(let message):
                self.errorMessage = message
            }
        }
        globalSearchFeatureModel.sessionsProvider = { [weak self] in self?.chatFeatureModel.sessions.allSessions ?? [] }
        globalSearchFeatureModel.fallbackNativeSearchProvider = { [weak self] kind, query, limit in
            self?.fallbackNativeSearchResults(kind: kind, query: query, limit: limit) ?? []
        }
        globalSearchFeatureModel.sourceReadinessProvider = { [weak self] in
            await self?.browserFeatureModel.waitForPendingIndexOperations()
        }
        globalSearchFeatureModel.defaultSearchURLProvider = { [weak self] query in
            self?.appSettingsModel.defaultSearchEngine.searchURL(for: query)
        }
        globalSearchFeatureModel.onDestination = { [weak self] destination in
            self?.handleGlobalSearchDestination(destination)
        }
        browserFeatureModel.sessionContextProvider = { [weak self] in
            guard let self else {
                return BrowserFeatureModel.SessionContext(
                    selectedSessionID: nil,
                    activeSessionID: "__fallback__",
                    sessionTitlesByID: [:]
                )
            }
            let sessions = self.chatFeatureModel.sessions.allSessions + self.chatFeatureModel.sessions.sessions
            return BrowserFeatureModel.SessionContext(
                selectedSessionID: self.chatFeatureModel.sessions.selectedSessionID,
                activeSessionID: self.activeChatSession.id,
                sessionTitlesByID: Dictionary(sessions.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
            )
        }
        browserFeatureModel.persistWorkspaceSnapshot = { [weak self] snapshot, sessionID in
            self?.persistBrowserWorkspaceSnapshot(snapshot, for: sessionID)
        }
        browserFeatureModel.onShowWorkspace = { [weak self] sessionID in
            guard let self else { return }
            self.selection = .agentChat
            if self.chatFeatureModel.sessions.selectedSessionID != sessionID { self.selectChatSession(sessionID) }
            self.rememberWorkspaceMode(.browser, for: sessionID)
        }
        browserFeatureModel.onReturnFromWorkspace = { [weak self] sessionID in
            guard let self else { return }
            if let sessionID, sessionID != self.chatFeatureModel.sessions.selectedSessionID { self.selectChatSession(sessionID) }
            self.selection = .agentChat
            self.rememberWorkspaceMode(.conversation, for: sessionID)
        }
        browserFeatureModel.onNavigateHistoryRecord = { [weak self] record, url in
            self?.openBrowserHistoryRecord(record, url: url)
        }
        browserFeatureModel.onEvent = { [weak self] event in
            self?.objectWillChange.send()
            if case let .operationFailed(message) = event { self?.errorMessage = message }
        }
        taskAutomationModel.createdBySessionIDProvider = { [weak self] in
            guard let self else { return "" }
            return self.chatFeatureModel.sessions.selectedSessionID ?? self.activeChatSession.id
        }
        taskAutomationModel.onEvent = { [weak self] event in
            self?.objectWillChange.send()
            switch event {
            case .operationSucceeded:
                break
            case .operationFailed(let message):
                self?.errorMessage = message
            }
        }
        sourceRuntimeModel.workingDirectoryURLProvider = { [weak self] in
            self?.workspaceSettingsModel.primaryRoot
                .map(\.path)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        }
        sourceRuntimeModel.onEvent = { [weak self] event in
            self?.objectWillChange.send()
            switch event {
            case .operationSucceeded:
                break
            case .operationFailed(let message):
                self?.errorMessage = message
            }
        }
        rssFeatureModel.sessionIDProvider = { [weak self] in
            guard let self else { return nil }
            return self.chatFeatureModel.sessions.selectedSessionID ?? self.activeChatSession.id
        }
        rssFeatureModel.sourceSetChanged = { [weak self] scope in
            guard let self else { return }
            switch scope {
            case .rssOnly:
                try await self.maintenanceCoordinator.reconcile(.rss)
            case .allSources:
                try await self.maintenanceCoordinator.reconcile(.allSources)
            }
            self.taskAutomationModel.reload()
        }
        rssFeatureModel.onEvent = { [weak self] event in
            self?.objectWillChange.send()
            if case let .operationFailed(message) = event {
                self?.errorMessage = message
            }
        }
        calendarFeatureModel.sourceSetChanged = { [weak self] in
            guard let self else { return }
            try await self.maintenanceCoordinator.reconcile(.calendar)
            self.taskAutomationModel.reload()
        }
        calendarFeatureModel.onEvent = { [weak self] event in
            guard let self else { return }
            self.objectWillChange.send()
            switch event {
            case .operationSucceeded:
                break
            case .operationFailed(let message):
                self.errorMessage = message
            case .presentationChanged(let events):
                self.scheduleCalendarSearchIndexRefresh(events: events)
            }
        }
        mailFeatureModel.sourceSetChanged = { [weak self] in
            guard let self else { return }
            try await self.maintenanceCoordinator.reconcile(.mail)
            self.taskAutomationModel.reload()
        }
        mailFeatureModel.onEvent = { [weak self] event in
            guard let self else { return }
            self.objectWillChange.send()
            if case let .operationFailed(message) = event { self.errorMessage = message }
        }
        contactsFeatureModel.onEvent = { [weak self] event in
            guard let self else { return }
            self.objectWillChange.send()
            switch event {
            case .operationSucceeded:
                break
            case .operationFailed(let message):
                self.errorMessage = message
            case .settingsMessageChanged(let message):
                self.setSettingsMessage(message, for: .preferences)
            }
        }
        if chatSessionRepository != nil {
            skillRuntimeModel.onAddRequest = { [weak self] request in
                guard let self else { throw AppChatRuntimeUnavailableError.nativeSessionManagerUnavailable }
                return try await self.performAddSkillRequest(request)
            }
            skillRuntimeModel.onEditRequest = { [weak self] card, request in
                guard let self else { throw AppChatRuntimeUnavailableError.nativeSessionManagerUnavailable }
                try await self.performEditSkillRequest(card: card, request: request)
            }
        }
        skillRuntimeModel.onEvent = { [weak self] event in
            self?.objectWillChange.send()
            switch event {
            case .operationSucceeded:
                break
            case .operationFailed(let message):
                self?.errorMessage = message
            }
        }
        chatSessionCoordinator.activeSessionIDProvider = { [weak self] in
            self?.activeChatSession.id ?? ""
        }
        chatSessionCoordinator.onSelectionWillChange = { [weak self] previousID, _ in
            guard let self else { return }
            if previousID != nil { _ = self.stopSpeechTranscriptionIfRunningForLeavingSession(previousID) }
            self.rememberCurrentWorkspaceMode()
        }
        chatSessionCoordinator.onSelectionStarted = { [weak self] sessionID in
            guard let self else { return }
            self.chatRunCoordinator.prepareSelection(sessionID: sessionID)
            self.chatFeatureModel.sessions.selectedArtifactDirectories = nil
        }
        chatSessionCoordinator.onSelectionLoaded = { [weak self] snapshot, generation, startedAt in
            self?.applySelectedChatSessionSnapshot(snapshot, generation: generation, startedAt: startedAt)
        }
        chatSessionCoordinator.onReloadSelectedSession = { [weak self] session, shouldRestoreWorkspaceMode in
            guard let self, let repository = self.chatSessionRepository else { return }
            let sessionID = session.id
            try self.loadSessionCapsule(sessionID: sessionID)
            try self.chatBackgroundTaskCoordinator.load(sessionID: sessionID)
            chatRunCoordinator.installManager(self.makeNativeSessionManager(for: session), fallbackSession: session)
            self.replaceSelectedChatTranscript(session.messages)
            self.restoreChatInputDraft(for: sessionID)
            self.refreshSelectedSubmittingState()
            if self.chatRunCoordinator.timeline(sessionID: sessionID) == nil {
                try self.restoreLatestAgentEventTimeline(sessionID: sessionID)
            }
            self.chatRunCoordinator.applyPresentation(
                timeline: self.chatRunCoordinator.timeline(sessionID: sessionID) ?? [],
                summary: try repository.loadLatestSummary(sessionID: sessionID),
                sessionID: sessionID
            )
            self.chatFeatureModel.sessions.selectedArtifactDirectories = try repository.artifactDirectories(sessionID: sessionID)
            if shouldRestoreWorkspaceMode { self.restoreWorkspaceMode(for: sessionID) }
        }
        chatSessionCoordinator.onSelectionCleared = { [weak self] in
            self?.clearSelectedChatRuntime()
        }
        chatSessionCoordinator.onSessionsChanged = { [weak self] sessions in
            self?.rebuildSessionSearchIndexSoon(sessions: sessions)
            self?.synchronizeSessionReadStates(from: sessions)
        }
        chatSessionCoordinator.onError = { [weak self] message in
            self?.errorMessage = message
        }
        chatAttentionCoordinator.selectedNavigation = { [weak self] in self?.selection ?? .agentChat }
        chatAttentionCoordinator.notificationSettings = { [weak self] in
            guard let self else { return (false, .none) }
            return (self.appSettingsModel.desktopNotificationsEnabled, self.appSettingsModel.sessionNewMessageNotificationLevel)
        }
        chatAttentionCoordinator.latestSelectedMessageID = { [weak self] in self?.chatFeatureModel.run.transcript.last?.id }
        chatAttentionCoordinator.canUseUserNotifications = { Bundle.main.bundleURL.pathExtension == "app" }
        chatAttentionCoordinator.onLoadedReadStateChanged = { [weak self] sessionID, state in
            guard let self, self.chatRunCoordinator.fallbackSession.id == sessionID else { return }
            var session = self.chatRunCoordinator.fallbackSession
            session.readState = state
            self.chatRunCoordinator.updateFallbackSession(session)
        }
        chatAttentionCoordinator.onError = { [weak self] message in self?.errorMessage = message }
        chatBackgroundTaskCoordinator.generateTitle = { [weak self] prompts, sessionID in
            guard let self else { throw CancellationError() }
            return try await self.generateTitleFromUserPrompts(prompts, sessionID: sessionID)
        }
        chatBackgroundTaskCoordinator.onSessionRenamed = { [weak self] session in self?.synchronizeRenamedChatSession(session) }
        chatBackgroundTaskCoordinator.onRequestListRefresh = { [weak self] reason in self?.scheduleChatSessionListRefresh(reason: reason) }
        chatBackgroundTaskCoordinator.onError = { [weak self] message in self?.errorMessage = message }
        chatApprovalCoordinator.activeSessionID = { [weak self] in self?.chatRunCoordinator.activeSession.id ?? "" }
        chatApprovalCoordinator.permissionMode = { [weak self] in self?.agentPermissionMode ?? .askToWrite }
        chatApprovalCoordinator.backendForApproval = { [weak self] approval in self?.backendForPendingApproval(approval) }
        chatApprovalCoordinator.onAlwaysAllow = { [weak self] in
            guard let self else { return }
            self.agentPermissionMode = .trustedWrite
            self.saveLLMSettings()
        }
        chatApprovalCoordinator.onError = { [weak self] message in self?.errorMessage = message }
        chatComposerCoordinator.selectedSessionID = { [weak self] in self?.chatFeatureModel.sessions.selectedSessionID }
        chatComposerCoordinator.autoSaveDraftsEnabled = { [weak self] in self?.inputSettingsModel.autoSaveDraftsEnabled ?? true }
        chatComposerCoordinator.speechEnabled = { [weak self] in self?.inputSettingsModel.sessionSpeechTranscriptionEnabled ?? false }
        chatComposerCoordinator.selectedModelID = { [weak self] in self?.llmSelectedModel ?? "" }
        chatComposerCoordinator.skillDisplayName = { [weak self] slug in
            self?.skillRuntimeModel.definitions.first(where: { $0.slug == slug })?.manifest.name
                ?? self?.skillRuntimeModel.presentation.cards.first(where: { $0.id == slug })?.title
                ?? slug
        }
        chatComposerCoordinator.onBackgroundTask = { [weak self] task in self?.chatBackgroundTaskCoordinator.upsert(task) }
        chatRunCoordinator.selectedSessionID = { [weak self] in self?.chatFeatureModel.sessions.selectedSessionID }
        chatRunCoordinator.onTimelineChanged = { [weak self] sessionID, timeline in
            self?.scheduleActivityTimelineCacheSave(sessionID: sessionID, timeline: timeline)
        }
        chatRunCoordinator.onSubmittingChanged = { [weak self] in
            guard let self else { return }
            self.maintenanceCoordinator.updateKeepScreenAwake(
                enabled: self.appSettingsModel.keepScreenAwake,
                hasActiveRun: self.chatRunCoordinator.isActive
            )
        }
        maintenanceCoordinator.runScheduledTasks = { [weak self] in await self?.performScheduledTaskRun() }
        maintenanceCoordinator.runBackgroundJobs = { [weak self] in
            guard let self else { return }
            await self.maintenanceCoordinator.runMemoryBackgroundJobs(
                facade: self.memoryOSFacade,
                aiExecutorProvider: self.backgroundAIExecutorProvider,
                onError: { [weak self] in self?.errorMessage = $0 }
            )
        }
        maintenanceCoordinator.runDailySweep = { [weak self] in
            guard let self else { return }
            await self.maintenanceCoordinator.runMemoryDailySweep(facade: self.memoryOSFacade)
        }
        maintenanceCoordinator.onApplicationDidFinishLaunching = { [weak self] in self?.chatAttentionCoordinator.refreshDockBadge() }
        maintenanceCoordinator.reconcileSources = { [weak self] scope in
            guard let self else { throw CancellationError() }
            switch scope {
            case .allSources: try await self.reconcileSourceRefreshTasks()
            case .rss: try await self.reconcileRSSSourceRefreshTasks()
            case .calendar: try await self.reconcileCalendarAccountRefreshTasks()
            case .mail: try await self.reconcileMailAccountRefreshTasks()
            }
        }
        if startupMode == .immediate {
            runImmediateStartupWork(initialSession: initialSession)
        }
    }

    private func runImmediateStartupWork(initialSession: AgentSession) {
        prepareInteractiveStartup(initialSession: initialSession)
        productOSControlModel.reloadRegistry()
        productOSControlModel.reloadAutomation(governanceConfig: governanceConfig)
        productOSControlModel.reloadExecutionHistory()
        taskAutomationModel.reload()
        Task { @MainActor in
            do {
                try await maintenanceCoordinator.reconcile(.allSources)
                taskAutomationModel.reload()
            } catch {
                errorMessage = String(describing: error)
            }
        }
        sourceRuntimeModel.reload()
        skillRuntimeModel.reload()
        Task { await rssFeatureModel.reload() }
        Task { await calendarFeatureModel.reload() }
        Task { await contactsFeatureModel.reload() }
        Task { await mailFeatureModel.reload() }
        browserFeatureModel.loadHistory()
        graphDiagnosticsModel.reloadSchemaHealthReport()
        scheduleMemoryOSSearchIndexRepairIfNeeded()
    }

    func prepareInteractiveStartup(snapshot: AppInteractiveBootstrapSnapshot? = nil) {
        guard let snapshot else {
            prepareInteractiveStartup(initialSession: chatRunCoordinator.fallbackSession)
            return
        }
        applyInteractiveLLMSettings(snapshot.llmSettings)
        applyInteractiveRuntimeSettings(snapshot.runtimeSettings)
        applyInteractiveSessionContent(snapshot.sessionContent)
        Task { await reloadLLMModelConnections() }
    }

    func prepareDemoInteractiveStartup() {
        let session = chatRunCoordinator.fallbackSession
        chatSessionCoordinator.installStartupSessions([session], allSessions: [session])
        synchronizeSessionReadStates(from: [session])
        chatSessionCoordinator.adoptDirectSelection(session.id)
        replaceSelectedChatTranscript(session.messages)
        chatRunCoordinator.installManager(chatRunCoordinator.runtimeFactory?.makeNativeSessionManager(session: session))
    }

    private func applyInteractiveLLMSettings(_ result: StartupDomainResult<AppLLMSettings>) {
        guard let settings = result.value else {
            if let failureMessage = result.failureMessage { errorMessage = failureMessage }
            return
        }
        aiConnectionsModel.apply(settings)
    }

    private func applyInteractiveRuntimeSettings(_ result: StartupDomainResult<AgentRuntimeSettings>) {
        guard let settings = result.value else {
            if let failureMessage = result.failureMessage { errorMessage = failureMessage }
            return
        }
        runtimeSettingsCoordinator.installLoadedSnapshot(settings)
        isLoadingRuntimeSettings = true
        loadedLoopConfiguration = settings.loop
        appSettingsModel.apply(settings)
        inputSettingsModel.apply(settings)
        permissionSettingsModel.apply(settings)
        workspaceSettingsModel.applyRecentPaths(settings.workspace.recentWorkspacePaths)
        userPreferencesModel.apply(settings.preferences)
        let shouldPersistSystemDefaults = userPreferencesModel.fillEmptyFieldsFromSystem()
        browserFeatureModel.internalBrowserEnabled = settings.app.internalBrowserEnabled
        shellFeatureModel.clearAllSettingsMessages()
        isLoadingRuntimeSettings = false
        if hasActivatedRuntimeSettingsSideEffects { applyRuntimeSettingsSideEffects() }
        if shouldPersistSystemDefaults { scheduleRuntimeSettingsAutosave() }
    }

    private func applyInteractiveSessionContent(_ result: StartupDomainResult<InitialSessionContentSnapshot>) {
        guard let snapshot = result.value else {
            replaceSelectedChatTranscript(activeChatTranscript)
            chatSessionCoordinator.installStartupSessions([activeChatSession], allSessions: [activeChatSession])
            synchronizeSessionReadStates(from: chatFeatureModel.sessions.allSessions)
            chatSessionCoordinator.adoptDirectSelection(activeChatSession.id)
            chatRunCoordinator.installManager(chatRunCoordinator.runtimeFactory?.makeNativeSessionManager(session: activeChatSession))
            if let failureMessage = result.failureMessage { errorMessage = failureMessage }
            return
        }
        chatSessionCoordinator.installStartupSessions(snapshot.sessions, allSessions: snapshot.allSessions)
        rebuildSessionSearchIndexSoon(sessions: snapshot.allSessions)
        synchronizeSessionReadStates(from: snapshot.allSessions)
        guard let session = snapshot.selectedSession else {
            clearSelectedChatSessionDetail()
            return
        }
        let sessionID = session.id
        chatSessionCoordinator.adoptDirectSelection(sessionID)
        if let state = snapshot.state {
            sessionStateSnapshotsBySessionID[sessionID] = state
            syncWorkspaceDraftsFromSession(state)
            if let mode = ChatSessionWorkspaceMode(rawValue: state.selectedPane ?? "") {
                chatWorkspaceCoordinator.setMode(mode, for: sessionID)
            }
        }
        sessionRecordsBySessionID[sessionID] = snapshot.records
        if let browserState = snapshot.browserState {
            browserFeatureModel.installLoadedWorkspaceSnapshot(browserState, for: sessionID)
        }
        chatBackgroundTaskCoordinator.install(snapshot.backgroundTasks, sessionID: sessionID)
        chatRunCoordinator.installManager(makeNativeSessionManager(for: session), fallbackSession: session)
        replaceSelectedChatTranscript(session.messages)
        restoreChatInputDraft(for: sessionID)
        refreshSelectedSubmittingState()
        chatRunCoordinator.applyPresentation(timeline: snapshot.timeline, summary: snapshot.latestSummary, sessionID: sessionID)
        chatFeatureModel.sessions.selectedArtifactDirectories = snapshot.artifactDirectories
        restoreWorkspaceMode(for: sessionID)
    }

    private func prepareInteractiveStartup(initialSession: AgentSession) {
        loadLLMSettings()
        Task { await reloadLLMModelConnections() }
        updateWelcomeState()
        loadRuntimeSettings()
        chatRunCoordinator.installManager(chatRunCoordinator.runtimeFactory?.makeNativeSessionManager(session: initialSession))
        reloadChatSessions()
    }

    func loadStartupContent(snapshot: AppContentBootstrapSnapshot? = nil) async {
        if let snapshot {
            productOSControlModel.applyStartupSnapshot(snapshot.productOS)
            taskAutomationModel.applyStartupSnapshot(snapshot.tasks)
            sourceRuntimeModel.applyStartupSnapshot(snapshot.sources)
            skillRuntimeModel.applyStartupSnapshot(snapshot.skills)
            browserFeatureModel.applyStartupHistory(snapshot.browserHistory)
        }

        async let rss: Void = rssFeatureModel.reload()
        async let calendar: Void = calendarFeatureModel.reload()
        async let contacts: Void = contactsFeatureModel.reload()
        async let mail: Void = mailFeatureModel.reload()
        _ = await (rss, calendar, contacts, mail)
    }

    func reconcileStartupRefreshTasks() async {
        do {
            try await maintenanceCoordinator.reconcile(.allSources)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func startStartupMaintenance(snapshot: AppMaintenanceBootstrapSnapshot? = nil) async {
        maintenanceCoordinator.startObservers()
        if let snapshot {
            taskAutomationModel.applyStartupSnapshot(snapshot.tasks)
            graphDiagnosticsModel.applyStartupMaintenance(
                promotionCandidates: snapshot.promotionCandidates,
                schemaHealth: snapshot.schemaHealth
            )
            if let approvals = snapshot.pendingApprovals.value {
                chatApprovalCoordinator.install(approvals)
            } else if let failureMessage = snapshot.pendingApprovals.failureMessage {
                errorMessage = failureMessage
            }
        }
        scheduleMemoryOSSearchIndexRepairIfNeeded()
    }

    func shutdownRuntimeResourcesForTests() {
        shutdownRuntimeResources()
    }

    func shutdownRuntimeResources() {
        maintenanceCoordinator.shutdown()
        chatSessionCoordinator.shutdown()
        chatApprovalCoordinator.shutdown()
        chatRunCoordinator.shutdown()
        chatComposerCoordinator.shutdown()
        chatBackgroundTaskCoordinator.shutdown()
        chatFeatureModel.shutdown()
        globalSearchFeatureModel.shutdown()
        runtimeSettingsCoordinator.shutdown()
        userPreferencesModel.shutdown()
        rssFeatureModel.shutdown()
        calendarFeatureModel.shutdown()
        contactsFeatureModel.shutdown()
        mailFeatureModel.shutdown()
        browserFeatureModel.shutdown()
    }

    private func applyPromotedGraphSnapshot(_ snapshot: GraphStoreSnapshot) {
        graphDiagnosticsModel.apply(snapshot: snapshot)
        let session = activeChatSession
        chatRunCoordinator.installManager(makeNativeSessionManager(for: session), fallbackSession: session)
        Task { await graphDiagnosticsModel.runSearch() }
        chatApprovalCoordinator.reload()
    }

    private func scheduleMemoryOSSearchIndexRepairIfNeeded() {
        maintenanceCoordinator.scheduleMemorySearchRepair(
            storagePaths: storagePaths,
            onStarted: { [weak self] messages in
                self?.isMemoryOSSearchIndexRepairing = true
                self?.memoryOSSearchHealthSummary = "Memory OS SearchKernel 后台修复中：\(messages)"
            },
            onSucceeded: { [weak self] documentCount, repairedKernel in
                guard let self else { return }
                self.isMemoryOSSearchIndexRepairing = false
                self.memoryOSSearchHealthSummary = "Memory OS SearchKernel 正常：后台索引已重建（\(documentCount) 条文档）。"
                if let store = self.memoryOSStore {
                    self.memoryOSFacade = AppMemoryOSFacade(store: store, searchKernel: repairedKernel)
                }
                self.rebuildNativeSessionManagerForActiveSession()
            },
            onFailed: { [weak self] message in
                self?.isMemoryOSSearchIndexRepairing = false
                self?.memoryOSSearchHealthSummary = "Memory OS SearchKernel 后台修复失败：\(message)"
            }
        )
    }

    private func performScheduledTaskRun() async {
        guard taskAutomationModel.beginScheduledTaskRun() else { return }
        guard let taskManagementRepository = taskAutomationModel.repository else {
            taskAutomationModel.endScheduledTaskRun()
            return
        }
        defer { taskAutomationModel.endScheduledTaskRun() }
        let runner = TaskTargetRunner.appRuntime(
            mailRefresh: { [weak self] request in
                guard let self else { throw TaskTargetRunnerError.unsupportedTarget("mail") }
                return try await self.mailFeatureModel.refreshForScheduledTask(sourceInstanceID: request.sourceInstanceID, runID: request.runID)
            },
            calendarRefresh: { [weak self] request in
                guard let self else { throw TaskTargetRunnerError.unsupportedTarget("calendar") }
                return await self.refreshCalendarForScheduledTask(sourceInstanceID: request.sourceInstanceID, runID: request.runID)
            },
            rssRefresh: { [weak self] request in
                guard let self else { throw TaskTargetRunnerError.unsupportedTarget("rss") }
                return try await self.refreshRSSForScheduledTask(sourceInstanceID: request.sourceInstanceID, runID: request.runID)
            },
            sessionMessage: { [weak self] request in
                guard let self else { throw TaskTargetRunnerError.unsupportedTarget("session.ai") }
                return await self.performTaskSessionMessage(request)
            },
            memoryOSPipeline: { [weak self] request in
                guard let self else { throw TaskTargetRunnerError.unsupportedTarget("memory_os.pipeline") }
                return try await self.performMemoryOSPipelineTask(request)
            }
        )
        do {
            try await maintenanceCoordinator.reconcile(.allSources)
            let scheduler = TaskSchedulerService()
            let service = TaskSchedulerRunnerService(repository: taskManagementRepository, scheduler: scheduler, runner: runner)
            _ = try await service.runDueTasks()
            taskAutomationModel.reload()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func reconcileSourceRefreshTasks(now: Date = Date()) async throws {
        try await reconcileRSSSourceRefreshTasks(now: now)
        try await reconcileCalendarAccountRefreshTasks(now: now)
        try await reconcileMailAccountRefreshTasks(now: now)
    }

    private func reconcileRSSSourceRefreshTasks(now: Date = Date()) async throws {
        guard let taskManagementRepository = taskAutomationModel.repository else { return }
        let materializer = SourceRefreshTaskMaterializer(taskRepository: taskManagementRepository, rssSourceRepository: rssFeatureModel.repository)
        _ = try await materializer.reconcileRSSSourceRefreshTasks(now: now)
    }

    private func reconcileCalendarAccountRefreshTasks(now: Date = Date()) async throws {
        guard let taskManagementRepository = taskAutomationModel.repository else { return }
        let materializer = CalendarRefreshTaskMaterializer(
            taskRepository: taskManagementRepository,
            calendarSourceRepository: calendarFeatureModel.accountRepository
        )
        _ = try await materializer.reconcileCalendarAccountRefreshTasks(now: now)
    }

    private func reconcileMailAccountRefreshTasks(now: Date = Date()) async throws {
        guard let taskManagementRepository = taskAutomationModel.repository,
              let repository = mailFeatureModel.sourceRepository else { return }
        let materializer = MailRefreshTaskMaterializer(taskRepository: taskManagementRepository, mailSourceRepository: repository)
        _ = try await materializer.reconcileMailAccountRefreshTasks(now: now)
    }

    private func refreshCalendarForScheduledTask(sourceInstanceID: String?, runID: String?) async -> String {
        await calendarFeatureModel.refreshForScheduledTask(
            sourceInstanceID: sourceInstanceID,
            runID: runID
        )
    }

    private func performMemoryOSPipelineTask(_ request: MemoryOSPipelineTaskRequest) async throws -> String {
        guard let memoryOSFacade else { throw TaskTargetRunnerError.unsupportedTarget("memory_os.pipeline") }
        switch request.operationName {
        case "plan_l1_unified_projection_jobs":
            let jobs = try memoryOSFacade.enqueueL1UnifiedProjectionBackgroundJobs()
            return "Memory OS planned \(jobs.count) L1 unified projection job(s)"
        default:
            throw TaskTargetRunnerError.unsupportedTarget("memory_os.pipeline:\(request.operationName)")
        }
    }

    private func refreshRSSForScheduledTask(sourceInstanceID: String?, runID: String?) async throws -> String {
        try await rssFeatureModel.refreshForScheduledTask(
            sourceInstanceID: sourceInstanceID,
            runID: runID
        )
    }

    private func performTaskSessionMessage(_ request: TaskSessionMessageRequest) async -> String {
        if request.createNewSession {
            guard let chatSessionRepository else { return "Session repository unavailable" }
            do {
                let session = try chatSessionRepository.createSession(title: request.title ?? "定时任务会话")
                reloadChatSessions()
                chatSessionCoordinator.adoptDirectSelection(session.id)
                chatRunCoordinator.installManager(makeNativeSessionManager(for: session), fallbackSession: session)
                _ = await submitChat(prompt: request.message, clearComposer: false)
                return "created session \(session.id) and sent task message"
            } catch {
                return "failed to create task session: \(error)"
            }
        }
        guard let sessionID = request.sessionID else { return "Missing sessionID" }
        chatSessionCoordinator.adoptDirectSelection(sessionID)
        if let session = try? chatSessionRepository?.loadSession(id: sessionID) {
            chatRunCoordinator.installManager(makeNativeSessionManager(for: session), fallbackSession: session)
        }
        _ = await submitChat(prompt: request.message, clearComposer: false)
        return "sent task message to session \(sessionID)"
    }

    func handleRSSFollowRequest(_ request: RSSFollowRequest) {
        let currentSessionID = chatFeatureModel.sessions.selectedSessionID ?? activeChatSession.id
        if browserFeatureModel.focusExistingTab(urlString: request.url.absoluteString, preferredSessionID: currentSessionID) {
            errorMessage = nil
            return
        }
        guard let chatSessionRepository else { return }
        rememberCurrentWorkspaceMode()
        do {
            let session = try chatSessionRepository.createSession(title: rssFollowSessionTitle(request.title))
            chatSessionCoordinator.adoptDirectSelection(session.id)
            chatRunCoordinator.clearProcessTimelines()
            browserFeatureModel.resetWorkspaceBinding()
            chatFeatureModel.sessions.selectedArtifactDirectories = try chatSessionRepository.artifactDirectories(sessionID: session.id)
            try loadSessionCapsule(sessionID: session.id)
            try chatBackgroundTaskCoordinator.load(sessionID: session.id)
            chatRunCoordinator.prepareNewSession(session, manager: makeNativeSessionManager(for: session))
            restoreChatInputDraft(for: session.id)
            reloadChatSessions(restoreWorkspaceMode: false)
            chatSessionCoordinator.adoptDirectSelection(session.id)
            openURLInCurrentChatBrowser(request.url)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func rssFollowSessionTitle(_ rawTitle: String) -> String {
        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return "关注 \(trimmedTitle.isEmpty ? "RSS 文章" : trimmedTitle)"
    }

    private func performAddSkillRequest(_ request: String) async throws -> String {
        guard let chatSessionRepository else {
            throw AppChatRuntimeUnavailableError.nativeSessionManagerUnavailable
        }
        let knownSkillSlugs = currentUserSkillSlugs()
        let title = sanitizedSessionTitle("添加技能：\(request)")
        let session = try chatSessionRepository.createSession(title: title)
        rememberWorkspaceMode(.conversation, for: session.id)
        try chatBackgroundTaskCoordinator.load(sessionID: session.id)
        reloadChatSessions(restoreWorkspaceMode: false)
        try await runAddSkillRequestInBackgroundSession(session: session, userRequest: request)
        let createdSlug = try ensureSkillPackageExists(for: request, excluding: knownSkillSlugs)
        reloadChatSessions(restoreWorkspaceMode: false)
        return createdSlug
    }

    private func performEditSkillRequest(card: SkillManagerCard, request: String) async throws {
        guard let chatSessionRepository else {
            throw AppChatRuntimeUnavailableError.nativeSessionManagerUnavailable
        }
        let title = sanitizedSessionTitle("编辑技能：\(card.title)")
        let session = try chatSessionRepository.createSession(title: title)
        rememberWorkspaceMode(.conversation, for: session.id)
        try chatBackgroundTaskCoordinator.load(sessionID: session.id)
        reloadChatSessions(restoreWorkspaceMode: false)
        try await runSkillRequestInBackgroundSession(
            session: session,
            prompt: buildEditSkillAgentPrompt(card: card, userRequest: request),
            displayPrompt: "编辑技能：\(card.title) — \(request)"
        )
        reloadChatSessions(restoreWorkspaceMode: false)
    }

    private func runAddSkillRequestInBackgroundSession(session: AgentSession, userRequest: String) async throws {
        try await runSkillRequestInBackgroundSession(
            session: session,
            prompt: buildAddSkillAgentPrompt(userRequest: userRequest),
            displayPrompt: "添加技能：\(userRequest)"
        )
    }

    private func runSkillRequestInBackgroundSession(session: AgentSession, prompt: String, displayPrompt: String) async throws {
        guard var manager = makeNativeSessionManager(for: session) else {
            throw AppChatRuntimeUnavailableError.nativeSessionManagerUnavailable
        }
        manager.permissionMode = .trustedWrite
        let sessionID = session.id
        let liveBackend = manager.backend
        guard chatRunCoordinator.begin(sessionID: sessionID, backend: liveBackend) else {
            throw AppChatRuntimeUnavailableError.nativeSessionManagerUnavailable
        }
        defer { chatRunCoordinator.finish(sessionID: sessionID) }
        _ = try await manager.submit(
            prompt,
            sessionSummary: nil,
            displayPrompt: displayPrompt,
            onRunStarted: { [weak self] runID in
                _ = self?.chatRunCoordinator.registerRun(sessionID: sessionID, runID: runID, backend: liveBackend)
            },
            onEventPresentation: { [weak self] presentation in
                guard let self else { return }
                self.chatRunCoordinator.appendEvent(presentation, sessionID: sessionID)
                self.skillRuntimeModel.reloadIfNeeded(after: presentation)
            }
        )
    }

    private func buildAddSkillAgentPrompt(userRequest: String) -> String {
        SkillAgentPromptBuilder().addSkillPrompt(
            userRequest: userRequest,
            skillRootPath: storagePaths?.skillsDirectory.path ?? "~/Library/Application Support/Connor/skills",
            existingSlugs: currentUserSkillSlugs()
        )
    }

    private func buildEditSkillAgentPrompt(card: SkillManagerCard, userRequest: String) -> String {
        SkillAgentPromptBuilder().editSkillPrompt(card: card, userRequest: userRequest)
    }

    private func currentUserSkillSlugs() -> Set<String> {
        guard let storagePaths else { return [] }
        let root = storagePaths.skillsDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return Set(entries.compactMap { entry in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
            guard FileManager.default.fileExists(atPath: entry.appendingPathComponent("SKILL.md").path) else { return nil }
            return entry.lastPathComponent
        })
    }

    private func ensureSkillPackageExists(for userRequest: String, excluding previousSlugs: Set<String>) throws -> String {
        guard let storagePaths else { throw AppChatRuntimeUnavailableError.nativeSessionManagerUnavailable }
        let currentSlugs = currentUserSkillSlugs()
        if let created = currentSlugs.subtracting(previousSlugs).sorted().first {
            return created
        }
        let planner = SkillCreationFallbackPlanner()
        let identity = planner.suggestedIdentity(for: userRequest, existingSlugs: currentSlugs)
        let directory = storagePaths.skillsDirectory.appendingPathComponent(identity.slug, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let skillURL = directory.appendingPathComponent("SKILL.md")
        try planner.generatedSkillMarkdown(name: identity.name, slug: identity.slug, userRequest: userRequest).write(to: skillURL, atomically: true, encoding: .utf8)
        return identity.slug
    }

    func runCommercialReadinessReleaseGate() {
        productOSControlModel.runCommercialReadinessReleaseGate(dashboard: commercialReadinessDashboard)
    }

    private func appendAutomationMatchedEvents(_ records: [ProductOSAutomationTriggerRecord]) {
        for record in records {
            let payload = AgentAutomationPlaceholderEvent(
                sessionID: record.sessionID,
                trigger: record.trigger.rawValue,
                message: "Automation \(record.ruleName) matched. Actions are recorded for governed review: \(record.actionSummaries.joined(separator: "; "))"
            )
            chatFeatureModel.run.eventTimeline.insert(AgentEventPresenter().presentation(for: .automationTriggered(payload)), at: 0)
        }
    }

    private func appendProductOSRegistryEvent(kind: String, entryID: String, status: ProductOSRegistryEntryStatus, message: String) {
        let sessionID = chatFeatureModel.sessions.selectedSessionID ?? activeChatSession.id
        let payload = AgentProductOSRegistryEvent(
            sessionID: sessionID,
            registryKind: kind,
            entryID: entryID,
            status: status,
            message: message
        )
        let event: AgentEvent = kind == "source" ? .sourceRegistryChanged(payload) : .skillRegistryChanged(payload)
        chatFeatureModel.run.eventTimeline.insert(AgentEventPresenter().presentation(for: event), at: 0)
    }

    func loadLLMSettings() {
        aiConnectionsModel.loadSettings()
        if let message = aiConnectionsModel.errorMessage { errorMessage = message }
    }

    func reloadLLMModelConnections() async {
        await aiConnectionsModel.reloadModelConnections()
    }

    func updateWelcomeState() {
        aiConnectionsModel.updateWelcomeState()
    }

    func handleSuccessfulLLMSetup() {
        aiConnectionsModel.handleSuccessfulSetup()
    }

    func selectLLMModel(_ modelID: String, providerMode: AppLLMProviderMode, connectionID: String? = nil) {
        guard !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        llmProviderMode = providerMode
        if let connectionID { llmDefaultConnectionID = connectionID }
        llmSelectedModel = modelID

        // Write session-level override (not global)
        let sessionID = chatFeatureModel.sessions.selectedSessionID ?? activeChatSession.id
        var state = sessionStateSnapshotsBySessionID[sessionID]
            ?? AppSessionStateSnapshot(sessionID: sessionID)
        state.llmOverride = SessionLLMOverride(
            providerMode: providerMode.rawValue,
            model: modelID,
            connectionID: connectionID,
            thinkingLevel: state.llmOverride?.thinkingLevel
        )
        state.updatedAt = Date()
        sessionStateSnapshotsBySessionID[sessionID] = state
        try? chatSessionRepository?.saveSessionState(state, sessionID: sessionID)

        rebuildNativeSessionManagerForActiveSession()
        Task { await reloadLLMModelConnections() }
    }

    func saveLLMSettings() {
        persistLLMSettings(rebuildRuntime: true)
    }

    func selectDefaultLLMConnection(_ connectionID: String) {
        aiConnectionsModel.selectDefaultConnection(connectionID)
    }

    func selectLLMThinkingLevel(_ level: AppLLMThinkingLevel) {
        llmThinkingLevel = level
        let sessionID = chatFeatureModel.sessions.selectedSessionID ?? activeChatSession.id
        var state = sessionStateSnapshotsBySessionID[sessionID]
            ?? AppSessionStateSnapshot(sessionID: sessionID)
        let settings = try? llmSettingsRepository.loadSettings()
        let providerMode = state.llmOverride?.providerMode ?? llmProviderMode.rawValue
        let model = state.llmOverride?.model ?? llmSelectedModel
        let connectionID = state.llmOverride?.connectionID ?? llmDefaultConnectionID
        state.llmOverride = SessionLLMOverride(
            providerMode: providerMode,
            model: model,
            baseURLString: state.llmOverride?.baseURLString,
            connectionID: connectionID,
            thinkingLevel: level.rawValue
        )
        state.updatedAt = Date()
        sessionStateSnapshotsBySessionID[sessionID] = state
        try? chatSessionRepository?.saveSessionState(state, sessionID: sessionID)
        if state.llmOverride?.connectionID == nil, settings?.defaultConnectionID == connectionID {
            // Keep the session override explicit; this setting is intentionally session-scoped.
        }
        rebuildNativeSessionManagerForActiveSession()
    }

    func selectDefaultLLMThinkingLevel(_ level: AppLLMThinkingLevel) {
        aiConnectionsModel.selectDefaultThinkingLevel(level)
        if let message = aiConnectionsModel.errorMessage { errorMessage = message }
    }

    @discardableResult
    func addLLMConnection(
        providerMode: AppLLMProviderMode,
        name: String? = nil,
        baseURLString: String? = nil,
        model: String? = nil,
        selectedModel: String? = nil
    ) -> AppLLMConnectionConfig {
        let idBase = providerMode == .openAICompatible ? "openai-compatible" : "claude"
        let id = "\(idBase)-\(UUID().uuidString.prefix(8).lowercased())"
        return addLLMConnection(
            id: id,
            providerMode: providerMode,
            name: name,
            baseURLString: baseURLString,
            model: model,
            selectedModel: selectedModel,
            hasAPIKey: false
        )
    }

    @discardableResult
    func addAuthenticatedLLMConnection(
        id: String,
        providerMode: AppLLMProviderMode,
        name: String,
        baseURLString: String,
        model: String,
        selectedModel: String,
        apiKey: String? = nil,
        oauthTokens: AppLLMOAuthTokens? = nil
    ) throws -> AppLLMConnectionConfig {
        let connection = addLLMConnection(
            id: id,
            providerMode: providerMode,
            name: name,
            baseURLString: baseURLString,
            model: model,
            selectedModel: selectedModel,
            hasAPIKey: apiKey?.isEmpty == false || oauthTokens != nil
        )
        let settings = AppLLMSettings(connections: llmConnectionConfigs, defaultConnectionID: connection.id)
        try llmSettingsRepository.save(settings: settings, apiKey: apiKey)
        if let oauthTokens {
            try llmSettingsRepository.saveOAuthTokens(oauthTokens, connectionID: connection.id)
        }
        loadLLMSettings()
        rebuildNativeSessionManagerForActiveSession()
        Task { await reloadLLMModelConnections() }
        return connection
    }

    @discardableResult
    func setupLLMConnection(_ input: AppLLMConnectionSetupInput) async throws -> AppLLMConnectionConfig {
        let connection = try await aiConnectionsModel.setupConnection(input)
        errorMessage = aiConnectionsModel.errorMessage
        return connection
    }

    @discardableResult
    private func addLLMConnection(
        id: String,
        providerMode: AppLLMProviderMode,
        name: String? = nil,
        baseURLString: String? = nil,
        model: String? = nil,
        selectedModel: String? = nil,
        hasAPIKey: Bool,
        shouldFetchModelsList: Bool = true
    ) -> AppLLMConnectionConfig {
        let defaultName = providerMode == .openAICompatible ? "新 OpenAI Compatible 连接" : "新 Claude 连接"
        let defaultBaseURL = providerMode == .openAICompatible ? "https://api.openai.com/v1" : ""
        let defaultModel = providerMode == .openAICompatible ? "gpt-4o-mini" : "claude-sdk-default"
        let normalizedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? model! : defaultModel
        let normalizedSelectedModel = selectedModel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? selectedModel! : AppLLMConnectionConfig.firstModel(in: normalizedModel)
        let connection = AppLLMConnectionConfig(
            id: id,
            name: name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? name! : defaultName,
            providerMode: providerMode,
            baseURLString: baseURLString ?? defaultBaseURL,
            model: normalizedModel,
            selectedModel: normalizedSelectedModel,
            hasAPIKey: hasAPIKey,
            shouldFetchModelsList: shouldFetchModelsList
        )
        llmConnectionConfigs.removeAll { $0.id == connection.id }
        llmConnectionConfigs.append(connection)
        llmDefaultConnectionID = connection.id
        selectDefaultLLMConnection(connection.id)
        return connection
    }

    func deleteSelectedLLMConnection() {
        deleteLLMConnection(llmDefaultConnectionID)
    }

    func deleteLLMConnection(_ connectionID: String) {
        aiConnectionsModel.deleteConnection(connectionID)
        errorMessage = aiConnectionsModel.errorMessage
    }

    func capabilityDetailPresentation(for connectionID: String) -> AppProviderCapabilityDetailPresentation? {
        aiConnectionsModel.capabilityDetailPresentation(for: connectionID)
    }

    func renameLLMConnection(_ connectionID: String, name: String) {
        aiConnectionsModel.renameConnection(connectionID, name: name)
        errorMessage = aiConnectionsModel.errorMessage
    }

    private func persistLLMSettings(rebuildRuntime: Bool) {
        aiConnectionsModel.persistSettings(rebuildRuntime: rebuildRuntime)
        errorMessage = aiConnectionsModel.errorMessage
    }

    func clearLLMAPIKey() {
        aiConnectionsModel.clearAPIKey()
        errorMessage = aiConnectionsModel.errorMessage
    }

    func testLLMConnection() async {
        await aiConnectionsModel.testConnection()
        errorMessage = aiConnectionsModel.errorMessage
    }

    func selectSettingsSection(_ section: ConnorSettingsSection) {
        shellFeatureModel.selectSettingsSection(section)
    }

    func settingsMessage(for section: ConnorSettingsSection) -> String? {
        shellFeatureModel.settingsMessage(for: section)
    }

    func setSettingsMessage(_ message: String?, for section: ConnorSettingsSection) {
        shellFeatureModel.setSettingsMessage(message, for: section)
    }

    func clearSettingsMessage(for section: ConnorSettingsSection) {
        shellFeatureModel.clearSettingsMessage(for: section)
    }

    var effectiveLoopConfiguration: AgentLoopConfiguration {
        var configuration = loadedLoopConfiguration
        configuration.permissionMode = permissionSettingsModel.defaultPermissionMode == .allowAll ? .askToWrite : permissionSettingsModel.defaultPermissionMode
        return configuration
    }

    private func makeNativeSessionManager(for session: AgentSession) -> NativeSessionManager? {
        let configuration = effectiveLoopConfiguration
        return chatRunCoordinator.makeManager(
            for: session,
            permissionMode: configuration.permissionMode,
            configuration: configuration,
            sessionWorkspace: sessionStateSnapshotsBySessionID[session.id]?.workspace,
            sessionLLMOverride: sessionStateSnapshotsBySessionID[session.id]?.llmOverride
        )
    }

    var noteImportRuntimeFactory: NoteImportRuntimeFactory {
        NoteImportRuntimeFactory(
            databasePath: databasePath,
            sessionRepository: chatSessionRepository,
            runCoordinator: chatRunCoordinator,
            storagePaths: storagePaths
        )
    }

    private func rebuildNativeSessionManagerForActiveSession() {
        let session = activeChatSession
        _ = ensureSessionLLMOverride(sessionID: session.id)
        chatRunCoordinator.installManager(makeNativeSessionManager(for: session), fallbackSession: session)
    }

    @discardableResult
    private func ensureSessionLLMOverride(sessionID: String) -> SessionLLMOverride? {
        var state = sessionStateSnapshotsBySessionID[sessionID]
        if state == nil, let loaded = try? chatSessionRepository?.loadSessionState(sessionID: sessionID) {
            state = loaded
        }
        if let existing = state?.llmOverride, !existing.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sessionStateSnapshotsBySessionID[sessionID] = state ?? AppSessionStateSnapshot(sessionID: sessionID)
            return existing
        }
        guard let settings = try? llmSettingsRepository.loadSettings(),
              let connection = settings.defaultConnection else { return nil }
        let model = connection.effectiveModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return nil }
        var nextState = state ?? AppSessionStateSnapshot(sessionID: sessionID)
        let override = SessionLLMOverride(
            providerMode: connection.providerMode.rawValue,
            model: model,
            baseURLString: nil,
            connectionID: connection.id,
            thinkingLevel: settings.defaultThinkingLevel.rawValue
        )
        nextState.llmOverride = override
        nextState.updatedAt = Date()
        sessionStateSnapshotsBySessionID[sessionID] = nextState
        try? chatSessionRepository?.saveSessionState(nextState, sessionID: sessionID)
        return override
    }

    private func sessionAgentModelProvider(sessionID: String) throws -> AnyAgentModelProvider {
        let override = ensureSessionLLMOverride(sessionID: sessionID)
        guard let provider = chatRunCoordinator.makeAgentModelProvider(sessionLLMOverride: override) else {
            throw OpenAICompatibleProviderError.missingAPIKey
        }
        return provider
    }

    private func sessionLLMProvider(sessionID: String) throws -> AnyLLMProvider {
        let provider = try sessionAgentModelProvider(sessionID: sessionID)
        return AnyLLMProvider { prompt, context in
            let response = try await provider.complete(AgentModelRequest(messages: [
                AgentModelMessage(role: .system, content: AgentInstructionSection.defaultConnorInstruction),
                AgentModelMessage(role: .user, content: "Question:\n\(prompt)\n\nGraph Context:\n\(context.renderedText)")
            ]))
            return LLMResponse(text: response.text ?? "", citations: context.items.map(\.sourceID))
        }
    }

    private func syncLLMModelDisplayFromSession(_ sessionID: String) {
        _ = ensureSessionLLMOverride(sessionID: sessionID)
        if let override = sessionStateSnapshotsBySessionID[sessionID]?.llmOverride {
            llmSelectedModel = override.model
            llmThinkingLevel = AppLLMThinkingLevel.normalized(override.thinkingLevel) ?? ((try? llmSettingsRepository.loadSettings())?.defaultThinkingLevel ?? llmThinkingLevel)
            if let overrideMode = AppLLMProviderMode(rawValue: override.providerMode) {
                llmProviderMode = overrideMode
            }
            if let connectionID = override.connectionID {
                llmDefaultConnectionID = connectionID
            }
        } else {
            let settings = try? llmSettingsRepository.loadSettings()
            llmSelectedModel = settings?.defaultConnection?.effectiveModel ?? ""
            llmThinkingLevel = settings?.defaultThinkingLevel ?? llmThinkingLevel
            llmProviderMode = settings?.defaultConnection?.providerMode ?? .openAICompatible
            llmDefaultConnectionID = settings?.defaultConnectionID ?? ""
        }
    }

    private func syncActiveSessionLLMOverride(to connection: AppLLMConnectionConfig) {
        let sessionID = chatFeatureModel.sessions.selectedSessionID ?? activeChatSession.id
        let settings = try? llmSettingsRepository.loadSettings()
        let thinkingLevel = sessionStateSnapshotsBySessionID[sessionID]?.llmOverride?.thinkingLevel
            ?? settings?.defaultThinkingLevel.rawValue
        var state = sessionStateSnapshotsBySessionID[sessionID]
            ?? (try? chatSessionRepository?.loadSessionState(sessionID: sessionID))
            ?? AppSessionStateSnapshot(sessionID: sessionID)
        state.llmOverride = SessionLLMOverride(
            providerMode: connection.providerMode.rawValue,
            model: connection.effectiveModel,
            baseURLString: nil,
            connectionID: connection.id,
            thinkingLevel: thinkingLevel
        )
        state.updatedAt = Date()
        sessionStateSnapshotsBySessionID[sessionID] = state
        try? chatSessionRepository?.saveSessionState(state, sessionID: sessionID)
        llmProviderMode = connection.providerMode
        llmSelectedModel = connection.effectiveModel
        llmDefaultConnectionID = connection.id
    }

    var sessionHasLLMOverride: Bool {
        let sessionID = chatFeatureModel.sessions.selectedSessionID ?? activeChatSession.id
        return sessionStateSnapshotsBySessionID[sessionID]?.llmOverride != nil
    }

    func clearSessionLLMOverride() {
        let sessionID = chatFeatureModel.sessions.selectedSessionID ?? activeChatSession.id
        var state = sessionStateSnapshotsBySessionID[sessionID]
            ?? AppSessionStateSnapshot(sessionID: sessionID)
        state.llmOverride = nil
        state.updatedAt = Date()
        sessionStateSnapshotsBySessionID[sessionID] = state
        try? chatSessionRepository?.saveSessionState(state, sessionID: sessionID)

        // Fall back to global settings for UI display
        let settings = try? llmSettingsRepository.loadSettings()
        llmSelectedModel = settings?.defaultConnection?.effectiveModel ?? ""
        llmThinkingLevel = settings?.defaultThinkingLevel ?? llmThinkingLevel
        llmProviderMode = settings?.defaultConnection?.providerMode ?? .openAICompatible
        llmDefaultConnectionID = settings?.defaultConnectionID ?? ""

        rebuildNativeSessionManagerForActiveSession()
        Task { await reloadLLMModelConnections() }
    }

    private func syncWorkspaceDraftsFromSession(_ state: AppSessionStateSnapshot?) {
        workspaceSettingsModel.applySessionState(state)
    }

    private func currentSessionIDForWorkspaceDrafts() -> String? {
        chatFeatureModel.sessions.selectedSessionID ?? activeChatSession.id
    }

    private func sessionWorkspaceReference(
        roots: [WorkspaceRootDraft],
        defaultWorkingDirectoryPath: String,
        source: String = "session"
    ) -> AppSessionWorkspaceReference? {
        let primaryID = roots.first(where: \.isPrimary)?.id ?? roots.first?.id
        let references = roots.map { draft in
            AppSessionWorkspaceRootReference(
                id: draft.id,
                displayName: draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? URL(fileURLWithPath: draft.path).lastPathComponent : draft.displayName,
                path: draft.path.trimmingCharacters(in: .whitespacesAndNewlines),
                role: draft.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "project" : draft.role,
                isPrimary: draft.id == primaryID
            )
        }.filter { !$0.path.isEmpty }
        let primary = references.first(where: \.isPrimary) ?? references.first
        let workingDirectoryPath = primary?.path ?? defaultWorkingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workingDirectoryPath.isEmpty || !references.isEmpty else { return nil }
        return AppSessionWorkspaceReference(workingDirectoryPath: workingDirectoryPath, source: source, roots: references)
    }

    private func saveWorkspaceDraftsToCurrentSession(
        roots: [WorkspaceRootDraft],
        defaultWorkingDirectoryPath: String
    ) {
        guard let sessionID = currentSessionIDForWorkspaceDrafts() else { return }
        do {
            var state = try chatSessionRepository?.loadSessionState(sessionID: sessionID) ?? AppSessionStateSnapshot(sessionID: sessionID)
            state.workspace = sessionWorkspaceReference(roots: roots, defaultWorkingDirectoryPath: defaultWorkingDirectoryPath)
            state.updatedAt = Date()
            sessionStateSnapshotsBySessionID[sessionID] = state
            try chatSessionRepository?.saveSessionState(state, sessionID: sessionID)
            if activeChatSession.id == sessionID || chatFeatureModel.sessions.selectedSessionID == sessionID { rebuildNativeSessionManagerForActiveSession() }
            setSettingsMessage("当前会话 Workspace 已保存。", for: .app)
            errorMessage = nil
        } catch { errorMessage = String(describing: error) }
    }

    func loadRuntimeSettings() {
        guard let settings = runtimeSettingsCoordinator.load() else { return }
        isLoadingRuntimeSettings = true
        loadedLoopConfiguration = settings.loop
        appSettingsModel.apply(settings)
        inputSettingsModel.apply(settings)
        permissionSettingsModel.apply(settings)
        workspaceSettingsModel.applyRecentPaths(settings.workspace.recentWorkspacePaths)
        if let sessionID = currentSessionIDForWorkspaceDrafts() {
            workspaceSettingsModel.applySessionState(sessionStateSnapshotsBySessionID[sessionID])
        } else {
            workspaceSettingsModel.applySessionState(nil)
        }
        userPreferencesModel.apply(settings.preferences)
        let shouldPersistSystemDefaults = userPreferencesModel.fillEmptyFieldsFromSystem()
        browserFeatureModel.internalBrowserEnabled = settings.app.internalBrowserEnabled
        shellFeatureModel.clearAllSettingsMessages()
        errorMessage = nil
        isLoadingRuntimeSettings = false
        if hasActivatedRuntimeSettingsSideEffects { applyRuntimeSettingsSideEffects() }
        if shouldPersistSystemDefaults { scheduleRuntimeSettingsAutosave() }
    }

    func saveRuntimeSettings() {
        runtimeSettingsCoordinator.save(snapshot: runtimeSettingsSnapshot())
    }

    func scheduleRuntimeSettingsAutosave() {
        guard !isLoadingRuntimeSettings else { return }
        runtimeSettingsCoordinator.scheduleAutosave { [weak self] in
            self?.runtimeSettingsSnapshot() ?? .default
        }
    }

    private func runtimeSettingsSnapshot() -> AgentRuntimeSettings {
        var settings = runtimeSettingsCoordinator.baseSnapshot()
        settings.schemaVersion = 4
        settings.loop = loadedLoopConfiguration
        appSettingsModel.apply(to: &settings)
        inputSettingsModel.apply(to: &settings)
        permissionSettingsModel.apply(to: &settings)
        settings.app.internalBrowserEnabled = browserFeatureModel.internalBrowserEnabled
        settings.workspace.recentWorkspacePaths = workspaceSettingsModel.recentPaths
        userPreferencesModel.apply(to: &settings)
        return settings
    }

    private func handleRuntimeSettingsSaved(_ settings: AgentRuntimeSettings) {
        loadedLoopConfiguration = settings.loop
        applyRuntimeSettingsSideEffects()
        if chatFeatureModel.run.submittingSessionIDs.isEmpty {
            rebuildNativeSessionManagerForActiveSession()
        } else {
            chatRunCoordinator.mutateManager { $0.permissionMode = settings.loop.permissionMode }
        }
        shellFeatureModel.clearAllSettingsMessages()
        errorMessage = nil
    }

    func activateRuntimeSettingsSideEffectsAfterLaunch() {
        guard !hasActivatedRuntimeSettingsSideEffects else { return }
        hasActivatedRuntimeSettingsSideEffects = true
        applyRuntimeSettingsSideEffects()
    }

    private func applyRuntimeSettingsSideEffects() {
        applyKeepScreenAwakeSetting()
        requestDesktopNotificationAuthorizationIfNeeded()
    }

    private func requestDesktopNotificationAuthorizationIfNeeded() {
        guard hasActivatedRuntimeSettingsSideEffects, appSettingsModel.desktopNotificationsEnabled, canUseUserNotifications else { return }
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    private func applyKeepScreenAwakeSetting() {
        maintenanceCoordinator.updateKeepScreenAwake(
            enabled: appSettingsModel.keepScreenAwake,
            hasActiveRun: chatRunCoordinator.isActive
        )
    }

    func resetSessionNotificationSettings() {
        appSettingsModel.sessionNewMessageNotificationLevel = SessionNotificationSettings.default.newMessageLevel
    }

    func markSessionRead(_ sessionID: String) {
        chatAttentionCoordinator.markRead(sessionID)
    }

    private func noteSessionUpdate(
        sessionID: String,
        messageID: String?,
        preview: String?,
        notificationBody: String
    ) {
        chatAttentionCoordinator.noteUpdate(
            sessionID: sessionID,
            messageID: messageID,
            preview: preview,
            notificationBody: notificationBody
        )
    }

    private func notificationPreview(from content: String) -> String {
        let collapsed = content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > 140 else { return collapsed }
        return String(collapsed.prefix(140)) + "…"
    }

    func shouldTreatSessionUpdateAsRead(sessionID: String) -> Bool {
        chatAttentionCoordinator.shouldTreatUpdateAsRead(sessionID: sessionID)
    }

    private func synchronizeSessionReadStates(from sessions: [AgentSession]) {
        chatAttentionCoordinator.synchronize(from: sessions)
    }

    private func refreshDockBadge() {
        chatAttentionCoordinator.refreshDockBadge()
    }

    static func applyDockBadge(count: Int, application: NSApplication?) {
        ChatAttentionCoordinator.applyDockBadge(count: count, application: application)
    }

    private var canUseUserNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    func upsertStatusDefinition(_ definition: AgentSessionStatusDefinition) {
        governanceModel.upsertStatus(definition)
    }

    func canDeleteStatusDefinition(_ definition: AgentSessionStatusDefinition) -> Bool {
        governanceModel.canDeleteStatus(definition)
    }

    func deleteStatusDefinition(_ definition: AgentSessionStatusDefinition) {
        governanceModel.deleteStatus(definition)
    }

    func upsertLabelDefinition(_ definition: AgentSessionLabelDefinition) {
        governanceModel.upsertLabel(definition)
    }

    func deleteLabelDefinition(_ definition: AgentSessionLabelDefinition) {
        governanceModel.deleteLabel(definition)
    }

    func resetRuntimeSettings() {
        guard let settings = runtimeSettingsCoordinator.reset() else { return }
        loadedLoopConfiguration = settings.loop
        appSettingsModel.apply(settings)
        inputSettingsModel.apply(settings)
        permissionSettingsModel.apply(settings)
        workspaceSettingsModel.applyRecentPaths(settings.workspace.recentWorkspacePaths)
        userPreferencesModel.apply(settings.preferences)
        browserFeatureModel.internalBrowserEnabled = settings.app.internalBrowserEnabled
        setSettingsMessage("设置已恢复默认值。", for: .app)
        errorMessage = nil
    }

    func reloadChatSessionsIfNeededAfterInitialLoad(restoreWorkspaceMode shouldRestoreWorkspaceMode: Bool = true) {
        chatSessionCoordinator.reloadIfNeeded(restoreWorkspaceMode: shouldRestoreWorkspaceMode)
    }

    private func rebuildSessionSearchIndexSoon(sessions: [AgentSession]) {
        globalSearchFeatureModel.rebuildSessionIndex(sessions: sessions)
    }

    func reloadChatSessions(restoreWorkspaceMode shouldRestoreWorkspaceMode: Bool = true) {
        if chatSessionRepository == nil {
            replaceSelectedChatTranscript(activeChatTranscript)
            chatFeatureModel.sessions.sessions = [activeChatSession]
            chatFeatureModel.sessions.allSessions = [activeChatSession]
            synchronizeSessionReadStates(from: chatFeatureModel.sessions.allSessions)
            chatSessionCoordinator.adoptDirectSelection(activeChatSession.id)
            return
        }
        chatSessionCoordinator.reload(restoreWorkspaceMode: shouldRestoreWorkspaceMode)
    }

    private func replaceSelectedChatTranscript(_ messages: [AgentMessage]) { chatRunCoordinator.replaceTranscript(messages) }

    private func clearSelectedChatSessionDetail() {
        chatSessionCoordinator.clearSelection()
    }

    private func clearSelectedChatRuntime() {
        chatRunCoordinator.clearSelectedRuntime()
        chatFeatureModel.sessions.selectedArtifactDirectories = nil
        browserFeatureModel.isVisible = false
        browserFeatureModel.resetWorkspaceBinding()
        refreshSelectedSubmittingState()
    }

    func newChatSession() {
        guard let chatSessionRepository else { return }
        _ = stopSpeechTranscriptionIfRunningForLeavingSession(chatFeatureModel.sessions.selectedSessionID)
        rememberCurrentWorkspaceMode()
        do {
            let session = try chatSessionRepository.createSession()
            chatSessionCoordinator.adoptDirectSelection(session.id)
            chatRunCoordinator.clearProcessTimelines()
            browserFeatureModel.isVisible = false
            browserFeatureModel.resetWorkspaceBinding()
            rememberWorkspaceMode(.conversation, for: session.id)
            chatFeatureModel.sessions.selectedArtifactDirectories = try chatSessionRepository.artifactDirectories(sessionID: session.id)
            try loadSessionCapsule(sessionID: session.id)
            try chatBackgroundTaskCoordinator.load(sessionID: session.id)
            chatRunCoordinator.prepareNewSession(session, manager: makeNativeSessionManager(for: session))
            restoreChatInputDraft(for: session.id)
            reloadChatSessions()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    };

    func newNoteSession() {
        guard let chatSessionRepository else { return }
        _ = stopSpeechTranscriptionIfRunningForLeavingSession(chatFeatureModel.sessions.selectedSessionID)
        rememberCurrentWorkspaceMode()
        do {
            let session = try chatSessionRepository.createSession()
            var noteSession = session
            noteSession.governance.kind = .note
            noteSession.title = "未命名的笔记"
            _ = try chatSessionRepository.saveSession(noteSession)
            chatSessionCoordinator.adoptDirectSelection(noteSession.id)
            chatRunCoordinator.clearProcessTimelines()
            browserFeatureModel.isVisible = false
            browserFeatureModel.resetWorkspaceBinding()
            rememberWorkspaceMode(.conversation, for: noteSession.id)
            chatFeatureModel.sessions.selectedArtifactDirectories = try chatSessionRepository.artifactDirectories(sessionID: noteSession.id)
            try loadSessionCapsule(sessionID: noteSession.id)
            try chatBackgroundTaskCoordinator.load(sessionID: noteSession.id)
            chatRunCoordinator.prepareNewSession(noteSession, manager: makeNativeSessionManager(for: noteSession))
            restoreChatInputDraft(for: noteSession.id)
            reloadChatSessions()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    };

    func renameChatSession(_ sessionID: String, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let chatSessionRepository else { return }
        do {
            let updated = try chatSessionRepository.renameSession(sessionID: sessionID, title: trimmed)
            synchronizeRenamedChatSession(updated)
            reloadChatSessions()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func synchronizeRenamedChatSession(_ updated: AgentSession) {
        if let index = chatFeatureModel.sessions.sessions.firstIndex(where: { $0.id == updated.id }) {
            chatFeatureModel.sessions.sessions[index] = updated
        }
        if let index = chatFeatureModel.sessions.allSessions.firstIndex(where: { $0.id == updated.id }) {
            chatFeatureModel.sessions.allSessions[index] = updated
        }
        if chatFeatureModel.sessions.selectedSessionID == updated.id {
            chatRunCoordinator.installManager(makeNativeSessionManager(for: updated), fallbackSession: updated)
            replaceSelectedChatTranscript(updated.messages)
        }
    }

    func backgroundTasks(for sessionID: String?) -> [AppSessionBackgroundTask] {
        chatBackgroundTaskCoordinator.tasks(for: sessionID)
    }

    var activeSessionBackgroundTasks: [AppSessionBackgroundTask] {
        backgroundTasks(for: chatFeatureModel.sessions.selectedSessionID)
    }

    var hasRunningActiveSessionBackgroundTask: Bool {
        activeSessionBackgroundTasks.contains { $0.status == .queued || $0.status == .running }
    }

    func hasRunningBackgroundTask(sessionID: String) -> Bool {
        chatBackgroundTaskCoordinator.hasRunningTask(sessionID: sessionID)
    }

    @discardableResult
    private func stopSpeechTranscriptionIfRunningForLeavingSession(_ sessionID: String?) -> AppSessionBackgroundTask? {
        chatComposerCoordinator.stopSpeechForLeavingSession(sessionID)
    }

    @discardableResult
    private func stopSpeechTranscriptionIfRunningForDeletedSession(_ sessionID: String?) -> AppSessionBackgroundTask? {
        chatComposerCoordinator.stopSpeechForDeletedSession(sessionID)
    }

    private func stopSpeechTranscriptionForDisabledSetting() { chatComposerCoordinator.stopSpeechForDisabledSetting() }

    private func runningBackgroundTasksForDeletionCheck(sessionID: String) throws -> [AppSessionBackgroundTask] {
        try chatBackgroundTaskCoordinator.runningTasksForDeletionCheck(sessionID: sessionID)
    }

    func canDeleteChatSession(_ sessionID: String) -> Bool {
        (try? runningBackgroundTasksForDeletionCheck(sessionID: sessionID).isEmpty) ?? !hasRunningBackgroundTask(sessionID: sessionID)
    }

    func regenerateChatSessionTitle(_ sessionID: String) {
        chatBackgroundTaskCoordinator.regenerateTitle(sessionID: sessionID)
    }

    private func generateTitleFromUserPrompts(_ prompts: [String], sessionID: String) async throws -> String {
        let provider = try sessionAgentModelProvider(sessionID: sessionID)
        let joinedPrompts = prompts.enumerated().map { index, prompt in
            "用户 Prompt \(index + 1):\n\(prompt)"
        }.joined(separator: "\n\n---\n\n")
        let userPrompt = """
        请根据下面这个对话中所有用户 Prompt，生成一个中文会话标题。

        要求：
        - 20 个汉字以内
        - 不要引号
        - 不要句号
        - 不要解释
        - 只输出标题本身

        \(joinedPrompts)
        """
        let response = try await provider.complete(AgentModelRequest(
            messages: [
                AgentModelMessage(role: .system, content: "你是会话标题生成器。"),
                AgentModelMessage(role: .user, content: userPrompt)
            ],
            temperature: 1.0
        ))
        return sanitizedSessionTitle(response.text ?? "")
    }

    private func sanitizedSessionTitle(_ raw: String) -> String {
        var title = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’`。，.：:；;！!？?"))
        if title.count > 20 {
            title = String(title.prefix(20))
        }
        return title.isEmpty ? "新对话" : title
    }

    func deleteChatSession(_ sessionID: String) {
        guard let chatSessionRepository else { return }
        do {
            _ = stopSpeechTranscriptionIfRunningForDeletedSession(sessionID)
            let runningTasks = try runningBackgroundTasksForDeletionCheck(sessionID: sessionID)
            guard runningTasks.isEmpty else {
                errorMessage = "无法删除会话: 仍有 \(runningTasks.count) 个后台任务正在运行。"
                return
            }
            try chatSessionRepository.deleteSession(sessionID: sessionID)
            chatBackgroundTaskCoordinator.removeSession(sessionID)
            chatComposerCoordinator.removeSession(sessionID)
            chatRunCoordinator.removeSession(sessionID)
            chatWorkspaceCoordinator.removeSession(sessionID)
            if chatFeatureModel.sessions.selectedSessionID == sessionID {
                chatSessionCoordinator.clearSelection()
            }
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
            if chatFeatureModel.sessions.selectedSessionID == sessionID { syncWorkspaceDraftsFromSession(state) }
            if let mode = ChatSessionWorkspaceMode(rawValue: state.selectedPane ?? "") {
                chatWorkspaceCoordinator.setMode(mode, for: sessionID)
            }
        } else {
            let state = AppSessionStateSnapshot(sessionID: sessionID, updatedAt: Date())
            sessionStateSnapshotsBySessionID[sessionID] = state
            if chatFeatureModel.sessions.selectedSessionID == sessionID { syncWorkspaceDraftsFromSession(state) }
            try chatSessionRepository.saveSessionState(state, sessionID: sessionID)
        }
        sessionRecordsBySessionID[sessionID] = try chatSessionRepository.loadSessionRecords(sessionID: sessionID, limit: nil)
        if let browserState = try chatSessionRepository.loadBrowserState(sessionID: sessionID) {
            browserFeatureModel.installLoadedWorkspaceSnapshot(browserState, for: sessionID)
        }
        _ = try chatSessionRepository.refreshSessionManifest(sessionID: sessionID)
    }

    private func persistBrowserWorkspaceSnapshot(_ snapshot: AppBrowserStateSnapshot, for sessionID: String) {
        do {
            try chatSessionRepository?.saveBrowserState(snapshot, sessionID: sessionID)
            if let state = try chatSessionRepository?.loadSessionState(sessionID: sessionID) {
                sessionStateSnapshotsBySessionID[sessionID] = state
            }
            _ = try chatSessionRepository?.refreshSessionManifest(sessionID: sessionID)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func openBrowserHistoryRecord(_ record: BrowserHistoryRecord, url: URL) {
        if browserHistorySessionExists(record.sessionID) {
            if record.sessionID != chatFeatureModel.sessions.selectedSessionID { selectChatSession(record.sessionID) }
            browserFeatureModel.openURL(url, preferredSessionID: record.sessionID)
        } else {
            openBrowserHistoryRecordInNewSession(record, url: url)
        }
    }

    private func browserHistorySessionExists(_ sessionID: String) -> Bool {
        guard let chatSessionRepository else { return false }
        return (try? chatSessionRepository.loadSession(id: sessionID)) != nil
    }

    private func openBrowserHistoryRecordInNewSession(_ record: BrowserHistoryRecord, url: URL) {
        guard let chatSessionRepository else { return }
        rememberCurrentWorkspaceMode()
        do {
            let session = try chatSessionRepository.createSession(title: browserHistorySessionTitle(for: record))
            chatSessionCoordinator.adoptDirectSelection(session.id)
            chatRunCoordinator.clearProcessTimelines()
            browserFeatureModel.resetWorkspaceBinding()
            chatFeatureModel.sessions.selectedArtifactDirectories = try chatSessionRepository.artifactDirectories(sessionID: session.id)
            try loadSessionCapsule(sessionID: session.id)
            try chatBackgroundTaskCoordinator.load(sessionID: session.id)
            chatRunCoordinator.prepareNewSession(session, manager: makeNativeSessionManager(for: session))
            restoreChatInputDraft(for: session.id)
            reloadChatSessions(restoreWorkspaceMode: false)
            chatSessionCoordinator.adoptDirectSelection(session.id)
            openURLInCurrentChatBrowser(url)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func browserHistorySessionTitle(for record: BrowserHistoryRecord) -> String {
        let rawTitle = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawTitle.isEmpty { return "浏览 \(rawTitle)" }
        if let host = URL(string: record.url)?.host, !host.isEmpty { return "浏览 \(host)" }
        return "浏览历史"
    }

    private func rememberCurrentWorkspaceMode() {
        rememberWorkspaceMode(browserFeatureModel.isVisible ? .browser : .conversation, for: chatFeatureModel.sessions.selectedSessionID ?? activeChatSession.id)
    }

    private func rememberWorkspaceMode(_ mode: ChatSessionWorkspaceMode, for sessionID: String?) {
        chatWorkspaceCoordinator.setMode(mode, for: sessionID)
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
        let mode = chatWorkspaceCoordinator.mode(for: sessionID)
        browserFeatureModel.restoreWorkspaceMode(isBrowser: mode == .browser, sessionID: sessionID)
        selection = .agentChat
    }

    func appendSessionRecord(kind: String, title: String? = nil, body: String? = nil, metadata: [String: String] = [:], sessionID: String? = nil) {
        let targetSessionID = sessionID ?? chatFeatureModel.sessions.selectedSessionID ?? activeChatSession.id
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
              let sessionID = chatFeatureModel.sessions.selectedSessionID
        else { return [] }
        let cacheKey = "\(sessionID):\(process.id)"
        if let cached = chatRunCoordinator.cachedProcessTimeline(key: cacheKey) { return cached }
        guard let sourceUserMessageID = process.sourceUserMessageID else {
            chatRunCoordinator.cacheProcessTimeline([], key: cacheKey)
            return []
        }
        do {
            let runs = try chatSessionRepository.loadRuns(sessionID: sessionID, statuses: nil, limit: 200)
            guard let run = runs.first(where: { $0.metadata["user_message_id"] == sourceUserMessageID }) else {
                chatRunCoordinator.cacheProcessTimeline([], key: cacheKey)
                return []
            }
            let restored = try restoreAgentEventTimeline(runID: run.id, sessionID: sessionID)
            chatRunCoordinator.cacheProcessTimeline(restored, key: cacheKey)
            return restored
        } catch {
            chatRunCoordinator.cacheProcessTimeline([], key: cacheKey)
            return []
        }
    }

    private func restoreAgentEventTimeline(runID: String, sessionID: String) throws -> [AgentEventPresentation] {
        guard let chatSessionRepository else { return [] }
        let restored = presentations(from: try chatSessionRepository.loadRunEvents(runID: runID, limit: nil))
        if !restored.isEmpty { return restored }
        return presentations(
            from: try chatSessionRepository.loadRecentJournalEvents(sessionID: sessionID, limit: nil)
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
            chatRunCoordinator.setTimeline([], sessionID: sessionID)
            return
        }

        let cachedTimeline = try chatSessionRepository.loadActivityTimelineCache(sessionID: sessionID)
        if !cachedTimeline.isEmpty {
            chatRunCoordinator.setTimeline(cachedTimeline, sessionID: sessionID)
            return
        }

        let runs = try chatSessionRepository.loadRuns(
            sessionID: sessionID,
            statuses: [.completed, .failed, .cancelled],
            limit: 3
        )
        for run in runs {
            let restored = presentations(from: try chatSessionRepository.loadRunEvents(runID: run.id, limit: 200))
            if !restored.isEmpty {
                chatRunCoordinator.setTimeline(restored, sessionID: sessionID)
                return
            }
        }

        let recentEvents = try chatSessionRepository.loadRecentJournalEvents(sessionID: sessionID, limit: 400)
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
                chatRunCoordinator.setTimeline(restored, sessionID: sessionID)
                return
            }
        }

        chatRunCoordinator.setTimeline([], sessionID: sessionID)
    }

    func openSessionFromNotification(_ sessionID: String) {
        selection = .agentChat
        chatFeatureModel.sessions.searchQuery = ""
        selectChatSession(sessionID)
    }

    func selectChatSession(_ sessionID: String) {
        chatSessionCoordinator.select(sessionID)
    }

    private func applySelectedChatSessionSnapshot(
        _ snapshot: ChatSessionDetailLoadSnapshot,
        generation: Int,
        startedAt: ContinuousClock.Instant
    ) {
        let session = snapshot.session
        do {
            markSessionRead(session.id)
            chatRunCoordinator.clearProcessTimelines()
            try loadSessionCapsule(sessionID: session.id)
            try chatBackgroundTaskCoordinator.load(sessionID: session.id)
            _ = ensureSessionLLMOverride(sessionID: session.id)
            chatRunCoordinator.applySelectedSnapshot(
                session: session,
                manager: makeNativeSessionManager(for: session),
                timeline: snapshot.timeline,
                summary: snapshot.latestSummary
            )
            restoreChatInputDraft(for: session.id)
            chatFeatureModel.sessions.selectedArtifactDirectories = snapshot.artifactDirectories
            restoreWorkspaceMode(for: session.id)
            syncLLMModelDisplayFromSession(session.id)
            errorMessage = nil
            let elapsed = startedAt.duration(to: ContinuousClock.now)
            let milliseconds = Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
            AppPerformanceLog.chatTurnLogger.info("sessionDetail.loaded session=\(session.id, privacy: .public) generation=\(generation, privacy: .public) messages=\(session.messages.count, privacy: .public) timeline=\(snapshot.timeline.count, privacy: .public) duration=\(milliseconds, privacy: .public)ms")
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func setSessionListFilter(_ filter: AgentSessionListFilter, restoreWorkspaceMode: Bool = true) {
        chatSessionCoordinator.setFilter(filter, restoreWorkspaceMode: restoreWorkspaceMode)
    }

    func setSelectedSessionStatus(_ status: AgentSessionStatus) {
        guard let selectedChatSessionID = chatFeatureModel.sessions.selectedSessionID else { return }
        setChatSessionStatus(selectedChatSessionID, status: status)
    }

    func setChatSessionStatus(_ sessionID: String, status: AgentSessionStatus) {
        guard let chatSessionRepository else { return }
        do {
            let previousStatus = try chatSessionRepository.loadSession(id: sessionID)?.governance.status
            let session = try chatSessionRepository.setStatus(sessionID: sessionID, status: status)
            if chatFeatureModel.sessions.selectedSessionID == sessionID {
                chatRunCoordinator.updateFallbackSession(session)
            }
            reloadChatSessions()
            appendGovernanceEvent(.sessionStatusChanged(AgentSessionGovernanceEvent(sessionID: session.id, message: "状态已更新为 \(status.displayName)", status: status)))
            productOSControlModel.evaluateAutomation(ProductOSAutomationEventContext(triggerKind: .sessionStatusChanged, sessionID: session.id, status: status), governanceConfig: governanceConfig)
            dispatchTaskSessionStatusChanged(sessionID: session.id, fromStatus: previousStatus?.rawValue, toStatus: status.rawValue)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func dispatchTaskSessionStatusChanged(sessionID: String, fromStatus: String?, toStatus: String) {
        guard let taskManagementRepository = taskAutomationModel.repository else { return }
        let runner = TaskTargetRunner.appRuntime(
            calendarRefresh: { [weak self] request in
                guard let self else { throw TaskTargetRunnerError.unsupportedTarget("calendar") }
                return await self.refreshCalendarForScheduledTask(sourceInstanceID: request.sourceInstanceID, runID: request.runID)
            },
            rssRefresh: { [weak self] request in
                guard let self else { throw TaskTargetRunnerError.unsupportedTarget("rss") }
                return try await self.refreshRSSForScheduledTask(sourceInstanceID: request.sourceInstanceID, runID: request.runID)
            },
            sessionMessage: { [weak self] request in
                guard let self else { throw TaskTargetRunnerError.unsupportedTarget("session.ai") }
                return await self.performTaskSessionMessage(request)
            }
        )
        Task { @MainActor in
            do {
                let dispatcher = TaskEventDispatcher(repository: taskManagementRepository, runner: runner)
                _ = try await dispatcher.dispatchSessionStatusChanged(sessionID: sessionID, fromStatus: fromStatus, toStatus: toStatus)
                taskAutomationModel.reload()
            } catch {
                errorMessage = String(describing: error)
            }
        }
    }

    func toggleSelectedSessionFlag() {
        guard let selectedChatSessionID = chatFeatureModel.sessions.selectedSessionID, let chatSessionRepository else { return }
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
        guard let selectedChatSessionID = chatFeatureModel.sessions.selectedSessionID else { return }
        toggleChatSessionLabel(selectedChatSessionID, labelID: labelID)
    }

    func toggleChatSessionLabel(_ sessionID: String, labelID: String) {
        guard let chatSessionRepository else { return }
        do {
            guard let session = try chatSessionRepository.loadSession(id: sessionID) else { return }
            var labels = session.governance.labels
            let didRemove: Bool
            if labels.contains(where: { $0.id == labelID }) {
                labels.removeAll { $0.id == labelID }
                didRemove = true
            } else {
                labels.append(AgentSessionLabel(id: labelID))
                didRemove = false
            }
            let updated = try chatSessionRepository.setLabels(sessionID: sessionID, labels: labels)
            if chatFeatureModel.sessions.selectedSessionID == sessionID {
                chatRunCoordinator.updateFallbackSession(updated)
            }
            reloadChatSessions()
            appendGovernanceEvent(.sessionLabelsChanged(AgentSessionGovernanceEvent(sessionID: updated.id, message: "标签已更新：\(updated.governance.labels.map(\.id).joined(separator: ", "))", labels: updated.governance.labels)))
            productOSControlModel.evaluateAutomation(ProductOSAutomationEventContext(triggerKind: didRemove ? .sessionLabelRemoved : .sessionLabelAdded, sessionID: updated.id, labelID: labelID), governanceConfig: governanceConfig)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func appendGovernanceEvent(_ event: AgentEvent) {
        chatFeatureModel.run.eventTimeline.insert(AgentEventPresenter().presentation(for: event), at: 0)
    }

    private func backendForPendingApproval(_ approval: AgentPendingApproval) -> AnyAgentBackend? {
        chatRunCoordinator.backend(for: approval)
    }

    func saveBrowserSelectionAsEpisode(_ selection: BrowserSelectionContext) async {
        guard let memoryOSFacade else {
            errorMessage = "当前没有可用的 Memory OS，无法保存网页证据。"
            return
        }
        do {
            let draft = BrowserGraphEvidenceBuilder().makeEpisodeDraft(
                selection: selection,
                groupID: "default",
                sessionID: chatFeatureModel.sessions.selectedSessionID ?? activeChatSession.id
            )
            _ = try memoryOSFacade.ingestWebPageEvidence(
                evidenceID: draft.episode.id,
                title: draft.episode.title,
                content: draft.episode.content,
                occurredAt: draft.episode.occurredAt,
                sessionID: draft.episode.sessionID,
                metadata: draft.episode.metadata
            )
            errorMessage = nil
            graphDiagnosticsModel.lastPromotionResultSummary = "已保存网页证据到 Memory OS：\(draft.episode.title)"
            maintenanceCoordinator.scheduleBackgroundJobs()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func submitChat() async {
        let prompt = chatFeatureModel.composer.input.trimmingCharacters(in: .whitespacesAndNewlines)
        await submitChat(prompt: prompt, clearComposer: true)
    }

    private func scheduleActivityTimelineCacheSave(sessionID: String, timeline: [AgentEventPresentation]) {
        guard let activityTimelineCacheWriter else { return }
        Task(priority: .utility) {
            await activityTimelineCacheWriter.scheduleSave(sessionID: sessionID, timeline: timeline)
        }
    }

    private func flushActivityTimelineCache(sessionID: String) async {
        guard let activityTimelineCacheWriter else { return }
        let startedAt = ContinuousClock.now
        do {
            try await activityTimelineCacheWriter.flush(sessionID: sessionID)
            let elapsed = startedAt.duration(to: ContinuousClock.now)
            let milliseconds = Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
            AppPerformanceLog.chatTurnLogger.info("timelineCache.flush session=\(sessionID, privacy: .public) duration=\(milliseconds, privacy: .public)ms")
        } catch {
            AppPerformanceLog.chatTurnLogger.warning("timelineCache.flush.failed session=\(sessionID, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
    }

    private func scheduleChatSessionListRefresh(reason: String) {
        guard let chatSessionRepository else { return }
        let filter = chatFeatureModel.sessions.filter
        let coordinator = chatSessionListRefreshCoordinator
        Task(priority: .utility) { [weak self] in
            let startedAt = ContinuousClock.now
            do {
                let result = try await coordinator.refresh(repository: chatSessionRepository, filter: filter)
                let elapsed = startedAt.duration(to: ContinuousClock.now)
                let milliseconds = Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.chatFeatureModel.sessions.sessions = result.visibleSessions
                    self.chatFeatureModel.sessions.allSessions = result.allSessions
                    self.rebuildSessionSearchIndexSoon(sessions: result.allSessions)
                    self.synchronizeSessionReadStates(from: result.allSessions)
                    AppPerformanceLog.chatTurnLogger.info("sessionList.asyncRefresh reason=\(reason, privacy: .public) visible=\(result.visibleSessions.count, privacy: .public) all=\(result.allSessions.count, privacy: .public) duration=\(milliseconds, privacy: .public)ms")
                }
            } catch {
                AppPerformanceLog.chatTurnLogger.warning("sessionList.asyncRefresh.failed reason=\(reason, privacy: .public) error=\(String(describing: error), privacy: .public)")
            }
        }
    }

    func cancelActiveChatRun() {
        guard let sessionID = chatFeatureModel.sessions.selectedSessionID else { return }
        switch chatRunCoordinator.requestCancellation(sessionID: sessionID, reason: "cancelled by user") {
        case .queued:
            appendChatCancellationPresentation(
                sessionID: sessionID,
                runID: nil,
                title: "Run cancellation requested",
                detail: "已请求终止本轮 agent loop，正在等待 runtime run ID。"
            )
        case .active(let sessionID, let runID, let reason, let backend):
            cancelRunningChatRun(sessionID: sessionID, runID: runID, reason: reason, backend: backend)
        case .alreadyQueued, .unavailable:
            return
        }
    }

    private func cancelRunningChatRun(sessionID: String, runID: String, reason: String, backend: AnyAgentBackend?) {
        chatRunCoordinator.cancelActive(sessionID: sessionID, runID: runID, reason: reason, backend: backend)
        appendChatCancellationPresentation(
            sessionID: sessionID,
            runID: runID,
            title: "Run cancelled",
            detail: "已手动终止本轮 agent loop。"
        )
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
        var timeline = chatRunCoordinator.selectedOrStoredTimeline(sessionID: sessionID)
        timeline.append(cancellation)
        chatRunCoordinator.setTimeline(timeline, sessionID: sessionID)
    }

    private func resolveActiveSkillInstructions(sessionID: String) -> String? {
        guard let slug = chatFeatureModel.composer.activeSkillSlug else { return nil }
        if let storagePaths {
            let scanner = SkillPackageScanner()
            let snapshot = scanner.scan(storagePaths: storagePaths)
            if let resolution = snapshot.resolution(slug: slug) {
                let runtime = SkillInvocationRuntime()
                let request = SkillInvocationRequest(
                    slug: SkillSlug(slug),
                    rawInvocation: "[skill:\(slug)]",
                    arguments: "",
                    mode: .manual,
                    sessionID: sessionID
                )
                if let plan = try? runtime.buildPlan(request: request, resolution: resolution) {
                    return plan.renderedInstructions
                }
            }
        }
        guard let card = skillRuntimeModel.presentation.cards.first(where: { $0.id == slug }) else { return nil }
        return renderActiveSkillCardInstructions(card)
    }

    private func renderActiveSkillCardInstructions(_ card: SkillManagerCard) -> String? {
        let body = card.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        let requiredSources = card.requiredSources.joined(separator: ", ")
        return """
        <connor-skill-invocation slug=\"\(card.id)\" sourceTier=\"\(card.sourceTier)\" risk=\"\(card.riskLabel)\">
        # \(card.title)

        Description: \(card.subtitle)
        Skill ID: \(card.id)
        Source tier: \(card.sourceTier)
        Trust state: \(card.trustState)
        Required sources: \(requiredSources)

        \(body)
        </connor-skill-invocation>
        """
    }

    private func buildSkillChatPromptAugmentation(prompt: String, sessionID: String) -> SkillChatPromptAugmentation {
        guard let storagePaths else {
            return SkillChatPromptAugmentation(originalPrompt: prompt, augmentedPrompt: prompt)
        }
        return SkillChatPromptAugmentor(storagePaths: storagePaths).augment(
            prompt: prompt,
            sessionID: sessionID
        )
    }

    @discardableResult
    func submitChat(
        prompt rawPrompt: String,
        clearComposer: Bool = false,
        displayPrompt rawDisplayPrompt: String? = nil,
        attachments explicitAttachments: [AgentMessageAttachmentRef]? = nil,
        personReferences: [PersonReference] = []
    ) async -> String? {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayPrompt = rawDisplayPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachmentsForSubmission = explicitAttachments ?? chatFeatureModel.composer.pendingAttachmentRefs
        guard !prompt.isEmpty || !attachmentsForSubmission.isEmpty else { return nil }
        guard !isLoadingSelectedChatSessionDetail else { return nil }
        guard var manager = chatRunCoordinator.manager else {
            errorMessage = String(describing: AppChatRuntimeUnavailableError.nativeSessionManagerUnavailable)
            return nil
        }
        let submittingSessionID = manager.session.id
        guard chatFeatureModel.sessions.selectedSessionID == nil || chatFeatureModel.sessions.selectedSessionID == submittingSessionID else { return nil }
        guard !chatFeatureModel.run.submittingSessionIDs.contains(submittingSessionID) else { return nil }
        let liveBackend = manager.backend
        guard chatRunCoordinator.begin(sessionID: submittingSessionID, backend: liveBackend) else { return nil }
        if clearComposer { chatComposerCoordinator.consumeForSubmission(sessionID: submittingSessionID) }
        let optimisticTranscript = chatFeatureModel.run.transcript
        let baselineMessageCount = manager.session.messages.count
        let baselineUserMessageCount = manager.session.messages.filter { $0.role == .user }.count
        let shouldAutoGenerateInitialTitle = baselineUserMessageCount == 0
        let submittedActiveSkillSlug = chatFeatureModel.composer.activeSkillSlug
        let submittedActiveSkillDisplayName = chatFeatureModel.composer.activeSkillDisplayName
        let submittedActiveSkillContextSnapshot: String? = {
            let displayName = submittedActiveSkillDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let slug = submittedActiveSkillSlug?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !displayName.isEmpty || !slug.isEmpty else { return nil }
            return "Active skill: \(displayName.isEmpty ? slug : displayName)\(slug.isEmpty ? "" : " (\(slug))")"
        }()
        let optimisticUserMessage = AgentMessage(
            role: .user,
            content: displayPrompt?.isEmpty == false ? displayPrompt! : prompt,
            contextSnapshot: submittedActiveSkillContextSnapshot,
            attachments: attachmentsForSubmission,
            personReferences: personReferences
        )
        chatRunCoordinator.applyOptimisticTranscript(optimisticTranscript + [optimisticUserMessage], sessionID: submittingSessionID)
        defer { chatRunCoordinator.finish(sessionID: submittingSessionID) }
        do {
            let sessionSummary: AgentSessionSummary?
            if let chatSessionRepository {
                let candidateSummary = try chatSessionRepository.loadLatestSummary(sessionID: submittingSessionID)
                sessionSummary = AgentSessionSummaryPolicy().summaryForContext(candidateSummary, session: manager.session)
            } else {
                sessionSummary = nil
            }
            let attachmentContextPlan = await buildAttachmentContextPlanOffMain(
                sessionID: submittingSessionID,
                attachments: attachmentsForSubmission
            )
            let noteAugmentedPrompt = NoteSessionPromptBuilder.augmentedPrompt(
                prompt,
                sessionKind: manager.session.governance.kind,
                hasExistingMessages: !manager.session.messages.isEmpty
            )
            let skillAugmentation = buildSkillChatPromptAugmentation(prompt: noteAugmentedPrompt, sessionID: submittingSessionID)
            let resolvedSkillInstructions = resolveActiveSkillInstructions(sessionID: submittingSessionID)
            if resolvedSkillInstructions != nil {
                chatComposerCoordinator.clearActiveSkill()
            }
            let submitStartedAt = ContinuousClock.now
            let response = try await manager.submit(
                skillAugmentation.augmentedPrompt,
                sessionSummary: sessionSummary,
                displayPrompt: displayPrompt?.isEmpty == false ? displayPrompt : nil,
                attachments: attachmentsForSubmission,
                attachmentContextPlan: attachmentContextPlan,
                personReferences: personReferences,
                skillInstructions: resolvedSkillInstructions,
                activeSkillSlug: resolvedSkillInstructions == nil ? nil : submittedActiveSkillSlug,
                activeSkillDisplayName: resolvedSkillInstructions == nil ? nil : submittedActiveSkillDisplayName,
                onRunStarted: { [weak self] runID in
                    guard let self else { return }
                    if let reason = self.chatRunCoordinator.registerRun(sessionID: submittingSessionID, runID: runID, backend: liveBackend) {
                        self.cancelRunningChatRun(sessionID: submittingSessionID, runID: runID, reason: reason, backend: liveBackend)
                    }
                },
                onEventPresentation: { [weak self] presentation in
                    guard let self else { return }
                    self.chatRunCoordinator.appendEvent(presentation, sessionID: submittingSessionID)
                    if presentation.kind == AgentEventKind.permissionRequested.rawValue {
                        self.chatApprovalCoordinator.reload()
                    }
                    self.skillRuntimeModel.reloadIfNeeded(after: presentation)
                }
            )
            let submitElapsed = submitStartedAt.duration(to: ContinuousClock.now)
            let submitMilliseconds = Double(submitElapsed.components.seconds) * 1_000 + Double(submitElapsed.components.attoseconds) / 1_000_000_000_000_000
            AppPerformanceLog.chatTurnLogger.info("nativeSubmit.completed session=\(submittingSessionID, privacy: .public) events=\(manager.eventPresentations.count, privacy: .public) duration=\(submitMilliseconds, privacy: .public)ms")
            chatRunCoordinator.setTimeline(manager.eventPresentations, sessionID: submittingSessionID)
            await flushActivityTimelineCache(sessionID: submittingSessionID)
            if chatFeatureModel.sessions.selectedSessionID == submittingSessionID {
                chatRunCoordinator.applyCompletedRun(
                    manager: manager,
                    session: response.session,
                    summary: try chatSessionRepository?.loadLatestSummary(sessionID: response.session.id)
                )
                chatSessionCoordinator.adoptDirectSelection(response.session.id)
            }
            chatApprovalCoordinator.reload()
            scheduleChatSessionListRefresh(reason: "chatSubmitCompleted")
            if shouldAutoGenerateInitialTitle {
                regenerateChatSessionTitle(submittingSessionID)
            }
            errorMessage = nil
            let latestAssistantMessage = response.session.messages
                .dropFirst(baselineMessageCount)
                .last(where: { $0.role == AgentRole.assistant })
            noteSessionUpdate(
                sessionID: response.session.id,
                messageID: latestAssistantMessage?.id,
                preview: latestAssistantMessage.map { notificationPreview(from: $0.content) },
                notificationBody: latestAssistantMessage.map { notificationPreview(from: $0.content) } ?? response.session.title
            )
            maintenanceCoordinator.scheduleBackgroundJobs()
            maintenanceCoordinator.scheduleDailySweep()
            return latestAssistantMessage?.content
        } catch {
            let recoveredSession = (try? chatSessionRepository?.loadSession(id: submittingSessionID)) ?? manager.session
            if chatFeatureModel.sessions.selectedSessionID == submittingSessionID {
                chatRunCoordinator.applyRecoveredRun(
                    manager: manager,
                    session: recoveredSession,
                    transcript: recoveredSession.messages.isEmpty ? optimisticTranscript + [optimisticUserMessage] : recoveredSession.messages
                )
            }
            chatApprovalCoordinator.reload()
            chatRunCoordinator.clearPendingCancellation(sessionID: submittingSessionID)
            if case NativeSessionManagerError.runCancelled = error {
                errorMessage = nil
            } else {
                let errorDescription = String(describing: error)
                errorMessage = errorDescription
                noteSessionUpdate(
                    sessionID: submittingSessionID,
                    messageID: nil,
                    preview: errorDescription,
                    notificationBody: errorDescription
                )
            }
            return nil
        }
    }


}

extension AppViewModel {
    var hasMemoryOSBackendForTests: Bool {
        memoryOSFacade != nil
    }
}

/// 笔记会话首条消息的系统指令构建器
struct NoteSessionPromptBuilder {
    static func augmentedPrompt(
        _ prompt: String,
        sessionKind: AgentSessionKind,
        hasExistingMessages: Bool
    ) -> String {
        guard sessionKind == .note, !hasExistingMessages, !prompt.isEmpty else {
            return prompt
        }
        return prompt + noteInstructionSuffix
    }

    static let noteInstructionSuffix = """

## 系统笔记指令

### 当前输入上下文
- session_kind: note
- note_phase: initial_capture
- persistence: session_backed

用户通过笔记界面提交了这个 Note Session 的第一条内容。这条用户消息已经由 Session OS 保存，并会通过既有后台摄取链路自动进入 Memory OS L0/L1；保存笔记不是一个需要你执行的工具动作。

不要为了保存这条笔记调用 `Write`、`Edit`、shell、知识库写入或 Memory 写入工具，也不要生成文件名、创建 Markdown 文件或选择保存路径。只有当用户在笔记内容中明确要求创建文件、导出到路径或修改现有文件时，才按普通工具权限规则执行相应操作。

完成本轮强制上下文与搜索 Bootstrap 后，请对用户的输入进行以下处理：

1. **总结核心内容**：用一段话概括用户输入的核心思想
2. **领域识别**：指出这段内容涉及的知识领域
3. **关系映射**：分析这个想法与同领域内其他概念的关联
4. **启发式拓展**：指出可进一步探索的方向、可连接的交叉领域、可追问的问题

然后以以下结构回复：

# 📝 笔记已保存

> [用户原文摘要]

**领域标签：**[识别出的领域]

**核心内容：**
[总结段落]

**关联概念：**
- 概念 A：关系说明
- 概念 B：关系说明

**拓展方向：**
- 方向 1：详细说明
- 方向 2：详细说明

---

*这条笔记已被系统保存。如果你希望围绕这些议题做进一步的探索、追问、或与已有知识建立连接，可以继续在这个会话中发送消息。*
"""
}
