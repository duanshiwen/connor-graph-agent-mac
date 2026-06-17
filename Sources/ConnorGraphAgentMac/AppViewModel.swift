import SwiftUI
import AppKit
import CoreLocation
import IOKit.pwr_mgt
import UserNotifications
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

@MainActor
final class AppViewModel: NSObject, ObservableObject {
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
    @Published var llmConnectionConfigs: [AppLLMConnectionConfig] = AppLLMSettings.default.connections
    @Published var llmDefaultConnectionID: String = AppLLMSettings.default.defaultConnectionID
    @Published var llmConnectionName: String = AppLLMSettings.default.defaultConnection.name
    @Published var llmProviderMode: AppLLMProviderMode = .openAICompatible
    @Published var llmBaseURLString: String = AppLLMSettings.default.baseURLString
    @Published var llmModel: String = AppLLMSettings.default.model
    @Published var llmSelectedModel: String = AppLLMSettings.default.effectiveModel
    @Published var llmThinkingLevel: AppLLMThinkingLevel = AppLLMSettings.default.defaultThinkingLevel
    @Published var llmAPIKeyInput: String = ""
    @Published var llmHasAPIKey: Bool = false
    @Published var sidecarExecutablePath: String = ""
    @Published var sidecarArguments: String = ""
    @Published var sidecarWorkingDirectoryPath: String = ""
    @Published var sidecarPermissionMode: AgentPermissionMode = .readOnly
    @Published var llmSettingsMessage: String?
    @Published var llmHealthCheckMessage: String?
    @Published var isTestingLLMConnection: Bool = false
    @Published var isAddingLLMConnection: Bool = false
    @Published var llmModelConnections: [AppLLMModelConnection] = []
    @Published var isLoadingLLMModelConnections: Bool = false
    @Published var chatSessions: [AgentSession] = []
    @Published var allChatSessions: [AgentSession] = []
    @Published var selectedChatSessionID: String?
    @Published var regeneratingTitleSessionIDs: Set<String> = []
    @Published var backgroundTasksBySessionID: [String: [AppSessionBackgroundTask]] = [:]
    @Published var isBackgroundTasksPresented: Bool = false
    @Published var sessionListFilter: AgentSessionListFilter = .all
    @Published var sessionSearchQuery: String = ""
    @Published var governanceConfig: AppSessionGovernanceConfig = .default
    @Published var productOSRegistry: ProductOSRegistrySnapshot = .default
    @Published var automationConfig: ProductOSAutomationConfig = .default
    @Published var automationTriggerRecords: [ProductOSAutomationTriggerRecord] = []
    @Published var automationExecutionHistory: [ProductOSAutomationExecutionHistoryRecord] = []
    @Published var sourceRuntimeConfigurations: [MCPSourceRuntimeConfiguration] = []
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
    @Published var browserAssistedWebFetchRequestsByTaskID: [UUID: BrowserAssistedWebFetchRequest] = [:]
    @Published var isBrowserBookmarksPanelVisible: Bool = false
    @Published var browserBookmarkRecords: [BrowserBookmarkRecord] = []
    @Published var filteredBrowserBookmarkRecords: [BrowserBookmarkRecord] = []
    @Published var selectedBrowserBookmarkGroupName: String?
    @Published var isBrowserHistoryPanelVisible: Bool = false
    @Published var browserHistoryRecords: [BrowserHistoryRecord] = []
    @Published var filteredBrowserHistoryRecords: [BrowserHistoryRecord] = []
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
    @Published var userCity: String = ""
    @Published var userCountry: String = ""
    @Published var userPreferenceNotes: String = ""
    @Published var userLocationStatusMessage: String?
    @Published var appSettingsMessage: String?
    @Published var pendingAttachmentRefs: [AgentMessageAttachmentRef] = []
    @Published var attachmentPreviewModel: AttachmentPreviewModel?

