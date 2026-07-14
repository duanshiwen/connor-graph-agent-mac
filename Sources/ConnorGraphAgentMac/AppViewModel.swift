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

enum AppViewModelStartupMode: Equatable {
    case immediate
    case deferred
}

@MainActor
final class AppViewModel: NSObject, ObservableObject {
#if DEBUG
    private let mainActorStallMonitor = AppMainActorStallMonitor()
#endif
    private let memoryOSMaintenanceWorker = AppMemoryOSMaintenanceWorker()
    private let chatSessionListRefreshCoordinator = ChatSessionListRefreshCoordinator()
    private let chatSessionDetailLoadCoordinator = ChatSessionDetailLoadCoordinator()
    private let chatSessionTitleGenerationWorker = ChatSessionTitleGenerationWorker()
    private var chatSessionSelectionTask: Task<Void, Never>?
    private var chatSessionSelectionGeneration = 0

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
    @Published var governanceConfig: AppSessionGovernanceConfig = .default
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
    @Published var sessionStateSnapshotsBySessionID: [String: AppSessionStateSnapshot] = [:]
    @Published var sessionRecordsBySessionID: [String: [AppSessionRecord]] = [:]
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
    private var pendingApprovalRepository: AppAgentPendingApprovalRepository?
    private var memoryOSStore: SQLiteMemoryOSStore?
    private var memoryOSFacade: AppMemoryOSFacade?
    private var chatSessionRepository: AppChatSessionRepository?
    private var activityTimelineCacheWriter: ActivityTimelineCacheWriter?
    private var governanceConfigRepository: AppSessionGovernanceConfigRepository?
    private var storagePaths: AppStoragePaths?
    private let runtimeSettingsCoordinator: RuntimeSettingsPersistenceCoordinator
    private var loadedLoopConfiguration = AgentLoopConfiguration()
    private var llmSettingsRepository: AppLLMSettingsRepository { aiConnectionsModel.settingsRepository }
    private var nativeSourceSearchBackend: (any NativeSourceSearchBackend)?
    private var applicationDidFinishLaunchingObserver: NSObjectProtocol?
    private var agentRuntimeFactory: AppGraphAgentRuntimeFactory?
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
    private var activeChatRunIDsBySessionID: [String: String] = [:]
    private var activeChatBackendsBySessionID: [String: AnyAgentBackend] = [:]
    private var activeChatBackendsByRunID: [String: AnyAgentBackend] = [:]
    private var pendingChatCancellationReasonsBySessionID: [String: String] = [:]
    private var chatInputDraftsBySessionID: [String: String] = [:]
    private var liveChatInputDraftSessionID: String?
    private var liveChatInputDraft: String = ""
    private var liveChatInputDraftRevision: UInt64 = 0
    private var pendingAttachmentRefsBySessionID: [String: [AgentMessageAttachmentRef]] = [:]
    private var isRestoringChatInputDraft = false
    private var agentEventTimelinesBySessionID: [String: [AgentEventPresentation]] = [:]
    private var agentEventTimelinesByProcessKey: [String: [AgentEventPresentation]] = [:]
    private var chatSessionWorkspaceModes = ChatSessionWorkspaceModeStore()
    private var isLoadingRuntimeSettings = false
    private var lastSessionNotificationAt: [String: Date] = [:]
    private let sameSessionNotificationCooldown: TimeInterval = 300
    private var idleSleepAssertionID: IOPMAssertionID = 0
    private var hasActivatedRuntimeSettingsSideEffects = false
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

    var isLoadingSelectedChatSessionDetail: Bool {
        guard let selectedChatSessionID = chatFeatureModel.sessions.selectedSessionID else { return false }
        return chatFeatureModel.sessions.loadingSessionDetailID == selectedChatSessionID
    }

