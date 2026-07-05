import SwiftUI
import AppKit
import CoreLocation
import IOKit.pwr_mgt
import UserNotifications
import WebKit
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

enum AppViewModelTaskCreationError: LocalizedError {
    case missingRepository

    var errorDescription: String? {
        switch self {
        case .missingRepository:
            return "任务管理存储尚未初始化，请稍后重试。"
        }
    }
}

enum AppSessionBackgroundTaskStatus: String, Codable, Equatable, Sendable {
    case queued
    case running
    case succeeded
    case failed
    case interrupted

    var displayName: String {
        switch self {
        case .queued: "排队中"
        case .running: "运行中"
        case .succeeded: "已完成"
        case .failed: "失败"
        case .interrupted: "已中断"
        }
    }

    var systemImage: String {
        switch self {
        case .queued: "clock"
        case .running: "arrow.triangle.2.circlepath"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .interrupted: "pause.circle.fill"
        }
    }
}

struct AppSessionBackgroundTask: Identifiable, Equatable, Sendable {
    var id: String = UUID().uuidString
    var sessionID: String
    var kind: String = "generic"
    var title: String
    var detail: String
    var status: AppSessionBackgroundTaskStatus = .queued
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var errorMessage: String?
    var payloadJSON: String = "{}"

    init(
        id: String = UUID().uuidString,
        sessionID: String,
        kind: String = "generic",
        title: String,
        detail: String,
        status: AppSessionBackgroundTaskStatus = .queued,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        errorMessage: String? = nil,
        payloadJSON: String = "{}"
    ) {
        self.id = id
        self.sessionID = sessionID
        self.kind = kind
        self.title = title
        self.detail = detail
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.errorMessage = errorMessage
        self.payloadJSON = payloadJSON
    }

    init(persisted task: PersistedSessionBackgroundTask) {
        self.init(
            id: task.id,
            sessionID: task.sessionID,
            kind: task.kind,
            title: task.title,
            detail: task.detail,
            status: AppSessionBackgroundTaskStatus(persisted: task.status),
            createdAt: task.createdAt,
            updatedAt: task.updatedAt,
            errorMessage: task.errorMessage,
            payloadJSON: task.payloadJSON
        )
    }

    var persisted: PersistedSessionBackgroundTask {
        PersistedSessionBackgroundTask(
            id: id,
            sessionID: sessionID,
            kind: kind,
            title: title,
            detail: detail,
            status: status.persisted,
            createdAt: createdAt,
            updatedAt: updatedAt,
            errorMessage: errorMessage,
            payloadJSON: payloadJSON
        )
    }
}

private extension AppSessionBackgroundTaskStatus {
    init(persisted status: PersistedSessionBackgroundTaskStatus) {
        switch status {
        case .queued: self = .queued
        case .running: self = .running
        case .succeeded: self = .succeeded
        case .failed: self = .failed
        case .interrupted: self = .interrupted
        }
    }

    var persisted: PersistedSessionBackgroundTaskStatus {
        switch self {
        case .queued: .queued
        case .running: .running
        case .succeeded: .succeeded
        case .failed: .failed
        case .interrupted: .interrupted
        }
    }
}

struct MCPSourceDraft: Equatable {
    var editingSourceID: String?
    var sourceID: String = ""
    var displayName: String = ""
    var transportKind: String = "stdio"
    var command: String = ""
    var argumentsText: String = ""
    var status: ProductOSRegistryEntryStatus = .draft
    var credentialRequirement: ProductOSCredentialRequirement = .none
    var credentialEnvironmentText: String = ""
    var credentialSecret: String = ""
    var allowExternalNetwork: Bool = true
    var allowReadSession: Bool = true
    var allowWorkspaceRead: Bool = false
    var tagsText: String = "mcp"
    var notes: String = ""

    init() {}

    init(configuration: MCPSourceRuntimeConfiguration) {
        editingSourceID = configuration.sourceID
        sourceID = configuration.sourceID
        displayName = configuration.displayName
        status = configuration.status
        credentialRequirement = configuration.credentialRequirement
        credentialEnvironmentText = configuration.credentialBindings.map { binding in
            binding.label.isEmpty || binding.label == binding.environmentVariable
                ? binding.environmentVariable
                : "\(binding.label):\(binding.environmentVariable)"
        }.joined(separator: ", ")
        allowExternalNetwork = configuration.allowedCapabilities.contains(.externalNetwork)
        allowReadSession = configuration.allowedCapabilities.contains(.readSession)
        allowWorkspaceRead = configuration.allowedCapabilities.contains(.readWorkspaceFile) || configuration.allowedCapabilities.contains(.listWorkspaceFiles)
        tagsText = configuration.tags.joined(separator: ", ")
        notes = configuration.notes
        switch configuration.transport {
        case .stdio(let command, let arguments):
            transportKind = "stdio"
            self.command = command
            self.argumentsText = arguments.joined(separator: " ")
        case .http(let url):
            transportKind = "http"
            self.command = url.absoluteString
            self.argumentsText = ""
        }
    }

    var parsedArguments: [String] {
        argumentsText
            .split(whereSeparator: { $0 == "\n" || $0 == " " || $0 == "\t" })
            .map(String.init)
    }