    private var repository: AppGraphRepository?
    private var promotionRepository: AppPromotionQueueRepository?
    private var graphWriteCandidateRepository: AppGraphWriteCandidateRepository?
    private var pendingApprovalRepository: AppAgentPendingApprovalRepository?
    private var graphExtractionTraceRepository: AppGraphExtractionTraceRepository?
    private var admissionHoldQueueRepository: AppGraphAdmissionHoldQueueRepository?
    private var memoryChangeLogRepository: AppGraphMemoryChangeLogRepository?
    private var chatSessionRepository: AppChatSessionRepository?
    private var governanceConfigRepository: AppSessionGovernanceConfigRepository?
    private var productOSRegistryRepository: AppProductOSRegistryRepository?
    private var automationRepository: AppProductOSAutomationRepository?
    private var sourceRuntimeRepository: AppMCPSourceRuntimeRepository?
    private var skillRuntimeRepository: AppSkillRuntimeRepository?
    private var storagePaths: AppStoragePaths?
    private var browserHistoryStore: BrowserHistoryStore?
    private var browserBookmarkStore: BrowserBookmarkStore?
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
    @Published private(set) var submittingChatSessionIDs: Set<String> = []
    private var activeChatRunIDsBySessionID: [String: String] = [:]
    private var activeChatBackendsBySessionID: [String: AnyAgentBackend] = [:]
    private var activeChatBackendsByRunID: [String: AnyAgentBackend] = [:]
    private var pendingChatCancellationReasonsBySessionID: [String: String] = [:]
    private var chatInputDraftsBySessionID: [String: String] = [:]
    private var pendingAttachmentRefsBySessionID: [String: [AgentMessageAttachmentRef]] = [:]
    private var browserAssistedWebFetchContinuationsByTaskID: [UUID: CheckedContinuation<BrowserAssistedWebFetchResult, Never>] = [:]
    private var isRestoringChatInputDraft = false
    private var agentEventTimelinesBySessionID: [String: [AgentEventPresentation]] = [:]
    private var agentEventTimelinesByProcessKey: [String: [AgentEventPresentation]] = [:]
    private var browserWorkspaceSessionBinding = BrowserWorkspaceSessionBinding()
    private var chatSessionWorkspaceModes = ChatSessionWorkspaceModeStore()
    private var isLoadingRuntimeSettings = false
    private var runtimeSettingsAutosaveTask: Task<Void, Never>?
    private var idleSleepAssertionID: IOPMAssertionID = 0
    private var hasActivatedRuntimeSettingsSideEffects = false
    private var locationCoordinator: UserLocationCoordinator?

    private var activeChatSession: AgentSession {
        nativeSessionManager?.session ?? fallbackChatSession
    }

    private var activeChatTranscript: [AgentMessage] {
        nativeSessionManager?.session.messages ?? fallbackChatSession.messages
    }