    var activeChatPendingApprovals: [AgentPendingApproval] {
        let activeSessionID = activeChatSession.id
        return chatFeatureModel.approvals.pendingApprovals.filter { approval in
            approval.sessionID == activeSessionID && !shouldAutoApprovePendingApproval(approval)
        }
    }

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
        nativeSessionManager?.permissionMode = mode
        persistLLMSettings(rebuildRuntime: chatFeatureModel.run.submittingSessionIDs.isEmpty)
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
        let approvals = chatFeatureModel.approvals.pendingApprovals.filter(shouldAutoApprovePendingApproval)
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
        chatFeatureModel.run.submittingSessionIDs.contains(sessionID)
    }

    private func updateLiveChatInputDraft(_ draft: String, for sessionID: String) {
        if liveChatInputDraftSessionID != sessionID {
            liveChatInputDraftSessionID = sessionID
        }
        guard liveChatInputDraft != draft else { return }
        liveChatInputDraft = draft
        liveChatInputDraftRevision &+= 1
    }

    private func setChatInputDraft(_ draft: String, for sessionID: String?) {
        if let sessionID {
            updateLiveChatInputDraft(draft, for: sessionID)
        } else {
            liveChatInputDraftSessionID = nil
            liveChatInputDraft = draft
            liveChatInputDraftRevision &+= 1
        }
        isRestoringChatInputDraft = true
        chatFeatureModel.composer.input = draft
        isRestoringChatInputDraft = false
    }

    func updateSelectedChatInputDraft(_ draft: String) {
        guard !isRestoringChatInputDraft,
              let selectedChatSessionID = chatFeatureModel.sessions.selectedSessionID
        else { return }
        updateLiveChatInputDraft(draft, for: selectedChatSessionID)
        if inputSettingsModel.autoSaveDraftsEnabled {
            chatInputDraftsBySessionID[selectedChatSessionID] = draft
        }
        speechTranscriptionCoordinator.noteUserEditedDraft(sessionID: selectedChatSessionID, draft: draft)
    }

    func currentSelectedChatInputDraftForSpeech() -> String {
        guard let selectedChatSessionID = chatFeatureModel.sessions.selectedSessionID else { return chatFeatureModel.composer.input }
        if liveChatInputDraftSessionID == selectedChatSessionID {
            return liveChatInputDraft
        }
        return inputSettingsModel.autoSaveDraftsEnabled ? (chatInputDraftsBySessionID[selectedChatSessionID] ?? chatFeatureModel.composer.input) : chatFeatureModel.composer.input
    }

    func appendToSelectedChatInputDraft(_ addition: String) {
        let updatedDraft = [currentSelectedChatInputDraftForSpeech(), addition]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
        updateSelectedChatInputDraft(updatedDraft)
        chatFeatureModel.composer.applyInput(updatedDraft)
    }

    private func restoreChatInputDraft(for sessionID: String?) {
        let draft: String
        if let sessionID, liveChatInputDraftSessionID == sessionID {
            draft = liveChatInputDraft
        } else if let sessionID, inputSettingsModel.autoSaveDraftsEnabled {
            draft = chatInputDraftsBySessionID[sessionID] ?? ""
        } else {
            draft = ""
        }
        setChatInputDraft(draft, for: sessionID)
        chatFeatureModel.composer.pendingAttachmentRefs = sessionID.flatMap { pendingAttachmentRefsBySessionID[$0] } ?? []
    }

    var canSubmitCurrentChat: Bool {
        !chatFeatureModel.composer.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !chatFeatureModel.composer.pendingAttachmentRefs.isEmpty
    }

    func removePendingAttachment(id: String) {
        chatFeatureModel.composer.pendingAttachmentRefs.removeAll { $0.id == id }
        if let selectedChatSessionID = chatFeatureModel.sessions.selectedSessionID {
            pendingAttachmentRefsBySessionID[selectedChatSessionID] = chatFeatureModel.composer.pendingAttachmentRefs
        }
    }

    func previewAttachment(_ attachment: AgentMessageAttachmentRef) {
        guard let selectedChatSessionID = chatFeatureModel.sessions.selectedSessionID, let storagePaths else { return }
        let store = AppSessionAttachmentStore(paths: storagePaths)
        chatFeatureModel.composer.attachmentPreviewModel = AttachmentPreviewLoader(store: store).load(
            sessionID: selectedChatSessionID,
            attachment: attachment
        )
    }

    func localAttachmentFileURL(_ attachment: AgentMessageAttachmentRef) -> URL? {
        guard let selectedChatSessionID = chatFeatureModel.sessions.selectedSessionID, let storagePaths else { return nil }
        return AttachmentPreviewLoader(store: AppSessionAttachmentStore(paths: storagePaths))
            .load(sessionID: selectedChatSessionID, attachment: attachment)
            .sourceFileURL
    }

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
        showAttachmentToast(
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
            showAttachmentToast(
                title: "已导出回复",
                message: url.path,
                systemImage: "square.and.arrow.down"
            )
        } catch {
            showAttachmentToast(
                title: "导出回复失败",
                message: String(describing: error),
                systemImage: "xmark.circle"
            )
        }
    }

    func downloadPreviewImage(_ model: AttachmentPreviewModel) {
        let service = AttachmentImageExportService()
        guard let filename = service.defaultFilename(for: model), let sourceURL = model.sourceFileURL else {
            showAttachmentToast(
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
            showAttachmentToast(
                title: "图片已下载",
                message: destinationURL.path,
                systemImage: "square.and.arrow.down"
            )
        } catch {
            showAttachmentToast(
                title: "图片下载失败",
                message: error.localizedDescription,
                systemImage: "xmark.circle"
            )
        }
    }

    @discardableResult
    func importAttachments(urls: [URL]) async -> AttachmentImportBatchResult {
        guard let selectedChatSessionID = chatFeatureModel.sessions.selectedSessionID, let storagePaths else { return AttachmentImportBatchResult() }
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
            chatFeatureModel.composer.pendingAttachmentRefs.append(contentsOf: imported)
            pendingAttachmentRefsBySessionID[selectedChatSessionID] = chatFeatureModel.composer.pendingAttachmentRefs
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
        chatFeatureModel.composer.attachmentToast = toast
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if self.chatFeatureModel.composer.attachmentToast?.id == toast.id {
                self.chatFeatureModel.composer.attachmentToast = nil
            }
        }
    }

    func retryAttachmentExtraction(attachmentID: String) {
        guard let selectedChatSessionID = chatFeatureModel.sessions.selectedSessionID, let storagePaths else { return }
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
        if chatFeatureModel.sessions.selectedSessionID == sessionID {
            chatFeatureModel.composer.pendingAttachmentRefs = refs
            if let model = chatFeatureModel.composer.attachmentPreviewModel,
               refs.contains(where: { $0.id == model.attachment.id }) {
                chatFeatureModel.composer.attachmentPreviewModel = AttachmentPreviewLoader(store: store).load(sessionID: sessionID, attachment: model.attachment)
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

    private func refreshSelectedSubmittingState() {
        chatFeatureModel.run.isSubmitting = chatFeatureModel.sessions.selectedSessionID.map { chatFeatureModel.run.submittingSessionIDs.contains($0) } ?? false
    }

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
        self.governanceConfig = governanceConfig
        if let storagePaths {
            self.nativeSourceSearchBackend = nativeSourceSearchBackend
            self.governanceConfigRepository = AppSessionGovernanceConfigRepository(configDirectory: storagePaths.configDirectory)
        }
        if let repository {
            self.pendingApprovalRepository = AppAgentPendingApprovalRepository(store: repository.store)
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
        self.fallbackChatSession = initialSession
        super.init()
        aiConnectionsModel.onRuntimeSettingsChanged = { [weak self] rebuildRuntime in
            guard let self else { return }
            if rebuildRuntime {
                self.rebuildNativeSessionManagerForActiveSession()
            } else {
                self.nativeSessionManager?.permissionMode = self.agentPermissionMode
            }
        }
        aiConnectionsModel.onConnectionSetup = { [weak self] connection in
            self?.syncActiveSessionLLMOverride(to: connection)
        }
        if startupMode == .immediate {
            registerMaintenanceObserversIfNeeded()
        }
        if let repository {
            self.agentRuntimeFactory = AppGraphAgentRuntimeFactory(
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
            )
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
                try await self.reconcileRSSSourceRefreshTasks()
            case .allSources:
                try await self.reconcileSourceRefreshTasks()
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
            try await self.reconcileCalendarAccountRefreshTasks()
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
            try await self.reconcileMailAccountRefreshTasks()
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
                try await reconcileSourceRefreshTasks()
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
            prepareInteractiveStartup(initialSession: fallbackChatSession)
            return
        }
        applyInteractiveLLMSettings(snapshot.llmSettings)
        applyInteractiveRuntimeSettings(snapshot.runtimeSettings)
        applyInteractiveSessionContent(snapshot.sessionContent)
        Task { await reloadLLMModelConnections() }
    }

    func prepareDemoInteractiveStartup() {
        hasLoadedInitialChatSessions = true
        let session = fallbackChatSession
        chatFeatureModel.sessions.sessions = [session]
        chatFeatureModel.sessions.allSessions = [session]
        synchronizeSessionReadStates(from: [session])
        chatFeatureModel.sessions.selectedSessionID = session.id
        replaceSelectedChatTranscript(session.messages)
        nativeSessionManager = agentRuntimeFactory?.makeNativeSessionManager(session: session)
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
        hasLoadedInitialChatSessions = true
        guard let snapshot = result.value else {
            replaceSelectedChatTranscript(activeChatTranscript)
            chatFeatureModel.sessions.sessions = [activeChatSession]
            chatFeatureModel.sessions.allSessions = [activeChatSession]
            synchronizeSessionReadStates(from: chatFeatureModel.sessions.allSessions)
            chatFeatureModel.sessions.selectedSessionID = activeChatSession.id
            nativeSessionManager = agentRuntimeFactory?.makeNativeSessionManager(session: activeChatSession)
            if let failureMessage = result.failureMessage { errorMessage = failureMessage }
            return
        }
        chatFeatureModel.sessions.sessions = snapshot.sessions
        chatFeatureModel.sessions.allSessions = snapshot.allSessions
        rebuildSessionSearchIndexSoon(sessions: snapshot.allSessions)
        synchronizeSessionReadStates(from: snapshot.allSessions)
        guard let session = snapshot.selectedSession else {
            clearSelectedChatSessionDetail()
            return
        }
        let sessionID = session.id
        chatFeatureModel.sessions.selectedSessionID = sessionID
        if let state = snapshot.state {
            sessionStateSnapshotsBySessionID[sessionID] = state
            syncWorkspaceDraftsFromSession(state)
            if let mode = ChatSessionWorkspaceMode(rawValue: state.selectedPane ?? "") {
                chatSessionWorkspaceModes.setMode(mode, for: sessionID)
            }
        }
        sessionRecordsBySessionID[sessionID] = snapshot.records
        if let browserState = snapshot.browserState {
            browserFeatureModel.installLoadedWorkspaceSnapshot(browserState, for: sessionID)
        }
        chatFeatureModel.sessions.backgroundTasksBySessionID[sessionID] = snapshot.backgroundTasks
        chatFeatureModel.sessions.regeneratingTitleSessionIDs.remove(sessionID)
        fallbackChatSession = session
        nativeSessionManager = makeNativeSessionManager(for: session)
        replaceSelectedChatTranscript(session.messages)
        restoreChatInputDraft(for: sessionID)
        refreshSelectedSubmittingState()
        agentEventTimelinesBySessionID[sessionID] = snapshot.timeline
        chatFeatureModel.run.eventTimeline = snapshot.timeline
        chatFeatureModel.run.latestSummary = snapshot.latestSummary
        chatFeatureModel.sessions.selectedArtifactDirectories = snapshot.artifactDirectories
        restoreWorkspaceMode(for: sessionID)
        chatFeatureModel.run.summaryMessage = nil
    }

    private func prepareInteractiveStartup(initialSession: AgentSession) {
        loadLLMSettings()
        Task { await reloadLLMModelConnections() }
        updateWelcomeState()
        loadRuntimeSettings()
        nativeSessionManager = agentRuntimeFactory?.makeNativeSessionManager(session: initialSession)
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
            try await reconcileSourceRefreshTasks()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func startStartupMaintenance(snapshot: AppMaintenanceBootstrapSnapshot? = nil) async {
        registerMaintenanceObserversIfNeeded()
        if let snapshot {
            taskAutomationModel.applyStartupSnapshot(snapshot.tasks)
            graphDiagnosticsModel.applyStartupMaintenance(
                promotionCandidates: snapshot.promotionCandidates,
                schemaHealth: snapshot.schemaHealth
            )
            if let approvals = snapshot.pendingApprovals.value {
                chatFeatureModel.approvals.pendingApprovals = approvals
                autoApproveCurrentPolicyPendingApprovals()
            } else if let failureMessage = snapshot.pendingApprovals.failureMessage {
                errorMessage = failureMessage
            }
        }
        scheduleMemoryOSSearchIndexRepairIfNeeded()
    }

    private func registerMaintenanceObserversIfNeeded() {
#if DEBUG
        mainActorStallMonitor.start()
#endif
        guard applicationDidFinishLaunchingObserver == nil else { return }
        applicationDidFinishLaunchingObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshDockBadge()
            }
        }
    }

    func shutdownRuntimeResourcesForTests() {
        shutdownRuntimeResources()
    }

    func shutdownRuntimeResources() {
        if let applicationDidFinishLaunchingObserver {
            NotificationCenter.default.removeObserver(applicationDidFinishLaunchingObserver)
            self.applicationDidFinishLaunchingObserver = nil
        }
        stopTaskSchedulerTimer()
        chatFeatureModel.shutdown()
        globalSearchFeatureModel.shutdown()
        runtimeSettingsCoordinator.shutdown()
        userPreferencesModel.shutdown()
        rssFeatureModel.shutdown()
        calendarFeatureModel.shutdown()
        contactsFeatureModel.shutdown()
        mailFeatureModel.shutdown()
        browserFeatureModel.shutdown()
        releaseIdleSleepAssertion()
    }

    private func releaseIdleSleepAssertion() {
        guard idleSleepAssertionID != 0 else { return }
        IOPMAssertionRelease(idleSleepAssertionID)
        idleSleepAssertionID = 0
    }

    private func applyPromotedGraphSnapshot(_ snapshot: GraphStoreSnapshot) {
        graphDiagnosticsModel.apply(snapshot: snapshot)
        let session = activeChatSession
        fallbackChatSession = session
        nativeSessionManager = makeNativeSessionManager(for: session)
        Task { await graphDiagnosticsModel.runSearch() }
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
            try await reconcileSourceRefreshTasks()
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
                chatFeatureModel.sessions.selectedSessionID = session.id
                fallbackChatSession = session
                nativeSessionManager = makeNativeSessionManager(for: session)
                _ = await submitChat(prompt: request.message, clearComposer: false)
                return "created session \(session.id) and sent task message"
            } catch {
                return "failed to create task session: \(error)"
            }
        }
        guard let sessionID = request.sessionID else { return "Missing sessionID" }
        chatFeatureModel.sessions.selectedSessionID = sessionID
        if let session = try? chatSessionRepository?.loadSession(id: sessionID) {
            fallbackChatSession = session
            nativeSessionManager = makeNativeSessionManager(for: session)
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
            chatFeatureModel.sessions.selectedSessionID = session.id
            agentEventTimelinesByProcessKey.removeAll(keepingCapacity: true)
            browserFeatureModel.resetWorkspaceBinding()
            chatFeatureModel.sessions.selectedArtifactDirectories = try chatSessionRepository.artifactDirectories(sessionID: session.id)
            try loadSessionCapsule(sessionID: session.id)
            try loadBackgroundTasks(sessionID: session.id)
            fallbackChatSession = session
            nativeSessionManager = makeNativeSessionManager(for: session)
            replaceSelectedChatTranscript([])
            restoreChatInputDraft(for: session.id)
            refreshSelectedSubmittingState()
            chatFeatureModel.run.eventTimeline = []
            agentEventTimelinesBySessionID[session.id] = []
            chatFeatureModel.run.latestSummary = nil
            chatFeatureModel.run.summaryMessage = nil
            chatFeatureModel.run.lastPromptInspection = nil
            reloadChatSessions(restoreWorkspaceMode: false)
            chatFeatureModel.sessions.selectedSessionID = session.id
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
        try loadBackgroundTasks(sessionID: session.id)
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
        try loadBackgroundTasks(sessionID: session.id)
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
        activeChatBackendsBySessionID[sessionID] = liveBackend
        chatFeatureModel.run.submittingSessionIDs.insert(sessionID)
        refreshSelectedSubmittingState()
        defer {
            activeChatBackendsBySessionID.removeValue(forKey: sessionID)
            if let runID = activeChatRunIDsBySessionID[sessionID] {
                activeChatBackendsByRunID.removeValue(forKey: runID)
            }
            chatFeatureModel.run.submittingSessionIDs.remove(sessionID)
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
                self.skillRuntimeModel.reloadIfNeeded(after: presentation)
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
        return agentRuntimeFactory?.makeNativeSessionManager(
            session: session,
            permissionMode: configuration.permissionMode,
            configuration: configuration,
            sessionWorkspace: sessionStateSnapshotsBySessionID[session.id]?.workspace,
            sessionLLMOverride: sessionStateSnapshotsBySessionID[session.id]?.llmOverride
        )
    }

    func makeNoteImportViewModel() -> NoteImportViewModel {
        guard let databasePath, let chatSessionRepository, let agentRuntimeFactory, let storagePaths else {
            return NoteImportViewModel(configurationError: "导入运行时不可用，请重新启动应用。")
        }
        do {
            let ledger = try AppNoteImportRepository(databasePath: databasePath)
            let attachmentStore = AppSessionAttachmentStore(paths: storagePaths)
            let sessionService = HeadlessNoteSessionService(
                repository: chatSessionRepository,
                managerFactory: { session in
                    agentRuntimeFactory.makeNativeSessionManager(session: session, permissionMode: .readOnly)
                },
                attachmentStore: attachmentStore
            )
            let coordinator = NoteImportCoordinator(
                ledger: ledger,
                sessionService: sessionService,
                attachmentImporter: NoteImportAttachmentImporter(store: attachmentStore),
                payloadStore: NoteImportPayloadStore(
                    rootDirectory: storagePaths.artifactsDirectory.appendingPathComponent("note-import-staging", isDirectory: true)
                )
            )
            return NoteImportViewModel(
                ledger: ledger,
                coordinator: coordinator,
                executionSupervisor: NoteImportExecutionSupervisor(coordinator: coordinator),
                sourceAccessService: NoteImportSourceAccessService()
            )
        } catch {
            return NoteImportViewModel(configurationError: "无法初始化导入功能：\(error.localizedDescription)")
        }
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
            nativeSessionManager?.permissionMode = settings.loop.permissionMode
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
        if appSettingsModel.keepScreenAwake && !chatFeatureModel.run.submittingSessionIDs.isEmpty {
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
        appSettingsModel.sessionNewMessageNotificationLevel = SessionNotificationSettings.default.newMessageLevel
    }

    func markSessionRead(_ sessionID: String) {
        guard chatFeatureModel.sessions.readStates[sessionID]?.highestLevel != SessionAttentionLevel.none || chatFeatureModel.sessions.readStates[sessionID]?.unreadCount ?? 0 > 0 else { return }
        var state = chatFeatureModel.sessions.readStates[sessionID] ?? .initial()
        state.markRead(messageID: latestMessageID(for: sessionID), at: Date())
        applySessionReadState(state, sessionID: sessionID, persist: true)
    }

    private func markSessionUnread(
        sessionID: String,
        messageID: String,
        preview: String?,
        level: SessionAttentionLevel
    ) {
        var state = chatFeatureModel.sessions.readStates[sessionID] ?? .initial()
        state.markUnread(messageID: messageID, preview: preview, level: level, at: Date())
        applySessionReadState(state, sessionID: sessionID, persist: true)
    }

    private func latestMessageID(for sessionID: String) -> String? {
        if chatFeatureModel.sessions.selectedSessionID == sessionID, let last = chatFeatureModel.run.transcript.last { return last.id }
        return chatFeatureModel.sessions.sessions.first(where: { $0.id == sessionID })?.messages.last?.id
            ?? chatFeatureModel.sessions.allSessions.first(where: { $0.id == sessionID })?.messages.last?.id
    }

    private func noteSessionUpdate(
        sessionID: String,
        messageID: String?,
        preview: String?,
        notificationBody: String
    ) {
        let level = appSettingsModel.sessionNewMessageNotificationLevel
        if shouldTreatSessionUpdateAsRead(sessionID: sessionID) {
            var state = chatFeatureModel.sessions.readStates[sessionID] ?? .initial()
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
        selection == .agentChat && chatFeatureModel.sessions.selectedSessionID == sessionID
    }

    private func postSessionNotificationIfNeeded(
        sessionID: String,
        body: String,
        level: SessionAttentionLevel
    ) {
        guard appSettingsModel.desktopNotificationsEnabled, canUseUserNotifications else { return }
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
        chatFeatureModel.sessions.readStates = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.readState) })
        refreshDockBadge()
    }

    private func applySessionReadState(_ state: SessionReadState, sessionID: String, persist: Bool) {
        chatFeatureModel.sessions.readStates[sessionID] = state
        updateLoadedSessionReadState(sessionID: sessionID, readState: state)
        if persist {
            persistSessionReadState(state, sessionID: sessionID)
        }
        refreshDockBadge()
    }

    private func updateLoadedSessionReadState(sessionID: String, readState: SessionReadState) {
        if let index = chatFeatureModel.sessions.sessions.firstIndex(where: { $0.id == sessionID }) {
            chatFeatureModel.sessions.sessions[index].readState = readState
        }
        if let index = chatFeatureModel.sessions.allSessions.firstIndex(where: { $0.id == sessionID }) {
            chatFeatureModel.sessions.allSessions[index].readState = readState
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
        let count = chatFeatureModel.sessions.readStates.values.reduce(0) { partial, state in
            guard state.highestLevel.shouldCountInDockBadge else { return partial }
            return partial + max(state.unreadCount, 1)
        }
        Self.applyDockBadge(count: count, application: NSApp)
    }

    static func applyDockBadge(count: Int, application: NSApplication?) {
        guard let application else { return }
        application.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    private var canUseUserNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
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
        governanceConfig.statuses.count > 1 && !chatFeatureModel.sessions.allSessions.contains { $0.governance.status.rawValue == definition.id }
    }

    func deleteStatusDefinition(_ definition: AgentSessionStatusDefinition) {
        guard governanceConfig.statuses.count > 1 else {
            errorMessage = "至少需要保留一个状态。"
            return
        }
        do {
            let sessions = try chatSessionRepository?.loadSessions(filter: .all) ?? chatFeatureModel.sessions.allSessions
            let sessionsUsingStatus = sessions.filter { $0.governance.status.rawValue == definition.id }
            guard sessionsUsingStatus.isEmpty else {
                errorMessage = "无法删除状态“\(definition.name)”: 仍有 \(sessionsUsingStatus.count) 个会话处于此状态。"
                return
            }
            var config = governanceConfig
            config.statuses.removeAll { $0.id == definition.id }
            saveGovernanceConfig(config, successMessage: "状态“\(definition.name)”已删除。", section: .statuses)
            if case .status(let selectedStatus) = chatFeatureModel.sessions.filter, selectedStatus.rawValue == definition.id {
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
            if case .label(let selectedLabelID) = chatFeatureModel.sessions.filter, selectedLabelID == definition.id {
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
            try productOSControlModel.reloadAutomationAfterGovernanceChange(governanceConfig: normalizedConfig)
            setSettingsMessage(successMessage, for: section)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
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
        guard !hasLoadedInitialChatSessions else { return }
        reloadChatSessions(restoreWorkspaceMode: shouldRestoreWorkspaceMode)
    }

    private func rebuildSessionSearchIndexSoon(sessions: [AgentSession]) {
        globalSearchFeatureModel.rebuildSessionIndex(sessions: sessions)
    }

    func reloadChatSessions(restoreWorkspaceMode shouldRestoreWorkspaceMode: Bool = true) {
        hasLoadedInitialChatSessions = true
        guard let chatSessionRepository else {
            replaceSelectedChatTranscript(activeChatTranscript)
            chatFeatureModel.sessions.sessions = [activeChatSession]
            chatFeatureModel.sessions.allSessions = [activeChatSession]
            synchronizeSessionReadStates(from: chatFeatureModel.sessions.allSessions)
            chatFeatureModel.sessions.selectedSessionID = activeChatSession.id
            return
        }
        do {
            var sessions = try chatSessionRepository.loadSessions(filter: chatFeatureModel.sessions.filter)
            if sessions.isEmpty, chatFeatureModel.sessions.filter == .all {
                let session = try chatSessionRepository.createSession()
                sessions = [session]
            }
            chatFeatureModel.sessions.sessions = sessions
            chatFeatureModel.sessions.allSessions = try chatSessionRepository.loadSessions(filter: .all)
            rebuildSessionSearchIndexSoon(sessions: chatFeatureModel.sessions.allSessions)
            synchronizeSessionReadStates(from: chatFeatureModel.sessions.allSessions)
            let selectedID = selectedChatSessionIDVisibleInCurrentFilter(sessions: sessions)
            chatFeatureModel.sessions.selectedSessionID = selectedID
            if let selectedID, let session = try chatSessionRepository.loadSession(id: selectedID) {
                try loadSessionCapsule(sessionID: selectedID)
                try loadBackgroundTasks(sessionID: selectedID)
                fallbackChatSession = session
                nativeSessionManager = makeNativeSessionManager(for: session)
                replaceSelectedChatTranscript(session.messages)
                restoreChatInputDraft(for: selectedID)
                refreshSelectedSubmittingState()
                if let cachedTimeline = agentEventTimelinesBySessionID[selectedID] {
                    chatFeatureModel.run.eventTimeline = cachedTimeline
                } else {
                    try restoreLatestAgentEventTimeline(sessionID: selectedID)
                }
                chatFeatureModel.run.latestSummary = try chatSessionRepository.loadLatestSummary(sessionID: selectedID)
                chatFeatureModel.sessions.selectedArtifactDirectories = try chatSessionRepository.artifactDirectories(sessionID: selectedID)
                if shouldRestoreWorkspaceMode {
                    restoreWorkspaceMode(for: selectedID)
                }
            } else {
                clearSelectedChatSessionDetail()
            }
            chatFeatureModel.run.summaryMessage = nil
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func selectedChatSessionIDVisibleInCurrentFilter(sessions: [AgentSession]) -> String? {
        if let selectedChatSessionID = chatFeatureModel.sessions.selectedSessionID {
            return sessions.contains(where: { $0.id == selectedChatSessionID }) ? selectedChatSessionID : nil
        }
        return chatFeatureModel.sessions.filter == .all ? sessions.first?.id : nil
    }

    private func replaceSelectedChatTranscript(_ messages: [AgentMessage]) {
        chatFeatureModel.run.transcript = messages
        chatFeatureModel.run.transcriptRevision += 1
    }

    private func clearSelectedChatSessionDetail() {
        chatSessionSelectionTask?.cancel()
        chatSessionSelectionGeneration += 1
        chatFeatureModel.sessions.loadingSessionDetailID = nil
        chatFeatureModel.sessions.selectedSessionID = nil
        nativeSessionManager = nil
        replaceSelectedChatTranscript([])
        chatFeatureModel.run.eventTimeline = []
        chatFeatureModel.run.latestSummary = nil
        chatFeatureModel.sessions.selectedArtifactDirectories = nil
        chatFeatureModel.run.summaryMessage = nil
        chatFeatureModel.run.lastContext = nil
        chatFeatureModel.run.lastPromptInspection = nil
        browserFeatureModel.isVisible = false
        browserFeatureModel.resetWorkspaceBinding()
        refreshSelectedSubmittingState()
    }

    func newChatSession() {
        guard let chatSessionRepository else { return }
        chatSessionSelectionTask?.cancel()
        chatSessionSelectionGeneration += 1
        chatFeatureModel.sessions.loadingSessionDetailID = nil
        _ = stopSpeechTranscriptionIfRunningForLeavingSession(chatFeatureModel.sessions.selectedSessionID)
        rememberCurrentWorkspaceMode()
        do {
            let session = try chatSessionRepository.createSession()
            chatFeatureModel.sessions.selectedSessionID = session.id
            agentEventTimelinesByProcessKey.removeAll(keepingCapacity: true)
            browserFeatureModel.isVisible = false
            browserFeatureModel.resetWorkspaceBinding()
            rememberWorkspaceMode(.conversation, for: session.id)
            chatFeatureModel.sessions.selectedArtifactDirectories = try chatSessionRepository.artifactDirectories(sessionID: session.id)
            try loadSessionCapsule(sessionID: session.id)
            try loadBackgroundTasks(sessionID: session.id)
            fallbackChatSession = session
            nativeSessionManager = makeNativeSessionManager(for: session)
            replaceSelectedChatTranscript([])
            restoreChatInputDraft(for: session.id)
            refreshSelectedSubmittingState()
            chatFeatureModel.run.eventTimeline = []
            agentEventTimelinesBySessionID[session.id] = []
            chatFeatureModel.run.latestSummary = nil
            chatFeatureModel.run.summaryMessage = nil
            chatFeatureModel.run.lastPromptInspection = nil
            reloadChatSessions()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    };

    func newNoteSession() {
        guard let chatSessionRepository else { return }
        chatSessionSelectionTask?.cancel()
        chatSessionSelectionGeneration += 1
        chatFeatureModel.sessions.loadingSessionDetailID = nil
        _ = stopSpeechTranscriptionIfRunningForLeavingSession(chatFeatureModel.sessions.selectedSessionID)
        rememberCurrentWorkspaceMode()
        do {
            let session = try chatSessionRepository.createSession()
            var noteSession = session
            noteSession.governance.kind = .note
            noteSession.title = "未命名的笔记"
            _ = try chatSessionRepository.saveSession(noteSession)
            chatFeatureModel.sessions.selectedSessionID = noteSession.id
            agentEventTimelinesByProcessKey.removeAll(keepingCapacity: true)
            browserFeatureModel.isVisible = false
            browserFeatureModel.resetWorkspaceBinding()
            rememberWorkspaceMode(.conversation, for: noteSession.id)
            chatFeatureModel.sessions.selectedArtifactDirectories = try chatSessionRepository.artifactDirectories(sessionID: noteSession.id)
            try loadSessionCapsule(sessionID: noteSession.id)
            try loadBackgroundTasks(sessionID: noteSession.id)
            fallbackChatSession = noteSession
            nativeSessionManager = makeNativeSessionManager(for: noteSession)
            replaceSelectedChatTranscript([])
            restoreChatInputDraft(for: noteSession.id)
            refreshSelectedSubmittingState()
            chatFeatureModel.run.eventTimeline = []
            agentEventTimelinesBySessionID[noteSession.id] = []
            chatFeatureModel.run.latestSummary = nil
            chatFeatureModel.run.summaryMessage = nil
            chatFeatureModel.run.lastPromptInspection = nil
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
            fallbackChatSession = updated
            nativeSessionManager = makeNativeSessionManager(for: updated)
            replaceSelectedChatTranscript(updated.messages)
        }
    }

    func backgroundTasks(for sessionID: String?) -> [AppSessionBackgroundTask] {
        guard let sessionID else { return [] }
        return chatFeatureModel.sessions.backgroundTasksBySessionID[sessionID, default: []]
            .sorted { $0.createdAt > $1.createdAt }
    }

    var activeSessionBackgroundTasks: [AppSessionBackgroundTask] {
        backgroundTasks(for: chatFeatureModel.sessions.selectedSessionID)
    }

    var hasRunningActiveSessionBackgroundTask: Bool {
        activeSessionBackgroundTasks.contains { $0.status == .queued || $0.status == .running }
    }

    func hasRunningBackgroundTask(sessionID: String) -> Bool {
        chatFeatureModel.sessions.backgroundTasksBySessionID[sessionID, default: []]
            .contains { $0.status == .queued || $0.status == .running }
    }

    var isSpeechTranscriptionRunningForSelectedSession: Bool {
        speechTranscriptionCoordinator.isRunning(sessionID: chatFeatureModel.sessions.selectedSessionID)
    }

    func toggleSpeechTranscriptionForSelectedSession() {
        if isSpeechTranscriptionRunningForSelectedSession {
            finishSpeechTranscriptionForSelectedSession()
        } else {
            beginSpeechTranscriptionForSelectedSession()
        }
    }

    func beginSpeechTranscriptionForSelectedSession(speechInsertionRange: NSRange? = nil) {
        guard inputSettingsModel.sessionSpeechTranscriptionEnabled else { return }
        let task = speechTranscriptionCoordinator.beginHoldToTalk(
            selectedSessionID: chatFeatureModel.sessions.selectedSessionID,
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
        if chatFeatureModel.sessions.selectedSessionID == sessionID { chatFeatureModel.composer.speechProvisionalTranscript = nil }
        syncSpeechTranscriptionState()
        upsertSpeechTranscriptionBackgroundTask(task)
        return task
    }

    @discardableResult
    private func stopSpeechTranscriptionIfRunningForDeletedSession(_ sessionID: String?) -> AppSessionBackgroundTask? {
        let task = speechTranscriptionCoordinator.stopIfRunningForDeletedSession(sessionID)
        if chatFeatureModel.sessions.selectedSessionID == sessionID { chatFeatureModel.composer.speechProvisionalTranscript = nil }
        syncSpeechTranscriptionState()
        upsertSpeechTranscriptionBackgroundTask(task)
        return task
    }

    private func stopSpeechTranscriptionForDisabledSetting() {
        guard chatFeatureModel.composer.speechTranscriptionStatus.isRunning else { return }
        let task = speechTranscriptionCoordinator.stop(reason: .appLifecycle)
        chatFeatureModel.composer.speechProvisionalTranscript = nil
        syncSpeechTranscriptionState()
        upsertSpeechTranscriptionBackgroundTask(task)
    }

    private func setSpeechTranscriptionDraft(_ draft: String, for sessionID: String) {
        chatInputDraftsBySessionID[sessionID] = draft
        if chatFeatureModel.sessions.selectedSessionID == sessionID {
            setChatInputDraft(draft, for: sessionID)
        }
    }

    private func setSpeechProvisionalTranscript(_ transcript: String?, for sessionID: String) {
        guard chatFeatureModel.sessions.selectedSessionID == sessionID else { return }
        chatFeatureModel.composer.speechProvisionalTranscript = transcript?.isEmpty == true ? nil : transcript
    }

    private func syncSpeechTranscriptionState() {
        chatFeatureModel.composer.speechTranscriptionStatus = speechTranscriptionCoordinator.status
    }

    private func upsertSpeechTranscriptionBackgroundTask(_ task: AppSessionBackgroundTask?) {
        guard let task else { return }
        upsertBackgroundTask(task)
    }

    private func runningBackgroundTasksForDeletionCheck(sessionID: String) throws -> [AppSessionBackgroundTask] {
        let persistedTasks = try chatSessionRepository?.loadBackgroundTasks(sessionID: sessionID).map(AppSessionBackgroundTask.init(persisted:)) ?? []
        let memoryTasks = chatFeatureModel.sessions.backgroundTasksBySessionID[sessionID, default: []]
        return (persistedTasks + memoryTasks).filter { $0.status == .queued || $0.status == .running }
    }

    func canDeleteChatSession(_ sessionID: String) -> Bool {
        (try? runningBackgroundTasksForDeletionCheck(sessionID: sessionID).isEmpty) ?? !hasRunningBackgroundTask(sessionID: sessionID)
    }

    private func loadBackgroundTasks(sessionID: String) throws {
        guard let chatSessionRepository else { return }
        let activeInMemoryTaskIDs = Set(
            chatFeatureModel.sessions.backgroundTasksBySessionID[sessionID, default: []]
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
        chatFeatureModel.sessions.backgroundTasksBySessionID[sessionID] = tasks
        if didInterruptActiveTasks || !hasRunningTitleTask(sessionID: sessionID) {
            chatFeatureModel.sessions.regeneratingTitleSessionIDs.remove(sessionID)
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
        chatFeatureModel.sessions.backgroundTasksBySessionID[sessionID, default: []].contains { task in
            task.kind == "title_generation" && (task.status == .queued || task.status == .running)
        }
    }

    @discardableResult
    private func enqueueBackgroundTask(sessionID: String, title: String, detail: String, kind: String = "generic") -> AppSessionBackgroundTask {
        let task = AppSessionBackgroundTask(sessionID: sessionID, kind: kind, title: title, detail: detail)
        chatFeatureModel.sessions.backgroundTasksBySessionID[sessionID, default: []].append(task)
        do {
            try chatSessionRepository?.saveBackgroundTask(task.persisted)
        } catch {
            errorMessage = String(describing: error)
        }
        if kind == "title_generation" { chatFeatureModel.sessions.regeneratingTitleSessionIDs.insert(sessionID) }
        return task
    }

    private func updateBackgroundTask(sessionID: String, taskID: String, status: AppSessionBackgroundTaskStatus, detail: String? = nil, errorMessage: String? = nil) {
        guard var tasks = chatFeatureModel.sessions.backgroundTasksBySessionID[sessionID], let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = status
        tasks[index].updatedAt = Date()
        if let detail { tasks[index].detail = detail }
        tasks[index].errorMessage = errorMessage
        chatFeatureModel.sessions.backgroundTasksBySessionID[sessionID] = tasks
        do {
            try chatSessionRepository?.saveBackgroundTask(tasks[index].persisted)
        } catch {
            self.errorMessage = String(describing: error)
        }
        if !hasRunningTitleTask(sessionID: sessionID) {
            chatFeatureModel.sessions.regeneratingTitleSessionIDs.remove(sessionID)
        }
    }

    private func upsertBackgroundTask(_ task: AppSessionBackgroundTask) {
        var tasks = chatFeatureModel.sessions.backgroundTasksBySessionID[task.sessionID, default: []]
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.append(task)
        }
        chatFeatureModel.sessions.backgroundTasksBySessionID[task.sessionID] = tasks
        do {
            try chatSessionRepository?.saveBackgroundTask(task.persisted)
        } catch {
            errorMessage = String(describing: error)
        }
        if !hasRunningTitleTask(sessionID: task.sessionID) {
            chatFeatureModel.sessions.regeneratingTitleSessionIDs.remove(task.sessionID)
        }
    }

    private func runTitleGenerationTask(taskID: String, sessionID: String) {
        updateBackgroundTask(sessionID: sessionID, taskID: taskID, status: .running)
        Task {
            do {
                guard let chatSessionRepository else { return }
                let userPrompts = try await chatSessionTitleGenerationWorker.userPrompts(repository: chatSessionRepository, sessionID: sessionID)
                guard !userPrompts.isEmpty else {
                    let updated = try await chatSessionTitleGenerationWorker.renameSession(repository: chatSessionRepository, sessionID: sessionID, title: "新对话")
                    synchronizeRenamedChatSession(updated)
                    scheduleChatSessionListRefresh(reason: "titleGenerationCompleted")
                    updateBackgroundTask(sessionID: sessionID, taskID: taskID, status: .succeeded, detail: "没有用户 Prompt，已使用默认标题。")
                    return
                }
                let title = try await generateTitleFromUserPrompts(userPrompts, sessionID: sessionID)
                let updated = try await chatSessionTitleGenerationWorker.renameSession(repository: chatSessionRepository, sessionID: sessionID, title: title)
                synchronizeRenamedChatSession(updated)
                scheduleChatSessionListRefresh(reason: "titleGenerationCompleted")
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
            chatFeatureModel.sessions.regeneratingTitleSessionIDs.remove(sessionID)
            chatFeatureModel.sessions.backgroundTasksBySessionID.removeValue(forKey: sessionID)
            chatInputDraftsBySessionID.removeValue(forKey: sessionID)
            pendingAttachmentRefsBySessionID.removeValue(forKey: sessionID)
            agentEventTimelinesBySessionID.removeValue(forKey: sessionID)
            agentEventTimelinesByProcessKey = agentEventTimelinesByProcessKey.filter { key, _ in !key.hasPrefix("\(sessionID):") }
            if chatFeatureModel.sessions.selectedSessionID == sessionID {
                chatFeatureModel.sessions.selectedSessionID = nil
                replaceSelectedChatTranscript([])
                chatFeatureModel.run.eventTimeline = []
                chatFeatureModel.run.latestSummary = nil
                chatFeatureModel.sessions.selectedArtifactDirectories = nil
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
                chatSessionWorkspaceModes.setMode(mode, for: sessionID)
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
            chatFeatureModel.sessions.selectedSessionID = session.id
            agentEventTimelinesByProcessKey.removeAll(keepingCapacity: true)
            browserFeatureModel.resetWorkspaceBinding()
            chatFeatureModel.sessions.selectedArtifactDirectories = try chatSessionRepository.artifactDirectories(sessionID: session.id)
            try loadSessionCapsule(sessionID: session.id)
            try loadBackgroundTasks(sessionID: session.id)
            fallbackChatSession = session
            nativeSessionManager = makeNativeSessionManager(for: session)
            replaceSelectedChatTranscript([])
            restoreChatInputDraft(for: session.id)
            refreshSelectedSubmittingState()
            chatFeatureModel.run.eventTimeline = []
            agentEventTimelinesBySessionID[session.id] = []
            chatFeatureModel.run.latestSummary = nil
            chatFeatureModel.run.summaryMessage = nil
            chatFeatureModel.run.lastPromptInspection = nil
            reloadChatSessions(restoreWorkspaceMode: false)
            chatFeatureModel.sessions.selectedSessionID = session.id
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
            chatFeatureModel.run.eventTimeline = []
            return
        }

        let cachedTimeline = try chatSessionRepository.loadActivityTimelineCache(sessionID: sessionID)
        if !cachedTimeline.isEmpty {
            agentEventTimelinesBySessionID[sessionID] = cachedTimeline
            chatFeatureModel.run.eventTimeline = cachedTimeline
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
                agentEventTimelinesBySessionID[sessionID] = restored
                scheduleActivityTimelineCacheSave(sessionID: sessionID, timeline: restored)
                chatFeatureModel.run.eventTimeline = restored
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
                agentEventTimelinesBySessionID[sessionID] = restored
                scheduleActivityTimelineCacheSave(sessionID: sessionID, timeline: restored)
                chatFeatureModel.run.eventTimeline = restored
                return
            }
        }

        agentEventTimelinesBySessionID[sessionID] = []
        chatFeatureModel.run.eventTimeline = []
    }

    func openSessionFromNotification(_ sessionID: String) {
        selection = .agentChat
        chatFeatureModel.sessions.searchQuery = ""
        selectChatSession(sessionID)
    }

    func selectChatSession(_ sessionID: String) {
        guard let chatSessionRepository else { return }
        if chatFeatureModel.sessions.selectedSessionID == sessionID,
           chatFeatureModel.sessions.loadingSessionDetailID == nil,
           activeChatSession.id == sessionID {
            return
        }
        if chatFeatureModel.sessions.selectedSessionID != sessionID {
            _ = stopSpeechTranscriptionIfRunningForLeavingSession(chatFeatureModel.sessions.selectedSessionID)
        }
        rememberCurrentWorkspaceMode()
        chatSessionSelectionTask?.cancel()
        chatSessionSelectionGeneration += 1
        let generation = chatSessionSelectionGeneration
        let coordinator = chatSessionDetailLoadCoordinator
        let startedAt = ContinuousClock.now

        chatFeatureModel.sessions.selectedSessionID = sessionID
        chatFeatureModel.sessions.loadingSessionDetailID = sessionID
        replaceSelectedChatTranscript([])
        chatFeatureModel.run.eventTimeline = agentEventTimelinesBySessionID[sessionID] ?? []
        chatFeatureModel.run.latestSummary = nil
        chatFeatureModel.sessions.selectedArtifactDirectories = nil
        refreshSelectedSubmittingState()
        errorMessage = nil

        chatSessionSelectionTask = Task(priority: .userInitiated) { [weak self] in
            do {
                guard let snapshot = try await coordinator.load(repository: chatSessionRepository, sessionID: sessionID) else {
                    guard let self,
                          self.chatSessionSelectionGeneration == generation,
                          self.chatFeatureModel.sessions.selectedSessionID == sessionID
                    else { return }
                    self.errorMessage = "无法加载所选会话。"
                    self.chatFeatureModel.sessions.loadingSessionDetailID = nil
                    return
                }
                try Task.checkCancellation()
                guard let self,
                      self.isCurrentChatSessionSelection(sessionID: sessionID, generation: generation)
                else { return }
                self.applySelectedChatSessionSnapshot(snapshot, generation: generation, startedAt: startedAt)
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.isCurrentChatSessionSelection(sessionID: sessionID, generation: generation)
                else { return }
                self.errorMessage = String(describing: error)
                self.chatFeatureModel.sessions.loadingSessionDetailID = nil
            }
        }
    }

    private func isCurrentChatSessionSelection(sessionID: String, generation: Int) -> Bool {
        chatSessionSelectionGeneration == generation
            && chatFeatureModel.sessions.selectedSessionID == sessionID
            && chatFeatureModel.sessions.loadingSessionDetailID == sessionID
    }

    private func applySelectedChatSessionSnapshot(
        _ snapshot: ChatSessionDetailLoadSnapshot,
        generation: Int,
        startedAt: ContinuousClock.Instant
    ) {
        let session = snapshot.session
        do {
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
            agentEventTimelinesBySessionID[session.id] = snapshot.timeline
            chatFeatureModel.run.eventTimeline = snapshot.timeline
            chatFeatureModel.run.latestSummary = snapshot.latestSummary
            chatFeatureModel.sessions.selectedArtifactDirectories = snapshot.artifactDirectories
            restoreWorkspaceMode(for: session.id)
            syncLLMModelDisplayFromSession(session.id)
            chatFeatureModel.run.summaryMessage = nil
            chatFeatureModel.run.lastContext = nil
            chatFeatureModel.run.lastPromptInspection = nil
            chatFeatureModel.sessions.loadingSessionDetailID = nil
            errorMessage = nil
            let elapsed = startedAt.duration(to: ContinuousClock.now)
            let milliseconds = Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
            AppPerformanceLog.chatTurnLogger.info("sessionDetail.loaded session=\(session.id, privacy: .public) generation=\(generation, privacy: .public) messages=\(session.messages.count, privacy: .public) timeline=\(snapshot.timeline.count, privacy: .public) duration=\(milliseconds, privacy: .public)ms")
        } catch {
            errorMessage = String(describing: error)
            chatFeatureModel.sessions.loadingSessionDetailID = nil
        }
    }

    func setSessionListFilter(_ filter: AgentSessionListFilter, restoreWorkspaceMode: Bool = true) {
        chatFeatureModel.sessions.filter = filter
        reloadChatSessions(restoreWorkspaceMode: restoreWorkspaceMode)
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
                self.chatFeatureModel.sessions.selectedSessionID = session.id
                fallbackChatSession = session
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
                fallbackChatSession = updated
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

    func reloadPendingApprovals() {
        do {
            chatFeatureModel.approvals.pendingApprovals = try pendingApprovalRepository?.loadPending() ?? []
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
                chatFeatureModel.approvals.lastResultSummary = didSendToLiveBackend
                    ? "已批准权限请求 \(approval.requestID)，并写入审计、timeline，且已向当前运行中的 agent run 发送 resume。"
                    : "已批准权限请求 \(approval.requestID)，并写入审计、timeline；但当前未找到仍在线等待的 run，未发送 resume。请重试该会话请求。"
            case .denied:
                chatFeatureModel.approvals.lastResultSummary = didSendToLiveBackend
                    ? "已拒绝权限请求 \(approval.requestID)，并写入审计、timeline，且已向当前运行中的 agent run 发送 deny。"
                    : "已拒绝权限请求 \(approval.requestID)，并写入审计、timeline；但当前未找到仍在线等待的 run。"
            case .cancelled:
                chatFeatureModel.approvals.lastResultSummary = didSendToLiveBackend
                    ? "已取消权限请求 \(approval.requestID)，并写入审计、timeline，且已向当前运行中的 agent run 发送 cancel/deny。"
                    : "已取消权限请求 \(approval.requestID)，并写入审计、timeline；但当前未找到仍在线等待的 run。"
            case .pending:
                chatFeatureModel.approvals.lastResultSummary = "权限请求 \(approval.requestID) 仍为 pending。"
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
            Task { await runBackgroundJobs() }
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
        guard let submittingSessionID = chatFeatureModel.sessions.selectedSessionID,
              chatFeatureModel.run.submittingSessionIDs.contains(submittingSessionID)
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
        } else if var manager = nativeSessionManager, chatFeatureModel.sessions.selectedSessionID == sessionID {
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
        chatFeatureModel.run.submittingSessionIDs.remove(sessionID)
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
        var timeline = agentEventTimelinesBySessionID[sessionID] ?? chatFeatureModel.run.eventTimeline
        timeline.append(cancellation)
        agentEventTimelinesBySessionID[sessionID] = timeline
        scheduleActivityTimelineCacheSave(sessionID: sessionID, timeline: timeline)
        if chatFeatureModel.sessions.selectedSessionID == sessionID {
            chatFeatureModel.run.eventTimeline = timeline
        }
    }

    func setActiveSkill(slug: String) {
        chatFeatureModel.composer.activeSkillSlug = slug
        chatFeatureModel.composer.activeSkillDisplayName = skillRuntimeModel.definitions.first(where: { $0.slug == slug })?.manifest.name
            ?? skillRuntimeModel.presentation.cards.first(where: { $0.id == slug })?.title
            ?? slug
    }

    func clearActiveSkill() {
        chatFeatureModel.composer.activeSkillSlug = nil
        chatFeatureModel.composer.activeSkillDisplayName = nil
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
        guard var manager = nativeSessionManager else {
            errorMessage = String(describing: AppChatRuntimeUnavailableError.nativeSessionManagerUnavailable)
            return nil
        }
        let submittingSessionID = manager.session.id
        guard chatFeatureModel.sessions.selectedSessionID == nil || chatFeatureModel.sessions.selectedSessionID == submittingSessionID else { return nil }
        guard !chatFeatureModel.run.submittingSessionIDs.contains(submittingSessionID) else { return nil }
        let liveBackend = manager.backend
        activeChatBackendsBySessionID[submittingSessionID] = liveBackend
        if clearComposer {
            chatInputDraftsBySessionID[submittingSessionID] = ""
            if chatFeatureModel.sessions.selectedSessionID == submittingSessionID { setChatInputDraft("", for: submittingSessionID) }
            pendingAttachmentRefsBySessionID[submittingSessionID] = []
            if chatFeatureModel.sessions.selectedSessionID == submittingSessionID { chatFeatureModel.composer.pendingAttachmentRefs = [] }
        }
        agentEventTimelinesBySessionID[submittingSessionID] = []
        agentEventTimelinesByProcessKey = agentEventTimelinesByProcessKey.filter { key, _ in !key.hasPrefix("\(submittingSessionID):") }
        chatFeatureModel.run.eventTimeline = []
        chatFeatureModel.run.submittingSessionIDs.insert(submittingSessionID)
        activeChatRunIDsBySessionID.removeValue(forKey: submittingSessionID)
        refreshSelectedSubmittingState()
        applyKeepScreenAwakeSetting()
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
        if chatFeatureModel.sessions.selectedSessionID == submittingSessionID {
            chatFeatureModel.run.transcript = optimisticTranscript + [optimisticUserMessage]
        }
        chatFeatureModel.run.lastContext = nil
        chatFeatureModel.run.lastPromptInspection = nil
        defer {
            activeChatBackendsBySessionID.removeValue(forKey: submittingSessionID)
            if let runID = activeChatRunIDsBySessionID[submittingSessionID] {
                activeChatBackendsByRunID.removeValue(forKey: runID)
            }
            chatFeatureModel.run.submittingSessionIDs.remove(submittingSessionID)
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
                clearActiveSkill()
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
                    if self.chatFeatureModel.run.submittingSessionIDs.contains(submittingSessionID) {
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
                    if self.chatFeatureModel.sessions.selectedSessionID == submittingSessionID {
                        self.chatFeatureModel.run.eventTimeline = timeline
                    }
                    if presentation.kind == AgentEventKind.permissionRequested.rawValue {
                        self.reloadPendingApprovals()
                    }
                    self.skillRuntimeModel.reloadIfNeeded(after: presentation)
                }
            )
            let submitElapsed = submitStartedAt.duration(to: ContinuousClock.now)
            let submitMilliseconds = Double(submitElapsed.components.seconds) * 1_000 + Double(submitElapsed.components.attoseconds) / 1_000_000_000_000_000
            AppPerformanceLog.chatTurnLogger.info("nativeSubmit.completed session=\(submittingSessionID, privacy: .public) events=\(manager.eventPresentations.count, privacy: .public) duration=\(submitMilliseconds, privacy: .public)ms")
            agentEventTimelinesBySessionID[submittingSessionID] = manager.eventPresentations
            scheduleActivityTimelineCacheSave(sessionID: submittingSessionID, timeline: manager.eventPresentations)
            await flushActivityTimelineCache(sessionID: submittingSessionID)
            if chatFeatureModel.sessions.selectedSessionID == submittingSessionID {
                nativeSessionManager = manager
                fallbackChatSession = response.session
                chatFeatureModel.run.transcript = manager.session.messages
                chatFeatureModel.run.eventTimeline = manager.eventPresentations
                chatFeatureModel.sessions.selectedSessionID = response.session.id
                chatFeatureModel.run.latestSummary = try chatSessionRepository?.loadLatestSummary(sessionID: response.session.id)
                chatFeatureModel.run.lastContext = nil
                chatFeatureModel.run.lastPromptInspection = nil
            }
            reloadPendingApprovals()
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
            Task { await runBackgroundJobs() }
            Task { await runDailySweepIfNeeded() }
            return latestAssistantMessage?.content
        } catch {
            let recoveredSession = (try? chatSessionRepository?.loadSession(id: submittingSessionID)) ?? manager.session
            if chatFeatureModel.sessions.selectedSessionID == submittingSessionID {
                nativeSessionManager = manager
                fallbackChatSession = recoveredSession
                chatFeatureModel.run.transcript = recoveredSession.messages.isEmpty ? optimisticTranscript + [optimisticUserMessage] : recoveredSession.messages
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
        guard let selectedChatSessionID = chatFeatureModel.sessions.selectedSessionID, let chatSessionRepository else { return }
        chatFeatureModel.run.isSummarizing = true
        defer { chatFeatureModel.run.isSummarizing = false }
        do {
            let provider = try sessionLLMProvider(sessionID: selectedChatSessionID)
            let summarizer = AgentSessionSummarizer(provider: provider)
            let summary = try await chatSessionRepository.summarizeSession(id: selectedChatSessionID, using: summarizer)
            chatFeatureModel.run.latestSummary = summary
            chatFeatureModel.run.summaryMessage = latestChatSummaryRefreshState.successMessage
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