    var parsedCredentialBindings: [MCPSourceCredentialBinding] {
        guard credentialRequirement != .none else { return [] }
        var bindings: [String: MCPSourceCredentialBinding] = [:]
        for token in credentialEnvironmentText.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == " " || $0 == "\t" }) {
            let parsed = Self.parseCredentialBindingToken(String(token))
            if let parsed { bindings[parsed.environmentVariable] = parsed }
        }
        for env in parsedCredentialSecretByEnvironment.keys.sorted() where bindings[env] == nil {
            bindings[env] = MCPSourceCredentialBinding(label: env, environmentVariable: env)
        }
        return bindings.values.sorted { $0.environmentVariable < $1.environmentVariable }
    }

    var parsedCredentialSecretByEnvironment: [String: String] {
        var values: [String: String] = [:]
        for line in credentialSecret.split(whereSeparator: { $0 == "\n" || $0 == ";" }) {
            let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separatorIndex = text.firstIndex(of: "=") else { continue }
            let key = String(text[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let value = String(text[text.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty, !value.isEmpty { values[key] = value }
        }
        return values
    }

    var trimmedCredentialSecret: String {
        credentialSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parseCredentialBindingToken(_ raw: String) -> MCPSourceCredentialBinding? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let separator = text.firstIndex(where: { $0 == ":" || $0 == "=" }) {
            let label = String(text[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let env = String(text[text.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !label.isEmpty, !env.isEmpty else { return nil }
            return MCPSourceCredentialBinding(label: label, environmentVariable: env)
        }
        let env = text.uppercased()
        return MCPSourceCredentialBinding(label: env, environmentVariable: env)
    }

    var parsedTags: [String] {
        Array(Set(tagsText
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == " " || $0 == "\t" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }))
        .sorted()
    }

    var runtimeTransport: MCPSourceRuntimeTransport? {
        let endpoint = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if transportKind == "http" {
            guard let url = URL(string: endpoint), url.scheme != nil, url.host != nil else { return nil }
            return .http(url: url)
        }
        return .stdio(command: endpoint, arguments: parsedArguments)
    }

    var allowedCapabilities: [AgentPermissionCapability] {
        var capabilities: [AgentPermissionCapability] = []
        if allowExternalNetwork { capabilities.append(.externalNetwork) }
        if allowReadSession { capabilities.append(.readSession) }
        if allowWorkspaceRead {
            capabilities.append(.readWorkspaceFile)
            capabilities.append(.listWorkspaceFiles)
        }
        return capabilities.isEmpty ? [.readSession] : capabilities
    }

    var normalizedSourceID: String {
        sourceID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var normalizedDisplayName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? normalizedSourceID : trimmed
    }

    var isEditing: Bool { editingSourceID != nil }
}

@MainActor
final class AppViewModel: NSObject, ObservableObject {
#if DEBUG
    private let mainActorStallMonitor = AppMainActorStallMonitor()
#endif
    private let memoryOSMaintenanceWorker = AppMemoryOSMaintenanceWorker()

    private static let birthDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let customGenderIdentitySelection = "__custom_gender_identity__"
    static let genderIdentityPresetValues: Set<String> = ["女性", "男性", "非二元", "性别流动", "无性别", "酷儿 / 性别酷儿", "不愿透露"]

    @Published var selection: SidebarItem? = .agentChat
    @Published var query: String = "记忆"
    @Published var searchResults: [GraphSearchHit] = []
    @Published var chatInput: String = "" {
        didSet {
            guard autoSaveDraftsEnabled, !isRestoringChatInputDraft, let selectedChatSessionID else { return }
            chatInputDraftsBySessionID[selectedChatSessionID] = chatInput
        }
    }
    @Published var transcript: [AgentMessage] = []
    @Published var selectedChatTranscriptRevision: Int = 0
    @Published var lastContext: AgentContext?
    @Published var lastPromptInspection: AgentChatPromptInspection?
    @Published var errorMessage: String?
    @Published var attachmentToast: AgentChatToast?
    @Published var entities: [GraphEntity]
    @Published var statements: [GraphStatement]
    @Published var episodes: [GraphEpisodeV3]
    @Published var observeLogEntries: [ObserveLogEntry]
    @Published var databasePath: String?
    @Published var schemaHealthReport: GraphSchemaHealthReport?
    @Published var promotionCandidates: [ObserveLogEntry] = []
    @Published var pendingApprovals: [AgentPendingApproval] = []
    @Published var lastPromotionResultSummary: String?
    @Published var lastPendingApprovalResultSummary: String?
    @Published var llmConnectionConfigs: [AppLLMConnectionConfig] = []
    @Published var llmDefaultConnectionID: String = ""
    @Published var llmConnectionName: String = ""
    @Published var llmProviderMode: AppLLMProviderMode = .openAICompatible
    @Published var llmBaseURLString: String = ""
    @Published var llmModel: String = ""
    @Published var llmSelectedModel: String = ""
    @Published var llmThinkingLevel: AppLLMThinkingLevel = AppLLMSettings.default.defaultThinkingLevel
    @Published var llmAPIKeyInput: String = ""
    @Published var llmHasAPIKey: Bool = false
    @Published var agentPermissionMode: AgentPermissionMode = .readOnly
    @Published var llmSettingsMessage: String?
    @Published var llmHealthCheckMessage: String?
    @Published var isTestingLLMConnection: Bool = false
    @Published var isAddingLLMConnection: Bool = false
    @Published var llmModelConnections: [AppLLMModelConnection] = []
    @Published var isLoadingLLMModelConnections: Bool = false
    @Published var showWelcomePlaceholder: Bool = false
    @Published var chatSessions: [AgentSession] = []
    @Published var allChatSessions: [AgentSession] = []
    @Published var selectedChatSessionID: String?
    @Published private(set) var sessionReadStates: [String: SessionReadState] = [:]
    @Published var regeneratingTitleSessionIDs: Set<String> = []
    @Published var backgroundTasksBySessionID: [String: [AppSessionBackgroundTask]] = [:]
    @Published var speechTranscriptionStatus: SessionSpeechTranscriptionStatus = .idle
    @Published var speechProvisionalTranscript: String?
    @Published var isBackgroundTasksPresented: Bool = false
    @Published var sessionListFilter: AgentSessionListFilter = .all
    @Published var sessionSearchQuery: String = ""
    @Published var globalSearchQuery: String = ""
    @Published var isGlobalSearchFieldFocused: Bool = false
    @Published var isGlobalSearchOverlayPresented: Bool = false
    @Published var globalSearchPreviewState: GlobalSearchPreviewState = .empty
    @Published var globalSearchSelectedItem: GlobalSearchSelectableItem? = .action(.newChat)
    @Published private(set) var globalSearchTimings: [GlobalSearchSectionTiming] = []
    @Published var governanceConfig: AppSessionGovernanceConfig = .default
    @Published var productOSRegistry: ProductOSRegistrySnapshot = .default
    @Published var automationConfig: ProductOSAutomationConfig = .default
    @Published var automationTriggerRecords: [ProductOSAutomationTriggerRecord] = []
    @Published var automationExecutionHistory: [ProductOSAutomationExecutionHistoryRecord] = []
    @Published var taskManagementPresentation = TaskManagementUIPresentation(
        summary: TaskManagementUISummary(totalTaskCount: 0, scheduledTaskCount: 0, eventTriggeredTaskCount: 0, systemTaskCount: 0, userTaskCount: 0, aiTaskCount: 0, stoppedTaskCount: 0, failedTaskCount: 0),
        cards: []
    )
    @Published var selectedTaskAutomationID: String?
    @Published var isRunningScheduledTasks: Bool = false
    @Published var sourceRuntimeConfigurations: [MCPSourceRuntimeConfiguration] = []
    @Published var sourceRuntimeHealthRecords: [MCPSourceRuntimeHealthRecord] = []
    @Published var sourceRuntimeToolCatalogs: [String: [MCPSourceToolDescriptor]] = [:]
    @Published var sourceRuntimeAuditRecordsBySource: [String: [MCPSourceRuntimeAuditRecord]] = [:]
    @Published var selectedSourceRuntimeCardID: String?
    @Published var testingSourceRuntimeIDs: Set<String> = []
    @Published var sourceRuntimeTestMessages: [String: String] = [:]
    @Published var isPresentingAddSourceSheet: Bool = false
    @Published var addSourceDraft = MCPSourceDraft()
    @Published var addSourceMessage: String?
    @Published var pendingSourceRuntimeDeletionID: String?
    @Published var pendingSourceRuntimeDeletionName: String?
    @Published var calendarBrowserPresentation: NativeCalendarBrowserPresentation = .empty
    @Published var calendarSearchQuery: String = ""
    @Published var calendarAccounts: [CalendarAccount] = []
    @Published var calendarCollections: [CalendarCollection] = []
    @Published var calendarEvents: [CalendarEvent] = []
    @Published var selectedCalendarEventID: CalendarEventID?
    @Published var isPresentingAddCalendarSourceSheet: Bool = false
    @Published var isSyncingSystemCalendar: Bool = false
    @Published var calendarSyncMessage: String?
    @Published var contactsBrowserPresentation: NativeContactsBrowserPresentation = .empty
    @Published var contactRecords: [ContactRecord] = []
    @Published var selectedContactID: ContactID?
    @Published var isSyncingSystemContacts: Bool = false
    @Published var contactsSyncMessage: String?
    @Published var mailBrowserPresentation: NativeMailBrowserPresentation = .empty
    @Published var mailSearchQuery: String = ""
    @Published var selectedMailAccountID: MailAccountID?
    @Published var selectedMailMailboxID: MailMailboxID?
    @Published var selectedMailMessageID: MailMessageID?
    @Published var mailPreferences: MailPreferences = MailPreferences()
    @Published var isPresentingAddMailAccountSheet: Bool = false
    @Published var mailSyncMessage: String?
    @Published var rssBrowserPresentation: NativeRSSBrowserPresentation = .empty
    @Published var rssSearchQuery: String = ""
    @Published var selectedRSSSourceID: RSSSourceID?
    @Published var selectedRSSItemID: RSSItemID?
    @Published var isPresentingAddRSSSourceSheet: Bool = false
    @Published var editingRSSSource: RSSSource?
    @Published var pendingRSSSourceDeletion: RSSSource?
    @Published var skillRuntimeDefinitions: [SkillRuntimeDefinition] = []
    @Published var commercialSkillManagerPresentation: SkillManagerPresentation = SkillManagerPresentation(
        summary: SkillManagerSummary(total: 0, enabled: 0, projectScoped: 0, risky: 0, invalid: 0, sourceBlocked: 0),
        cards: [],
        globalWarnings: []
    )
    @Published var selectedSkillManagerCardID: String?
    @Published var isAddSkillDialogPresented: Bool = false
    @Published var addSkillRequestDraft: String = ""
    @Published var isSubmittingAddSkillRequest: Bool = false
    @Published var addSkillDialogMessage: String?
    @Published var isEditSkillDialogPresented: Bool = false
    @Published var editSkillRequestDraft: String = ""
    @Published var editingSkillCard: SkillManagerCard?
    @Published var isSubmittingEditSkillRequest: Bool = false
    @Published var editSkillDialogMessage: String?
    @Published var pendingSkillDeletionCard: SkillManagerCard?
    @Published var activeSkillSlug: String?
    @Published var activeSkillDisplayName: String?
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
    let browserLiveWebViewStore = BrowserLiveWebViewStore()
    @Published var browserAssistedTasksByID: [UUID: BrowserAssistedTaskState] = [:]
    @Published var browserAssistedWebFetchRequestsByTaskID: [UUID: BrowserAssistedWebFetchRequest] = [:]
    @Published var isBrowserBookmarksPanelVisible: Bool = false
    @Published var browserBookmarkRecords: [BrowserBookmarkRecord] = []
    @Published var filteredBrowserBookmarkRecords: [BrowserBookmarkRecord] = []
    @Published var selectedBrowserBookmarkGroupName: String?
    @Published var isBrowserHistoryPanelVisible: Bool = false
    @Published var browserHistoryRecords: [BrowserHistoryRecord] = []
    @Published var filteredBrowserHistoryRecords: [BrowserHistoryRecord] = []
    @Published var browserHistorySearchQuery: String = ""
    @Published var selectedSettingsSection: ConnorSettingsSection = .app
    @Published var desktopNotificationsEnabled: Bool = true
    @Published var sessionNewMessageNotificationLevel: SessionAttentionLevel = .actionable
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
    @Published var sessionSpeechTranscriptionEnabled: Bool = false {
        didSet {
            guard oldValue != sessionSpeechTranscriptionEnabled, !sessionSpeechTranscriptionEnabled else { return }
            stopSpeechTranscriptionForDisabledSetting()
        }
    }
    @Published var shortcutSettings: AgentRuntimeShortcutSettings = AgentRuntimeShortcutSettings()
    @Published var recordingShortcutAction: AgentRuntimeShortcutAction?
    @Published var focusTopSearchRequestID: UUID?
    @Published var defaultPermissionMode: AgentPermissionMode = .askToWrite
    @Published var requireApprovalForNetwork: Bool = false
    @Published var requireApprovalForShell: Bool = true
    @Published var defaultWorkingDirectoryPath: String = ""
    @Published var workspaceRoots: [WorkspaceRootDraft] = []
    @Published var recentWorkspacePaths: [String] = []
    @Published var workspaceRootPathInput: String = ""
    @Published var userDisplayName: String = ""
    @Published var userTimezone: String = ""
    @Published var userPreferredLanguage: String = ""
    @Published var userGenderIdentity: String = ""
    @Published var userGenderIdentitySelection: String = ""
    @Published var userGenderIdentityCustomText: String = ""
    @Published var userBirthDate: String = ""
    @Published var userBirthDatePickerDate: Date = Date()
    @Published var userCity: String = ""
    @Published var userCountry: String = ""
    @Published var userPreferenceNotes: String = ""
    @Published var defaultSearchEngine: DefaultSearchEngine = .default
    @Published var userLocationStatusMessage: String?
    @Published var settingsSectionMessageStore = SettingsSectionMessageStore()
    @Published var pendingAttachmentRefs: [AgentMessageAttachmentRef] = []
    @Published var attachmentPreviewModel: AttachmentPreviewModel?
    @Published var memoryOSSearchHealthSummary: String?
    @Published private(set) var isMemoryOSSearchIndexRepairing = false

    private var repository: AppGraphRepository?
    private var promotionRepository: AppPromotionQueueRepository?
    private var pendingApprovalRepository: AppAgentPendingApprovalRepository?
    private var memoryOSStore: SQLiteMemoryOSStore?
    private var memoryOSFacade: AppMemoryOSFacade?
    private var chatSessionRepository: AppChatSessionRepository?
    private var activityTimelineCacheWriter: ActivityTimelineCacheWriter?
    private var governanceConfigRepository: AppSessionGovernanceConfigRepository?
    private var productOSRegistryRepository: AppProductOSRegistryRepository?
    private var automationRepository: AppProductOSAutomationRepository?
    private var taskManagementRepository: AppTaskManagementRepository?
    private var sourceRuntimeRepository: AppMCPSourceRuntimeRepository?
    private var mcpSourceCredentialStore = MCPSourceCredentialStore()
    private var skillRuntimeRepository: AppSkillRuntimeRepository?
    private var storagePaths: AppStoragePaths?
    private var browserHistoryStore: BrowserHistoryStore?
    private var browserBookmarkStore: BrowserBookmarkStore?
    private var runtimeSettingsRepository: AppRuntimeSettingsRepository?
    private var llmSettingsRepository: AppLLMSettingsRepository
    private var llmProviderHealthChecker: AppLLMProviderHealthChecker
    private var rssRuntime = RSSRuntime(repository: InMemoryRSSSourceRepository(), cache: InMemoryRSSSourceCache())
    private var nativeSourceSearchBackend: (any NativeSourceSearchBackend)?
    private var sessionSearchIndexService: SessionSearchIndexService?
    private var globalSearchPreviewTask: Task<Void, Never>?
    private var calendarStore: FileBackedCalendarSourceStore?
    private var calendarRuntimeStore: FileBackedCalendarSourceRuntimeStore?
    private var contactStore: FileBackedContactSourceStore?
    private var mailStore: FileBackedMailSourceStore?
    private var mailPreferencesStore: (any MailPreferencesStore)?
    private var calendarCredentialStore = AppCalendarCredentialStore()
    private var agentRuntimeFactory: AppGraphAgentRuntimeFactory?
    private var hybridSearchService: (any GraphHybridSearchService)?
    private var isRunningBackgroundJobs: Bool = false
    private var lastMemoryOSDailySweep: Date?
    private var hasScheduledMemoryOSSearchIndexRepair = false

    private var backgroundAIExecutorProvider: BackgroundAIExecutorProvider? {
        guard let agentRuntimeFactory, let memoryOSFacade else { return nil }
        let factory = agentRuntimeFactory
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
    private var hasLoadedInitialChatSessions = false
    // Product chat path: NativeSessionManager owns Connor session state and talks to replaceable AgentBackend implementations.
    // fallbackChatSession is UI-only for demo/no-runtime states.
    private var fallbackChatSession: AgentSession
    private var nativeSessionManager: NativeSessionManager?
    @Published private(set) var submittingChatSessionIDs: Set<String> = []
    private var activeChatRunIDsBySessionID: [String: String] = [:]
    private var activeChatBackendsBySessionID: [String: AnyAgentBackend] = [:]
    private var activeChatBackendsByRunID: [String: AnyAgentBackend] = [:]
    private var pendingChatCancellationReasonsBySessionID: [String: String] = [:]
    private var chatInputDraftsBySessionID: [String: String] = [:]
    private var pendingAttachmentRefsBySessionID: [String: [AgentMessageAttachmentRef]] = [:]
    private var browserAssistedWebFetchContinuationsByTaskID: [UUID: CheckedContinuation<BrowserAssistedWebFetchResult, Never>] = [:]
    private var browserHistoryContentFetchTasksByID: [UUID: Task<Void, Never>] = [:]
    private var isRestoringChatInputDraft = false
    private var agentEventTimelinesBySessionID: [String: [AgentEventPresentation]] = [:]
    private var agentEventTimelinesByProcessKey: [String: [AgentEventPresentation]] = [:]
    private var browserWorkspaceSessionBinding = BrowserWorkspaceSessionBinding()
    private var chatSessionWorkspaceModes = ChatSessionWorkspaceModeStore()
    private var isLoadingRuntimeSettings = false
    private var runtimeSettingsAutosaveTask: Task<Void, Never>?
    private var lastSessionNotificationAt: [String: Date] = [:]
    private let sameSessionNotificationCooldown: TimeInterval = 300
    private var idleSleepAssertionID: IOPMAssertionID = 0
    private var hasActivatedRuntimeSettingsSideEffects = false
    private var locationCoordinator: UserLocationCoordinator?
    private var taskSchedulerTimer: Timer?
    private lazy var speechTranscriptionCoordinator = SessionSpeechTranscriptionCoordinator(
        transcriber: SessionSpeechTranscriptionController()
    )

    private var activeChatSession: AgentSession {
        nativeSessionManager?.session ?? fallbackChatSession
    }

    private var activeChatTranscript: [AgentMessage] {
        nativeSessionManager?.session.messages ?? fallbackChatSession.messages
    }

    var runtimeSettingsAutosaveSignature: String {
        [
            desktopNotificationsEnabled.description,
            sessionNewMessageNotificationLevel.rawValue.description,
            keepScreenAwake.description,
            httpProxyEnabled.description,
            httpProxyURLString,
            appearanceMode.rawValue,
            showProviderIcons.description,
            richToolDescriptionsEnabled.description,
            composerSendShortcut,
            spellCheckEnabled.description,
            autoSaveDraftsEnabled.description,
            sessionSpeechTranscriptionEnabled.description,
            shortcutSettings.bindings.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue)=\($0.value.displayText)" }.joined(separator: ","),
            defaultPermissionMode.rawValue,
            requireApprovalForNetwork.description,
            requireApprovalForShell.description,
            userDisplayName,
            userTimezone,
            userPreferredLanguage,
            userGenderIdentity,
            userGenderIdentitySelection,
            userGenderIdentityCustomText,
            userBirthDate,
            userBirthDatePickerDate.timeIntervalSince1970.description,
            userCity,
            userCountry,
            userPreferenceNotes,
            defaultSearchEngine.rawValue
        ].joined(separator: "\u{1F}")
    }

    var activeChatPendingApprovals: [AgentPendingApproval] {
        let activeSessionID = activeChatSession.id
        return pendingApprovals.filter { approval in
            approval.sessionID == activeSessionID && !shouldAutoApprovePendingApproval(approval)
        }
    }

    func shortcut(for action: AgentRuntimeShortcutAction) -> AgentRuntimeKeyboardShortcut {
        shortcutSettings.shortcut(for: action)
    }

    func beginRecordingShortcut(for action: AgentRuntimeShortcutAction) {
        recordingShortcutAction = action
    }

    func updateShortcut(_ action: AgentRuntimeShortcutAction, shortcut: AgentRuntimeKeyboardShortcut) {
        shortcutSettings.bindings[action] = shortcut
        recordingShortcutAction = nil
        scheduleRuntimeSettingsAutosave()
    }

    func resetShortcut(_ action: AgentRuntimeShortcutAction) {
        if let defaultShortcut = AgentRuntimeShortcutSettings.defaultBindings[action] {
            shortcutSettings.bindings[action] = defaultShortcut
            scheduleRuntimeSettingsAutosave()
        }
    }

    func performShortcutAction(_ action: AgentRuntimeShortcutAction) {
        switch action {
        case .newSession:
            performShellCommand(.newSession)
        case .toggleBrowser:
            performShellCommand(.toggleBrowser)
        case .focusTopSearch:
            focusTopSearchRequestID = UUID()
        case .openSettings:
            performShellCommand(.openSettings)
        case .focusBrowserAddress, .newBrowserTab, .closeBrowserTab, .browserBack, .browserForward, .toggleBrowserBookmarks, .toggleBrowserHistory:
            break
        }
    }

    func setAgentPermissionMode(_ mode: AgentPermissionMode) {
        guard mode != .allowAll else { return }
        agentPermissionMode = mode
        nativeSessionManager?.permissionMode = mode
        persistLLMSettings(rebuildRuntime: submittingChatSessionIDs.isEmpty)
        autoApproveCurrentPolicyPendingApprovals()
    }

    private func shouldAutoApprovePendingApproval(_ approval: AgentPendingApproval) -> Bool {
        guard approval.status == .pending else { return false }
        switch agentPermissionMode {
        case .trustedWrite:
            switch approval.capability {
            case .readGraph, .readSession, .mutateSessionStatus, .modelCall, .proposeGraphWrite, .commitGraphWrite, .externalNetwork, .readWorkspaceFile, .listWorkspaceFiles, .searchWorkspaceFiles, .writeWorkspaceFile, .editWorkspaceFile, .computeScientific, .runReadOnlyShellCommand, .runWorkspaceShellCommand, .readContacts, .readCalendar, .readRSS, .readRSSContent, .mutateRSSState, .syncRSSSources, .exportRSSOPML, .readMail, .readMailBody, .createMailDraft:
                return true
            case .invalidateGraphStatement, .deleteGraphObject, .costlyModelCall, .deleteWorkspaceFile, .runNetworkShellCommand, .runDestructiveShellCommand, .mutateContacts, .mutateCalendar, .manageRSSSources, .importRSSOPML, .mutateMailState, .manageMailboxes, .sendMail, .importMailAttachment:
                return false
            }
        case .allowAll:
            return true
        case .readOnly, .askToWrite:
            return false
        }
    }

    private func autoApproveCurrentPolicyPendingApprovals() {
        let approvals = pendingApprovals.filter(shouldAutoApprovePendingApproval)
        for approval in approvals {
            Task {
                await resolvePendingApproval(
                    approval,
                    status: .approved,
                    reason: "Automatically approved by current \(agentPermissionMode.displayName) policy",
                    actor: "policy-auto-approver"
                )
            }
        }
    }

    func isChatSessionSubmitting(_ sessionID: String) -> Bool {
        submittingChatSessionIDs.contains(sessionID)
    }

    private func setChatInputDraft(_ draft: String, for sessionID: String?) {
        isRestoringChatInputDraft = true
        chatInput = sessionID.flatMap { chatInputDraftsBySessionID[$0] } ?? draft
        isRestoringChatInputDraft = false
    }

    func updateSelectedChatInputDraft(_ draft: String) {
        guard autoSaveDraftsEnabled, !isRestoringChatInputDraft, let selectedChatSessionID else { return }
        chatInputDraftsBySessionID[selectedChatSessionID] = draft
        speechTranscriptionCoordinator.noteUserEditedDraft(sessionID: selectedChatSessionID, draft: draft)
    }

    func currentSelectedChatInputDraftForSpeech() -> String {
        guard autoSaveDraftsEnabled, let selectedChatSessionID else { return chatInput }
        return chatInputDraftsBySessionID[selectedChatSessionID] ?? chatInput
    }

    private func restoreChatInputDraft(for sessionID: String?) {
        setChatInputDraft(autoSaveDraftsEnabled ? "" : chatInput, for: autoSaveDraftsEnabled ? sessionID : nil)
        pendingAttachmentRefs = sessionID.flatMap { pendingAttachmentRefsBySessionID[$0] } ?? []
    }

    var canSubmitCurrentChat: Bool {
        !chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachmentRefs.isEmpty
    }

    func removePendingAttachment(id: String) {
        pendingAttachmentRefs.removeAll { $0.id == id }
        if let selectedChatSessionID {
            pendingAttachmentRefsBySessionID[selectedChatSessionID] = pendingAttachmentRefs
        }
    }

    func previewAttachment(_ attachment: AgentMessageAttachmentRef) {
        guard let selectedChatSessionID, let storagePaths else { return }
        let store = AppSessionAttachmentStore(paths: storagePaths)
        attachmentPreviewModel = AttachmentPreviewLoader(store: store).load(
            sessionID: selectedChatSessionID,
            attachment: attachment
        )
    }

    func markdownPersistentCacheContext(messageID: String) -> AgentMarkdownPersistentCacheContext? {
        guard let selectedChatSessionID, let storagePaths else { return nil }
        return AgentMarkdownPersistentCacheContext(
            store: AgentMarkdownRenderCacheStore(storagePaths: storagePaths),
            sessionID: selectedChatSessionID,
            messageID: messageID
        )
    }

    @discardableResult
    func importAttachments(urls: [URL]) async -> AttachmentImportBatchResult {
        guard let selectedChatSessionID, let storagePaths else { return AttachmentImportBatchResult() }
        let store = AppSessionAttachmentStore(paths: storagePaths)
        var imported: [AgentMessageAttachmentRef] = []
        var rejected: [AttachmentRejectedFile] = []
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let manifest = try store.importFile(at: url, sessionID: selectedChatSessionID)
                imported.append(manifest.messageRef)
            } catch let error as AppSessionAttachmentImportError {
                switch error {
                case .rejected(let filename, let reason):
                    rejected.append(AttachmentRejectedFile(filename: filename, reason: reason))
                }
            } catch {
                rejected.append(AttachmentRejectedFile(filename: url.lastPathComponent, reason: .unsupportedUnknownExtension(url.pathExtension.isEmpty ? "unknown" : url.pathExtension.lowercased())))
            }
        }
        if !imported.isEmpty {
            pendingAttachmentRefs.append(contentsOf: imported)
            pendingAttachmentRefsBySessionID[selectedChatSessionID] = pendingAttachmentRefs
            Task { await runAttachmentExtractionJobs(sessionID: selectedChatSessionID) }
        }
        let result = AttachmentImportBatchResult(accepted: imported, rejected: rejected)
        if !rejected.isEmpty {
            showAttachmentImportToast(result)
        }
        return result
    }

    /// 检查当前选中的模型是否支持图片输入
    /// 基于模型 ID 的模式匹配，后续可接入模型 capabilities API
    func currentModelSupportsImages() -> Bool {
        let model = llmSelectedModel.lowercased()
        // OpenAI 模型
        if model.contains("gpt-4") || model.contains("gpt-4o") || model.contains("o1") || model.contains("o3") {
            return true
        }
        // Anthropic 模型
        if model.contains("claude-3") || model.contains("claude-4") || model.contains("claude-sonnet") || model.contains("claude-opus") || model.contains("claude-haiku") {
            return true
        }
        // Gemini 模型
        if model.contains("gemini-1.5") || model.contains("gemini-2") || model.contains("gemini-2.5") {
            return true
        }
        // 已知不支持图片的模型
        if model.contains("gpt-3.5") || model.contains("gpt-35") {
            return false
        }
        // 默认：保留判断，假设不支持以免意外透传
        return false
    }

    func showAttachmentToast(title: String, message: String, systemImage: String = "exclamationmark.triangle") {
        let toast = AgentChatToast(title: title, message: message, systemImage: systemImage)
        attachmentToast = toast
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if self.attachmentToast?.id == toast.id {
                self.attachmentToast = nil
            }
        }
    }

    func retryAttachmentExtraction(attachmentID: String) {
        guard let selectedChatSessionID, let storagePaths else { return }
        do {
            let manifest = try AppSessionAttachmentStore(paths: storagePaths).loadManifest(sessionID: selectedChatSessionID, attachmentID: attachmentID)
            _ = try AttachmentExtractionJobStore(paths: storagePaths).appendStatus(
                AgentAttachmentExtractionJob(
                    sessionID: selectedChatSessionID,
                    attachmentID: attachmentID,
                    requestedCapabilities: AppSessionAttachmentStore.requestedCapabilities(for: manifest.kind)
                ),
                status: .queued
            )
            showAttachmentToast(title: "已重新排队解析", message: manifest.displayName, systemImage: "arrow.clockwise")
            Task { await runAttachmentExtractionJobs(sessionID: selectedChatSessionID) }
        } catch {
            showAttachmentToast(title: "重新解析失败", message: String(describing: error), systemImage: "xmark.circle")
        }
    }

    private func runAttachmentExtractionJobs(sessionID: String) async {
        guard let storagePaths else { return }
        do {
            let queue = AttachmentExtractionQueue(
                jobStore: AttachmentExtractionJobStore(paths: storagePaths),
                processor: AttachmentExtractionJobProcessor(paths: storagePaths)
            )
            try await queue.drain(sessionID: sessionID)
            refreshPendingAttachmentRefs(sessionID: sessionID)
        } catch {
            showAttachmentToast(title: "附件解析失败", message: String(describing: error), systemImage: "exclamationmark.triangle")
        }
    }

    private func refreshPendingAttachmentRefs(sessionID: String) {
        guard let storagePaths else { return }
        let store = AppSessionAttachmentStore(paths: storagePaths)
        let refs = (pendingAttachmentRefsBySessionID[sessionID] ?? []).map { ref -> AgentMessageAttachmentRef in
            (try? store.loadManifest(sessionID: sessionID, attachmentID: ref.id).messageRef) ?? ref
        }
        pendingAttachmentRefsBySessionID[sessionID] = refs
        if selectedChatSessionID == sessionID {
            pendingAttachmentRefs = refs
            if let model = attachmentPreviewModel,
               refs.contains(where: { $0.id == model.attachment.id }) {
                attachmentPreviewModel = AttachmentPreviewLoader(store: store).load(sessionID: sessionID, attachment: model.attachment)
            }
        }
    }

    private func showAttachmentImportToast(_ result: AttachmentImportBatchResult) {
        showAttachmentToast(
            title: result.accepted.isEmpty ? "附件未添加" : "部分附件未添加",
            message: attachmentImportSummary(result),
            systemImage: result.accepted.isEmpty ? "xmark.circle" : "exclamationmark.triangle"
        )
    }

    private func attachmentImportSummary(_ result: AttachmentImportBatchResult) -> String {
        let supportedSummary = "Connor 当前支持添加文本、Markdown、日志、JSON/JSONL、CSV/TSV、XML/YAML、代码文件、常见图片（PNG/JPEG/GIF/WebP/HEIC/BMP/ICO/TIFF），以及 PDF、Word、Excel、PowerPoint 和 Apple iWork（Pages/Numbers/Keynote）文档附件。暂不支持 HTML、音频、视频、压缩包、SVG/AVIF、数据库、可执行文件或未知格式。"
        let rejectedLines = result.rejected.prefix(8).map { "- \($0.filename)：\($0.reason.userMessage)" }.joined(separator: "\n")
        let remaining = result.rejected.count > 8 ? "\n…另有 \(result.rejected.count - 8) 个文件未添加" : ""
        if result.accepted.isEmpty {
            return "\(supportedSummary)\n\n未添加：\n\(rejectedLines)\(remaining)"
        }
        return "已添加 \(result.accepted.count) 个附件，\(result.rejected.count) 个文件未添加。\n\n\(supportedSummary)\n\n未添加：\n\(rejectedLines)\(remaining)"
    }

    private func buildAttachmentContextPlan(
        sessionID: String,
        attachments: [AgentMessageAttachmentRef],
        perAttachmentCharacterLimit: Int = 20_000,
        totalCharacterLimit: Int = 60_000
    ) -> AttachmentContextPlan {
        guard !attachments.isEmpty, let storagePaths else { return AttachmentContextPlan() }
        let store = AppSessionAttachmentStore(paths: storagePaths)
        var inlineBlocks: [AttachmentInlineBlock] = []
        var imageBlocks: [AttachmentImageBlock] = []
        var omissions: [AttachmentOmission] = []
        var remainingBudget = totalCharacterLimit
        for attachment in attachments {
            guard remainingBudget > 0 else {
                omissions.append(AttachmentOmission(attachmentID: attachment.id, displayName: attachment.displayName, reason: "Total attachment prompt budget exhausted."))
                continue
            }
            do {
                let manifest = try store.loadManifest(sessionID: sessionID, attachmentID: attachment.id)
                if manifest.kind == .image {
                    let imageURL = storagePaths.sessionArtifactDirectories(sessionID: sessionID).root.appendingPathComponent(manifest.storedRelativePath)
                    let data = try Data(contentsOf: imageURL)
                    let mimeType = manifest.mimeType ?? "image/png"
                    let dataURL = "data:\(mimeType);base64,\(data.base64EncodedString())"
                    imageBlocks.append(AttachmentImageBlock(
                        attachmentID: manifest.id,
                        displayName: manifest.displayName,
                        mimeType: mimeType,
                        dataURL: dataURL,
                        sourceRelativePath: manifest.storedRelativePath
                    ))
                    continue
                }
                guard let relativePath = manifest.extractedTextRelativePath else {
                    omissions.append(AttachmentOmission(
                        attachmentID: attachment.id,
                        displayName: attachment.displayName,
                        reason: Self.attachmentOmissionReason(for: manifest)
                    ))
                    continue
                }
                let url = storagePaths.sessionArtifactDirectories(sessionID: sessionID).root.appendingPathComponent(relativePath)
                let content = try String(contentsOf: url, encoding: .utf8)
                let limit = min(perAttachmentCharacterLimit, remainingBudget)
                let isTruncated = content.count > limit
                let inlineContent = isTruncated ? String(content.prefix(limit)) : content
                remainingBudget -= inlineContent.count
                inlineBlocks.append(AttachmentInlineBlock(
                    attachmentID: manifest.id,
                    displayName: manifest.displayName,
                    kind: manifest.kind,
                    content: inlineContent,
                    sourceRelativePath: relativePath,
                    isTruncated: isTruncated
                ))
            } catch {
                omissions.append(AttachmentOmission(attachmentID: attachment.id, displayName: attachment.displayName, reason: "Failed to read extracted text: \(error)"))
            }
        }
        let estimatedTokens = max(1, inlineBlocks.reduce(0) { $0 + $1.content.count } / 4 + imageBlocks.count * 85)
        return AttachmentContextPlan(inlineBlocks: inlineBlocks, omittedAttachments: omissions, imageBlocks: imageBlocks, estimatedTokens: estimatedTokens)
    }

    private static func attachmentOmissionReason(for manifest: AgentAttachmentManifest) -> String {
        switch manifest.extractionStatus {
        case .pending:
            return "Text extraction is still pending; this attachment is saved locally but its contents are not included in this prompt yet."
        case .unsupported:
            return "Text extraction is unsupported or no extractor is currently available; the original file is saved locally but its contents are not included in this prompt."
        case .failed:
            let details = manifest.extractionReports.last?.errors.joined(separator: " ") ?? "unknown error"
            return "Text extraction failed (\(details)); the original file is saved locally but its contents are not included in this prompt."
        case .skippedOversize:
            return "Text extraction was skipped because the attachment is too large; the original file is saved locally but its contents are not included in this prompt."
        case .extracted:
            return "No extracted text file is available even though extraction is marked complete."
        }
    }

    private func refreshSelectedSubmittingState() {
        isSubmittingChat = selectedChatSessionID.map { submittingChatSessionIDs.contains($0) } ?? false
    }

    func navigate(to item: ConnorNativeShellItem) {
        DispatchQueue.main.async { [weak self] in
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
            isBrowserVisible = false
            selection = .agentChat
        case .search:
            selection = .search
        case .graphEntities:
            selection = .entities
        case .approvals:
            selection = .pendingApprovals
        case .automation, .localAutomationSurface:
            selection = .scheduledTasks
        case .productOS:
            selection = .productOS
        case .calendar:
            selection = .calendar
        case .contacts:
            selection = .contacts
        case .mail:
            selection = .mail
        case .rss:
            selection = .rss
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
        case .openGraphMemoryReview, .openApprovals, .openSources, .openSkills, .openAutomation, .openLocalAutomationSurface, .openCalendarSources, .openContactsSources, .openMailSources, .openRSSSources, .openSettings:
            if let command = ConnorNativeShellPresentation.default.command(for: commandID) {
                navigate(to: command.target)
            }
        }
    }

    func openURLInCurrentChatBrowser(_ url: URL) {
        let sessionID = selectedChatSessionID ?? activeChatSession.id
        let urlString = url.absoluteString
        let planner = BrowserExternalOpenPlanner()
        if focusExistingBrowserTabIfPresent(urlString: urlString, preferredSessionID: sessionID, planner: planner) {
            return
        }
        let currentSnapshot = browserWorkspaceSnapshotsBySessionID[sessionID] ?? AppBrowserStateSnapshot()
        let plannedSnapshot = planner.openOrFocus(urlString: urlString, in: currentSnapshot)
        browserTargetURLString = urlString
        saveBrowserWorkspaceSnapshot(plannedSnapshot, for: sessionID)
        showBrowserWorkspace(for: sessionID)
    }

    func activateGlobalSearchField() {
        isGlobalSearchFieldFocused = true
        let trimmed = globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isGlobalSearchOverlayPresented = true
        if globalSearchPreviewState.query != trimmed {
            scheduleGlobalSearchPreview(for: trimmed)
        }
    }

    func deactivateGlobalSearchField() {
        isGlobalSearchFieldFocused = false
        isGlobalSearchOverlayPresented = false
    }

    func updateGlobalSearchQuery(_ query: String) {
        globalSearchQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        globalSearchPreviewTask?.cancel()
        guard !trimmed.isEmpty else {
            isGlobalSearchOverlayPresented = false
            globalSearchPreviewState = .empty
            globalSearchSelectedItem = .action(.newChat)
            return
        }
        isGlobalSearchOverlayPresented = true
        scheduleGlobalSearchPreview(for: trimmed)
    }

    func clearGlobalSearch() {
        globalSearchPreviewTask?.cancel()
        globalSearchQuery = ""
        isGlobalSearchOverlayPresented = false
        globalSearchPreviewState = .empty
        globalSearchSelectedItem = .action(.newChat)
    }

    func dismissGlobalSearchOverlay() {
        isGlobalSearchOverlayPresented = false
    }

    var globalSearchSelectableItems: [GlobalSearchSelectableItem] {
        var items: [GlobalSearchSelectableItem] = [.action(.newChat), .action(.webSearch)]
        items.append(contentsOf: globalSearchPreviewState.chatSessionResults.map { .chatSession($0.id) })
        items.append(contentsOf: globalSearchPreviewState.calendarResults.map { .nativeResult($0.id) })
        items.append(contentsOf: globalSearchPreviewState.rssResults.map { .nativeResult($0.id) })
        items.append(contentsOf: globalSearchPreviewState.mailResults.map { .nativeResult($0.id) })
        items.append(contentsOf: globalSearchPreviewState.browserHistoryResults.prefix(3).map { .nativeResult($0.id) })
        return items
    }

    func moveGlobalSearchSelectionDown() {
        moveGlobalSearchSelection(delta: 1)
    }

    func moveGlobalSearchSelectionUp() {
        moveGlobalSearchSelection(delta: -1)
    }

    private func moveGlobalSearchSelection(delta: Int) {
        let items = globalSearchSelectableItems
        guard !items.isEmpty else {
            globalSearchSelectedItem = nil
            return
        }
        let currentIndex = globalSearchSelectedItem.flatMap { items.firstIndex(of: $0) } ?? 0
        let nextIndex = (currentIndex + delta + items.count) % items.count
        globalSearchSelectedItem = items[nextIndex]
    }

    private func normalizeGlobalSearchSelection() {
        let items = globalSearchSelectableItems
        guard !items.isEmpty else {
            globalSearchSelectedItem = nil
            return
        }
        if let selected = globalSearchSelectedItem, items.contains(selected) { return }
        globalSearchSelectedItem = items.first
    }

    func performSelectedGlobalSearchItem() {
        normalizeGlobalSearchSelection()
        guard let selected = globalSearchSelectedItem else { return }
        switch selected {
        case .action(.newChat):
            performGlobalSearchNewChat()
        case .action(.webSearch):
            performGlobalSearchWebSearch()
        case .chatSession(let sessionID):
            openGlobalSearchChatSessionResult(sessionID)
        case .nativeResult(let resultID):
            let results = globalSearchPreviewState.calendarResults
                + globalSearchPreviewState.rssResults
                + globalSearchPreviewState.mailResults
                + globalSearchPreviewState.browserHistoryResults
            guard let result = results.first(where: { $0.id == resultID }) else { return }
            openGlobalSearchResult(result)
        }
    }

    private func scheduleGlobalSearchPreview(for query: String) {
        globalSearchPreviewTask?.cancel()
        if globalSearchPreviewState == .empty {
            globalSearchPreviewState = GlobalSearchPreviewState(query: query, isLoading: false, searchTokens: globalSearchDisplayTokens(for: query))
        }
        globalSearchPreviewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            await self?.refreshGlobalSearchPreview(for: query)
        }
    }

    func refreshGlobalSearchPreview(for query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let tokens = globalSearchDisplayTokens(for: trimmed)
        globalSearchTimings = []
        let chatStartedAt = Date()
        let chatSessionResults = await searchChatSessions(query: trimmed, limit: 3)
        recordGlobalSearchTiming(query: trimmed, section: "chatSessions", startedAt: chatStartedAt, returnedCount: chatSessionResults.count, backend: sessionSearchIndexService == nil ? "fallback-scan" : "session-fts")
        guard globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }

        globalSearchPreviewState = GlobalSearchPreviewState(
            query: trimmed,
            loadingSections: [.calendar, .rss, .browserHistory],
            chatSessionResults: chatSessionResults,
            searchTokens: tokens,
            errorMessage: nil
        )
        normalizeGlobalSearchSelection()

        let limits: [NativeSearchSourceKind: Int] = [.calendar: 3, .rss: 3, .browserHistory: 3]
        await refreshGlobalSearchNativePreviewSections(query: trimmed, tokens: tokens, limitsBySource: limits)
    }

    nonisolated static func userFacingGlobalSearchErrorMessage(for error: Error) -> String? {
        if error is GlobalSearchTimeoutError { return nil }
        return String(describing: error)
    }

    private func refreshGlobalSearchNativePreviewSections(query: String, tokens: [String], limitsBySource: [NativeSearchSourceKind: Int]) async {
        if let nativeSourceSearchBackend {
            await refreshIndexedGlobalSearchNativePreviewSections(query: query, tokens: tokens, limitsBySource: limitsBySource, backend: nativeSourceSearchBackend)
            return
        }

        for kind in NativeSearchSourceKind.allCases {
            guard globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
            let startedAt = Date()
            let limit = limitsBySource[kind] ?? 3
            let results = fallbackNativeSearchResults(kind: kind, query: query, limit: limit)
            recordGlobalSearchTiming(query: query, section: GlobalSearchSectionKind(nativeSourceKind: kind).rawValue, startedAt: startedAt, returnedCount: results.count, backend: "fallback")
            applyGlobalSearchNativeSectionResult(
                GlobalSearchNativeSectionResult(kind: GlobalSearchSectionKind(nativeSourceKind: kind), results: results, errorMessage: nil),
                query: query,
                tokens: tokens
            )
        }
    }

    private func refreshIndexedGlobalSearchNativePreviewSections(query: String, tokens: [String], limitsBySource: [NativeSearchSourceKind: Int], backend: any NativeSourceSearchBackend) async {
        let health = await backend.health()
        applyGlobalSearchNativeHealth(health, query: query, tokens: tokens)
        let coordinator = GlobalSearchPreviewCoordinator(
            backend: backend,
            timeoutMilliseconds: 250,
            errorMessage: Self.userFacingGlobalSearchErrorMessage(for:)
        )
        for await sectionResult in coordinator.previewResults(query: query, limitsBySource: limitsBySource) {
            guard globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
            globalSearchTimings.append(sectionResult.timing)
            applyGlobalSearchNativeSectionResult(
                GlobalSearchNativeSectionResult(
                    kind: GlobalSearchSectionKind(nativeSourceKind: sectionResult.kind),
                    results: sectionResult.results,
                    errorMessage: sectionResult.errorMessage,
                    timing: sectionResult.timing
                ),
                query: query,
                tokens: tokens
            )
        }
    }

    private func recordGlobalSearchTiming(query: String, section: String, startedAt: Date, returnedCount: Int, backend: String) {
        globalSearchTimings.append(GlobalSearchSectionTiming(
            query: query,
            section: section,
            startedAt: startedAt,
            endedAt: Date(),
            candidateCount: returnedCount,
            returnedCount: returnedCount,
            backend: backend
        ))
    }

    private func applyGlobalSearchNativeHealth(_ health: NativeSourceSearchHealthSnapshot, query: String, tokens: [String]) {
        guard globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
        var state = globalSearchPreviewState
        state.query = query
        state.searchTokens = tokens
        for kind in NativeSearchSourceKind.allCases {
            let sectionKind = GlobalSearchSectionKind(nativeSourceKind: kind)
            state.sectionStatusMessages[sectionKind] = Self.globalSearchSectionStatusMessage(for: kind, health: health)
        }
        globalSearchPreviewState = state
    }

    nonisolated static func globalSearchSectionStatusMessage(for kind: NativeSearchSourceKind, health: NativeSourceSearchHealthSnapshot) -> String? {
        if let lastError = health.lastError, !lastError.isEmpty {
            return "索引暂不可用"
        }
        if health.pendingUpdateCount > 0 {
            return "后台正在更新索引，先显示已索引结果"
        }
        if health.staleSourceKinds.contains(kind) {
            return "索引可能过期，先显示上次索引结果"
        }
        if health.documentCountBySource[kind, default: 0] == 0 {
            return "尚未建立索引"
        }
        return nil
    }

    private func applyGlobalSearchNativeSectionResult(_ sectionResult: GlobalSearchNativeSectionResult, query: String, tokens: [String]) {
        var state = globalSearchPreviewState
        state.query = query
        state.searchTokens = tokens
        state.loadingSections.remove(sectionResult.kind)
        if let errorMessage = sectionResult.errorMessage, state.errorMessage == nil {
            state.errorMessage = errorMessage
        }
        if !sectionResult.results.isEmpty || sectionResult.errorMessage != nil {
            state.sectionStatusMessages[sectionResult.kind] = nil
        }
        switch sectionResult.kind {
        case .chatSessions:
            break
        case .calendar:
            state.calendarResults = sectionResult.results
        case .rss:
            state.rssResults = sectionResult.results
        case .mail:
            state.mailResults = sectionResult.results
        case .browserHistory:
            state.browserHistoryResults = sectionResult.results
        }
        globalSearchPreviewState = state
        normalizeGlobalSearchSelection()
    }

    private func globalSearchDisplayTokens(for query: String) -> [String] {
        GlobalSearchDisplayTokenBuilder.tokens(for: query)
    }

    private func searchChatSessions(query: String, limit: Int) async -> [GlobalSearchSessionResult] {
        if let sessionSearchIndexService,
           let indexed = try? await sessionSearchIndexService.search(query: query, limit: limit),
           !indexed.isEmpty {
            return indexed.map { result in
                GlobalSearchSessionResult(
                    id: result.id,
                    title: result.title,
                    snippet: result.snippet,
                    updatedAt: result.updatedAt,
                    messageCount: result.messageCount
                )
            }
        }
        let terms = Self.globalSearchMatchTerms(for: query)
        guard !terms.isEmpty else { return [] }
        return allChatSessions
            .compactMap { session -> (result: GlobalSearchSessionResult, score: Double)? in
                let titleScore = Self.globalSearchMatchScore(text: session.title, terms: terms, weight: 20)
                var bestMessageScore = 0.0
                var bestSnippet = session.messages.last?.content ?? session.title
                for message in session.messages {
                    let weight: Double = message.role == .user ? 8 : 5
                    let score = Self.globalSearchMatchScore(text: message.content, terms: terms, weight: weight)
                    if score > bestMessageScore {
                        bestMessageScore = score
                        bestSnippet = Self.globalSearchSnippet(text: message.content, terms: terms)
                    }
                }
                let totalScore = titleScore + bestMessageScore
                guard totalScore > 0 else { return nil }
                let snippet = titleScore > 0 && bestMessageScore == 0
                    ? "最近更新：\(session.updatedAt.connorLocalFormatted(date: .medium, time: .short))"
                    : bestSnippet
                return (
                    GlobalSearchSessionResult(
                        id: session.id,
                        title: session.title.isEmpty ? "新对话" : session.title,
                        snippet: snippet,
                        updatedAt: session.updatedAt,
                        messageCount: session.messages.count
                    ),
                    totalScore + min(3, Date().timeIntervalSince(session.updatedAt) / -86_400_000)
                )
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.result.updatedAt > rhs.result.updatedAt
            }
            .prefix(limit)
            .map(\.result)
    }

    private static func globalSearchMatchTerms(for query: String) -> [String] {
        let normalized = NativeSearchQueryNormalizer.normalize(query)
        var seen: Set<String> = []
        let normalizedTerms = normalized.scoringTokens
            .map(\.value)
            .filter { !$0.isEmpty }
            .filter { $0.count >= 2 || query.count <= 2 }
            .filter { seen.insert($0).inserted }
        if !normalizedTerms.isEmpty { return normalizedTerms }
        return query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func globalSearchMatchScore(text: String, terms: [String], weight: Double) -> Double {
        let lower = text.lowercased()
        let matchedTerms = terms.filter { lower.localizedCaseInsensitiveContains($0) }
        guard !matchedTerms.isEmpty else { return 0 }
        let requiredMatches = min(max(terms.count, 1), 2)
        guard matchedTerms.count >= requiredMatches else { return 0 }
        let coverage = Double(matchedTerms.count) / Double(max(terms.count, 1))
        let exactBonus = matchedTerms.reduce(0.0) { partial, term in
            partial + (lower == term.lowercased() ? 2.0 : 0.0)
        }
        return weight * (0.75 + coverage) + exactBonus
    }

    private static func globalSearchSnippet(text: String, terms: [String], maxLength: Int = 120) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let lower = trimmed.lowercased()
        guard let firstTerm = terms.first(where: { lower.localizedCaseInsensitiveContains($0) }),
              let range = lower.range(of: firstTerm.lowercased()) else {
            return String(trimmed.prefix(maxLength))
        }
        let startDistance = lower.distance(from: lower.startIndex, to: range.lowerBound)
        let snippetStart = max(0, startDistance - 36)
        let snippetEnd = min(trimmed.count, snippetStart + maxLength)
        let startIndex = trimmed.index(trimmed.startIndex, offsetBy: snippetStart)
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: snippetEnd)
        return String(trimmed[startIndex..<endIndex])
    }

    private func searchBrowserHistory(query: String, limit: Int) -> [BrowserHistoryRecord] {
        guard let browserHistoryStore else {
            return browserHistoryRecords
                .filter { browserHistoryRecord($0, matches: query) }
                .sorted { $0.visitedAt > $1.visitedAt }
                .prefix(limit)
                .map { $0 }
        }
        return browserHistoryStore.searchHistory(query: query)
            .sorted { $0.visitedAt > $1.visitedAt }
            .prefix(limit)
            .map { $0 }
    }

    private func browserHistoryRecord(_ record: BrowserHistoryRecord, matches query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }
        return record.url.lowercased().contains(normalized)
            || record.title.lowercased().contains(normalized)
            || record.sessionTitle.lowercased().contains(normalized)
            || (record.contentMarkdown?.lowercased().contains(normalized) ?? false)
    }

    private func searchNativeSource(kind: NativeSearchSourceKind, query: String, limit: Int) async throws -> [NativeSearchResult] {
        if let nativeSourceSearchBackend {
            return try await nativeSourceSearchBackend.search(NativeSearchQuery(
                text: query,
                sourceKinds: [kind],
                limit: limit,
                includeBodySnippets: true,
                rankingProfile: .recentFirst
            ))
        }
        return fallbackNativeSearchResults(kind: kind, query: query, limit: limit)
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
        return calendarEvents
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
        rssBrowserPresentation.items(sourceID: nil, query: query).prefix(limit).map { item in
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
        return mailBrowserPresentation.messages
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
        searchBrowserHistory(query: query, limit: limit).map { record in
            NativeSearchResult(
                id: "browser-history:\(record.id.uuidString)",
                sourceKind: .browserHistory,
                externalID: record.id.uuidString,
                sourceInstanceID: record.sessionID,
                title: record.title.isEmpty ? record.url : record.title,
                snippet: [record.sessionTitle, record.url].filter { !$0.isEmpty }.joined(separator: " · "),
                score: 1,
                lexicalScore: 1,
                freshnessScore: 0,
                fieldScore: 0,
                temporal: NativeSearchTemporalMetadata(primaryTime: record.visitedAt, primaryTimeKind: .updatedAt, updatedAt: record.visitedAt, indexedAt: now),
                resultTimeLabel: record.visitedAt.connorLocalFormatted(date: .medium, time: .short)
            )
        }
    }

    func performGlobalSearchNewChat() {
        let prompt = globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        clearGlobalSearch()
        newChatSession()
        selection = .agentChat
        Task { @MainActor in
            _ = await submitChat(prompt: prompt, clearComposer: false, displayPrompt: prompt)
        }
    }

    func defaultSearchURL(for query: String) -> URL? {
        defaultSearchEngine.searchURL(for: query)
    }

    func defaultSearchURLString(for query: String) -> String? {
        defaultSearchEngine.searchURLString(for: query)
    }

    func performGlobalSearchWebSearch() {
        let query = globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        guard let url = defaultSearchURL(for: query) else { return }
        dismissGlobalSearchOverlay()
        openURLInCurrentChatBrowser(url)
    }

    func openGlobalSearchBrowserHistoryResult(_ record: BrowserHistoryRecord) {
        dismissGlobalSearchOverlay()
        navigateToHistoryRecord(record)
    }

    func openGlobalSearchChatSessionResult(_ sessionID: String) {
        selection = .agentChat
        dismissGlobalSearchOverlay()
        selectChatSession(sessionID)
    }

    func openGlobalSearchResult(_ result: NativeSearchResult) {
        switch result.sourceKind {
        case .calendar:
            selection = .calendar
            selectedCalendarEventID = CalendarEventID(rawValue: result.externalID)
        case .rss:
            selection = .rss
            if let item = rssBrowserPresentation.item(id: RSSItemID(rawValue: result.externalID)) {
                selectRSSItem(item)
            } else {
                selectedRSSItemID = RSSItemID(rawValue: result.externalID)
            }
        case .mail:
            selection = .mail
            selectedMailMessageID = MailMessageID(rawValue: result.externalID)
            if let message = mailBrowserPresentation.message(id: selectedMailMessageID) {
                selectedMailAccountID = message.accountID
                selectedMailMailboxID = message.mailboxID
            }
        case .browserHistory:
            if let id = UUID(uuidString: result.externalID), let record = browserHistoryRecords.first(where: { $0.id == id }) ?? browserHistoryStore?.record(id: id) {
                navigateToHistoryRecord(record)
            } else {
                isBrowserHistoryPanelVisible = true
                showBrowserWorkspace()
            }
        }
        dismissGlobalSearchOverlay()
    }

    func showAllGlobalSearchResults(kind: GlobalSearchSectionKind) {
        let query = globalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .chatSessions:
            sessionSearchQuery = query
            isBrowserVisible = false
            selection = .agentChat
        case .calendar:
            calendarSearchQuery = query
            selection = .calendar
        case .rss:
            rssSearchQuery = query
            selection = .rss
        case .mail:
            mailSearchQuery = query
            selection = .mail
        case .browserHistory:
            browserHistorySearchQuery = query
            isBrowserHistoryPanelVisible = true
            showBrowserWorkspace()
            loadBrowserHistory()
            filterBrowserHistory(query: browserHistorySearchQuery)
        }
        dismissGlobalSearchOverlay()
    }

    func mailListMessages(direction: MailMessageDirectionFilter = .all) -> [MailMessageSummary] {
        mailBrowserPresentation.messages(accountID: nil, mailboxID: nil, query: mailSearchQuery, direction: direction)
    }

    private func rebuildCalendarSearchIndexIfNeeded() async throws {
        guard let nativeSourceSearchBackend else { return }
        try await nativeSourceSearchBackend.rebuildSource(kind: .calendar, sourceInstanceID: nil, documents: calendarEvents.map(NativeSourceSearchAdapters.calendarDocument(from:)))
    }

    private func scheduleCalendarSearchIndexRefresh() {
        guard nativeSourceSearchBackend != nil else { return }
        Task { @MainActor in
            try? await rebuildCalendarSearchIndexIfNeeded()
        }
    }

    private func rebuildBrowserHistorySearchIndexIfNeeded() async throws {
        guard let nativeSourceSearchBackend else { return }
        let records = browserHistoryStore?.loadHistory() ?? browserHistoryRecords
        try await nativeSourceSearchBackend.rebuildSource(kind: .browserHistory, sourceInstanceID: nil, documents: records.map { NativeSourceSearchAdapters.browserHistoryDocument(from: $0) })
    }

    private func indexBrowserHistoryRecord(_ record: BrowserHistoryRecord) {
        guard let nativeSourceSearchBackend else { return }
        Task { @MainActor in
            try? await nativeSourceSearchBackend.upsert([NativeSourceSearchAdapters.browserHistoryDocument(from: record)])
        }
    }

    private func deleteBrowserHistorySearchRecord(id: UUID) {
        guard let nativeSourceSearchBackend else { return }
        Task { @MainActor in
            try? await nativeSourceSearchBackend.delete(documentIDs: ["browser-history:\(id.uuidString)"])
        }
    }

    private func clearBrowserHistorySearchIndex() {
        guard let nativeSourceSearchBackend else { return }
        Task { @MainActor in
            try? await nativeSourceSearchBackend.deleteBySource(kind: .browserHistory, sourceInstanceID: nil)
        }
    }

    func openURLInSystemDefaultBrowser(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    private func focusExistingBrowserTabIfPresent(urlString: String, preferredSessionID: String, planner: BrowserExternalOpenPlanner = BrowserExternalOpenPlanner()) -> Bool {
        guard let existing = existingBrowserTab(for: urlString, preferredSessionID: preferredSessionID, planner: planner) else { return false }
        var snapshot = existing.snapshot
        snapshot.updatedAt = Date()
        snapshot.selectionPopover = nil
        snapshot.selectedTabID = existing.tabID
        browserTargetURLString = urlString
        saveBrowserWorkspaceSnapshot(snapshot, for: existing.sessionID)
        showBrowserWorkspace(for: existing.sessionID)
        return true
    }

    private func existingBrowserTab(for urlString: String, preferredSessionID: String, planner: BrowserExternalOpenPlanner) -> (sessionID: String, tabID: UUID, snapshot: AppBrowserStateSnapshot)? {
        for sessionID in browserWorkspaceSearchOrder(preferredSessionID: preferredSessionID) {
            guard let snapshot = browserWorkspaceSnapshotsBySessionID[sessionID],
                  let tabID = planner.matchingTabID(urlString: urlString, in: snapshot) else { continue }
            return (sessionID, tabID, snapshot)
        }
        return nil
    }

    private func browserWorkspaceSearchOrder(preferredSessionID: String) -> [String] {
        var ordered: [String] = []
        func appendIfNeeded(_ sessionID: String?) {
            guard let sessionID, !sessionID.isEmpty, !ordered.contains(sessionID) else { return }
            ordered.append(sessionID)
        }
        appendIfNeeded(preferredSessionID)
        appendIfNeeded(browserWorkspaceSessionID)
        appendIfNeeded(activeChatSession.id)
        for sessionID in browserWorkspaceSnapshotsBySessionID.keys.sorted() {
            appendIfNeeded(sessionID)
        }
        return ordered
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

    func performBrowserAssistedWebFetch(_ request: BrowserAssistedWebFetchRequest) async -> BrowserAssistedWebFetchResult? {
        let task = startBrowserAssistedWebFetch(request)
        let timeout = max(3_000, min(request.timeoutMilliseconds, 720_000))
        return await withCheckedContinuation { continuation in
            browserAssistedWebFetchContinuationsByTaskID[task.id] = continuation
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000)
                await MainActor.run {
                    guard let self, self.browserAssistedWebFetchContinuationsByTaskID[task.id] != nil else { return }
                    let result = BrowserAssistedWebFetchResult(
                        status: .timedOut,
                        urlString: request.urlString,
                        finalURLString: request.urlString,
                        title: "",
                        contentText: "",
                        taskID: task.id.uuidString,
                        sessionID: task.sessionID,
                        tabID: task.tabID.uuidString,
                        errorMessage: "Connor WKWebView web_fetch(js) timed out after \(timeout)ms",
                        interventionReason: nil,
                        truncated: false,
                        originalCharacterCount: 0
                    )
                    if let current = self.browserAssistedTasksByID[task.id] {
                        self.browserAssistedTasksByID[task.id] = BrowserAssistedTaskPlanner().fail(current, message: result.errorMessage ?? "Timed out")
                    }
                    self.browserAssistedWebFetchContinuationsByTaskID[task.id]?.resume(returning: result)
                    self.browserAssistedWebFetchContinuationsByTaskID[task.id] = nil
                    self.browserAssistedWebFetchRequestsByTaskID[task.id] = nil
                }
            }
        }
    }

    @discardableResult
    private func startBrowserAssistedWebFetch(_ request: BrowserAssistedWebFetchRequest) -> BrowserAssistedTaskState {
        let sessionID = selectedChatSessionID ?? activeChatSession.id
        let currentSnapshot = browserWorkspaceSnapshotsBySessionID[sessionID] ?? AppBrowserStateSnapshot()
        let taskRequest = BrowserAssistedTaskRequest(
            kind: .fetch,
            sessionID: sessionID,
            urlString: request.urlString,
            title: "Fetch: \(request.urlString)",
            visibility: request.revealImmediately ? .foreground : .background
        )
        let plan = BrowserAssistedTaskPlanner().start(taskRequest, in: currentSnapshot)
        browserAssistedTasksByID[plan.task.id] = plan.task
        browserAssistedWebFetchRequestsByTaskID[plan.task.id] = request
        browserTargetURLString = request.urlString
        saveBrowserWorkspaceSnapshot(plan.snapshot, for: sessionID)
        if plan.shouldRevealBrowser { showBrowserWorkspace(for: sessionID) }
        return plan.task
    }

    func completeBrowserAssistedWebFetch(_ taskID: UUID, title: String, finalURLString: String, text: String) {
        guard let task = browserAssistedTasksByID[taskID], let request = browserAssistedWebFetchRequestsByTaskID[taskID] else { return }
        let originalCount = text.count
        let maxCharacters = 100_000
        let truncated = originalCount > maxCharacters
        let returnedText = truncated ? String(text.prefix(maxCharacters)) : text
        let content: String
        if request.extractMode == "text" {
            content = returnedText + (truncated ? "\n\n[Content truncated by Connor web_fetch(js-wkwebview): original characters = \(originalCount), returned characters = \(maxCharacters)]" : "")
        } else {
            let heading = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Fetched Page" : title
            content = """
            # \(heading)
            **Source:** \(finalURLString.isEmpty ? request.urlString : finalURLString)
            **Render mode:** js-wkwebview

            ---

            \(returnedText)\(truncated ? "\n\n[Content truncated by Connor web_fetch(js-wkwebview): original characters = \(originalCount), returned characters = \(maxCharacters)]" : "")
            """
        }
        let result = BrowserAssistedWebFetchResult(
            status: .fetched,
            urlString: request.urlString,
            finalURLString: finalURLString.isEmpty ? request.urlString : finalURLString,
            title: title,
            contentText: content,
            taskID: task.id.uuidString,
            sessionID: task.sessionID,
            tabID: task.tabID.uuidString,
            errorMessage: nil,
            interventionReason: nil,
            truncated: truncated,
            originalCharacterCount: originalCount
        )
        browserAssistedTasksByID[taskID] = BrowserAssistedTaskPlanner().complete(task, message: "Fetched rendered page content")
        browserAssistedWebFetchContinuationsByTaskID[taskID]?.resume(returning: result)
        browserAssistedWebFetchContinuationsByTaskID[taskID] = nil
        browserAssistedWebFetchRequestsByTaskID[taskID] = nil
    }

    func revealBrowserAssistedTask(_ taskID: UUID, reason: String) {
        guard let task = browserAssistedTasksByID[taskID] else { return }
        let updated = BrowserAssistedTaskPlanner().requireUserIntervention(task, reason: reason)
        browserAssistedTasksByID[taskID] = updated
        if let request = browserAssistedWebFetchRequestsByTaskID[taskID], browserAssistedWebFetchContinuationsByTaskID[taskID] != nil {
            let result = BrowserAssistedWebFetchResult(
                status: .needsUserIntervention,
                urlString: request.urlString,
                finalURLString: updated.urlString,
                title: updated.title,
                contentText: "",
                taskID: updated.id.uuidString,
                sessionID: updated.sessionID,
                tabID: updated.tabID.uuidString,
                errorMessage: nil,
                interventionReason: reason,
                truncated: false,
                originalCharacterCount: 0
            )
            browserAssistedWebFetchContinuationsByTaskID[taskID]?.resume(returning: result)
            browserAssistedWebFetchContinuationsByTaskID[taskID] = nil
            browserAssistedWebFetchRequestsByTaskID[taskID] = nil
        }
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
        if let request = browserAssistedWebFetchRequestsByTaskID[taskID], browserAssistedWebFetchContinuationsByTaskID[taskID] != nil {
            let result = BrowserAssistedWebFetchResult(
                status: .failed,
                urlString: request.urlString,
                finalURLString: task.urlString,
                title: task.title,
                contentText: "",
                taskID: task.id.uuidString,
                sessionID: task.sessionID,
                tabID: task.tabID.uuidString,
                errorMessage: message,
                interventionReason: nil,
                truncated: false,
                originalCharacterCount: 0
            )
            browserAssistedWebFetchContinuationsByTaskID[taskID]?.resume(returning: result)
            browserAssistedWebFetchContinuationsByTaskID[taskID] = nil
            browserAssistedWebFetchRequestsByTaskID[taskID] = nil
        }
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
        if browserWorkspaceSnapshotsBySessionID[sessionID] == nil {
            browserTargetURLString = BrowserBuiltInPage.blankURLString
        }
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
        AppCommercialReadinessDashboardBuilder().build(
            chatSessions: chatSessions,
            activeChatSession: activeChatSession,
            governanceConfig: governanceConfig,
            artifactDirectoriesReady: storagePaths != nil,
            sourceRuntimeConfigurations: sourceRuntimeConfigurations,
            skillRuntimeDefinitions: skillRuntimeDefinitions,
            automationConfig: automationConfig,
            graphMemoryDashboard: graphMemoryDashboardPresentation
        )
    }


    private var graphMemoryDashboardPresentation: GraphMemoryDashboard {
        GraphMemoryDashboard(summary: GraphMemoryDashboardSummary(pendingCandidateCount: 0, openHoldCount: 0, recentChangeCount: 0), cards: [])
    }

    private var chatSummaryPresentation: AppChatSummaryPresentation {
        AppChatSummaryPresentationBuilder().build(
            latestSummary: latestChatSummary,
            activeSession: activeChatSession,
            isSummarizing: isSummarizingChatSession,
            hasTranscriptMessages: !transcript.isEmpty
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
            let nativeSourceSearchBackend: any NativeSourceSearchBackend = (try? SQLiteNativeSourceSearchBackend(databaseURL: storagePaths.nativeSourceSearchDatabaseURL)) ?? NativeSourceSearchService(storagePaths: storagePaths)
            self.nativeSourceSearchBackend = nativeSourceSearchBackend
            self.sessionSearchIndexService = try? SessionSearchIndexService(databaseURL: storagePaths.sessionSearchDatabaseURL)
            self.governanceConfigRepository = AppSessionGovernanceConfigRepository(configDirectory: storagePaths.configDirectory)
            self.productOSRegistryRepository = AppProductOSRegistryRepository(storagePaths: storagePaths)
            self.automationRepository = AppProductOSAutomationRepository(storagePaths: storagePaths)
            self.taskManagementRepository = AppTaskManagementRepository(storagePaths: storagePaths)
            self.sourceRuntimeRepository = AppMCPSourceRuntimeRepository(storagePaths: storagePaths)
            self.skillRuntimeRepository = AppSkillRuntimeRepository(storagePaths: storagePaths)
            self.browserHistoryStore = BrowserHistoryStore(historyURL: storagePaths.browserHistoryURL)
            self.browserBookmarkStore = BrowserBookmarkStore(bookmarksURL: storagePaths.browserBookmarksURL)
            self.rssRuntime = RSSRuntime(
                repository: FileBackedRSSSourceRepository(storagePaths: storagePaths),
                cache: FileBackedRSSSourceCache(storagePaths: storagePaths, searchService: nativeSourceSearchBackend)
            )
            self.calendarStore = FileBackedCalendarSourceStore(storagePaths: storagePaths)
            self.calendarRuntimeStore = FileBackedCalendarSourceRuntimeStore(storagePaths: storagePaths)
            self.contactStore = FileBackedContactSourceStore(storagePaths: storagePaths)
            self.mailStore = FileBackedMailSourceStore(storagePaths: storagePaths)
            self.mailPreferencesStore = FileBackedMailPreferencesStore(storagePaths: storagePaths)
        }
        if let repository {
            self.promotionRepository = AppPromotionQueueRepository(store: repository.store)
            self.pendingApprovalRepository = AppAgentPendingApprovalRepository(store: repository.store)
            let chatSessionRepository = AppChatSessionRepository(store: repository.store, storagePaths: storagePaths, governanceConfig: governanceConfig)
            self.chatSessionRepository = chatSessionRepository
            self.activityTimelineCacheWriter = ActivityTimelineCacheWriter(persistor: chatSessionRepository)
            if let storagePaths {
                self.runtimeSettingsRepository = AppRuntimeSettingsRepository(configDirectory: storagePaths.configDirectory)
            }
            self.hybridSearchService = SQLiteGraphHybridSearchService(store: repository.store)
        }
        if let storagePaths {
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
        self.fallbackChatSession = initialSession
        super.init()
#if DEBUG
        mainActorStallMonitor.start()
#endif
        browserLiveWebViewStore.onWillEvict = { [weak self] key, webView, metadata in
            guard let self else { return }
            self.recordBrowserWebViewEviction(key: key, webView: webView, metadata: metadata)
        }
        if let repository {
            self.agentRuntimeFactory = AppGraphAgentRuntimeFactory(
                store: repository.store,
                settingsRepository: llmSettingsRepository,
                storagePaths: storagePaths,
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
                },
                browserAssistedWebFetchHandler: { [weak self] request in
                    guard let self else { return nil }
                    return await self.performBrowserAssistedWebFetch(request)
                }
            )
        }
        self.searchResults = []
        loadLLMSettings()
        Task { await reloadLLMModelConnections() }
        updateWelcomeState()
        loadRuntimeSettings()
        self.nativeSessionManager = agentRuntimeFactory?.makeNativeSessionManager(session: initialSession)
        reloadProductOSRegistry()
        reloadAutomationConfig()
        reloadAutomationExecutionHistory()
        reloadTaskManagementPresentation()
        Task { @MainActor in
            do {
                try await reconcileSourceRefreshTasks()
                reloadTaskManagementPresentation()
            } catch {
                errorMessage = String(describing: error)
            }
        }
        reloadSourceRuntimeConfigurations()
        reloadSkillRuntimeDefinitions()
        Task { await reloadRSSBrowserPresentation() }
        Task { await reloadCalendarContactsFromStorage() }
        Task { await reloadMailBrowserPresentation() }
        reloadChatSessions()
        loadBrowserHistory()
        reloadSchemaHealthReport()
        scheduleMemoryOSSearchIndexRepairIfNeeded()
    }

    deinit {
        MainActor.assumeIsolated {
            shutdownRuntimeResources()
        }
    }

    func shutdownRuntimeResourcesForTests() {
        shutdownRuntimeResources()
    }

    private func shutdownRuntimeResources() {
        stopTaskSchedulerTimer()
        globalSearchPreviewTask?.cancel()
        globalSearchPreviewTask = nil
        runtimeSettingsAutosaveTask?.cancel()
        runtimeSettingsAutosaveTask = nil
        cancelBrowserHistoryContentFetchTasks()
        resumePendingBrowserAssistedWebFetchContinuationsForShutdown()
        releaseIdleSleepAssertion()
    }

    private func cancelBrowserHistoryContentFetchTasks() {
        for task in browserHistoryContentFetchTasksByID.values {
            task.cancel()
        }
        browserHistoryContentFetchTasksByID.removeAll()
    }

    private func resumePendingBrowserAssistedWebFetchContinuationsForShutdown() {
        let pendingContinuations = browserAssistedWebFetchContinuationsByTaskID
        browserAssistedWebFetchContinuationsByTaskID.removeAll()
        for (taskID, continuation) in pendingContinuations {
            let request = browserAssistedWebFetchRequestsByTaskID[taskID]
            let task = browserAssistedTasksByID[taskID]
            continuation.resume(returning: BrowserAssistedWebFetchResult(
                status: .failed,
                urlString: request?.urlString ?? task?.urlString ?? "",
                finalURLString: task?.urlString ?? request?.urlString ?? "",
                title: task?.title ?? "",
                contentText: "",
                taskID: taskID.uuidString,
                sessionID: task?.sessionID ?? "",
                tabID: task?.tabID.uuidString ?? "",
                errorMessage: "Browser assisted web fetch cancelled during shutdown",
                interventionReason: nil,
                truncated: false,
                originalCharacterCount: 0
            ))
        }
        browserAssistedWebFetchRequestsByTaskID.removeAll()
    }

    private func releaseIdleSleepAssertion() {
        guard idleSleepAssertionID != 0 else { return }
        IOPMAssertionRelease(idleSleepAssertionID)
        idleSleepAssertionID = 0
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
        reloadPendingApprovals()
    }

    private func scheduleMemoryOSSearchIndexRepairIfNeeded() {
        guard !hasScheduledMemoryOSSearchIndexRepair else { return }
        guard let storagePaths else { return }
        let report = AppMemoryOSSearchKernelFactory.healthReport(paths: storagePaths)
        guard report.status != .healthy else { return }
        hasScheduledMemoryOSSearchIndexRepair = true
        isMemoryOSSearchIndexRepairing = true
        memoryOSSearchHealthSummary = "Memory OS SearchKernel 后台修复中：\(report.messages.joined(separator: ", "))"
        Task.detached(priority: .utility) { [storagePaths] in
            do {
                let documentCount = try AppMemoryOSSearchKernelFactory.rebuildLiveIndex(paths: storagePaths)
                let repairedKernel = try AppMemoryOSSearchKernelFactory.makeLiveIfHealthy(paths: storagePaths)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isMemoryOSSearchIndexRepairing = false
                    self.memoryOSSearchHealthSummary = "Memory OS SearchKernel 正常：后台索引已重建（\(documentCount) 条文档）。"
                    if let store = self.memoryOSStore {
                        self.memoryOSFacade = AppMemoryOSFacade(store: store, searchKernel: repairedKernel)
                    }
                    self.rebuildNativeSessionManagerForActiveSession()
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isMemoryOSSearchIndexRepairing = false
                    self.memoryOSSearchHealthSummary = "Memory OS SearchKernel 后台修复失败：\(error)"
                }
            }
        }
    }

    func runBackgroundJobs() async {
        guard !isRunningBackgroundJobs else { return }
        guard let memoryOSFacade else { return }
        isRunningBackgroundJobs = true
        defer { isRunningBackgroundJobs = false }
        do {
            let aiExecutorProvider = backgroundAIExecutorProvider
            let startedAt = ContinuousClock.now
            let summary = try await memoryOSMaintenanceWorker.runBackgroundJobs(
                facade: memoryOSFacade,
                aiExecutorProvider: aiExecutorProvider,
                now: Date()
            )
            let elapsed = startedAt.duration(to: ContinuousClock.now)
            let milliseconds = Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
            AppPerformanceLog.chatTurnLogger.info("memoryOS.backgroundJobs.completed projectionRuns=\(summary.projectionRunCount, privacy: .public) aiRuns=\(summary.aiJobRunCount, privacy: .public) duration=\(milliseconds, privacy: .public)ms")
        } catch {
            await MainActor.run { errorMessage = String(describing: error) }
        }
    }

    func runDailySweepIfNeeded() async {
        guard let memoryOSFacade else { return }
        let now = Date()
        guard lastMemoryOSDailySweep.map({ now.timeIntervalSince($0) > 86400 }) ?? true else { return }
        lastMemoryOSDailySweep = now
        do {
            let startedAt = ContinuousClock.now
            let items = try await memoryOSMaintenanceWorker.runDailySweep(facade: memoryOSFacade, now: now)
            let elapsed = startedAt.duration(to: ContinuousClock.now)
            let milliseconds = Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
            AppPerformanceLog.chatTurnLogger.info("memoryOS.dailySweep.completed queued=\(items.count, privacy: .public) duration=\(milliseconds, privacy: .public)ms")
        } catch {
            AppPerformanceLog.chatTurnLogger.warning("memoryOS.dailySweep.failed error=\(String(describing: error), privacy: .public)")
            // silent failure — does not block main flow
        }
    }

    func reloadTaskManagementPresentation() {
        do {
            guard let taskManagementRepository else { return }
            let tasks = try taskManagementRepository.loadOrCreateDefault()
            let history = try taskManagementRepository.loadRunHistory(taskID: nil, limit: 100)
            taskManagementPresentation = TaskManagementUIPresentation.build(tasks: tasks, runHistory: history)
            if let selectedTaskAutomationID,
               !taskManagementPresentation.cards.contains(where: { $0.id == selectedTaskAutomationID }) {
                self.selectedTaskAutomationID = nil
            }
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    @discardableResult
    func createScheduledSessionMessageTask(
        name: String,
        runAt: Date,
        recurrence: ConnorTaskRecurrence,
        message: String,
        title: String,
        rationale: String?
    ) throws -> String {
        guard let taskManagementRepository else { throw AppViewModelTaskCreationError.missingRepository }
        let task = try TaskCreationService(repository: taskManagementRepository).createScheduledSessionMessageTask(
            origin: .user,
            name: name,
            runAt: runAt,
            recurrence: recurrence,
            timezoneIdentifier: TimeZone.current.identifier,
            message: message,
            title: title,
            createdBySessionID: selectedChatSessionID ?? activeChatSession.id,
            rationale: rationale
        )
        reloadTaskManagementPresentation()
        selectedTaskAutomationID = task.id
        return task.id
    }

    @discardableResult
    func createSessionStatusMessageTask(
        name: String,
        toStatus: String,
        message: String,
        sessionID: String?,
        rationale: String?
    ) throws -> String {
        guard let taskManagementRepository else { throw AppViewModelTaskCreationError.missingRepository }
        let task = try TaskCreationService(repository: taskManagementRepository).createSessionStatusMessageTask(
            origin: .user,
            name: name,
            toStatus: toStatus,
            message: message,
            sessionID: sessionID,
            createdBySessionID: selectedChatSessionID ?? activeChatSession.id,
            rationale: rationale
        )
        reloadTaskManagementPresentation()
        selectedTaskAutomationID = task.id
        return task.id
    }

    func stopTask(_ id: String) {
        do {
            _ = try taskManagementRepository?.stopTask(id: id, reason: "Stopped from Task Management UI")
            reloadTaskManagementPresentation()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func restoreTask(_ id: String) {
        do {
            _ = try taskManagementRepository?.restoreTask(id: id)
            reloadTaskManagementPresentation()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func deleteTask(_ id: String) {
        do {
            _ = try taskManagementRepository?.deleteTask(id: id, reason: "Deleted from Task Management UI")
            reloadTaskManagementPresentation()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func startTaskSchedulerTimer() {
        guard taskSchedulerTimer == nil else { return }
        Task { await runScheduledTasksNow() }
        taskSchedulerTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.runScheduledTasksNow()
            }
        }
    }

    func stopTaskSchedulerTimer() {
        taskSchedulerTimer?.invalidate()
        taskSchedulerTimer = nil
    }

    func runScheduledTasksNow() async {
        guard !isRunningScheduledTasks else { return }
        guard let taskManagementRepository else { return }
        isRunningScheduledTasks = true
        defer { isRunningScheduledTasks = false }
        let runner = TaskTargetRunner.appRuntime(
            mailRefresh: { [weak self] request in
                guard let self else { throw TaskTargetRunnerError.unsupportedTarget("mail") }
                return try await self.refreshMailForScheduledTask(sourceInstanceID: request.sourceInstanceID, runID: request.runID)
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
            try await reconcileSourceRefreshTasks()
            let scheduler = TaskSchedulerService()
            let service = TaskSchedulerRunnerService(repository: taskManagementRepository, scheduler: scheduler, runner: runner)
            _ = try await service.runDueTasks()
            reloadTaskManagementPresentation()
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
        guard let taskManagementRepository else { return }
        let materializer = SourceRefreshTaskMaterializer(taskRepository: taskManagementRepository, rssSourceRepository: rssRuntime.repository)
        _ = try await materializer.reconcileRSSSourceRefreshTasks(now: now)
    }

    private func reconcileCalendarAccountRefreshTasks(now: Date = Date()) async throws {
        guard let taskManagementRepository else { return }
        let materializer = CalendarRefreshTaskMaterializer(
            taskRepository: taskManagementRepository,
            calendarSourceRepository: CalendarAccountSnapshotRepository(accounts: calendarAccounts)
        )
        _ = try await materializer.reconcileCalendarAccountRefreshTasks(now: now)
    }

    private func reconcileMailAccountRefreshTasks(now: Date = Date()) async throws {
        guard let taskManagementRepository, let mailStore else { return }
        let materializer = MailRefreshTaskMaterializer(taskRepository: taskManagementRepository, mailSourceRepository: mailStore)
        _ = try await materializer.reconcileMailAccountRefreshTasks(now: now)
    }

    private func refreshCalendarForScheduledTask(sourceInstanceID: String?, runID: String?) async -> String {
        if let sourceInstanceID, !sourceInstanceID.isEmpty,
           sourceInstanceID != CalendarEventKitAdapter.systemAccountID.rawValue {
            guard let account = calendarAccounts.first(where: { $0.id.rawValue == sourceInstanceID }) else {
                return "Calendar account not found: \(sourceInstanceID)"
            }
            guard let calendarRuntimeStore else { return "Calendar runtime store unavailable" }
            let engine = CalendarSourceSyncEngine(
                connectors: [
                    CalendarICSSubscriptionConnector(),
                    CalendarCalDAVConnector(kind: .genericCalDAV),
                    CalendarCalDAVConnector(kind: .appleICloudCalDAV),
                    CalendarCalDAVConnector(kind: .fastmailCalDAV),
                    CalendarCalDAVConnector(kind: .nextcloudCalDAV)
                ],
                runtimeStore: calendarRuntimeStore
            )
            do {
                let credential = readCalendarCredential(for: account)
                let result = try await engine.sync(request: CalendarSourceSyncRequest(account: account, credential: credential, runID: runID))
                let snapshot = try await calendarRuntimeStore.loadSnapshot()
                calendarAccounts = mergeAccounts(calendarAccounts, snapshot.accounts)
                calendarCollections = mergeCollections(calendarCollections, snapshot.collections)
                calendarEvents = mergeEvents(calendarEvents, snapshot.events)
                reloadCalendarBrowserPresentation()
                scheduleCalendarSearchIndexRefresh()
                await persistCalendarSnapshot()
                return "Calendar refreshed account \(sourceInstanceID); synced \(result.events.count) events across \(result.collections.count) calendars"
            } catch {
                return "Calendar refresh failed for account \(sourceInstanceID): \(error.localizedDescription)"
            }
        }
        let succeeded = await syncSystemCalendarNow()
        return succeeded ? (calendarSyncMessage ?? "Calendar refreshed") : (calendarSyncMessage ?? "Calendar refresh failed")
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

    private func refreshMailForScheduledTask(sourceInstanceID: String?, runID: String?) async throws -> String {
        guard let mailStore else { return "Mail store unavailable" }
        let accounts: [MailAccount]
        if let sourceInstanceID, !sourceInstanceID.isEmpty {
            guard let account = try await mailStore.account(id: MailAccountID(rawValue: sourceInstanceID)) else {
                return "Mail account not found: \(sourceInstanceID)"
            }
            accounts = [account]
        } else {
            accounts = try await mailStore.listAccounts()
        }
        guard !accounts.isEmpty else { return "No mail accounts configured" }

        let syncService = MailIMAPInitialSyncService(messageLimit: 0)
        var syncedMessageCount = 0
        var summaries: [String] = []

        for account in accounts {
            let mailboxes = try await mailStore.listMailboxes(accountID: account.id)
            let storedUIDsByMailboxID = try await storedMailUIDsByMailboxID(for: account.id, mailboxes: mailboxes, in: mailStore)
            let storedUIDValidityByMailboxID = Dictionary(uniqueKeysWithValues: mailboxes.map { ($0.id, $0.status.syncCursor?.uidValidity) })
            let hasSyncedMailbox = mailboxes.contains { $0.status.lastSyncedAt != nil }
            let result: MailInitialSyncResult
            if !storedUIDsByMailboxID.isEmpty || hasSyncedMailbox {
                result = try await syncService.syncIncremental(
                    account: account,
                    storedUIDsByMailboxID: storedUIDsByMailboxID,
                    storedUIDValidityByMailboxID: storedUIDValidityByMailboxID
                )
            } else {
                result = try await syncService.sync(account: account)
            }

            try await mailStore.saveAccount(result.account)
            for mailbox in result.mailboxes {
                try await mailStore.saveMailbox(mailbox)
            }
            if !result.messages.isEmpty {
                try await mailStore.saveMessagesBatch(result.messages)
            }
            syncedMessageCount += result.messages.count
            summaries.append("\(result.account.displayName)：\(result.account.health.summary)")
        }

        await reloadMailBrowserPresentation()
        let summary = summaries.joined(separator: "；")
        if let sourceInstanceID, !sourceInstanceID.isEmpty {
            return "Mail refreshed account \(sourceInstanceID); synced \(syncedMessageCount) message(s). \(summary)"
        }
        return "Mail refreshed \(accounts.count) account(s); synced \(syncedMessageCount) message(s). \(summary)"
    }

    private func storedMailUIDsByMailboxID(for accountID: MailAccountID, mailboxes: [MailMailbox], in mailStore: any MailStoreProtocol) async throws -> [MailMailboxID: Set<String>] {
        let remoteMailboxes = mailboxes.map { mailbox in
            RemoteIMAPMailbox(name: mailbox.name, path: mailbox.path, role: mailbox.role)
        }
        var result: [MailMailboxID: Set<String>] = [:]
        let messageIDs = try await mailStore.allMessageIDs()
        for remoteMailbox in remoteMailboxes {
            let mailboxID = remoteMailbox.mailboxID(accountID: accountID)
            let uids = Set(messageIDs.compactMap { remoteMailbox.uid(fromMessageID: $0, accountID: accountID) })
            if !uids.isEmpty {
                result[mailboxID] = uids
            }
        }
        return result
    }

    private func refreshRSSForScheduledTask(sourceInstanceID: String?, runID: String?) async throws -> String {
        if let sourceInstanceID, !sourceInstanceID.isEmpty {
            let sourceID = RSSSourceID(rawValue: sourceInstanceID)
            let result = try await rssRuntime.syncSource(sourceID: sourceID, runID: runID, sessionID: selectedChatSessionID)
            await reloadRSSBrowserPresentation()
            return "RSS refreshed source \(sourceInstanceID); inserted \(result.insertedCount), duplicates \(result.duplicateCount)"
        }

        let sources = try await rssRuntime.listSources(runID: runID, sessionID: selectedChatSessionID)
        var inserted = 0
        var duplicates = 0
        for source in sources {
            let result = try await rssRuntime.syncSource(sourceID: source.id, runID: runID, sessionID: selectedChatSessionID)
            inserted += result.insertedCount
            duplicates += result.duplicateCount
        }
        await reloadRSSBrowserPresentation()
        return "RSS refreshed \(sources.count) sources; inserted \(inserted), duplicates \(duplicates)"
    }

    private func performTaskSessionMessage(_ request: TaskSessionMessageRequest) async -> String {
        if request.createNewSession {
            guard let chatSessionRepository else { return "Session repository unavailable" }
            do {
                let session = try chatSessionRepository.createSession(title: request.title ?? "定时任务会话")
                reloadChatSessions()
                selectedChatSessionID = session.id
                fallbackChatSession = session
                nativeSessionManager = makeNativeSessionManager(for: session)
                _ = await submitChat(prompt: request.message, clearComposer: false)
                return "created session \(session.id) and sent task message"
            } catch {
                return "failed to create task session: \(error)"
            }
        }
        guard let sessionID = request.sessionID else { return "Missing sessionID" }
        selectedChatSessionID = sessionID
        if let session = try? chatSessionRepository?.loadSession(id: sessionID) {
            fallbackChatSession = session
            nativeSessionManager = makeNativeSessionManager(for: session)
        }
        _ = await submitChat(prompt: request.message, clearComposer: false)
        return "sent task message to session \(sessionID)"
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

    func reloadCalendarBrowserPresentation() {
        calendarBrowserPresentation = NativeCalendarBrowserPresentation.build(events: calendarEvents)
        if let selectedCalendarEventID,
           !calendarEvents.contains(where: { $0.id == selectedCalendarEventID }) {
            self.selectedCalendarEventID = calendarEvents.first?.id
        }
        errorMessage = nil
    }

    func reloadContactsBrowserPresentation() {
        contactsBrowserPresentation = NativeContactsBrowserPresentation.build(records: contactRecords)
        if let selectedContactID,
           !contactRecords.contains(where: { $0.id == selectedContactID }) {
            self.selectedContactID = nil
        }
        errorMessage = nil
    }

    func reloadCalendarContactsFromStorage() async {
        do {
            let legacySnapshot = try await calendarStore?.loadSnapshot()
            let runtimeSnapshot = try await calendarRuntimeStore?.loadSnapshot()
            if legacySnapshot != nil || runtimeSnapshot != nil {
                calendarAccounts = mergeAccounts(legacySnapshot?.accounts ?? [], runtimeSnapshot?.accounts ?? [])
                calendarCollections = mergeCollections(legacySnapshot?.collections ?? [], runtimeSnapshot?.collections ?? [])
                calendarEvents = mergeEvents(legacySnapshot?.events ?? [], runtimeSnapshot?.events ?? [])
                reloadCalendarBrowserPresentation()
                scheduleCalendarSearchIndexRefresh()
            }
            if let records = try await contactStore?.loadRecords() {
                contactRecords = records
                reloadContactsBrowserPresentation()
            }
            await reloadMailBrowserPresentation()
            errorMessage = nil
        } catch {
            errorMessage = "无法加载日历/联系人/邮件缓存：\(error.localizedDescription)"
        }
    }

    func presentAddMailAccountSheet() {
        isPresentingAddMailAccountSheet = true
    }

    func rebuildMailCacheAndRefresh() async -> String {
        do {
            guard let mailStore else { return "Mail store unavailable" }
            try await mailStore.clearCachedMailData()
            await reloadMailBrowserPresentation()
            let result = try await refreshMailForScheduledTask(sourceInstanceID: nil, runID: nil)
            let message = "已清空本地邮件缓存并重新同步。\(result)"
            mailSyncMessage = message
            return message
        } catch {
            let message = "无法重建邮件缓存：\(error.localizedDescription)"
            errorMessage = message
            mailSyncMessage = message
            return message
        }
    }

    func reloadMailBrowserPresentation() async {
        do {
            guard let mailStore else { return }
            mailBrowserPresentation = try await mailStore.presentation()
            try await reconcileMailDefaultSendPreferences(accounts: mailBrowserPresentation.accounts)
            if selectedMailAccountID == nil || mailBrowserPresentation.account(id: selectedMailAccountID) == nil {
                selectedMailAccountID = mailBrowserPresentation.defaultAccountID()
            }
            if selectedMailMailboxID == nil || mailBrowserPresentation.mailbox(id: selectedMailMailboxID) == nil {
                selectedMailMailboxID = mailBrowserPresentation.defaultMailboxID(for: selectedMailAccountID)
            }
            if selectedMailMessageID == nil || mailBrowserPresentation.message(id: selectedMailMessageID) == nil {
                selectedMailMessageID = mailBrowserPresentation.defaultMessageID(accountID: selectedMailAccountID, mailboxID: selectedMailMailboxID)
            }
            errorMessage = nil
        } catch {
            errorMessage = "无法加载邮件缓存：\(error.localizedDescription)"
        }
    }

    private func reconcileMailDefaultSendPreferences(accounts: [MailAccount]) async throws {
        guard let mailPreferencesStore else { return }
        let loaded = try await mailPreferencesStore.load()
        let reconciled = MailDefaultSendAccountReconciler.reconcile(preferences: loaded, accounts: accounts)
        mailPreferences = reconciled
        if reconciled != loaded {
            try await mailPreferencesStore.save(reconciled)
        }
    }

    func setDefaultMailSendAccount(_ accountID: MailAccountID) async {
        do {
            guard let account = mailBrowserPresentation.account(id: accountID) else {
                errorMessage = "无法设置默认发信账户：账户不存在"
                return
            }
            guard let identity = account.identities.first(where: \.canSend) else {
                errorMessage = "无法设置默认发信账户：该账户没有可发送身份"
                return
            }
            let preferences = MailPreferences(defaultSendAccountID: account.id, defaultSendIdentityID: identity.id)
            mailPreferences = preferences
            try await mailPreferencesStore?.save(preferences)
            errorMessage = nil
        } catch {
            errorMessage = "无法保存默认发信账户：\(error.localizedDescription)"
        }
    }

    func loadMailBodyDisplay(for messageID: MailMessageID) async -> MailBodyDisplayPresentation {
        do {
            guard let detail = try await mailStore?.message(id: messageID) else {
                return MailBodyDisplayPresentation(kind: .error, text: "无法读取邮件正文：本地缓存中找不到这封邮件")
            }
            if MailBodyOnDemandFetchPlanner.hasDisplayableBody(detail) {
                return MailBodyDisplayPresentation(detail: detail)
            }
            do {
                let fetched = try await fetchAndCacheMailBodyIfNeeded(detail)
                return MailBodyDisplayPresentation(detail: fetched)
            } catch {
                let message = "无法按需读取邮件正文：\(error.localizedDescription)"
                errorMessage = message
                return MailBodyDisplayPresentation.error(message, fallback: detail.summary.snippet)
            }
        } catch {
            let message = "无法读取邮件正文：\(error.localizedDescription)"
            errorMessage = message
            return MailBodyDisplayPresentation(kind: .error, text: message)
        }
    }

    private func fetchAndCacheMailBodyIfNeeded(_ detail: MailMessageDetail) async throws -> MailMessageDetail {
        guard let mailStore else { return detail }
        guard let account = try await mailStore.account(id: detail.summary.accountID) else {
            throw NSError(domain: "Connor.MailBody", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到邮件账户"])
        }
        guard let uid = MailBodyOnDemandFetchPlanner.imapUID(for: detail) else {
            throw NSError(domain: "Connor.MailBody", code: 2, userInfo: [NSLocalizedDescriptionKey: "缺少邮件 UID"])
        }
        let mailboxes = try await mailStore.listMailboxes(accountID: detail.summary.accountID)
        let mailbox = mailboxes.first { $0.id == detail.summary.mailboxID }
        let service = MailIMAPInitialSyncService(credentialStore: AppMailCredentialStore(), messageLimit: 0)
        guard let fetched = try await service.fetchMessageBody(
            account: account,
            uid: uid,
            messageID: detail.id,
            mailboxID: detail.summary.mailboxID,
            mailboxPath: mailbox?.path ?? "INBOX",
            mailboxRole: mailbox?.role ?? .inbox,
            snippet: detail.summary.snippet
        ) else {
            throw NSError(domain: "Connor.MailBody", code: 3, userInfo: [NSLocalizedDescriptionKey: "服务器未返回可显示正文"])
        }
        guard MailBodyOnDemandFetchPlanner.hasDisplayableBody(fetched) else {
            throw NSError(domain: "Connor.MailBody", code: 4, userInfo: [NSLocalizedDescriptionKey: "服务器返回的正文为空"])
        }
        try await mailStore.saveMessage(fetched)
        await reloadMailBrowserPresentation()
        return fetched
    }

    func loadMailBodyText(for messageID: MailMessageID) async -> String? {
        let display = await loadMailBodyDisplay(for: messageID)
        return display.text
    }

    func loadMailBodyHTML(for messageID: MailMessageID) async -> String? {
        let display = await loadMailBodyDisplay(for: messageID)
        return display.html
    }

    func addMailAccountAndPrepareSync(preset: MailAccountProviderPreset, displayName: String, email: String, credential: String, incomingHost: String, incomingPort: Int, outgoingHost: String, outgoingPort: Int) async throws {
        let provider: MailProviderKind = switch preset {
        case .apple: .genericIMAPSMTP
        case .qq: .genericIMAPSMTP
        case .netease: .genericIMAPSMTP
        case .other: .genericIMAPSMTP
        }
        try await addMailAccountAndPrepareSync(
            displayName: displayName,
            email: email,
            provider: provider,
            incomingHost: incomingHost,
            incomingPort: incomingPort,
            incomingSecurity: preset.incomingSecurity,
            outgoingHost: outgoingHost,
            outgoingPort: outgoingPort,
            outgoingSecurity: preset.outgoingSecurity,
            username: email,
            password: credential,
            authMode: preset.authMode
        )
    }

    func addMailAccountAndPrepareSync(displayName: String, email: String, provider: MailProviderKind, incomingHost: String, incomingPort: Int, incomingSecurity: MailConnectionSecurity, outgoingHost: String, outgoingPort: Int, outgoingSecurity: MailConnectionSecurity, username: String, password: String, authMode: MailAuthMode) async throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let accountID = MailAccountID(rawValue: normalizedEmail)
        let resolvedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? normalizedEmail : username.trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = MailIdentity(id: MailIdentityID(rawValue: "identity-\(accountID.rawValue)"), displayName: displayName, address: MailAddress(name: displayName, email: normalizedEmail))
        let binding = AppMailCredentialStore.binding(accountID: accountID, email: resolvedUsername, authMode: authMode)
        let account = MailAccount(
            id: accountID,
            provider: provider,
            displayName: displayName.isEmpty ? email : displayName,
            identities: [identity],
            incoming: MailServerEndpoint(host: incomingHost, port: incomingPort, security: incomingSecurity, protocolKind: .imap),
            outgoing: MailServerEndpoint(host: outgoingHost, port: outgoingPort, security: outgoingSecurity, protocolKind: .smtp),
            credentialBinding: binding,
            health: MailAccountHealth(status: .unknown, summary: "Ready to sync")
        )
        let inbox = MailMailbox(id: MailMailboxID(rawValue: "\(accountID.rawValue)-inbox"), accountID: accountID, name: "Inbox", path: "INBOX", role: .inbox)
        try AppMailCredentialStore().saveCredential(password, binding: binding)
        try await mailStore?.saveAccount(account)
        try await mailStore?.saveMailbox(inbox)
        selectedMailAccountID = accountID
        selectedMailMailboxID = inbox.id
        isPresentingAddMailAccountSheet = false
        mailSyncMessage = "已添加邮箱：\(account.displayName)，正在同步最近邮件…"
        await reloadMailBrowserPresentation()
        do {
            try await reconcileMailAccountRefreshTasks()
            reloadTaskManagementPresentation()
            let summary = try await refreshMailForScheduledTask(sourceInstanceID: accountID.rawValue, runID: nil)
            mailSyncMessage = summary
            reloadTaskManagementPresentation()
        } catch {
            let message = String(describing: error)
            mailSyncMessage = "邮箱已添加，但同步失败：\(message)"
            errorMessage = message
        }
    }

    private static func mailPlainText(fromHTML html: String) -> String {
        var text = html.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"</p\s*>"#, with: "\n\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
        return text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func persistCalendarSnapshot() async {
        do {
            let snapshot = FileBackedCalendarSourceStore.Snapshot(
                accounts: calendarAccounts,
                collections: calendarCollections,
                events: calendarEvents
            )
            try await calendarStore?.saveSnapshot(snapshot)
            if let calendarRuntimeStore {
                let runtimeSnapshot = try await calendarRuntimeStore.loadSnapshot()
                try await calendarRuntimeStore.saveSnapshot(
                    CalendarSourceRuntimeSnapshot(
                        accounts: calendarAccounts,
                        collections: calendarCollections,
                        events: calendarEvents,
                        syncStates: runtimeSnapshot.syncStates,
                        diagnostics: runtimeSnapshot.diagnostics
                    )
                )
            }
        } catch {
            errorMessage = "无法保存日历缓存：\(error.localizedDescription)"
        }
    }

    private func persistContactRecords() async {
        do {
            try await contactStore?.saveRecords(contactRecords)
        } catch {
            errorMessage = "无法保存联系人缓存：\(error.localizedDescription)"
        }
    }

    @discardableResult
    func syncSystemCalendarNow() async -> Bool {
        guard !isSyncingSystemCalendar else { return false }
        isSyncingSystemCalendar = true
        calendarSyncMessage = "正在请求日历权限并同步…"
        do {
            let snapshot = try await CalendarEventKitAdapter.fetchSystemSnapshot()
            upsertSystemCalendarSnapshot(snapshot)
            await persistCalendarSnapshot()
            try await reconcileCalendarAccountRefreshTasks()
            reloadTaskManagementPresentation()
            calendarSyncMessage = "已同步本机日历：\(snapshot.collections.count) 个日历，\(snapshot.events.count) 个日程"
            errorMessage = nil
            isSyncingSystemCalendar = false
            return true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            calendarSyncMessage = message
            errorMessage = message
            isSyncingSystemCalendar = false
            return false
        }
    }

    func syncSystemCalendar() {
        Task { @MainActor in
            _ = await syncSystemCalendarNow()
        }
    }

    func syncSystemContacts() {
        guard !isSyncingSystemContacts else { return }
        isSyncingSystemContacts = true
        contactsSyncMessage = "正在请求通讯录权限并同步…"
        Task { @MainActor in
            do {
                let records = try await ContactsSystemAdapter.fetchSystemContacts()
                contactRecords = records
                reloadContactsBrowserPresentation()
                await persistContactRecords()
                contactsSyncMessage = "已同步系统通讯录：\(records.count) 个联系人"
                setSettingsMessage(contactsSyncMessage, for: .preferences)
                errorMessage = nil
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                contactsSyncMessage = message
                errorMessage = message
            }
            isSyncingSystemContacts = false
        }
    }

    private func readCalendarCredential(for account: CalendarAccount) -> String? {
        if account.configuration.authMode == .none { return nil }
        if let username = account.configuration.username {
            let binding = AppCalendarCredentialStore.binding(accountID: account.id, username: username, authMode: account.configuration.authMode)
            return try? calendarCredentialStore.readCredential(binding: binding)
        }
        if let binding = account.credentialBinding {
            return try? calendarCredentialStore.credentialStore.readSecret(service: binding.credentialNamespace, account: binding.accountName)
        }
        return nil
    }

    private func mergeAccounts(_ primary: [CalendarAccount], _ overlay: [CalendarAccount]) -> [CalendarAccount] {
        var byID = Dictionary(uniqueKeysWithValues: primary.map { ($0.id, $0) })
        for account in overlay { byID[account.id] = account }
        return byID.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func mergeCollections(_ primary: [CalendarCollection], _ overlay: [CalendarCollection]) -> [CalendarCollection] {
        var byID = Dictionary(uniqueKeysWithValues: primary.map { ($0.id, $0) })
        for collection in overlay { byID[collection.id] = collection }
        return byID.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func mergeEvents(_ primary: [CalendarEvent], _ overlay: [CalendarEvent]) -> [CalendarEvent] {
        var byID = Dictionary(uniqueKeysWithValues: primary.map { ($0.id, $0) })
        for event in overlay { byID[event.id] = event }
        return byID.values.sorted { $0.start.date < $1.start.date }
    }

    private func upsertSystemCalendarSnapshot(_ snapshot: CalendarEventKitSnapshot) {
        let systemAccountIDs = Set(snapshot.accounts.map(\.id))
        let systemCalendarIDs = Set(snapshot.collections.map(\.id))
        let nextAccounts = (calendarAccounts.filter { !systemAccountIDs.contains($0.id) } + snapshot.accounts)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        let nextCollections = (calendarCollections.filter { $0.accountID != CalendarEventKitAdapter.systemAccountID && !systemCalendarIDs.contains($0.id) } + snapshot.collections)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        let nextEvents = (calendarEvents.filter { !systemCalendarIDs.contains($0.calendarID) } + snapshot.events)
            .sorted { $0.start.date < $1.start.date }
        calendarAccounts = nextAccounts
        calendarCollections = nextCollections
        calendarEvents = nextEvents
        reloadCalendarBrowserPresentation()
        scheduleCalendarSearchIndexRefresh()
    }

    func addCalendarSource(
        provider: ConnectedAccountProviderKind,
        displayName rawDisplayName: String,
        calendarName rawCalendarName: String
    ) {
        if provider == .localFixture {
            syncSystemCalendar()
            isPresentingAddCalendarSourceSheet = false
            return
        }
        let displayName = rawDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendarName = rawCalendarName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedDisplayName = displayName.isEmpty ? calendarProviderDisplayName(provider) : displayName
        let resolvedCalendarName = calendarName.isEmpty ? "默认日历" : calendarName
        let slugBase = AccountConnectionRuntime.slug(for: "\(provider.rawValue)-\(resolvedDisplayName)-\(calendarAccounts.count + 1)")
        let accountID = CalendarAccountID(rawValue: "calendar-account-\(slugBase)")
        let collectionID = CalendarID(rawValue: "calendar-\(slugBase)")
        let now = Date()
        let account = CalendarAccount(
            id: accountID,
            provider: provider,
            displayName: resolvedDisplayName,
            health: CalendarAccountHealth(status: .ready, checkedAt: now, summary: "已添加，等待同步日程"),
            createdAt: now,
            updatedAt: now
        )
        let collection = CalendarCollection(
            id: collectionID,
            accountID: accountID,
            displayName: resolvedCalendarName,
            colorHex: "#F97316",
            isReadOnly: false,
            source: "connor-calendar-source"
        )
        calendarAccounts = (calendarAccounts + [account])
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        calendarCollections = (calendarCollections + [collection])
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        selectedCalendarEventID = nil
        isPresentingAddCalendarSourceSheet = false
        reloadCalendarBrowserPresentation()
        calendarSyncMessage = "已添加日历源：\(resolvedDisplayName)"
        Task { @MainActor in
            await persistCalendarSnapshot()
            do {
                try await reconcileCalendarAccountRefreshTasks(now: now)
                reloadTaskManagementPresentation()
            } catch {
                errorMessage = String(describing: error)
            }
        }
    }

    func addCalendarSourceFromWizard(account: CalendarAccount, credential: String?) {
        // Save credential to the local encrypted credential store if provided.
        if let credential, !credential.isEmpty, let username = account.configuration.username {
            let binding = AppCalendarCredentialStore.binding(
                accountID: account.id,
                username: username,
                authMode: account.configuration.authMode
            )
            try? calendarCredentialStore.saveCredential(credential, binding: binding)
        }

        calendarAccounts = (calendarAccounts + [account])
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        selectedCalendarEventID = nil
        isPresentingAddCalendarSourceSheet = false
        calendarSyncMessage = "已添加日历源：\(account.displayName)，正在同步…"
        reloadCalendarBrowserPresentation()

        Task { @MainActor in
            await persistCalendarSnapshot()
            do {
                try await reconcileCalendarAccountRefreshTasks()
                reloadCalendarBrowserPresentation()
                reloadTaskManagementPresentation()
            } catch {
                calendarSyncMessage = "日历源同步失败：\(error.localizedDescription)"
            }
        }
    }

    func deleteCalendarSource(_ account: CalendarAccount) {
        let collectionIDs = Set(calendarCollections.filter { $0.accountID == account.id }.map(\.id))
        let nextAccounts = calendarAccounts.filter { $0.id != account.id }
        let nextCollections = calendarCollections.filter { $0.accountID != account.id }
        let nextEvents = calendarEvents.filter { !collectionIDs.contains($0.calendarID) }
        calendarAccounts = nextAccounts
        calendarCollections = nextCollections
        calendarEvents = nextEvents
        if let selectedCalendarEventID,
           !nextEvents.contains(where: { $0.id == selectedCalendarEventID }) {
            self.selectedCalendarEventID = nil
        }
        reloadCalendarBrowserPresentation()
        scheduleCalendarSearchIndexRefresh()
        calendarSyncMessage = "已移除日历源：\(account.displayName)"
        Task { @MainActor in
            await persistCalendarSnapshot()
            do {
                try await reconcileCalendarAccountRefreshTasks()
                reloadTaskManagementPresentation()
            } catch {
                errorMessage = String(describing: error)
            }
        }
    }

    private func calendarProviderDisplayName(_ provider: ConnectedAccountProviderKind) -> String {
        switch provider {
        case .appleICloud: "Apple iCloud"
        case .microsoft365, .google: "已停止支持的旧账户"
        case .qq: "QQ"
        case .netEase: "网易"
        case .genericIMAPSMTP: "自定义 IMAP/SMTP"
        case .genericCalDAVCardDAV: "自定义 CalDAV / CardDAV"
        case .localFixture: "本机日历"
        }
    }

    func reloadRSSBrowserPresentation() async {
        do {
            let sources = try await rssRuntime.listSources(runID: nil, sessionID: selectedChatSessionID)
            let items = try await rssRuntime.listItems(sourceID: nil, includeHidden: false, limit: 200, runID: nil, sessionID: selectedChatSessionID)
            rssBrowserPresentation = NativeRSSBrowserPresentation(sources: sources, items: items)
            if let selectedRSSSourceID,
               !sources.contains(where: { $0.id == selectedRSSSourceID }) {
                self.selectedRSSSourceID = sources.first?.id
            } else if selectedRSSSourceID == nil {
                selectedRSSSourceID = sources.first?.id
            }
            if let selectedRSSItemID,
               !items.contains(where: { $0.id == selectedRSSItemID }) {
                self.selectedRSSItemID = items.first?.id
            } else if selectedRSSItemID == nil {
                selectedRSSItemID = items.first?.id
            }
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func selectRSSItem(_ item: RSSItemSummary) {
        selectedRSSSourceID = item.sourceID
        selectedRSSItemID = item.id
        guard !item.state.isRead else { return }
        markRSSItemsRead([item.id], isRead: true)
    }

    func markRSSItemsRead(_ itemIDs: [RSSItemID], isRead: Bool) {
        guard !itemIDs.isEmpty else { return }
        let targetIDs = Set(itemIDs)
        let updatedItems = rssBrowserPresentation.items.map { item in
            guard targetIDs.contains(item.id), item.state.isRead != isRead else { return item }
            var copy = item
            copy.state.isRead = isRead
            return copy
        }
        rssBrowserPresentation = NativeRSSBrowserPresentation(sources: rssBrowserPresentation.sources, items: updatedItems)
        Task { @MainActor in
            do {
                try await rssRuntime.setReadState(itemIDs: itemIDs, isRead: isRead, runID: nil, sessionID: selectedChatSessionID)
                await reloadRSSBrowserPresentation()
            } catch {
                errorMessage = String(describing: error)
                await reloadRSSBrowserPresentation()
            }
        }
    }

    func addRSSSourceAndSync(feedURL: URL, displayName: String?) async throws {
        let source = try await rssRuntime.addSource(feedURL: feedURL, displayName: displayName, runID: nil, sessionID: selectedChatSessionID)
        selectedRSSSourceID = source.id
        do {
            _ = try await rssRuntime.syncSource(sourceID: source.id, runID: nil, sessionID: selectedChatSessionID)
            errorMessage = nil
        } catch {
            errorMessage = "RSS 订阅源已添加，但首次抓取失败：\(error.localizedDescription)"
        }
        try await reconcileRSSSourceRefreshTasks()
        reloadTaskManagementPresentation()
        await reloadRSSBrowserPresentation()
    }

    func updateRSSSource(sourceID: RSSSourceID, feedURL: URL, displayName: String?) async throws {
        let source = try await rssRuntime.updateSource(sourceID: sourceID, feedURL: feedURL, displayName: displayName, runID: nil, sessionID: selectedChatSessionID)
        selectedRSSSourceID = source.id
        if let selectedRSSItemID,
           rssBrowserPresentation.item(id: selectedRSSItemID)?.sourceID == sourceID,
           source.feedURL == feedURL {
            self.selectedRSSItemID = selectedRSSItemID
        }
        try await reconcileRSSSourceRefreshTasks()
        reloadTaskManagementPresentation()
        errorMessage = nil
        await reloadRSSBrowserPresentation()
    }

    func deleteRSSSource(_ source: RSSSource) {
        Task { @MainActor in
            do {
                try await rssRuntime.deleteSource(sourceID: source.id, runID: nil, sessionID: selectedChatSessionID)
                if selectedRSSSourceID == source.id { selectedRSSSourceID = nil }
                if let selectedRSSItemID,
                   rssBrowserPresentation.item(id: selectedRSSItemID)?.sourceID == source.id {
                    self.selectedRSSItemID = nil
                }
                try await reconcileSourceRefreshTasks()
                reloadTaskManagementPresentation()
                pendingRSSSourceDeletion = nil
                errorMessage = nil
                await reloadRSSBrowserPresentation()
            } catch {
                pendingRSSSourceDeletion = nil
                errorMessage = String(describing: error)
                await reloadRSSBrowserPresentation()
            }
        }
    }

    func followRSSItemInNewSession(_ item: RSSItemSummary) {
        guard let url = item.link else {
            errorMessage = "这篇 RSS 文章没有可打开的原文链接。"
            return
        }
        if !item.state.isRead {
            markRSSItemsRead([item.id], isRead: true)
        }
        let currentSessionID = selectedChatSessionID ?? activeChatSession.id
        if focusExistingBrowserTabIfPresent(urlString: url.absoluteString, preferredSessionID: currentSessionID) {
            errorMessage = nil
            return
        }
        guard let chatSessionRepository else { return }
        rememberCurrentWorkspaceMode()
        do {
            let title = rssFollowSessionTitle(for: item)
            let session = try chatSessionRepository.createSession(title: title)
            selectedChatSessionID = session.id
            agentEventTimelinesByProcessKey.removeAll(keepingCapacity: true)
            browserWorkspaceSessionID = nil
            selectedSessionArtifactDirectories = try chatSessionRepository.artifactDirectories(sessionID: session.id)
            try loadSessionCapsule(sessionID: session.id)
            try loadBackgroundTasks(sessionID: session.id)
            fallbackChatSession = session
            nativeSessionManager = makeNativeSessionManager(for: session)
            replaceSelectedChatTranscript([])
            restoreChatInputDraft(for: session.id)
            refreshSelectedSubmittingState()
            agentEventTimeline = []
            agentEventTimelinesBySessionID[session.id] = []
            latestChatSummary = nil
            chatSummaryMessage = nil
            lastPromptInspection = nil
            reloadChatSessions(restoreWorkspaceMode: false)
            selectedChatSessionID = session.id
            openURLInCurrentChatBrowser(url)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func rssFollowSessionTitle(for item: RSSItemSummary) -> String {
        let rawTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = rawTitle.isEmpty ? "RSS 文章" : rawTitle
        return "关注 \(title)"
    }

    func reloadSourceRuntimeConfigurations() {
        do {
            let configurations = try sourceRuntimeRepository?.list() ?? []
            sourceRuntimeConfigurations = configurations
            sourceRuntimeHealthRecords = try sourceRuntimeRepository?.listHealthRecords() ?? []
            var catalogs: [String: [MCPSourceToolDescriptor]] = [:]
            var audits: [String: [MCPSourceRuntimeAuditRecord]] = [:]
            for configuration in configurations {
                catalogs[configuration.sourceID] = try sourceRuntimeRepository?.loadToolCatalog(sourceID: configuration.sourceID) ?? []
                audits[configuration.sourceID] = try sourceRuntimeRepository?.loadRecentAuditRecords(sourceID: configuration.sourceID, limit: 12) ?? []
            }
            sourceRuntimeToolCatalogs = catalogs
            sourceRuntimeAuditRecordsBySource = audits
            if let selectedSourceRuntimeCardID,
               !configurations.contains(where: { $0.sourceID == selectedSourceRuntimeCardID }) {
                self.selectedSourceRuntimeCardID = nil
            }
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func selectSourceRuntimeCard(_ id: String) {
        selectedSourceRuntimeCardID = id
    }

    func presentAddSourceSheet() {
        addSourceDraft = MCPSourceDraft()
        addSourceMessage = nil
        isPresentingAddSourceSheet = true
    }

    func presentEditSourceSheet(sourceID: String) {
        guard let configuration = sourceRuntimeConfigurations.first(where: { $0.sourceID == sourceID }) else {
            sourceRuntimeTestMessages[sourceID] = "Source configuration not found."
            return
        }
        addSourceDraft = MCPSourceDraft(configuration: configuration)
        addSourceMessage = nil
        isPresentingAddSourceSheet = true
    }

    func dismissAddSourceSheet() {
        isPresentingAddSourceSheet = false
        addSourceMessage = nil
    }

    func saveSourceRuntimeDraft() {
        guard let repository = sourceRuntimeRepository else {
            addSourceMessage = "Source runtime repository is not available."
            return
        }
        let draft = addSourceDraft
        let originalConfiguration = draft.editingSourceID.flatMap { sourceID in
            sourceRuntimeConfigurations.first(where: { $0.sourceID == sourceID })
        }
        if let originalSourceID = draft.editingSourceID, draft.normalizedSourceID != originalSourceID {
            addSourceMessage = "Editing Source ID is not supported yet. Create a new source instead."
            return
        }
        let sourceID = originalConfiguration?.sourceID ?? draft.normalizedSourceID
        guard let transport = draft.runtimeTransport else {
            addSourceMessage = "Invalid HTTP MCP endpoint URL. Use https://host/path, or http://localhost/path for local development."
            return
        }
        let configuration = MCPSourceRuntimeConfiguration(
            sourceID: sourceID,
            displayName: draft.normalizedDisplayName,
            transport: transport,
            status: draft.status,
            credentialRequirement: draft.credentialRequirement,
            credentialBindings: draft.parsedCredentialBindings,
            allowedCapabilities: draft.allowedCapabilities,
            toolNamePrefix: originalConfiguration?.toolNamePrefix ?? sourceID,
            graphIngestionEnabled: false,
            graphWritePolicy: .readOnly,
            tags: draft.parsedTags,
            notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: originalConfiguration?.createdAt ?? Date()
        )
        do {
            try repository.save(configuration)
            if configuration.credentialRequirement == .none {
                if let originalConfiguration {
                    try mcpSourceCredentialStore.deleteSecrets(sourceID: configuration.sourceID, bindings: originalConfiguration.credentialBindings)
                }
            } else if !draft.trimmedCredentialSecret.isEmpty {
                let secretsByEnvironment = draft.parsedCredentialSecretByEnvironment
                for binding in configuration.credentialBindings {
                    let secret = secretsByEnvironment[binding.environmentVariable] ?? draft.trimmedCredentialSecret
                    try mcpSourceCredentialStore.saveSecret(
                        secret,
                        sourceID: configuration.sourceID,
                        environmentVariable: binding.environmentVariable
                    )
                }
            }
            reloadSourceRuntimeConfigurations()
            selectedSourceRuntimeCardID = configuration.sourceID
            sourceRuntimeTestMessages[configuration.sourceID] = draft.isEditing
                ? "Source updated. Run Test Source to refresh tools if transport changed."
                : "Source saved. Run Test Source to discover tools."
            isPresentingAddSourceSheet = false
            addSourceMessage = nil
            errorMessage = nil
        } catch {
            addSourceMessage = "Unable to save source: \(String(describing: error))"
        }
    }

    func setSourceRuntimeStatus(sourceID: String, status: ProductOSRegistryEntryStatus) {
        guard let repository = sourceRuntimeRepository else {
            sourceRuntimeTestMessages[sourceID] = "Source runtime repository is not available."
            return
        }
        guard var configuration = sourceRuntimeConfigurations.first(where: { $0.sourceID == sourceID }) else {
            sourceRuntimeTestMessages[sourceID] = "Source configuration not found."
            return
        }
        configuration.status = status
        do {
            try repository.save(configuration)
            reloadSourceRuntimeConfigurations()
            selectedSourceRuntimeCardID = sourceID
            sourceRuntimeTestMessages[sourceID] = "Source status updated to \(status.rawValue)."
            errorMessage = nil
        } catch {
            sourceRuntimeTestMessages[sourceID] = "Unable to update source status: \(String(describing: error))"
        }
    }

    func archiveSourceRuntime(sourceID: String) {
        setSourceRuntimeStatus(sourceID: sourceID, status: .deprecated)
        sourceRuntimeTestMessages[sourceID] = "Source archived as deprecated. Catalog, health and audit history are preserved."
    }

    func requestDeleteSourceRuntime(sourceID: String) {
        guard let configuration = sourceRuntimeConfigurations.first(where: { $0.sourceID == sourceID }) else {
            sourceRuntimeTestMessages[sourceID] = "Source configuration not found."
            return
        }
        pendingSourceRuntimeDeletionID = sourceID
        pendingSourceRuntimeDeletionName = configuration.displayName
    }

    func cancelDeleteSourceRuntime() {
        pendingSourceRuntimeDeletionID = nil
        pendingSourceRuntimeDeletionName = nil
    }

    func confirmDeleteSourceRuntime() {
        guard let sourceID = pendingSourceRuntimeDeletionID else { return }
        guard let repository = sourceRuntimeRepository else {
            sourceRuntimeTestMessages[sourceID] = "Source runtime repository is not available."
            cancelDeleteSourceRuntime()
            return
        }
        do {
            let configuration = sourceRuntimeConfigurations.first(where: { $0.sourceID == sourceID })
            if let configuration {
                try mcpSourceCredentialStore.deleteSecrets(sourceID: sourceID, bindings: configuration.credentialBindings)
            }
            try repository.deleteSourceRuntime(sourceID: sourceID)
            sourceRuntimeTestMessages.removeValue(forKey: sourceID)
            sourceRuntimeToolCatalogs.removeValue(forKey: sourceID)
            sourceRuntimeAuditRecordsBySource.removeValue(forKey: sourceID)
            sourceRuntimeHealthRecords.removeAll { $0.sourceID == sourceID }
            if selectedSourceRuntimeCardID == sourceID {
                selectedSourceRuntimeCardID = nil
            }
            cancelDeleteSourceRuntime()
            reloadSourceRuntimeConfigurations()
            errorMessage = nil
        } catch {
            sourceRuntimeTestMessages[sourceID] = "Unable to delete source: \(String(describing: error))"
            cancelDeleteSourceRuntime()
        }
    }

    func testSourceRuntime(sourceID: String) async {
        guard !testingSourceRuntimeIDs.contains(sourceID) else { return }
        guard let repository = sourceRuntimeRepository else {
            sourceRuntimeTestMessages[sourceID] = "Source runtime repository is not available."
            return
        }
        guard let configuration = sourceRuntimeConfigurations.first(where: { $0.sourceID == sourceID }) else {
            sourceRuntimeTestMessages[sourceID] = "Source configuration not found."
            return
        }
        testingSourceRuntimeIDs.insert(sourceID)
        sourceRuntimeTestMessages[sourceID] = "Testing source…"
        defer { testingSourceRuntimeIDs.remove(sourceID) }

        let workingDirectoryURL = primaryWorkspaceRootDraft
            .map(\.path)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        let service = MCPSourceTestService(
            repository: repository,
            currentDirectoryURL: workingDirectoryURL,
            credentialStore: mcpSourceCredentialStore
        )
        do {
            let report = try await service.testSource(configuration)
            sourceRuntimeTestMessages[sourceID] = report.success
                ? "Source test passed · discovered \(report.catalog.count) tools."
                : "Source test completed with unhealthy status · discovered \(report.catalog.count) tools."
            reloadSourceRuntimeConfigurations()
            selectedSourceRuntimeCardID = sourceID
            errorMessage = nil
        } catch {
            sourceRuntimeTestMessages[sourceID] = "Source test failed: \(String(describing: error))"
            reloadSourceRuntimeConfigurations()
            selectedSourceRuntimeCardID = sourceID
        }
    }

    func reloadSkillRuntimeDefinitions() {
        do {
            skillRuntimeDefinitions = try skillRuntimeRepository?.list() ?? []
            commercialSkillManagerPresentation = buildCommercialSkillManagerPresentation()
            if let selectedSkillManagerCardID,
               !commercialSkillManagerPresentation.cards.contains(where: { $0.id == selectedSkillManagerCardID }) {
                self.selectedSkillManagerCardID = nil
            }
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func reloadSkillRuntimeDefinitionsIfNeeded(after presentation: AgentEventPresentation) {
        guard presentation.kind == AgentEventKind.toolFinished.rawValue else { return }
        let skillMutationToolNames: Set<String> = [
            "connor_skill_create",
            "connor_skill_update",
            "connor_skill_delete"
        ]
        guard skillMutationToolNames.contains(where: { presentation.title.contains($0) }) else { return }
        reloadSkillRuntimeDefinitions()
    }

    func selectSkillManagerCard(_ id: String) {
        selectedSkillManagerCardID = id
    }

    func presentAddSkillDialog() {
        addSkillRequestDraft = ""
        addSkillDialogMessage = nil
        isSubmittingAddSkillRequest = false
        isAddSkillDialogPresented = true
    }

    func cancelAddSkillDialog() {
        guard !isSubmittingAddSkillRequest else { return }
        isAddSkillDialogPresented = false
        addSkillRequestDraft = ""
        addSkillDialogMessage = nil
    }

    func submitAddSkillRequest() async {
        let request = addSkillRequestDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !isSubmittingAddSkillRequest else { return }
        guard let chatSessionRepository else {
            addSkillDialogMessage = "会话系统尚未初始化。"
            return
        }
        isSubmittingAddSkillRequest = true
        addSkillDialogMessage = "康纳正在根据你的需求创建技能…"
        do {
            let knownSkillSlugs = currentUserSkillSlugs()
            let title = sanitizedSessionTitle("添加技能：\(request)")
            let session = try chatSessionRepository.createSession(title: title)
            rememberWorkspaceMode(.conversation, for: session.id)
            try loadBackgroundTasks(sessionID: session.id)
            reloadChatSessions(restoreWorkspaceMode: false)
            try await runAddSkillRequestInBackgroundSession(session: session, userRequest: request)
            let createdSlug = try ensureSkillPackageExists(for: request, excluding: knownSkillSlugs)
            addSkillRequestDraft = ""
            addSkillDialogMessage = "技能已创建：\(createdSlug)。"
            reloadChatSessions(restoreWorkspaceMode: false)
            reloadSkillRuntimeDefinitions()
            selectedSkillManagerCardID = createdSlug
            errorMessage = nil
        } catch {
            addSkillDialogMessage = "创建失败：\(String(describing: error))"
            errorMessage = String(describing: error)
        }
        isSubmittingAddSkillRequest = false
    }

    func presentEditSkillDialog(card: SkillManagerCard) {
        editingSkillCard = card
        editSkillRequestDraft = ""
        editSkillDialogMessage = nil
        isSubmittingEditSkillRequest = false
        isEditSkillDialogPresented = true
    }

    func cancelEditSkillDialog() {
        guard !isSubmittingEditSkillRequest else { return }
        isEditSkillDialogPresented = false
        editSkillRequestDraft = ""
        editSkillDialogMessage = nil
        editingSkillCard = nil
    }

    func submitEditSkillRequest() async {
        guard let card = editingSkillCard else { return }
        let request = editSkillRequestDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !isSubmittingEditSkillRequest else { return }
        guard let chatSessionRepository else {
            editSkillDialogMessage = "会话系统尚未初始化。"
            return
        }
        isSubmittingEditSkillRequest = true
        editSkillDialogMessage = "康纳正在根据你的需求修改技能…"
        do {
            let title = sanitizedSessionTitle("编辑技能：\(card.title)")
            let session = try chatSessionRepository.createSession(title: title)
            rememberWorkspaceMode(.conversation, for: session.id)
            try loadBackgroundTasks(sessionID: session.id)
            reloadChatSessions(restoreWorkspaceMode: false)
            try await runSkillRequestInBackgroundSession(
                session: session,
                prompt: buildEditSkillAgentPrompt(card: card, userRequest: request),
                displayPrompt: "编辑技能：\(card.title) — \(request)"
            )
            editSkillRequestDraft = ""
            editSkillDialogMessage = "修改请求已提交。完成后技能列表会自动刷新。"
            reloadChatSessions(restoreWorkspaceMode: false)
            reloadSkillRuntimeDefinitions()
            selectedSkillManagerCardID = card.id
            errorMessage = nil
        } catch {
            editSkillDialogMessage = "修改失败：\(String(describing: error))"
            errorMessage = String(describing: error)
        }
        isSubmittingEditSkillRequest = false
    }

    func requestDeleteSkill(card: SkillManagerCard) {
        pendingSkillDeletionCard = card
    }

    func cancelDeleteSkill() {
        pendingSkillDeletionCard = nil
    }

    func confirmDeletePendingSkill() {
        guard let card = pendingSkillDeletionCard else { return }
        do {
            try deleteSkill(card: card)
            pendingSkillDeletionCard = nil
            reloadSkillRuntimeDefinitions()
            if selectedSkillManagerCardID == card.id {
                selectedSkillManagerCardID = nil
            }
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func deleteSkill(card: SkillManagerCard) throws {
        guard card.sourceTier == SkillSourceTier.user.rawValue else {
            throw AppSkillRuntimeRepositoryError.unsafePermissionMode("Only user skills can be deleted from the skill manager. Skill \(card.id) is \(card.sourceTier).")
        }
        let packagePath = card.packagePath.isEmpty ? URL(fileURLWithPath: card.path).deletingLastPathComponent().path : card.packagePath
        guard let storagePaths else { throw AppChatRuntimeUnavailableError.nativeSessionManagerUnavailable }
        let packageURL = URL(fileURLWithPath: packagePath, isDirectory: true).standardizedFileURL
        let rootURL = storagePaths.skillsDirectory.standardizedFileURL
        guard packageURL.path == rootURL.appendingPathComponent(card.id, isDirectory: true).standardizedFileURL.path else {
            throw AppSkillRuntimeRepositoryError.unsafePermissionMode("Refusing to delete skill outside user skill directory: \(packageURL.path)")
        }
        try FileManager.default.removeItem(at: packageURL)
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
        activeChatBackendsBySessionID[sessionID] = liveBackend
        submittingChatSessionIDs.insert(sessionID)
        refreshSelectedSubmittingState()
        defer {
            activeChatBackendsBySessionID.removeValue(forKey: sessionID)
            if let runID = activeChatRunIDsBySessionID[sessionID] {
                activeChatBackendsByRunID.removeValue(forKey: runID)
            }
            submittingChatSessionIDs.remove(sessionID)
            activeChatRunIDsBySessionID.removeValue(forKey: sessionID)
            refreshSelectedSubmittingState()
        }
        _ = try await manager.submit(
            prompt,
            sessionSummary: nil,
            displayPrompt: displayPrompt,
            onRunStarted: { [weak self] runID in
                guard let self else { return }
                self.activeChatRunIDsBySessionID[sessionID] = runID
                self.activeChatBackendsByRunID[runID] = liveBackend
            },
            onEventPresentation: { [weak self] presentation in
                guard let self else { return }
                self.agentEventTimelinesBySessionID[sessionID, default: []].append(presentation)
                self.reloadSkillRuntimeDefinitionsIfNeeded(after: presentation)
            }
        )
        if let timeline = agentEventTimelinesBySessionID[sessionID] {
            scheduleActivityTimelineCacheSave(sessionID: sessionID, timeline: timeline)
        }
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

    private func buildCommercialSkillManagerPresentation() -> SkillManagerPresentation {
        guard let storagePaths else {
            return SkillManagerPresentation(
                summary: SkillManagerSummary(total: 0, enabled: 0, projectScoped: 0, risky: 0, invalid: 0, sourceBlocked: 0),
                cards: [],
                globalWarnings: ["Storage paths are not initialized."]
            )
        }
        let snapshot = SkillPackageScanner().scan(storagePaths: storagePaths)
        return SkillCommercialUIPresentationBuilder().build(snapshot: snapshot)
    }

    func runCommercialReadinessReleaseGate() {
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
            let connection = settings.defaultConnection
            llmConnectionConfigs = settings.connections
            llmDefaultConnectionID = settings.defaultConnectionID
            llmConnectionName = connection.name
            llmProviderMode = connection.providerMode
            llmBaseURLString = connection.baseURLString
            llmModel = connection.model
            llmSelectedModel = connection.effectiveModel
            llmThinkingLevel = settings.defaultThinkingLevel
            llmHasAPIKey = connection.hasAPIKey
            llmAPIKeyInput = ""
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

    func updateWelcomeState() {
        // 有连接配置就不显示欢迎页，不管连接是否可用
        showWelcomePlaceholder = llmConnectionConfigs.isEmpty
    }

    func selectLLMModel(_ modelID: String, providerMode: AppLLMProviderMode, connectionID: String? = nil) {
        guard !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        llmProviderMode = providerMode
        if let connectionID { llmDefaultConnectionID = connectionID }
        llmSelectedModel = modelID

        // Write session-level override (not global)
        let sessionID = selectedChatSessionID ?? activeChatSession.id
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
        guard let connection = llmConnectionConfigs.first(where: { $0.id == connectionID }) else { return }
        llmDefaultConnectionID = connection.id
        llmConnectionName = connection.name
        llmProviderMode = connection.providerMode
        llmBaseURLString = connection.baseURLString
        llmModel = connection.model
        llmSelectedModel = connection.effectiveModel
        llmHasAPIKey = connection.hasAPIKey
        llmAPIKeyInput = ""
        persistLLMSettings(rebuildRuntime: true)
    }

    func selectLLMThinkingLevel(_ level: AppLLMThinkingLevel) {
        llmThinkingLevel = level
        let sessionID = selectedChatSessionID ?? activeChatSession.id
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
        do {
            let existing = (try? llmSettingsRepository.loadSettings()) ?? .default
            let settings = AppLLMSettings(
                connections: existing.connections,
                defaultConnectionID: existing.defaultConnectionID,
                defaultThinkingLevel: level
            )
            try llmSettingsRepository.save(settings: settings, apiKey: nil)
            llmThinkingLevel = level
            rebuildNativeSessionManagerForActiveSession()
            llmSettingsMessage = "默认思考强度已保存。"
        } catch {
            errorMessage = String(describing: error)
        }
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
        isAddingLLMConnection = true
        defer { isAddingLLMConnection = false }
        let service = AppLLMConnectionSetupService(settingsRepository: llmSettingsRepository)
        let result = try await service.setupConnection(input)
        loadLLMSettings()
        if llmConnectionConfigs.count == 1, let firstConnection = llmConnectionConfigs.first {
            selectDefaultLLMConnection(firstConnection.id)
        }
        rebuildNativeSessionManagerForActiveSession()
        await reloadLLMModelConnections()
        llmSettingsMessage = result.message
        llmHealthCheckMessage = result.message
        errorMessage = nil
        return result.connection
    }

    @discardableResult
    private func addLLMConnection(
        id: String,
        providerMode: AppLLMProviderMode,
        name: String? = nil,
        baseURLString: String? = nil,
        model: String? = nil,
        selectedModel: String? = nil,
        hasAPIKey: Bool
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
            hasAPIKey: hasAPIKey
        )
        llmConnectionConfigs.removeAll { $0.id == connection.id }
        llmConnectionConfigs.append(connection)
        llmDefaultConnectionID = connection.id
        selectDefaultLLMConnection(connection.id)
        return connection
    }

    func deleteSelectedLLMConnection() {
        guard llmConnectionConfigs.count > 1 else {
            llmSettingsMessage = "至少需要保留一个 AI 连接。"
            return
        }
        let deletingID = llmDefaultConnectionID
        llmConnectionConfigs.removeAll { $0.id == deletingID }
        try? llmSettingsRepository.clearAPIKey(connectionID: deletingID)
        llmDefaultConnectionID = llmConnectionConfigs.first?.id ?? AppLLMSettings.default.defaultConnectionID
        selectDefaultLLMConnection(llmDefaultConnectionID)
    }

    func renameLLMConnection(_ connectionID: String, name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = llmConnectionConfigs.firstIndex(where: { $0.id == connectionID }) else { return }

        var renamedConnection = llmConnectionConfigs[index]
        guard renamedConnection.name != trimmedName else { return }
        renamedConnection.name = trimmedName

        do {
            try llmSettingsRepository.updateConnection(renamedConnection)
            loadLLMSettings()
            rebuildNativeSessionManagerForActiveSession()
            Task { await reloadLLMModelConnections() }
            llmSettingsMessage = "连接名称已更新。"
            llmHealthCheckMessage = nil
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func persistLLMSettings(rebuildRuntime: Bool) {
        do {
            let existing = (try? llmSettingsRepository.loadSettings()) ?? .default
            var connections = llmConnectionConfigs.isEmpty ? existing.connections : llmConnectionConfigs
            let targetID = llmDefaultConnectionID.isEmpty ? existing.defaultConnectionID : llmDefaultConnectionID
            let updatedConnection = AppLLMConnectionConfig(
                id: targetID,
                name: llmConnectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? (connections.first(where: { $0.id == targetID })?.name ?? (llmProviderMode == .openAICompatible ? "OpenAI Compatible" : "Claude"))
                    : llmConnectionName.trimmingCharacters(in: .whitespacesAndNewlines),
                providerMode: llmProviderMode,
                baseURLString: llmBaseURLString.trimmingCharacters(in: .whitespacesAndNewlines),
                model: llmModel.trimmingCharacters(in: .whitespacesAndNewlines),
                selectedModel: llmSelectedModel.trimmingCharacters(in: .whitespacesAndNewlines),
                hasAPIKey: llmHasAPIKey
            )
            if let index = connections.firstIndex(where: { $0.id == targetID }) {
                connections[index] = updatedConnection
            } else {
                connections.append(updatedConnection)
            }
            let settings = AppLLMSettings(connections: connections, defaultConnectionID: targetID, defaultThinkingLevel: llmThinkingLevel)
            llmConnectionConfigs = settings.connections
            llmDefaultConnectionID = settings.defaultConnectionID
            let apiKey = llmAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
            try llmSettingsRepository.save(settings: settings, apiKey: apiKey.isEmpty ? nil : apiKey)
            loadLLMSettings()
            if rebuildRuntime {
                let session = activeChatSession
                fallbackChatSession = session
                nativeSessionManager = makeNativeSessionManager(for: session)
            } else {
                nativeSessionManager?.permissionMode = agentPermissionMode
            }
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

    func settingsMessage(for section: ConnorSettingsSection) -> String? {
        settingsSectionMessageStore.message(for: section)
    }

    func setSettingsMessage(_ message: String?, for section: ConnorSettingsSection) {
        var store = settingsSectionMessageStore
        store.set(message, for: section)
        settingsSectionMessageStore = store
    }

    func clearSettingsMessage(for section: ConnorSettingsSection) {
        var store = settingsSectionMessageStore
        store.clear(for: section)
        settingsSectionMessageStore = store
    }

    private func makeNativeSessionManager(for session: AgentSession) -> NativeSessionManager? {
        agentRuntimeFactory?.makeNativeSessionManager(
            session: session,
            permissionMode: defaultPermissionMode == .allowAll ? .askToWrite : defaultPermissionMode,
            sessionWorkspace: sessionStateSnapshotsBySessionID[session.id]?.workspace,
            sessionLLMOverride: sessionStateSnapshotsBySessionID[session.id]?.llmOverride
        )
    }

    private func rebuildNativeSessionManagerForActiveSession() {
        let session = activeChatSession
        _ = ensureSessionLLMOverride(sessionID: session.id)
        fallbackChatSession = session
        nativeSessionManager = makeNativeSessionManager(for: session)
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
        guard let settings = try? llmSettingsRepository.loadSettings() else { return nil }
        let connection = settings.defaultConnection
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
        guard let provider = agentRuntimeFactory?.makeAgentModelProvider(sessionLLMOverride: override) else {
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
            llmSelectedModel = settings?.defaultConnection.effectiveModel ?? llmSelectedModel
            llmThinkingLevel = settings?.defaultThinkingLevel ?? llmThinkingLevel
            llmProviderMode = settings?.defaultConnection.providerMode ?? llmProviderMode
            llmDefaultConnectionID = settings?.defaultConnectionID ?? llmDefaultConnectionID
        }
    }

    var sessionHasLLMOverride: Bool {
        let sessionID = selectedChatSessionID ?? activeChatSession.id
        return sessionStateSnapshotsBySessionID[sessionID]?.llmOverride != nil
    }

    func clearSessionLLMOverride() {
        let sessionID = selectedChatSessionID ?? activeChatSession.id
        var state = sessionStateSnapshotsBySessionID[sessionID]
            ?? AppSessionStateSnapshot(sessionID: sessionID)
        state.llmOverride = nil
        state.updatedAt = Date()
        sessionStateSnapshotsBySessionID[sessionID] = state
        try? chatSessionRepository?.saveSessionState(state, sessionID: sessionID)

        // Fall back to global settings for UI display
        let settings = try? llmSettingsRepository.loadSettings()
        llmSelectedModel = settings?.defaultConnection.effectiveModel ?? llmSelectedModel
        llmThinkingLevel = settings?.defaultThinkingLevel ?? llmThinkingLevel
        llmProviderMode = settings?.defaultConnection.providerMode ?? llmProviderMode
        llmDefaultConnectionID = settings?.defaultConnectionID ?? llmDefaultConnectionID

        rebuildNativeSessionManagerForActiveSession()
        Task { await reloadLLMModelConnections() }
    }

    private func syncWorkspaceDraftsFromSession(_ state: AppSessionStateSnapshot?) {
        if let workspace = state?.workspace {
            workspaceRoots = AppWorkspaceRootDraftMapper.drafts(from: workspace)
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
            setSettingsMessage("当前会话 Workspace 已保存。", for: .app)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func loadRuntimeSettings() {
        do {
            isLoadingRuntimeSettings = true
            var shouldPersistSystemPreferenceDefaults = false
            defer {
                isLoadingRuntimeSettings = false
                if hasActivatedRuntimeSettingsSideEffects {
                    applyRuntimeSettingsSideEffects()
                }
                if shouldPersistSystemPreferenceDefaults {
                    scheduleRuntimeSettingsAutosave()
                }
            }
            var settings = try runtimeSettingsRepository?.loadOrCreateDefault() ?? .default
            defaultPermissionMode = settings.loop.permissionMode == .allowAll ? .askToWrite : settings.loop.permissionMode
            showProviderIcons = settings.ui.showProviderIcons
            richToolDescriptionsEnabled = settings.ui.richToolDescriptionsEnabled
            desktopNotificationsEnabled = settings.app.desktopNotificationsEnabled
            sessionNewMessageNotificationLevel = settings.app.sessionNotificationSettings.newMessageLevel
            keepScreenAwake = settings.app.keepScreenAwake
            internalBrowserEnabled = settings.app.internalBrowserEnabled
            httpProxyEnabled = settings.app.httpProxyEnabled
            httpProxyURLString = settings.app.httpProxyURLString
            appearanceMode = ConnorAppearanceMode(rawValue: settings.appearance.mode) ?? .system
            spellCheckEnabled = settings.input.spellCheckEnabled
            autoSaveDraftsEnabled = settings.input.autoSaveDraftsEnabled
            sessionSpeechTranscriptionEnabled = settings.input.sessionSpeechTranscriptionEnabled
            composerSendShortcut = settings.input.composerSendShortcut
            shortcutSettings = settings.shortcuts
            requireApprovalForNetwork = settings.permissions.requireApprovalForNetwork
            requireApprovalForShell = settings.permissions.requireApprovalForShell
            recentWorkspacePaths = settings.workspace.recentWorkspacePaths
            if let sessionID = currentSessionIDForWorkspaceDrafts() {
                syncWorkspaceDraftsFromSession(sessionStateSnapshotsBySessionID[sessionID])
            } else {
                defaultWorkingDirectoryPath = ""
                workspaceRoots = []
            }
            shouldPersistSystemPreferenceDefaults = settings.preferences.fillEmptyFields(from: .current())
            userDisplayName = settings.preferences.displayName
            userTimezone = settings.preferences.timezone
            userPreferredLanguage = settings.preferences.preferredLanguage
            applyLoadedGenderIdentity(settings.preferences.genderIdentity)
            userBirthDate = settings.preferences.birthDate
            if let parsedBirthDate = Self.birthDateFormatter.date(from: settings.preferences.birthDate) {
                userBirthDatePickerDate = parsedBirthDate
            }
            userCity = settings.preferences.city
            userCountry = settings.preferences.country
            userPreferenceNotes = settings.preferences.notes
            defaultSearchEngine = settings.preferences.defaultSearchEngine
            settingsSectionMessageStore = SettingsSectionMessageStore()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func saveRuntimeSettings() {
        do {
            var settings = try runtimeSettingsRepository?.loadOrCreateDefault() ?? .default
            settings.schemaVersion = 4
            settings.loop.permissionMode = defaultPermissionMode == .allowAll ? .askToWrite : defaultPermissionMode
            settings.ui.showProviderIcons = showProviderIcons
            settings.ui.richToolDescriptionsEnabled = richToolDescriptionsEnabled
            settings.app.desktopNotificationsEnabled = desktopNotificationsEnabled
            settings.app.sessionNotificationSettings = SessionNotificationSettings(newMessageLevel: sessionNewMessageNotificationLevel)
            settings.app.keepScreenAwake = keepScreenAwake
            settings.app.internalBrowserEnabled = internalBrowserEnabled
            settings.app.httpProxyEnabled = httpProxyEnabled
            settings.app.httpProxyURLString = httpProxyURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.appearance.mode = appearanceMode.rawValue
            settings.input.spellCheckEnabled = spellCheckEnabled
            settings.input.autoSaveDraftsEnabled = autoSaveDraftsEnabled
            settings.input.sessionSpeechTranscriptionEnabled = sessionSpeechTranscriptionEnabled
            settings.input.composerSendShortcut = composerSendShortcut
            settings.shortcuts = shortcutSettings
            settings.permissions.requireApprovalForNetwork = requireApprovalForNetwork
            settings.permissions.requireApprovalForShell = requireApprovalForShell
                // Workspace roots are session-scoped and saved into Session Capsule.
            // Keep runtime-settings.workspace as a legacy fallback/template only.
            settings.workspace.recentWorkspacePaths = recentWorkspacePaths
            settings.preferences.displayName = userDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.preferences.timezone = userTimezone.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.preferences.preferredLanguage = userPreferredLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.preferences.genderIdentity = resolvedUserGenderIdentity().trimmingCharacters(in: .whitespacesAndNewlines)
            settings.preferences.birthDate = userBirthDate.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.preferences.city = userCity.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.preferences.country = userCountry.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.preferences.notes = userPreferenceNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.preferences.defaultSearchEngine = defaultSearchEngine
            try runtimeSettingsRepository?.save(settings)
            applyRuntimeSettingsSideEffects()
            if submittingChatSessionIDs.isEmpty {
                rebuildNativeSessionManagerForActiveSession()
            } else {
                nativeSessionManager?.permissionMode = settings.loop.permissionMode
            }
            settingsSectionMessageStore = SettingsSectionMessageStore()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func scheduleRuntimeSettingsAutosave() {
        guard !isLoadingRuntimeSettings else { return }
        runtimeSettingsAutosaveTask?.cancel()
        runtimeSettingsAutosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.saveRuntimeSettings()
            }
        }
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
        guard hasActivatedRuntimeSettingsSideEffects, desktopNotificationsEnabled, canUseUserNotifications else { return }
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    private func applyKeepScreenAwakeSetting() {
        if keepScreenAwake && !submittingChatSessionIDs.isEmpty {
            guard idleSleepAssertionID == 0 else { return }
            var assertionID = IOPMAssertionID(0)
            let reason = "Connor session is running" as CFString
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &assertionID)
            if result == kIOReturnSuccess {
                idleSleepAssertionID = assertionID
            }
        } else {
            releaseIdleSleepAssertion()
        }
    }

    func resetSessionNotificationSettings() {
        sessionNewMessageNotificationLevel = SessionNotificationSettings.default.newMessageLevel
    }

    func markSessionRead(_ sessionID: String) {
        guard sessionReadStates[sessionID]?.highestLevel != SessionAttentionLevel.none || sessionReadStates[sessionID]?.unreadCount ?? 0 > 0 else { return }
        var state = sessionReadStates[sessionID] ?? .initial()
        state.markRead(messageID: latestMessageID(for: sessionID), at: Date())
        applySessionReadState(state, sessionID: sessionID, persist: true)
    }

    private func markSessionUnread(
        sessionID: String,
        messageID: String,
        preview: String?,
        level: SessionAttentionLevel
    ) {
        var state = sessionReadStates[sessionID] ?? .initial()
        state.markUnread(messageID: messageID, preview: preview, level: level, at: Date())
        applySessionReadState(state, sessionID: sessionID, persist: true)
    }

    private func latestMessageID(for sessionID: String) -> String? {
        if selectedChatSessionID == sessionID, let last = transcript.last { return last.id }
        return chatSessions.first(where: { $0.id == sessionID })?.messages.last?.id
            ?? allChatSessions.first(where: { $0.id == sessionID })?.messages.last?.id
    }

    private func noteSessionUpdate(
        sessionID: String,
        messageID: String?,
        preview: String?,
        notificationBody: String
    ) {
        let level = sessionNewMessageNotificationLevel
        if shouldTreatSessionUpdateAsRead(sessionID: sessionID) {
            var state = sessionReadStates[sessionID] ?? .initial()
            state.markRead(messageID: messageID ?? latestMessageID(for: sessionID), at: Date())
            applySessionReadState(state, sessionID: sessionID, persist: true)
            return
        }
        let unreadMessageID = messageID ?? "attention-event-\(UUID().uuidString)"
        markSessionUnread(sessionID: sessionID, messageID: unreadMessageID, preview: preview, level: level)
        postSessionNotificationIfNeeded(sessionID: sessionID, body: notificationBody, level: level)
    }

    private func notificationPreview(from content: String) -> String {
        let collapsed = content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > 140 else { return collapsed }
        return String(collapsed.prefix(140)) + "…"
    }

    func shouldTreatSessionUpdateAsRead(sessionID: String) -> Bool {
        selection == .agentChat && selectedChatSessionID == sessionID
    }

    private func postSessionNotificationIfNeeded(
        sessionID: String,
        body: String,
        level: SessionAttentionLevel
    ) {
        guard desktopNotificationsEnabled, canUseUserNotifications else { return }
        guard level.shouldRequestSystemNotification else { return }
        guard !shouldTreatSessionUpdateAsRead(sessionID: sessionID) else { return }
        let now = Date()
        if let last = lastSessionNotificationAt[sessionID], now.timeIntervalSince(last) < sameSessionNotificationCooldown {
            return
        }
        lastSessionNotificationAt[sessionID] = now
        let content = UNMutableNotificationContent()
        content.title = "康纳同学：主人，有新消息需要你关注"
        content.body = body
        content.sound = .default
        if level == .interruptive {
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1.0
        }
        content.userInfo = [
            "sessionID": sessionID,
            "attentionLevel": level.rawValue,
            "bundlePath": Bundle.main.bundlePath
        ]
        let request = UNNotificationRequest(identifier: "session-\(sessionID)-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func synchronizeSessionReadStates(from sessions: [AgentSession]) {
        sessionReadStates = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.readState) })
        refreshDockBadge()
    }

    private func applySessionReadState(_ state: SessionReadState, sessionID: String, persist: Bool) {
        sessionReadStates[sessionID] = state
        updateLoadedSessionReadState(sessionID: sessionID, readState: state)
        if persist {
            persistSessionReadState(state, sessionID: sessionID)
        }
        refreshDockBadge()
    }

    private func updateLoadedSessionReadState(sessionID: String, readState: SessionReadState) {
        if let index = chatSessions.firstIndex(where: { $0.id == sessionID }) {
            chatSessions[index].readState = readState
        }
        if let index = allChatSessions.firstIndex(where: { $0.id == sessionID }) {
            allChatSessions[index].readState = readState
        }
        if fallbackChatSession.id == sessionID {
            fallbackChatSession.readState = readState
        }
    }

    private func persistSessionReadState(_ state: SessionReadState, sessionID: String) {
        do {
            let updated = try chatSessionRepository?.updateReadState(sessionID: sessionID, readState: state)
            if let updated {
                updateLoadedSessionReadState(sessionID: updated.id, readState: updated.readState)
            }
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func refreshDockBadge() {
        let count = sessionReadStates.values.reduce(0) { partial, state in
            guard state.highestLevel.shouldCountInDockBadge else { return partial }
            return partial + max(state.unreadCount, 1)
        }
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    private var canUseUserNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    func setUserGenderIdentitySelection(_ selection: String) {
        userGenderIdentitySelection = selection
        if selection == Self.customGenderIdentitySelection {
            userGenderIdentity = userGenderIdentityCustomText
        } else {
            userGenderIdentityCustomText = ""
            userGenderIdentity = selection
        }
        scheduleRuntimeSettingsAutosave()
    }

    func setUserGenderIdentityCustomText(_ text: String) {
        userGenderIdentityCustomText = text
        if userGenderIdentitySelection == Self.customGenderIdentitySelection {
            userGenderIdentity = text
        }
        scheduleRuntimeSettingsAutosave()
    }

    private func applyLoadedGenderIdentity(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        userGenderIdentity = trimmed
        if trimmed.isEmpty {
            userGenderIdentitySelection = ""
            userGenderIdentityCustomText = ""
        } else if Self.genderIdentityPresetValues.contains(trimmed) {
            userGenderIdentitySelection = trimmed
            userGenderIdentityCustomText = ""
        } else {
            userGenderIdentitySelection = Self.customGenderIdentitySelection
            userGenderIdentityCustomText = trimmed
        }
    }

    private func resolvedUserGenderIdentity() -> String {
        if userGenderIdentitySelection == Self.customGenderIdentitySelection {
            return userGenderIdentityCustomText
        }
        return userGenderIdentitySelection
    }

    func setUserBirthDateFromPicker(_ date: Date) {
        userBirthDatePickerDate = date
        userBirthDate = Self.birthDateFormatter.string(from: date)
        scheduleRuntimeSettingsAutosave()
    }

    func clearUserBirthDate() {
        userBirthDate = ""
        scheduleRuntimeSettingsAutosave()
    }

    func refreshSystemPreferenceDefaults() {
        let systemDefaults = AgentRuntimePreferenceSystemDefaults.current()
        if userDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userDisplayName = systemDefaults.displayName
        }
        if userTimezone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userTimezone = systemDefaults.timezone
        }
        if userPreferredLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userPreferredLanguage = systemDefaults.preferredLanguage
        }
        if userCountry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userCountry = systemDefaults.country
        }
    }

    func requestUserLocation() {
        userLocationStatusMessage = "正在请求位置权限…"
        locationCoordinator = UserLocationCoordinator { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let placemark):
                    if let city = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea {
                        self.userCity = city
                    }
                    if let country = placemark.country {
                        self.userCountry = country
                    }
                    self.userLocationStatusMessage = "位置已更新。"
                    self.scheduleRuntimeSettingsAutosave()
                case .failure(let error):
                    self.userLocationStatusMessage = error.localizedDescription
                }
                self.locationCoordinator = nil
            }
        }
        locationCoordinator?.requestLocation()
    }

    func upsertStatusDefinition(_ definition: AgentSessionStatusDefinition) {
        var config = governanceConfig
        let trimmedID = definition.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedID.isEmpty, let index = config.statuses.firstIndex(where: { $0.id == trimmedID }) {
            var updatedDefinition = definition
            updatedDefinition.id = trimmedID
            config.statuses[index] = updatedDefinition
        } else {
            var newDefinition = definition
            newDefinition.id = makeUniqueGovernanceStatusID(existingIDs: Set(config.statuses.map(\.id)), preferredName: definition.name)
            config.statuses.append(newDefinition)
        }
        saveGovernanceConfig(config, successMessage: "状态定义已保存。", section: .statuses)
    }

    func canDeleteStatusDefinition(_ definition: AgentSessionStatusDefinition) -> Bool {
        governanceConfig.statuses.count > 1 && !allChatSessions.contains { $0.governance.status.rawValue == definition.id }
    }

    func deleteStatusDefinition(_ definition: AgentSessionStatusDefinition) {
        guard governanceConfig.statuses.count > 1 else {
            errorMessage = "至少需要保留一个状态。"
            return
        }
        do {
            let sessions = try chatSessionRepository?.loadSessions(filter: .all) ?? allChatSessions
            let sessionsUsingStatus = sessions.filter { $0.governance.status.rawValue == definition.id }
            guard sessionsUsingStatus.isEmpty else {
                errorMessage = "无法删除状态“\(definition.name)”: 仍有 \(sessionsUsingStatus.count) 个会话处于此状态。"
                return
            }
            var config = governanceConfig
            config.statuses.removeAll { $0.id == definition.id }
            saveGovernanceConfig(config, successMessage: "状态“\(definition.name)”已删除。", section: .statuses)
            if case .status(let selectedStatus) = sessionListFilter, selectedStatus.rawValue == definition.id {
                setSessionListFilter(.all, restoreWorkspaceMode: false)
            } else {
                reloadChatSessions(restoreWorkspaceMode: false)
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func makeUniqueGovernanceStatusID(existingIDs: Set<String>, preferredName: String = "") -> String {
        makeUniqueGovernanceSlug(existingIDs: existingIDs, prefix: "status", preferredName: preferredName)
    }

    func upsertLabelDefinition(_ definition: AgentSessionLabelDefinition) {
        var config = governanceConfig
        let trimmedID = definition.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedID.isEmpty, let index = config.labels.firstIndex(where: { $0.id == trimmedID }) {
            var updatedDefinition = definition
            updatedDefinition.id = trimmedID
            config.labels[index] = updatedDefinition
        } else {
            var newDefinition = definition
            newDefinition.id = makeUniqueGovernanceLabelID(existingIDs: Set(config.labels.map(\.id)), preferredName: definition.name)
            config.labels.append(newDefinition)
        }
        saveGovernanceConfig(config, successMessage: "标签定义已保存。", section: .labels)
    }

    func deleteLabelDefinition(_ definition: AgentSessionLabelDefinition) {
        guard let chatSessionRepository else { return }
        do {
            let sessions = try chatSessionRepository.loadSessions(filter: .all)
            var removedFromSessionCount = 0
            for session in sessions where session.governance.labels.contains(where: { $0.id == definition.id }) {
                let remainingLabels = session.governance.labels.filter { $0.id != definition.id }
                _ = try chatSessionRepository.setLabels(sessionID: session.id, labels: remainingLabels)
                removedFromSessionCount += 1
            }

            var config = governanceConfig
            config.labels.removeAll { $0.id == definition.id }
            saveGovernanceConfig(config, successMessage: "标签“\(definition.name)”已删除，并已从 \(removedFromSessionCount) 个会话移除。", section: .labels)
            if case .label(let selectedLabelID) = sessionListFilter, selectedLabelID == definition.id {
                setSessionListFilter(.all, restoreWorkspaceMode: false)
            } else {
                reloadChatSessions(restoreWorkspaceMode: false)
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func makeUniqueGovernanceLabelID(existingIDs: Set<String>, preferredName: String = "") -> String {
        makeUniqueGovernanceSlug(existingIDs: existingIDs, prefix: "label", preferredName: preferredName)
    }

    private func makeUniqueGovernanceSlug(existingIDs: Set<String>, prefix: String, preferredName: String) -> String {
        let allowedScalars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        let slug = preferredName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .unicodeScalars
            .map { scalar -> Character in
                allowedScalars.contains(scalar) ? Character(scalar) : "-"
            }
            .reduce(into: "") { partial, character in
                if character == "-", partial.last == "-" { return }
                partial.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .replacingOccurrences(of: "-", with: "_")
        let base = slug.isEmpty ? "\(prefix)_\(shortGovernanceIDFragment())" : slug
        var candidate = base
        var suffix = 2
        while existingIDs.contains(candidate) {
            candidate = "\(base)_\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func shortGovernanceIDFragment() -> String {
        String(UUID().uuidString.lowercased().prefix(8))
    }

    private func saveGovernanceConfig(_ config: AppSessionGovernanceConfig, successMessage: String, section: ConnorSettingsSection) {
        do {
            let normalizedConfig = AppSessionGovernanceConfig(statuses: config.statuses, labels: config.labels)
            try governanceConfigRepository?.save(normalizedConfig)
            governanceConfig = normalizedConfig
            chatSessionRepository?.governanceConfig = normalizedConfig
            automationConfig = try automationRepository?.loadOrCreateDefault(governanceConfig: normalizedConfig) ?? automationConfig
            setSettingsMessage(successMessage, for: section)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    var primaryWorkspaceRootDraft: WorkspaceRootDraft? {
        workspaceRoots.first(where: \.isPrimary) ?? workspaceRoots.first
    }

    func addWorkspaceRoot(path rawPath: String) {
        guard AppWorkspaceRootDraftEditor.addRoot(path: rawPath, to: &workspaceRoots, makePrimary: false) else {
            workspaceRootPathInput = ""
            return
        }
        defaultWorkingDirectoryPath = workspaceRoots.first(where: \.isPrimary)?.path ?? ""
        workspaceRootPathInput = ""
        saveWorkspaceDraftsToCurrentSession()
    }

    func addWorkspaceRootAndSetPrimary(path rawPath: String) {
        guard AppWorkspaceRootDraftEditor.addRoot(path: rawPath, to: &workspaceRoots, makePrimary: true) else {
            workspaceRootPathInput = ""
            return
        }
        defaultWorkingDirectoryPath = workspaceRoots.first(where: \.isPrimary)?.path ?? ""
        workspaceRootPathInput = ""
        rememberWorkspacePath(defaultWorkingDirectoryPath)
        saveWorkspaceDraftsToCurrentSession()
    }

    private func rememberWorkspacePath(_ path: String) {
        do {
            var settings = try runtimeSettingsRepository?.loadOrCreateDefault() ?? .default
            settings.workspace.rememberWorkspacePath(path)
            recentWorkspacePaths = settings.workspace.recentWorkspacePaths
            try runtimeSettingsRepository?.save(settings)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func clearRecentWorkspacePaths() {
        do {
            var settings = try runtimeSettingsRepository?.loadOrCreateDefault() ?? .default
            settings.workspace.clearRecentWorkspacePaths()
            recentWorkspacePaths = settings.workspace.recentWorkspacePaths
            try runtimeSettingsRepository?.save(settings)
        } catch {
            errorMessage = String(describing: error)
        }
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
        AppWorkspaceRootDraftEditor.removeRoot(id: id, from: &workspaceRoots)
        defaultWorkingDirectoryPath = workspaceRoots.first(where: \.isPrimary)?.path ?? ""
        saveWorkspaceDraftsToCurrentSession()
    }

    func setPrimaryWorkspaceRoot(id: String) {
        AppWorkspaceRootDraftEditor.setPrimaryRoot(id: id, in: &workspaceRoots)
        defaultWorkingDirectoryPath = workspaceRoots.first(where: \.isPrimary)?.path ?? ""
        saveWorkspaceDraftsToCurrentSession()
    }

    func resetRuntimeSettings() {
        do {
            try runtimeSettingsRepository?.save(.default)
            loadRuntimeSettings()
            setSettingsMessage("设置已恢复默认值。", for: .app)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func reloadChatSessionsIfNeededAfterInitialLoad(restoreWorkspaceMode shouldRestoreWorkspaceMode: Bool = true) {
        guard !hasLoadedInitialChatSessions else { return }
        reloadChatSessions(restoreWorkspaceMode: shouldRestoreWorkspaceMode)
    }

    private func rebuildSessionSearchIndexSoon(sessions: [AgentSession]) {
        guard let sessionSearchIndexService else { return }
        Task { try? await sessionSearchIndexService.rebuild(sessions: sessions) }
    }

    func reloadChatSessions(restoreWorkspaceMode shouldRestoreWorkspaceMode: Bool = true) {
        hasLoadedInitialChatSessions = true
        guard let chatSessionRepository else {
            replaceSelectedChatTranscript(activeChatTranscript)
            chatSessions = [activeChatSession]
            allChatSessions = [activeChatSession]
            synchronizeSessionReadStates(from: allChatSessions)
            selectedChatSessionID = activeChatSession.id
            return
        }
        do {
            var sessions = try chatSessionRepository.loadSessions(filter: sessionListFilter)
            if sessions.isEmpty, sessionListFilter == .all {
                let session = try chatSessionRepository.createSession()
                sessions = [session]
            }
            chatSessions = sessions
            allChatSessions = try chatSessionRepository.loadSessions(filter: .all)
            rebuildSessionSearchIndexSoon(sessions: allChatSessions)
            synchronizeSessionReadStates(from: allChatSessions)
            let selectedID = selectedChatSessionIDVisibleInCurrentFilter(sessions: sessions)
            selectedChatSessionID = selectedID
            if let selectedID, let session = try chatSessionRepository.loadSession(id: selectedID) {
                try loadSessionCapsule(sessionID: selectedID)
                try loadBackgroundTasks(sessionID: selectedID)
                fallbackChatSession = session
                nativeSessionManager = makeNativeSessionManager(for: session)
                replaceSelectedChatTranscript(session.messages)
                restoreChatInputDraft(for: selectedID)
                refreshSelectedSubmittingState()
                if let cachedTimeline = agentEventTimelinesBySessionID[selectedID] {
                    agentEventTimeline = cachedTimeline
                } else {
                    try restoreLatestAgentEventTimeline(sessionID: selectedID)
                }
                latestChatSummary = try chatSessionRepository.loadLatestSummary(sessionID: selectedID)
                selectedSessionArtifactDirectories = try chatSessionRepository.artifactDirectories(sessionID: selectedID)
                if shouldRestoreWorkspaceMode {
                    restoreWorkspaceMode(for: selectedID)
                }
            } else {
                clearSelectedChatSessionDetail()
            }
            chatSummaryMessage = nil
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func selectedChatSessionIDVisibleInCurrentFilter(sessions: [AgentSession]) -> String? {
        if let selectedChatSessionID {
            return sessions.contains(where: { $0.id == selectedChatSessionID }) ? selectedChatSessionID : nil
        }
        return sessionListFilter == .all ? sessions.first?.id : nil
    }

    private func replaceSelectedChatTranscript(_ messages: [AgentMessage]) {
        transcript = messages
        selectedChatTranscriptRevision += 1
    }

    private func clearSelectedChatSessionDetail() {
        selectedChatSessionID = nil
        nativeSessionManager = nil
        replaceSelectedChatTranscript([])
        agentEventTimeline = []
        latestChatSummary = nil
        selectedSessionArtifactDirectories = nil
        chatSummaryMessage = nil
        lastContext = nil
        lastPromptInspection = nil
        isBrowserVisible = false
        browserWorkspaceSessionID = nil
        refreshSelectedSubmittingState()
    }

    func newChatSession() {
        guard let chatSessionRepository else { return }
        _ = stopSpeechTranscriptionIfRunningForLeavingSession(selectedChatSessionID)
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
            try loadBackgroundTasks(sessionID: session.id)
            fallbackChatSession = session
            nativeSessionManager = makeNativeSessionManager(for: session)
            replaceSelectedChatTranscript([])
            restoreChatInputDraft(for: session.id)
            refreshSelectedSubmittingState()
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
    };

    func newNoteSession() {
        guard let chatSessionRepository else { return }
        _ = stopSpeechTranscriptionIfRunningForLeavingSession(selectedChatSessionID)
        rememberCurrentWorkspaceMode()
        do {
            let session = try chatSessionRepository.createSession()
            var noteSession = session
            noteSession.governance.kind = .note
            noteSession.title = "未命名的笔记"
            _ = try chatSessionRepository.saveSession(noteSession)
            selectedChatSessionID = noteSession.id
            agentEventTimelinesByProcessKey.removeAll(keepingCapacity: true)
            isBrowserVisible = false
            browserWorkspaceSessionID = nil
            rememberWorkspaceMode(.conversation, for: noteSession.id)
            selectedSessionArtifactDirectories = try chatSessionRepository.artifactDirectories(sessionID: noteSession.id)
            try loadSessionCapsule(sessionID: noteSession.id)
            try loadBackgroundTasks(sessionID: noteSession.id)
            fallbackChatSession = noteSession
            nativeSessionManager = makeNativeSessionManager(for: noteSession)
            replaceSelectedChatTranscript([])
            restoreChatInputDraft(for: noteSession.id)
            refreshSelectedSubmittingState()
            agentEventTimeline = []
            agentEventTimelinesBySessionID[noteSession.id] = []
            latestChatSummary = nil
            chatSummaryMessage = nil
            lastPromptInspection = nil
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
        if let index = chatSessions.firstIndex(where: { $0.id == updated.id }) {
            chatSessions[index] = updated
        }
        if let index = allChatSessions.firstIndex(where: { $0.id == updated.id }) {
            allChatSessions[index] = updated
        }
        if selectedChatSessionID == updated.id {
            fallbackChatSession = updated
            nativeSessionManager = makeNativeSessionManager(for: updated)
            replaceSelectedChatTranscript(updated.messages)
        }
    }

    func backgroundTasks(for sessionID: String?) -> [AppSessionBackgroundTask] {
        guard let sessionID else { return [] }
        return backgroundTasksBySessionID[sessionID, default: []]
            .sorted { $0.createdAt > $1.createdAt }
    }

    var activeSessionBackgroundTasks: [AppSessionBackgroundTask] {
        backgroundTasks(for: selectedChatSessionID)
    }

    var hasRunningActiveSessionBackgroundTask: Bool {
        activeSessionBackgroundTasks.contains { $0.status == .queued || $0.status == .running }
    }

    func hasRunningBackgroundTask(sessionID: String) -> Bool {
        backgroundTasksBySessionID[sessionID, default: []]
            .contains { $0.status == .queued || $0.status == .running }
    }

    var isSpeechTranscriptionRunningForSelectedSession: Bool {
        speechTranscriptionCoordinator.isRunning(sessionID: selectedChatSessionID)
    }

    func toggleSpeechTranscriptionForSelectedSession() {
        if isSpeechTranscriptionRunningForSelectedSession {
            finishSpeechTranscriptionForSelectedSession()
        } else {
            beginSpeechTranscriptionForSelectedSession()
        }
    }

    func beginSpeechTranscriptionForSelectedSession(speechInsertionRange: NSRange? = nil) {
        guard sessionSpeechTranscriptionEnabled else { return }
        let task = speechTranscriptionCoordinator.beginHoldToTalk(
            selectedSessionID: selectedChatSessionID,
            currentDraft: currentSelectedChatInputDraftForSpeech(),
            speechInsertionRange: speechInsertionRange,
            setDraft: { [weak self] sessionID, draft in
                self?.setSpeechTranscriptionDraft(draft, for: sessionID)
            },
            setProvisionalTranscript: { [weak self] sessionID, transcript in
                self?.setSpeechProvisionalTranscript(transcript, for: sessionID)
            }
        )
        syncSpeechTranscriptionState()
        upsertSpeechTranscriptionBackgroundTask(task)
    }

    func finishSpeechTranscriptionForSelectedSession() {
        let task = speechTranscriptionCoordinator.finishHoldToTalk()
        syncSpeechTranscriptionState()
        upsertSpeechTranscriptionBackgroundTask(task)
    }

    @discardableResult
    private func stopSpeechTranscriptionIfRunningForLeavingSession(_ sessionID: String?) -> AppSessionBackgroundTask? {
        let task = speechTranscriptionCoordinator.stopIfRunningForLeavingSession(sessionID)
        if selectedChatSessionID == sessionID { speechProvisionalTranscript = nil }
        syncSpeechTranscriptionState()
        upsertSpeechTranscriptionBackgroundTask(task)
        return task
    }

    @discardableResult
    private func stopSpeechTranscriptionIfRunningForDeletedSession(_ sessionID: String?) -> AppSessionBackgroundTask? {
        let task = speechTranscriptionCoordinator.stopIfRunningForDeletedSession(sessionID)
        if selectedChatSessionID == sessionID { speechProvisionalTranscript = nil }
        syncSpeechTranscriptionState()
        upsertSpeechTranscriptionBackgroundTask(task)
        return task
    }

    private func stopSpeechTranscriptionForDisabledSetting() {
        guard speechTranscriptionStatus.isRunning else { return }
        let task = speechTranscriptionCoordinator.stop(reason: .appLifecycle)
        speechProvisionalTranscript = nil
        syncSpeechTranscriptionState()
        upsertSpeechTranscriptionBackgroundTask(task)
    }

    private func setSpeechTranscriptionDraft(_ draft: String, for sessionID: String) {
        chatInputDraftsBySessionID[sessionID] = draft
        if selectedChatSessionID == sessionID {
            setChatInputDraft(draft, for: sessionID)
        }
    }

    private func setSpeechProvisionalTranscript(_ transcript: String?, for sessionID: String) {
        guard selectedChatSessionID == sessionID else { return }
        speechProvisionalTranscript = transcript?.isEmpty == true ? nil : transcript
    }

    private func syncSpeechTranscriptionState() {
        speechTranscriptionStatus = speechTranscriptionCoordinator.status
    }

    private func upsertSpeechTranscriptionBackgroundTask(_ task: AppSessionBackgroundTask?) {
        guard let task else { return }
        upsertBackgroundTask(task)
    }

    private func runningBackgroundTasksForDeletionCheck(sessionID: String) throws -> [AppSessionBackgroundTask] {
        let persistedTasks = try chatSessionRepository?.loadBackgroundTasks(sessionID: sessionID).map(AppSessionBackgroundTask.init(persisted:)) ?? []
        let memoryTasks = backgroundTasksBySessionID[sessionID, default: []]
        return (persistedTasks + memoryTasks).filter { $0.status == .queued || $0.status == .running }
    }

    func canDeleteChatSession(_ sessionID: String) -> Bool {
        (try? runningBackgroundTasksForDeletionCheck(sessionID: sessionID).isEmpty) ?? !hasRunningBackgroundTask(sessionID: sessionID)
    }

    private func loadBackgroundTasks(sessionID: String) throws {
        guard let chatSessionRepository else { return }
        let activeInMemoryTaskIDs = Set(
            backgroundTasksBySessionID[sessionID, default: []]
                .filter { $0.status == .queued || $0.status == .running }
                .map(\.id)
        )
        var tasks = try chatSessionRepository.loadBackgroundTasks(sessionID: sessionID)
            .map(AppSessionBackgroundTask.init(persisted:))
        var didInterruptActiveTasks = false
        for index in tasks.indices where (tasks[index].status == .queued || tasks[index].status == .running) && !activeInMemoryTaskIDs.contains(tasks[index].id) {
            tasks[index].status = .interrupted
            tasks[index].updatedAt = Date()
            tasks[index].errorMessage = "应用重启或会话恢复后，旧后台任务不会自动继续执行。"
            didInterruptActiveTasks = true
            try chatSessionRepository.saveBackgroundTask(tasks[index].persisted)
        }
        backgroundTasksBySessionID[sessionID] = tasks
        if didInterruptActiveTasks || !hasRunningTitleTask(sessionID: sessionID) {
            regeneratingTitleSessionIDs.remove(sessionID)
        }
    }

    func regenerateChatSessionTitle(_ sessionID: String) {
        guard !hasRunningTitleTask(sessionID: sessionID) else { return }
        let task = enqueueBackgroundTask(
            sessionID: sessionID,
            title: "重新生成会话标题",
            detail: "根据此会话中的所有用户 Prompt 生成 20 字以内标题。",
            kind: "title_generation"
        )
        runTitleGenerationTask(taskID: task.id, sessionID: sessionID)
    }

    private func hasRunningTitleTask(sessionID: String) -> Bool {
        backgroundTasksBySessionID[sessionID, default: []].contains { task in
            task.kind == "title_generation" && (task.status == .queued || task.status == .running)
        }
    }

    @discardableResult
    private func enqueueBackgroundTask(sessionID: String, title: String, detail: String, kind: String = "generic") -> AppSessionBackgroundTask {
        let task = AppSessionBackgroundTask(sessionID: sessionID, kind: kind, title: title, detail: detail)
        backgroundTasksBySessionID[sessionID, default: []].append(task)
        do {
            try chatSessionRepository?.saveBackgroundTask(task.persisted)
        } catch {
            errorMessage = String(describing: error)
        }
        if kind == "title_generation" { regeneratingTitleSessionIDs.insert(sessionID) }
        return task
    }

    private func updateBackgroundTask(sessionID: String, taskID: String, status: AppSessionBackgroundTaskStatus, detail: String? = nil, errorMessage: String? = nil) {
        guard var tasks = backgroundTasksBySessionID[sessionID], let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = status
        tasks[index].updatedAt = Date()
        if let detail { tasks[index].detail = detail }
        tasks[index].errorMessage = errorMessage
        backgroundTasksBySessionID[sessionID] = tasks
        do {
            try chatSessionRepository?.saveBackgroundTask(tasks[index].persisted)
        } catch {
            self.errorMessage = String(describing: error)
        }
        if !hasRunningTitleTask(sessionID: sessionID) {
            regeneratingTitleSessionIDs.remove(sessionID)
        }
    }

    private func upsertBackgroundTask(_ task: AppSessionBackgroundTask) {
        var tasks = backgroundTasksBySessionID[task.sessionID, default: []]
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
        backgroundTasksBySessionID[task.sessionID] = tasks
        do {
            try chatSessionRepository?.saveBackgroundTask(task.persisted)
        } catch {
            errorMessage = String(describing: error)
        }
        if !hasRunningTitleTask(sessionID: task.sessionID) {
            regeneratingTitleSessionIDs.remove(task.sessionID)
        }
    }

    private func runTitleGenerationTask(taskID: String, sessionID: String) {
        updateBackgroundTask(sessionID: sessionID, taskID: taskID, status: .running)
        Task {
            do {
                guard let chatSessionRepository,
                      let session = try chatSessionRepository.loadSession(id: sessionID)
                else { return }
                let userPrompts = session.messages
                    .filter { $0.role == .user }
                    .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                guard !userPrompts.isEmpty else {
                    renameChatSession(sessionID, title: "新对话")
                    updateBackgroundTask(sessionID: sessionID, taskID: taskID, status: .succeeded, detail: "没有用户 Prompt，已使用默认标题。")
                    return
                }
                let title = try await generateTitleFromUserPrompts(userPrompts, sessionID: sessionID)
                renameChatSession(sessionID, title: title)
                updateBackgroundTask(sessionID: sessionID, taskID: taskID, status: .succeeded, detail: "已更新为：\(title)")
            } catch {
                updateBackgroundTask(sessionID: sessionID, taskID: taskID, status: .failed, errorMessage: String(describing: error))
                errorMessage = String(describing: error)
            }
        }
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
            regeneratingTitleSessionIDs.remove(sessionID)
            backgroundTasksBySessionID.removeValue(forKey: sessionID)
            chatInputDraftsBySessionID.removeValue(forKey: sessionID)
            pendingAttachmentRefsBySessionID.removeValue(forKey: sessionID)
            agentEventTimelinesBySessionID.removeValue(forKey: sessionID)
            agentEventTimelinesByProcessKey = agentEventTimelinesByProcessKey.filter { key, _ in !key.hasPrefix("\(sessionID):") }
            if selectedChatSessionID == sessionID {
                selectedChatSessionID = nil
                replaceSelectedChatTranscript([])
                agentEventTimeline = []
                latestChatSummary = nil
                selectedSessionArtifactDirectories = nil
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

    private func recordBrowserWebViewEviction(key: BrowserLiveWebViewKey, webView: WKWebView, metadata: BrowserLiveWebViewStore.SnapshotMetadata) {
        var snapshot = browserWorkspaceSnapshotsBySessionID[key.sessionID] ?? AppBrowserStateSnapshot()
        guard let index = snapshot.tabs.firstIndex(where: { $0.id == key.tabID }) else { return }
        var tab = snapshot.tabs[index]
        tab.title = webView.title ?? tab.title
        tab.currentURLString = webView.url?.absoluteString ?? tab.currentURLString
        tab.isLoading = false
        tab.canGoBack = webView.canGoBack
        tab.canGoForward = webView.canGoForward
        tab.lastAccessedAt = Date()
        tab.scrollX = metadata.scrollX ?? tab.scrollX
        tab.scrollY = metadata.scrollY ?? tab.scrollY
        tab.viewportWidth = metadata.viewportWidth ?? tab.viewportWidth
        tab.viewportHeight = metadata.viewportHeight ?? tab.viewportHeight
        tab.contentFingerprint = metadata.contentFingerprint ?? tab.contentFingerprint
        tab.focusedElementHint = metadata.focusedElementHint ?? tab.focusedElementHint
        tab.restorationStatus = .evicted
        snapshot.tabs[index] = tab
        saveBrowserWorkspaceSnapshot(snapshot, for: key.sessionID)
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

    // MARK: - Browser Bookmarks

    func loadBrowserBookmarks() {
        guard let store = browserBookmarkStore else { return }
        browserBookmarkRecords = store.loadBookmarks()
        applyBrowserBookmarkFilter()
    }

    var browserBookmarkGroupNames: [String] {
        let names = Set(browserBookmarkRecords.map { $0.groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? BrowserBookmarkRecord.defaultGroupName : $0.groupName })
        return names.sorted { lhs, rhs in
            if lhs == BrowserBookmarkRecord.defaultGroupName { return true }
            if rhs == BrowserBookmarkRecord.defaultGroupName { return false }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    func toggleBrowserBookmarksPanel() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isBrowserBookmarksPanelVisible.toggle()
            if isBrowserBookmarksPanelVisible { isBrowserHistoryPanelVisible = false }
        }
        if isBrowserBookmarksPanelVisible { loadBrowserBookmarks() }
    }

    func addBrowserBookmark(url: String, title: String, groupName: String? = nil) {
        guard let store = browserBookmarkStore else { return }
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty,
              !trimmedURL.hasPrefix("connor://"),
              !trimmedURL.hasPrefix("about:"),
              !trimmedURL.hasPrefix("data:")
        else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedGroup = groupName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookmark = BrowserBookmarkRecord(
            url: trimmedURL,
            title: trimmedTitle.isEmpty ? (URL(string: trimmedURL)?.host ?? trimmedURL) : trimmedTitle,
            groupName: resolvedGroup?.isEmpty == false ? resolvedGroup! : BrowserBookmarkRecord.defaultGroupName,
            createdAt: Date(),
            updatedAt: Date()
        )
        store.upsertBookmark(bookmark)
        loadBrowserBookmarks()
    }

    func toggleBrowserBookmark(url: String, title: String, groupName: String? = nil) {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }
        if isBrowserBookmarked(url: trimmedURL) {
            browserBookmarkStore?.deleteBookmark(url: trimmedURL)
            loadBrowserBookmarks()
        } else {
            addBrowserBookmark(url: trimmedURL, title: title, groupName: groupName)
        }
    }

    func isBrowserBookmarked(url: String) -> Bool {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return false }
        return browserBookmarkRecords.contains { $0.url == trimmedURL }
    }

    func filterBrowserBookmarks(query: String, groupName: String? = nil) {
        selectedBrowserBookmarkGroupName = groupName
        applyBrowserBookmarkFilter(query: query)
    }

    func deleteBrowserBookmark(_ id: UUID) {
        browserBookmarkStore?.deleteBookmark(id: id)
        loadBrowserBookmarks()
    }

    func navigateToBookmark(_ bookmark: BrowserBookmarkRecord) {
        guard let url = URL(string: bookmark.url) else { return }
        openURLInCurrentChatBrowser(url)
    }

    private func applyBrowserBookmarkFilter(query: String = "") {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let selectedGroup = selectedBrowserBookmarkGroupName?.trimmingCharacters(in: .whitespacesAndNewlines)
        filteredBrowserBookmarkRecords = browserBookmarkRecords.filter { bookmark in
            let matchesGroup = selectedGroup?.isEmpty != false || bookmark.groupName == selectedGroup
            let matchesQuery = trimmedQuery.isEmpty
                || bookmark.url.lowercased().contains(trimmedQuery)
                || bookmark.title.lowercased().contains(trimmedQuery)
                || bookmark.groupName.lowercased().contains(trimmedQuery)
            return matchesGroup && matchesQuery
        }
    }

    // MARK: - Browser History

    func loadBrowserHistory() {
        guard let store = browserHistoryStore else { return }
        browserHistoryRecords = store.loadHistory()
        filteredBrowserHistoryRecords = browserHistoryRecords
        Task { @MainActor in
            try? await rebuildBrowserHistorySearchIndexIfNeeded()
        }
    }

    func recordBrowserHistory(url: String, title: String, sessionID: String) {
        guard let store = browserHistoryStore else { return }
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty,
              !trimmedURL.hasPrefix("connor://"),
              !trimmedURL.hasPrefix("about:"),
              !trimmedURL.hasPrefix("data:")
        else { return }
        let sessionTitle = sessionTitleForHistory(sessionID: sessionID)
        let record = BrowserHistoryRecord(
            url: trimmedURL,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            sessionID: sessionID,
            sessionTitle: sessionTitle,
            contentFetchStatus: .pending
        )
        guard let appendedRecord = store.appendRecord(record) else { return }
        browserHistoryRecords = store.loadHistory()
        applyBrowserHistoryFilter()
        indexBrowserHistoryRecord(appendedRecord)
        fetchContentForBrowserHistoryRecord(appendedRecord)
    }

    private func fetchContentForBrowserHistoryRecord(_ record: BrowserHistoryRecord) {
        guard let store = browserHistoryStore else { return }
        let recordID = record.id
        guard browserHistoryContentFetchTasksByID[recordID] == nil else { return }
        let url = record.url
        let task = Task.detached(priority: .utility) {
            let tool = NativeWebFetchTool()
            let arguments = AgentToolArguments(values: [
                "url": .string(url),
                "extract_mode": .string("markdown"),
                "render_mode": .string("auto"),
                "timeout_ms": .int(60_000)
            ])
            let context = AgentToolExecutionContext(
                runID: "browser-history-content-fetch-\(recordID.uuidString)",
                sessionID: record.sessionID,
                groupID: "browser-history",
                userPrompt: "Fetch browser history page content",
                toolCallID: UUID().uuidString,
                policyEngine: AgentPolicyEngine(permissionMode: .allowAll),
                approvedCapabilities: [.externalNetwork]
            )
            do {
                let result = try await tool.execute(arguments: arguments, context: context)
                guard !Task.isCancelled else { return }
                store.updateContent(id: recordID, markdown: result.contentText, status: .fetched)
            } catch {
                guard !Task.isCancelled else { return }
                store.updateContent(id: recordID, markdown: nil, status: .failed, error: String(describing: error))
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.browserHistoryContentFetchTasksByID[recordID] = nil
                self.loadBrowserHistory()
            }
        }
        browserHistoryContentFetchTasksByID[recordID] = task
    }

    func toggleBrowserHistoryPanel() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isBrowserHistoryPanelVisible.toggle()
            if isBrowserHistoryPanelVisible { isBrowserBookmarksPanelVisible = false }
        }
        if isBrowserHistoryPanelVisible {
            loadBrowserHistory()
        }
    }

    func filterBrowserHistory(query: String) {
        browserHistorySearchQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            filteredBrowserHistoryRecords = browserHistoryRecords
        } else if let store = browserHistoryStore {
            filteredBrowserHistoryRecords = store.searchHistory(query: trimmed)
        } else {
            filteredBrowserHistoryRecords = browserHistoryRecords.filter { browserHistoryRecord($0, matches: trimmed) }
        }
    }

    func deleteBrowserHistoryRecord(_ id: UUID) {
        browserHistoryStore?.deleteRecord(id: id)
        deleteBrowserHistorySearchRecord(id: id)
        loadBrowserHistory()
    }

    func clearBrowserHistory() {
        browserHistoryStore?.clearHistory()
        clearBrowserHistorySearchIndex()
        browserHistoryRecords = []
        filteredBrowserHistoryRecords = []
        browserHistorySearchQuery = ""
    }

    func navigateToHistoryRecord(_ record: BrowserHistoryRecord) {
        guard let url = URL(string: record.url) else {
            errorMessage = "这条浏览历史没有可打开的 URL。"
            return
        }
        let planner = BrowserExternalOpenPlanner()
        if focusExistingBrowserTabIfPresent(urlString: record.url, preferredSessionID: record.sessionID, planner: planner) {
            errorMessage = nil
            return
        }
        if browserHistorySessionExists(record.sessionID) {
            if record.sessionID != selectedChatSessionID {
                selectChatSession(record.sessionID)
            }
            openURLInCurrentChatBrowser(url)
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
            selectedChatSessionID = session.id
            agentEventTimelinesByProcessKey.removeAll(keepingCapacity: true)
            browserWorkspaceSessionID = nil
            selectedSessionArtifactDirectories = try chatSessionRepository.artifactDirectories(sessionID: session.id)
            try loadSessionCapsule(sessionID: session.id)
            try loadBackgroundTasks(sessionID: session.id)
            fallbackChatSession = session
            nativeSessionManager = makeNativeSessionManager(for: session)
            replaceSelectedChatTranscript([])
            restoreChatInputDraft(for: session.id)
            refreshSelectedSubmittingState()
            agentEventTimeline = []
            agentEventTimelinesBySessionID[session.id] = []
            latestChatSummary = nil
            chatSummaryMessage = nil
            lastPromptInspection = nil
            reloadChatSessions(restoreWorkspaceMode: false)
            selectedChatSessionID = session.id
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

    private func sessionTitleForHistory(sessionID: String) -> String {
        if let session = allChatSessions.first(where: { $0.id == sessionID }) {
            return session.title
        }
        if let session = chatSessions.first(where: { $0.id == sessionID }) {
            return session.title
        }
        return sessionID
    }

    private func applyBrowserHistoryFilter() {
        filterBrowserHistory(query: browserHistorySearchQuery)
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
            agentEventTimelinesBySessionID[sessionID] = []
            agentEventTimeline = []
            return
        }

        let runs = try chatSessionRepository.loadRuns(
            sessionID: sessionID,
            statuses: [.completed, .failed, .cancelled],
            limit: 10
        )
        for run in runs {
            let restored = presentations(from: try chatSessionRepository.loadRunEvents(runID: run.id, limit: nil))
            if !restored.isEmpty {
                agentEventTimelinesBySessionID[sessionID] = restored
                scheduleActivityTimelineCacheSave(sessionID: sessionID, timeline: restored)
                agentEventTimeline = restored
                return
            }
        }

        let cachedTimeline = try chatSessionRepository.loadActivityTimelineCache(sessionID: sessionID)
        if !cachedTimeline.isEmpty {
            agentEventTimelinesBySessionID[sessionID] = cachedTimeline
            agentEventTimeline = cachedTimeline
            return
        }

        let recentEvents = try chatSessionRepository.loadRecentJournalEvents(sessionID: sessionID, limit: nil)
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
                scheduleActivityTimelineCacheSave(sessionID: sessionID, timeline: restored)
                agentEventTimeline = restored
                return
            }
        }

        agentEventTimelinesBySessionID[sessionID] = []
        agentEventTimeline = []
    }

    func openSessionFromNotification(_ sessionID: String) {
        selection = .agentChat
        sessionSearchQuery = ""
        selectChatSession(sessionID)
    }

    func selectChatSession(_ sessionID: String) {
        guard let chatSessionRepository else { return }
        if selectedChatSessionID != sessionID {
            _ = stopSpeechTranscriptionIfRunningForLeavingSession(selectedChatSessionID)
        }
        rememberCurrentWorkspaceMode()
        do {
            guard let session = try chatSessionRepository.loadSession(id: sessionID) else { return }
            selectedChatSessionID = session.id
            markSessionRead(session.id)
            agentEventTimelinesByProcessKey.removeAll(keepingCapacity: true)
            try loadSessionCapsule(sessionID: session.id)
            try loadBackgroundTasks(sessionID: session.id)
            _ = ensureSessionLLMOverride(sessionID: session.id)
            fallbackChatSession = session
            nativeSessionManager = makeNativeSessionManager(for: session)
            replaceSelectedChatTranscript(session.messages)
            restoreChatInputDraft(for: session.id)
            refreshSelectedSubmittingState()
            if let cachedTimeline = agentEventTimelinesBySessionID[session.id] {
                agentEventTimeline = cachedTimeline
            } else {
                try restoreLatestAgentEventTimeline(sessionID: session.id)
            }
            latestChatSummary = try chatSessionRepository.loadLatestSummary(sessionID: session.id)
            selectedSessionArtifactDirectories = try chatSessionRepository.artifactDirectories(sessionID: session.id)
            restoreWorkspaceMode(for: session.id)
            syncLLMModelDisplayFromSession(sessionID)
            chatSummaryMessage = nil
            lastContext = nil
            lastPromptInspection = nil
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func setSessionListFilter(_ filter: AgentSessionListFilter, restoreWorkspaceMode: Bool = true) {
        sessionListFilter = filter
        reloadChatSessions(restoreWorkspaceMode: restoreWorkspaceMode)
    }

    func setSelectedSessionStatus(_ status: AgentSessionStatus) {
        guard let selectedChatSessionID else { return }
        setChatSessionStatus(selectedChatSessionID, status: status)
    }

    func setChatSessionStatus(_ sessionID: String, status: AgentSessionStatus) {
        guard let chatSessionRepository else { return }
        do {
            let previousStatus = try chatSessionRepository.loadSession(id: sessionID)?.governance.status
            let session = try chatSessionRepository.setStatus(sessionID: sessionID, status: status)
            if selectedChatSessionID == sessionID {
                self.selectedChatSessionID = session.id
                fallbackChatSession = session
            }
            reloadChatSessions()
            appendGovernanceEvent(.sessionStatusChanged(AgentSessionGovernanceEvent(sessionID: session.id, message: "状态已更新为 \(status.displayName)", status: status)))
            evaluateAutomation(ProductOSAutomationEventContext(triggerKind: .sessionStatusChanged, sessionID: session.id, status: status))
            dispatchTaskSessionStatusChanged(sessionID: session.id, fromStatus: previousStatus?.rawValue, toStatus: status.rawValue)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func dispatchTaskSessionStatusChanged(sessionID: String, fromStatus: String?, toStatus: String) {
        guard let taskManagementRepository else { return }
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
                reloadTaskManagementPresentation()
            } catch {
                errorMessage = String(describing: error)
            }
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
        guard let selectedChatSessionID else { return }
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
            if selectedChatSessionID == sessionID {
                fallbackChatSession = updated
            }
            reloadChatSessions()
            appendGovernanceEvent(.sessionLabelsChanged(AgentSessionGovernanceEvent(sessionID: updated.id, message: "标签已更新：\(updated.governance.labels.map(\.id).joined(separator: ", "))", labels: updated.governance.labels)))
            evaluateAutomation(ProductOSAutomationEventContext(triggerKind: didRemove ? .sessionLabelRemoved : .sessionLabelAdded, sessionID: updated.id, labelID: labelID))
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

    func reloadPendingApprovals() {
        do {
            pendingApprovals = try pendingApprovalRepository?.loadPending() ?? []
            autoApproveCurrentPolicyPendingApprovals()
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
        agentPermissionMode = .trustedWrite
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
            let didSendToLiveBackend: Bool
            if let resolved, let backend = backendForPendingApproval(resolved) {
                try await backend.resolveApproval(resolved, status: status, reason: reason, actor: actor)
                didSendToLiveBackend = true
            } else {
                didSendToLiveBackend = false
            }
            reloadPendingApprovals()
            switch status {
            case .approved:
                lastPendingApprovalResultSummary = didSendToLiveBackend
                    ? "已批准权限请求 \(approval.requestID)，并写入审计、timeline，且已向当前运行中的 agent run 发送 resume。"
                    : "已批准权限请求 \(approval.requestID)，并写入审计、timeline；但当前未找到仍在线等待的 run，未发送 resume。请重试该会话请求。"
            case .denied:
                lastPendingApprovalResultSummary = didSendToLiveBackend
                    ? "已拒绝权限请求 \(approval.requestID)，并写入审计、timeline，且已向当前运行中的 agent run 发送 deny。"
                    : "已拒绝权限请求 \(approval.requestID)，并写入审计、timeline；但当前未找到仍在线等待的 run。"
            case .cancelled:
                lastPendingApprovalResultSummary = didSendToLiveBackend
                    ? "已取消权限请求 \(approval.requestID)，并写入审计、timeline，且已向当前运行中的 agent run 发送 cancel/deny。"
                    : "已取消权限请求 \(approval.requestID)，并写入审计、timeline；但当前未找到仍在线等待的 run。"
            case .pending:
                lastPendingApprovalResultSummary = "权限请求 \(approval.requestID) 仍为 pending。"
            }
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func backendForPendingApproval(_ approval: AgentPendingApproval) -> AnyAgentBackend? {
        activeChatBackendsByRunID[approval.runID]
            ?? activeChatBackendsBySessionID[approval.sessionID]
            ?? nativeSessionManager?.backend
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
        guard let memoryOSFacade else {
            errorMessage = "当前没有可用的 Memory OS，无法保存网页证据。"
            return
        }
        do {
            let draft = BrowserGraphEvidenceBuilder().makeEpisodeDraft(
                selection: selection,
                groupID: "default",
                sessionID: selectedChatSessionID
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
            lastPromotionResultSummary = "已保存网页证据到 Memory OS：\(draft.episode.title)"
            Task { await runBackgroundJobs() }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func submitChat() async {
        let prompt = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
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

    func cancelActiveChatRun() {
        guard let submittingSessionID = selectedChatSessionID,
              submittingChatSessionIDs.contains(submittingSessionID)
        else { return }
        let reason = "cancelled by user"
        guard let runID = activeChatRunIDsBySessionID[submittingSessionID] else {
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
        if let backend = activeChatBackendsByRunID[runID] ?? activeChatBackendsBySessionID[sessionID] {
            backend.abort(runID: runID)
        } else if var manager = nativeSessionManager, selectedChatSessionID == sessionID {
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
        submittingChatSessionIDs.remove(sessionID)
        activeChatRunIDsBySessionID.removeValue(forKey: sessionID)
        refreshSelectedSubmittingState()
        applyKeepScreenAwakeSetting()
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
        scheduleActivityTimelineCacheSave(sessionID: sessionID, timeline: timeline)
        if selectedChatSessionID == sessionID {
            agentEventTimeline = timeline
        }
    }

    func setActiveSkill(slug: String) {
        activeSkillSlug = slug
        activeSkillDisplayName = skillRuntimeDefinitions.first(where: { $0.slug == slug })?.manifest.name
            ?? commercialSkillManagerPresentation.cards.first(where: { $0.id == slug })?.title
            ?? slug
    }

    func clearActiveSkill() {
        activeSkillSlug = nil
        activeSkillDisplayName = nil
    }

    private func resolveActiveSkillInstructions(sessionID: String) -> String? {
        guard let slug = activeSkillSlug else { return nil }
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
        guard let card = commercialSkillManagerPresentation.cards.first(where: { $0.id == slug }) else { return nil }
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
        attachments explicitAttachments: [AgentMessageAttachmentRef]? = nil
    ) async -> String? {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayPrompt = rawDisplayPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachmentsForSubmission = explicitAttachments ?? pendingAttachmentRefs
        guard !prompt.isEmpty || !attachmentsForSubmission.isEmpty else { return nil }
        guard var manager = nativeSessionManager else {
            errorMessage = String(describing: AppChatRuntimeUnavailableError.nativeSessionManagerUnavailable)
            return nil
        }
        let submittingSessionID = manager.session.id
        guard !submittingChatSessionIDs.contains(submittingSessionID) else { return nil }
        let liveBackend = manager.backend
        activeChatBackendsBySessionID[submittingSessionID] = liveBackend
        if clearComposer {
            chatInputDraftsBySessionID[submittingSessionID] = ""
            if selectedChatSessionID == submittingSessionID { setChatInputDraft("", for: submittingSessionID) }
            pendingAttachmentRefsBySessionID[submittingSessionID] = []
            if selectedChatSessionID == submittingSessionID { pendingAttachmentRefs = [] }
        }
        agentEventTimelinesBySessionID[submittingSessionID] = []
        agentEventTimelinesByProcessKey = agentEventTimelinesByProcessKey.filter { key, _ in !key.hasPrefix("\(submittingSessionID):") }
        agentEventTimeline = []
        submittingChatSessionIDs.insert(submittingSessionID)
        activeChatRunIDsBySessionID.removeValue(forKey: submittingSessionID)
        refreshSelectedSubmittingState()
        applyKeepScreenAwakeSetting()
        let optimisticTranscript = transcript
        let baselineMessageCount = manager.session.messages.count
        let baselineUserMessageCount = manager.session.messages.filter { $0.role == .user }.count
        let shouldAutoGenerateInitialTitle = baselineUserMessageCount == 0
        let submittedActiveSkillSlug = activeSkillSlug
        let submittedActiveSkillDisplayName = activeSkillDisplayName
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
            attachments: attachmentsForSubmission
        )
        if selectedChatSessionID == submittingSessionID {
            transcript = optimisticTranscript + [optimisticUserMessage]
        }
        lastContext = nil
        lastPromptInspection = nil
        defer {
            activeChatBackendsBySessionID.removeValue(forKey: submittingSessionID)
            if let runID = activeChatRunIDsBySessionID[submittingSessionID] {
                activeChatBackendsByRunID.removeValue(forKey: runID)
            }
            submittingChatSessionIDs.remove(submittingSessionID)
            activeChatRunIDsBySessionID.removeValue(forKey: submittingSessionID)
            refreshSelectedSubmittingState()
            applyKeepScreenAwakeSetting()
        }
        do {
            let sessionSummary: AgentSessionSummary?
            if let chatSessionRepository {
                let candidateSummary = try chatSessionRepository.loadLatestSummary(sessionID: submittingSessionID)
                sessionSummary = AgentSessionSummaryPolicy().summaryForContext(candidateSummary, session: manager.session)
            } else {
                sessionSummary = nil
            }
            let attachmentContextPlan = buildAttachmentContextPlan(
                sessionID: submittingSessionID,
                attachments: attachmentsForSubmission
            )
            let noteAugmentedPrompt: String = {
                guard manager.session.governance.kind == .note,
                      manager.session.messages.isEmpty,
                      !prompt.isEmpty
                else { return prompt }
                return prompt + NoteSessionPromptBuilder.noteInstructionSuffix
            }()
            let skillAugmentation = buildSkillChatPromptAugmentation(prompt: noteAugmentedPrompt, sessionID: submittingSessionID)
            let resolvedSkillInstructions = resolveActiveSkillInstructions(sessionID: submittingSessionID)
            if resolvedSkillInstructions != nil {
                clearActiveSkill()
            }
            let submitStartedAt = ContinuousClock.now
            let response = try await manager.submit(
                skillAugmentation.augmentedPrompt,
                sessionSummary: sessionSummary,
                displayPrompt: displayPrompt?.isEmpty == false ? displayPrompt : nil,
                attachments: attachmentsForSubmission,
                attachmentContextPlan: attachmentContextPlan,
                skillInstructions: resolvedSkillInstructions,
                activeSkillSlug: resolvedSkillInstructions == nil ? nil : submittedActiveSkillSlug,
                activeSkillDisplayName: resolvedSkillInstructions == nil ? nil : submittedActiveSkillDisplayName,
                onRunStarted: { [weak self] runID in
                    guard let self else { return }
                    if self.submittingChatSessionIDs.contains(submittingSessionID) {
                        self.activeChatRunIDsBySessionID[submittingSessionID] = runID
                        self.activeChatBackendsByRunID[runID] = liveBackend
                        self.activeChatBackendsBySessionID[submittingSessionID] = liveBackend
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
                    self.scheduleActivityTimelineCacheSave(sessionID: submittingSessionID, timeline: timeline)
                    if self.selectedChatSessionID == submittingSessionID {
                        self.agentEventTimeline = timeline
                    }
                    if presentation.kind == AgentEventKind.permissionRequested.rawValue {
                        self.reloadPendingApprovals()
                    }
                    self.reloadSkillRuntimeDefinitionsIfNeeded(after: presentation)
                }
            )
            let submitElapsed = submitStartedAt.duration(to: ContinuousClock.now)
            let submitMilliseconds = Double(submitElapsed.components.seconds) * 1_000 + Double(submitElapsed.components.attoseconds) / 1_000_000_000_000_000
            AppPerformanceLog.chatTurnLogger.info("nativeSubmit.completed session=\(submittingSessionID, privacy: .public) events=\(manager.eventPresentations.count, privacy: .public) duration=\(submitMilliseconds, privacy: .public)ms")
            agentEventTimelinesBySessionID[submittingSessionID] = manager.eventPresentations
            scheduleActivityTimelineCacheSave(sessionID: submittingSessionID, timeline: manager.eventPresentations)
            await flushActivityTimelineCache(sessionID: submittingSessionID)
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
                let duration = try AppPerformanceLog.measure {
                    self.chatSessions = try chatSessionRepository.loadSessions(filter: self.sessionListFilter)
                    self.allChatSessions = try chatSessionRepository.loadSessions(filter: .all)
                }
                AppPerformanceLog.chatTurnLogger.info("sessionList.reloadAfterSubmit session=\(submittingSessionID, privacy: .public) visible=\(self.chatSessions.count, privacy: .public) all=\(self.allChatSessions.count, privacy: .public) duration=\(duration.milliseconds, privacy: .public)ms")
            }
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
            Task { await runBackgroundJobs() }
            Task { await runDailySweepIfNeeded() }
            return latestAssistantMessage?.content
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

    func summarizeSelectedChatSession() async {
        guard let selectedChatSessionID, let chatSessionRepository else { return }
        isSummarizingChatSession = true
        defer { isSummarizingChatSession = false }
        do {
            let provider = try sessionLLMProvider(sessionID: selectedChatSessionID)
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

extension AppViewModel {
    var hasMemoryOSBackendForTests: Bool {
        memoryOSFacade != nil
    }
}

private final class UserLocationCoordinator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let completion: @Sendable (Result<CLPlacemark, Error>) -> Void

    init(completion: @escaping @Sendable (Result<CLPlacemark, Error>) -> Void) {
        self.completion = completion
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            completion(.failure(LocationPreferenceError.permissionDenied))
        @unknown default:
            completion(.failure(LocationPreferenceError.permissionDenied))
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            completion(.failure(LocationPreferenceError.permissionDenied))
        case .notDetermined:
            break
        @unknown default:
            completion(.failure(LocationPreferenceError.permissionDenied))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            completion(.failure(LocationPreferenceError.locationUnavailable))
            return
        }
        geocoder.reverseGeocodeLocation(location) { [completion] placemarks, error in
            if let error {
                completion(.failure(error))
            } else if let placemark = placemarks?.first {
                completion(.success(placemark))
            } else {
                completion(.failure(LocationPreferenceError.locationUnavailable))
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        completion(.failure(error))
    }
}

private enum LocationPreferenceError: LocalizedError {
    case permissionDenied
    case locationUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "定位权限未开启。请在系统设置中允许康纳同学访问位置，或手动填写城市和国家/地区。"
        case .locationUnavailable:
            return "暂时无法读取当前位置。你仍可以手动填写城市和国家/地区。"
        }
    }
}

/// 笔记会话首条消息的系统指令构建器
struct NoteSessionPromptBuilder {
    static let noteInstructionSuffix = """

## 系统笔记指令

用户正在创建一个笔记。请对用户的输入进行以下处理：

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