    var runtimeSettingsAutosaveSignature: String {
        [
            desktopNotificationsEnabled.description,
            keepScreenAwake.description,
            httpProxyEnabled.description,
            httpProxyURLString,
            appearanceMode.rawValue,
            showProviderIcons.description,
            richToolDescriptionsEnabled.description,
            composerSendShortcut,
            spellCheckEnabled.description,
            autoSaveDraftsEnabled.description,
            shortcutSettings.bindings.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue)=\($0.value.displayText)" }.joined(separator: ","),
            defaultPermissionMode.rawValue,
            requireApprovalForNetwork.description,
            requireApprovalForShell.description,
            userDisplayName,
            userTimezone,
            userPreferredLanguage,
            userCity,
            userCountry,
            userPreferenceNotes
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

    func setSidecarPermissionMode(_ mode: AgentPermissionMode) {
        guard mode != .allowAll else { return }
        sidecarPermissionMode = mode
        nativeSessionManager?.permissionMode = mode
        persistLLMSettings(rebuildRuntime: submittingChatSessionIDs.isEmpty)
        autoApproveCurrentPolicyPendingApprovals()
    }

    private func shouldAutoApprovePendingApproval(_ approval: AgentPendingApproval) -> Bool {
        guard approval.status == .pending else { return false }
        switch sidecarPermissionMode {
        case .trustedWrite:
            switch approval.capability {
            case .readGraph, .readSession, .modelCall, .proposeGraphWrite, .commitGraphWrite, .externalNetwork, .readWorkspaceFile, .listWorkspaceFiles, .searchWorkspaceFiles, .writeWorkspaceFile, .editWorkspaceFile, .computeScientific, .runReadOnlyShellCommand, .runWorkspaceShellCommand:
                return true
            case .invalidateGraphStatement, .deleteGraphObject, .costlyModelCall, .deleteWorkspaceFile, .runNetworkShellCommand, .runDestructiveShellCommand:
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
                    reason: "Automatically approved by current \(sidecarPermissionMode.displayName) policy",
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
        let supportedSummary = "Connor 当前支持添加文本、Markdown、日志、JSON/JSONL、CSV/TSV、XML/YAML、代码文件、常见图片（PNG/JPEG/GIF/WebP/HEIC/BMP/ICO/TIFF），以及 PDF、Word、Excel、PowerPoint 文档附件。暂不支持 HTML、音频、视频、iWork、压缩包、SVG/AVIF、数据库、可执行文件或未知格式。"
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
            selectedSidecarRuntimeDiagnostics: selectedSidecarRuntimeDiagnostics,
            sourceRuntimeConfigurations: sourceRuntimeConfigurations,
            skillRuntimeDefinitions: skillRuntimeDefinitions,
            automationConfig: automationConfig,
            graphMemoryDashboard: graphMemoryDashboardPresentation
        )
    }

    private var selectedSidecarRuntimeDiagnostics: ClaudeSDKSidecarRuntimeDiagnostics? {
        let activeID = activeChatSession.id
        return sidecarRuntimeDiagnostics.first { $0.record.connorSessionID == activeID } ?? sidecarRuntimeDiagnostics.first
    }

    private var graphMemoryDashboardPresentation: GraphMemoryDashboard {
        AppGraphMemoryDashboardBuilder().build(
            graphWriteCandidates: graphWriteCandidates,
            admissionHoldQueueItems: admissionHoldQueueItems,
            memoryChangeLogEntries: memoryChangeLogEntries
        )
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
            self.governanceConfigRepository = AppSessionGovernanceConfigRepository(configDirectory: storagePaths.configDirectory)
            self.productOSRegistryRepository = AppProductOSRegistryRepository(storagePaths: storagePaths)
            self.automationRepository = AppProductOSAutomationRepository(storagePaths: storagePaths)
            self.sourceRuntimeRepository = AppMCPSourceRuntimeRepository(storagePaths: storagePaths)
            self.skillRuntimeRepository = AppSkillRuntimeRepository(storagePaths: storagePaths)
            self.browserHistoryStore = BrowserHistoryStore(historyURL: storagePaths.browserHistoryURL)
            self.browserBookmarkStore = BrowserBookmarkStore(bookmarksURL: storagePaths.browserBookmarksURL)
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
        super.init()
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
        loadRuntimeSettings()
        self.nativeSessionManager = agentRuntimeFactory?.makeNativeSessionManager(session: initialSession)
        reloadProductOSRegistry()
        reloadAutomationConfig()
        reloadAutomationExecutionHistory()
        reloadSourceRuntimeConfigurations()
        reloadSkillRuntimeDefinitions()
        reloadSidecarRuntimeDiagnostics()
        reloadChatSessions()
        loadBrowserHistory()
        reloadSchemaHealthReport()
        reloadGraphExtractionTraces()
        reloadMemoryChangeLog()
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
            commercialSkillManagerPresentation = buildCommercialSkillManagerPresentation()
            if selectedSkillManagerCardID == nil || !commercialSkillManagerPresentation.cards.contains(where: { $0.id == selectedSkillManagerCardID }) {
                selectedSkillManagerCardID = commercialSkillManagerPresentation.cards.first?.id
            }
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
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
                selectedSkillManagerCardID = commercialSkillManagerPresentation.cards.first?.id
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
            }
        )
        if let timeline = agentEventTimelinesBySessionID[sessionID] {
            try chatSessionRepository?.saveActivityTimelineCache(sessionID: sessionID, timeline: timeline)
        }
    }

    private func buildAddSkillAgentPrompt(userRequest: String) -> String {
        let skillRoot = storagePaths?.skillsDirectory.path ?? "~/Library/Application Support/Connor/skills"
        let suggestion = suggestedSkillIdentity(for: userRequest, existingSlugs: currentUserSkillSlugs())
        return """
        你正在帮助用户为 Connor 创建一个新技能。用户在“添加技能”弹窗中输入了以下需求：

        \(userRequest)

        请按成熟技能创建流程工作：
        1. 如果需求不清楚，先用简短问题澄清技能的用途、触发时机、输入、输出和约束。
        2. 如果需求足够清楚，必须调用 `connor_skill_create` 创建技能；不要只在回复中说“已添加”。
        3. 推荐技能名称：\(suggestion.name)
        4. 推荐 slug：\(suggestion.slug)
        5. 目标目录：\(skillRoot)/\(suggestion.slug)/
        6. `connor_skill_create` 的 instructions 参数应包含完整 Markdown 工作流说明，包括适用场景、步骤、输出格式和注意事项。
        7. 创建完成后，请验证技能可以被 Connor 扫描，并告诉用户技能名称、slug 和文件路径。

        首选工具：`connor_skill_create`。只有当该工具不可用时，才使用通用文件写入工具，并明确说明降级原因。
        """
    }

    private func buildEditSkillAgentPrompt(card: SkillManagerCard, userRequest: String) -> String {
        return """
        你正在帮助用户修改一个已有 Connor 技能。用户在“编辑技能”弹窗中输入了以下修改需求：

        \(userRequest)

        当前技能信息：
        - slug: \(card.id)
        - name: \(card.title)
        - description: \(card.subtitle)
        - source tier: \(card.sourceTier)
        - skill file: \(card.path)
        - package: \(card.packagePath)
        - risk: \(card.riskLabel)
        - lifecycle: \(card.lifecycleLabel)
        - required sources: \(card.requiredSources.joined(separator: ", "))
        - permissions: \(card.permissionLabels.joined(separator: ", "))

        当前技能正文：
        ```markdown
        \(card.instructions)
        ```

        请按成熟技能修改流程工作：
        1. 如果修改需求不清楚，先简短澄清。
        2. 如果需求足够清楚，必须调用 `connor_skill_update` 修改 slug 为 `\(card.id)` 的技能；不要只回复修改建议。
        3. 尽量保留当前技能的有效结构，只调整用户要求改变的部分。
        4. 修改完成后，请说明修改了什么，并确认技能仍可被 Connor 扫描。

        首选工具：`connor_skill_update`。只有当该工具不可用时，才使用通用文件编辑工具，并明确说明降级原因。
        """
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
        let identity = suggestedSkillIdentity(for: userRequest, existingSlugs: currentSlugs)
        let directory = storagePaths.skillsDirectory.appendingPathComponent(identity.slug, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let skillURL = directory.appendingPathComponent("SKILL.md")
        try generatedSkillMarkdown(name: identity.name, slug: identity.slug, userRequest: userRequest).write(to: skillURL, atomically: true, encoding: .utf8)
        return identity.slug
    }

    private func suggestedSkillIdentity(for userRequest: String, existingSlugs: Set<String>) -> (name: String, slug: String) {
        let lowercased = userRequest.lowercased()
        let name: String
        let baseSlug: String
        if lowercased.contains("golang") || lowercased.contains("go language") || lowercased.contains(" go ") || lowercased.contains(".go") || lowercased.contains("go.mod") {
            name = "Go 语言专家"
            baseSlug = "go-expert"
        } else if let firstSentence = userRequest.split(whereSeparator: { ".。\n".contains($0) }).first {
            let trimmed = String(firstSentence).trimmingCharacters(in: .whitespacesAndNewlines)
            name = String(trimmed.prefix(28)).isEmpty ? "新技能" : String(trimmed.prefix(28))
            baseSlug = skillSlug(from: trimmed)
        } else {
            name = "新技能"
            baseSlug = "custom-skill"
        }
        var candidate = baseSlug.isEmpty ? "custom-skill" : baseSlug
        var suffix = 2
        while existingSlugs.contains(candidate) {
            candidate = "\(baseSlug)-\(suffix)"
            suffix += 1
        }
        return (name, candidate)
    }

    private func skillSlug(from text: String) -> String {
        let lowercased = text.lowercased()
        var result = ""
        var lastWasDash = false
        for scalar in lowercased.unicodeScalars {
            if CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").contains(scalar) {
                result.append(Character(scalar))
                lastWasDash = false
            } else if !lastWasDash {
                result.append("-")
                lastWasDash = true
            }
            if result.count >= 48 { break }
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.count >= 3 ? trimmed : "custom-skill"
    }

    private func generatedSkillMarkdown(name: String, slug: String, userRequest: String) -> String {
        let escapedName = name.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedDescription = userRequest.replacingOccurrences(of: "\"", with: "\\\"")
        let lowercased = userRequest.lowercased()
        let globs = (lowercased.contains("go") || lowercased.contains("golang")) ? "\n  - \"**/*.go\"\n  - \"**/go.mod\"" : ""
        return """
        ---
        name: "\(escapedName)"
        description: "\(escapedDescription)"
        tags:
          - generated
          - skill
        globs:\(globs.isEmpty ? " []" : globs)
        x-connor:
          lifecycle: stable
          riskLevel: low
          requiredCapabilities:
            - readSession
          graphContextPolicy: readOnly
          sourcePolicy: preenableIfReady
        ---

        # \(name)

        Use this skill when the user request matches the following need:

        > \(userRequest)

        ## When to use

        - The user asks for work in this specialty area.
        - The current task, files, or project context match the triggers described above.
        - The user needs structured review, debugging, planning, or implementation guidance.

        ## Workflow

        1. Restate the concrete task and identify the relevant context.
        2. Inspect available files, errors, requirements, or examples before making changes.
        3. Apply domain-specific best practices and explain important trade-offs.
        4. Produce actionable output: code, review findings, diagnosis, plan, or next steps.
        5. Call out assumptions, risks, validation steps, and follow-up work.

        ## Output

        - Be concise and practical.
        - Prefer concrete recommendations over generic advice.
        - Include commands, file paths, or code snippets when they help the user act.

        ## Notes

        Created by Connor Skill Manager as `\(slug)`.
        """
    }

    private func buildCommercialSkillManagerPresentation() -> SkillManagerPresentation {
        guard let storagePaths else {
            return SkillManagerPresentation(
                summary: SkillManagerSummary(total: 0, enabled: 0, projectScoped: 0, risky: 0, invalid: 0, sourceBlocked: 0),
                cards: [],
                globalWarnings: ["Storage paths are not initialized."]
            )
        }
        let roots = workspaceRoots
            .map { $0.path.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        let nestedRoots: [URL]
        if let primary = primaryWorkspaceRootDraft?.path.trimmingCharacters(in: .whitespacesAndNewlines), !primary.isEmpty {
            nestedRoots = [URL(fileURLWithPath: primary, isDirectory: true)]
        } else {
            nestedRoots = []
        }
        let snapshot = SkillPackageScanner().scan(storagePaths: storagePaths, projectRoots: roots, nestedRoots: nestedRoots)
        return SkillCommercialUIPresentationBuilder().build(snapshot: snapshot)
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
            sidecarExecutablePath = connection.sidecarExecutablePath
            sidecarArguments = connection.sidecarArguments
            sidecarWorkingDirectoryPath = connection.sidecarWorkingDirectoryPath
            sidecarPermissionMode = connection.sidecarPermissionMode
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
        sidecarExecutablePath = connection.sidecarExecutablePath
        sidecarArguments = connection.sidecarArguments
        sidecarWorkingDirectoryPath = connection.sidecarWorkingDirectoryPath
        sidecarPermissionMode = connection.sidecarPermissionMode
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
        let defaultBaseURL = providerMode == .openAICompatible ? AppLLMSettings.default.baseURLString : ""
        let defaultModel = providerMode == .openAICompatible ? AppLLMSettings.default.model : "claude-sdk-default"
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
                hasAPIKey: llmHasAPIKey,
                sidecarExecutablePath: sidecarExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines),
                sidecarArguments: sidecarArguments.trimmingCharacters(in: .whitespacesAndNewlines),
                sidecarWorkingDirectoryPath: sidecarWorkingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines),
                sidecarPermissionMode: sidecarPermissionMode
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
                nativeSessionManager?.permissionMode = sidecarPermissionMode
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
        fallbackChatSession = session
        nativeSessionManager = makeNativeSessionManager(for: session)
    }

    private func syncLLMModelDisplayFromSession(_ sessionID: String) {
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
            llmSelectedModel = settings?.effectiveModel ?? llmSelectedModel
            llmThinkingLevel = settings?.defaultThinkingLevel ?? llmThinkingLevel
            llmProviderMode = settings?.providerMode ?? llmProviderMode
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
        llmSelectedModel = settings?.effectiveModel ?? llmSelectedModel
        llmThinkingLevel = settings?.defaultThinkingLevel ?? llmThinkingLevel
        llmProviderMode = settings?.providerMode ?? llmProviderMode
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
            appSettingsMessage = "当前会话 Workspace 已保存。"
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
            if settings.schemaVersion < 3,
               settings.preferences.displayName == "诗闻",
               settings.preferences.timezone == "Asia/Shanghai",
               settings.preferences.city == "杭州",
               settings.preferences.country == "中国",
               settings.preferences.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                settings.preferences = AgentRuntimePreferenceSettings()
                settings.schemaVersion = 3
                shouldPersistSystemPreferenceDefaults = true
            }
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
            settings.schemaVersion = 4
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
            settings.shortcuts = shortcutSettings
            settings.permissions.requireApprovalForNetwork = requireApprovalForNetwork
            settings.permissions.requireApprovalForShell = requireApprovalForShell
                // Workspace roots are session-scoped and saved into Session Capsule.
            // Keep runtime-settings.workspace as a legacy fallback/template only.
            settings.workspace.recentWorkspacePaths = recentWorkspacePaths
            settings.preferences.displayName = userDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.preferences.timezone = userTimezone.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.preferences.preferredLanguage = userPreferredLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.preferences.city = userCity.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.preferences.country = userCountry.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.preferences.notes = userPreferenceNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            try runtimeSettingsRepository?.save(settings)
            applyRuntimeSettingsSideEffects()
            if submittingChatSessionIDs.isEmpty {
                rebuildNativeSessionManagerForActiveSession()
            } else {
                nativeSessionManager?.permissionMode = settings.loop.permissionMode
            }
            appSettingsMessage = nil
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
        } else if idleSleepAssertionID != 0 {
            IOPMAssertionRelease(idleSleepAssertionID)
            idleSleepAssertionID = 0
        }
    }

    private func postDesktopNotification(title: String, body: String) {
        guard desktopNotificationsEnabled, canUseUserNotifications else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private var canUseUserNotifications: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
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
        saveGovernanceConfig(config, successMessage: "状态定义已保存。")
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
            saveGovernanceConfig(config, successMessage: "状态“\(definition.name)”已删除。")
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
        saveGovernanceConfig(config, successMessage: "标签定义已保存。")
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
            saveGovernanceConfig(config, successMessage: "标签“\(definition.name)”已删除，并已从 \(removedFromSessionCount) 个会话移除。")
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

    private func saveGovernanceConfig(_ config: AppSessionGovernanceConfig, successMessage: String) {
        do {
            let normalizedConfig = AppSessionGovernanceConfig(statuses: config.statuses, labels: config.labels)
            try governanceConfigRepository?.save(normalizedConfig)
            governanceConfig = normalizedConfig
            chatSessionRepository?.governanceConfig = normalizedConfig
            automationConfig = try automationRepository?.loadOrCreateDefault(governanceConfig: normalizedConfig) ?? automationConfig
            appSettingsMessage = successMessage
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
            appSettingsMessage = "设置已恢复默认值。"
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func reloadChatSessions(restoreWorkspaceMode shouldRestoreWorkspaceMode: Bool = true) {
        guard let chatSessionRepository else {
            transcript = activeChatTranscript
            chatSessions = [activeChatSession]
            allChatSessions = [activeChatSession]
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
            let selectedID = selectedChatSessionID ?? sessions.first?.id
            selectedChatSessionID = selectedID
            if let selectedID, let session = try chatSessionRepository.loadSession(id: selectedID) {
                try loadSessionCapsule(sessionID: selectedID)
                try loadBackgroundTasks(sessionID: selectedID)
                fallbackChatSession = session
                nativeSessionManager = makeNativeSessionManager(for: session)
                transcript = session.messages
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
            try loadBackgroundTasks(sessionID: session.id)
            fallbackChatSession = session
            nativeSessionManager = makeNativeSessionManager(for: session)
            transcript = []
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
            transcript = updated.messages
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
                let title = try await generateTitleFromUserPrompts(userPrompts)
                renameChatSession(sessionID, title: title)
                updateBackgroundTask(sessionID: sessionID, taskID: taskID, status: .succeeded, detail: "已更新为：\(title)")
            } catch {
                updateBackgroundTask(sessionID: sessionID, taskID: taskID, status: .failed, errorMessage: String(describing: error))
                errorMessage = String(describing: error)
            }
        }
    }

    private func generateTitleFromUserPrompts(_ prompts: [String]) async throws -> String {
        let provider = Self.makeLLMProvider(settingsRepository: llmSettingsRepository)
        let joinedPrompts = prompts.enumerated().map { index, prompt in
            "用户 Prompt \(index + 1):\n\(prompt)"
        }.joined(separator: "\n\n---\n\n")
        let prompt = """
        你是会话标题生成器。请根据下面这个对话中所有用户 Prompt，生成一个中文会话标题。

        要求：
        - 20 个汉字以内
        - 不要引号
        - 不要句号
        - 不要解释
        - 只输出标题本身

        \(joinedPrompts)
        """
        let response = try await provider.complete(prompt: prompt, context: AgentContext(query: "session-title", items: []))
        return sanitizedSessionTitle(response.text)
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
                transcript = []
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
        browserTargetURLString = bookmark.url
        showBrowserWorkspace()
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
        fetchContentForBrowserHistoryRecord(appendedRecord)
    }

    private func fetchContentForBrowserHistoryRecord(_ record: BrowserHistoryRecord) {
        guard let store = browserHistoryStore else { return }
        let recordID = record.id
        let url = record.url
        Task.detached(priority: .utility) {
            let tool = SearchEngineMCPWebFetchTool()
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
                store.updateContent(id: recordID, markdown: result.contentText, status: .fetched)
            } catch {
                store.updateContent(id: recordID, markdown: nil, status: .failed, error: String(describing: error))
            }
            await MainActor.run { [weak self] in
                self?.loadBrowserHistory()
            }
        }
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
        guard let store = browserHistoryStore else { return }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            filteredBrowserHistoryRecords = browserHistoryRecords
        } else {
            filteredBrowserHistoryRecords = store.searchHistory(query: trimmed)
        }
    }

    func deleteBrowserHistoryRecord(_ id: UUID) {
        browserHistoryStore?.deleteRecord(id: id)
        loadBrowserHistory()
    }

    func clearBrowserHistory() {
        browserHistoryStore?.clearHistory()
        browserHistoryRecords = []
        filteredBrowserHistoryRecords = []
    }

    func navigateToHistoryRecord(_ record: BrowserHistoryRecord) {
        // Switch to the session that owns this history record
        if record.sessionID != selectedChatSessionID {
            selectChatSession(record.sessionID)
        }
        // Open URL in browser — the onChange handler in BrowserWorkspaceView
        // will detect the URL change and navigate the active WKWebView
        browserTargetURLString = record.url
        showBrowserWorkspace()
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
        filteredBrowserHistoryRecords = browserHistoryRecords
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
                try? chatSessionRepository.saveActivityTimelineCache(sessionID: sessionID, timeline: restored)
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
            try loadBackgroundTasks(sessionID: session.id)
            fallbackChatSession = session
            nativeSessionManager = makeNativeSessionManager(for: session)
            transcript = session.messages
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
            let session = try chatSessionRepository.setStatus(sessionID: sessionID, status: status)
            if selectedChatSessionID == sessionID {
                self.selectedChatSessionID = session.id
                fallbackChatSession = session
            }
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
                    ? "已批准权限请求 \(approval.requestID)，并写入审计、timeline，且已向当前运行中的 sidecar/run 发送 resume。"
                    : "已批准权限请求 \(approval.requestID)，并写入审计、timeline；但当前未找到仍在线等待的 run，未发送 resume。请重试该会话请求。"
            case .denied:
                lastPendingApprovalResultSummary = didSendToLiveBackend
                    ? "已拒绝权限请求 \(approval.requestID)，并写入审计、timeline，且已向当前运行中的 sidecar/run 发送 deny。"
                    : "已拒绝权限请求 \(approval.requestID)，并写入审计、timeline；但当前未找到仍在线等待的 run。"
            case .cancelled:
                lastPendingApprovalResultSummary = didSendToLiveBackend
                    ? "已取消权限请求 \(approval.requestID)，并写入审计、timeline，且已向当前运行中的 sidecar/run 发送 cancel/deny。"
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
        postDesktopNotification(title: "康纳同学已取消", body: "当前会话运行已终止。")
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

    private func buildSkillChatPromptAugmentation(prompt: String, sessionID: String) -> SkillChatPromptAugmentation {
        guard let storagePaths else {
            return SkillChatPromptAugmentation(originalPrompt: prompt, augmentedPrompt: prompt)
        }
        let roots = workspaceRoots
            .map { $0.path.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        let nestedRoots: [URL]
        if let primary = primaryWorkspaceRootDraft?.path.trimmingCharacters(in: .whitespacesAndNewlines), !primary.isEmpty {
            nestedRoots = [URL(fileURLWithPath: primary, isDirectory: true)]
        } else {
            nestedRoots = []
        }
        return SkillChatPromptAugmentor(storagePaths: storagePaths).augment(
            prompt: prompt,
            sessionID: sessionID,
            projectRoots: roots,
            nestedRoots: nestedRoots
        )
    }

    @discardableResult
    func submitChat(prompt rawPrompt: String, clearComposer: Bool = false, displayPrompt rawDisplayPrompt: String? = nil) async -> String? {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayPrompt = rawDisplayPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachmentsForSubmission = pendingAttachmentRefs
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
        let optimisticUserMessage = AgentMessage(
            role: .user,
            content: displayPrompt?.isEmpty == false ? displayPrompt! : prompt,
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
            let skillAugmentation = buildSkillChatPromptAugmentation(prompt: prompt, sessionID: submittingSessionID)
            let response = try await manager.submit(
                skillAugmentation.augmentedPrompt,
                sessionSummary: sessionSummary,
                displayPrompt: displayPrompt?.isEmpty == false ? displayPrompt : nil,
                attachments: attachmentsForSubmission,
                attachmentContextPlan: attachmentContextPlan,
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
                allChatSessions = try chatSessionRepository.loadSessions(filter: .all)
            }
            if shouldAutoGenerateInitialTitle {
                regenerateChatSessionTitle(submittingSessionID)
            }
            errorMessage = nil
            postDesktopNotification(title: "康纳同学完成了工作", body: response.session.title)
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
                postDesktopNotification(title: "康纳同学遇到错误", body: String(describing: error))
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
