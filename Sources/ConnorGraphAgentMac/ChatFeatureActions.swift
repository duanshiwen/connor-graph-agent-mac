import Foundation
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore

@MainActor protocol ChatSessionCommanding: AnyObject {
    var isLoadingSelectedChatSessionDetail: Bool { get }
    func reloadChatSessionsIfNeededAfterInitialLoad(restoreWorkspaceMode: Bool)
    func reloadChatSessions(restoreWorkspaceMode: Bool)
    func loadMoreChatSessionsIfNeeded(currentSessionID: String)
    func newChatSession()
    func selectChatSession(_ sessionID: String)
    func renameChatSession(_ sessionID: String, title: String)
    func setSessionListFilter(_ filter: AgentSessionListFilter, restoreWorkspaceMode: Bool)
    func setSelectedSessionStatus(_ status: AgentSessionStatus)
    func toggleSelectedSessionFlag()
    func toggleSelectedSessionLabel(_ labelID: String)
}

extension ChatSessionCommanding {
    func reloadChatSessionsIfNeededAfterInitialLoad() { reloadChatSessionsIfNeededAfterInitialLoad(restoreWorkspaceMode: true) }
    func reloadChatSessions() { reloadChatSessions(restoreWorkspaceMode: true) }
    func setSessionListFilter(_ filter: AgentSessionListFilter) { setSessionListFilter(filter, restoreWorkspaceMode: true) }
}

@MainActor protocol ChatComposerCommanding: AnyObject {
    var canSubmitCurrentChat: Bool { get }
    var isSpeechTranscriptionRunningForSelectedSession: Bool { get }
    func updateSelectedChatInputDraft(_ draft: String)
    func appendToSelectedChatInputDraft(_ addition: String)
    func enqueueAttachmentImport(urls: [URL])
    func importAttachments(urls: [URL]) async -> AttachmentImportBatchResult
    func showAttachmentToast(title: String, message: String, systemImage: String)
    func removePendingAttachment(id: String)
    func previewAttachment(_ attachment: AgentMessageAttachmentRef)
    func localAttachmentFileURL(_ attachment: AgentMessageAttachmentRef) -> URL?
    func retryAttachmentExtraction(attachmentID: String)
    func currentModelSupportsImages() -> Bool
    func setActiveSkill(slug: String)
    func clearActiveSkill()
    func toggleSpeechTranscriptionForSelectedSession()
    func beginSpeechTranscriptionForSelectedSession(speechInsertionRange: NSRange?)
    func finishSpeechTranscriptionForSelectedSession()
}

extension ChatComposerCommanding {
    func showAttachmentToast(title: String, message: String) { showAttachmentToast(title: title, message: message, systemImage: "exclamationmark.triangle") }
}

@MainActor protocol ChatRunCommanding: AnyObject {
    var activeSessionBackgroundTasks: [AppSessionBackgroundTask] { get }
    var hasRunningActiveSessionBackgroundTask: Bool { get }
    var latestChatSummaryFreshness: AgentSessionSummaryFreshness? { get }
    var latestChatSummaryContextMessage: String { get }
    func submitNewChat(prompt: String, displayPrompt: String?) async -> String?
    func submitChat(prompt: String, clearComposer: Bool, displayPrompt: String?, attachments: [AgentMessageAttachmentRef]?, personReferences: [PersonReference]) async -> String?
    func cancelActiveChatRun()
    func setAgentPermissionMode(_ mode: AgentPermissionMode)
    func restoredAgentEventTimeline(for process: AgentChatTurnProcessPresentation) async -> [AgentEventPresentation]
    func markdownPersistentCacheContext(messageID: String) -> AgentMarkdownPersistentCacheContext?
    func copyAssistantMessageToPasteboard(_ message: AgentChatMessagePresentation)
    func exportAssistantMessageToFile(_ message: AgentChatMessagePresentation, now: Date)
    func downloadPreviewImage(_ model: AttachmentPreviewModel)
    func clearSessionLLMOverride()
    func selectLLMModel(_ model: String, providerMode: AppLLMProviderMode, connectionID: String?)
    func selectLLMThinkingLevel(_ level: AppLLMThinkingLevel)
    func selectDefaultLLMThinkingLevel(_ level: AppLLMThinkingLevel)
    func reloadLLMModelConnections() async
    func setSessionRemoteKnowledgeBaseIDs(_ ids: [String]?)
    func setSessionAllowedMCPToolNames(_ names: [String]?)
}

extension ChatRunCommanding {
    func submitChat(prompt: String, clearComposer: Bool = false, displayPrompt: String? = nil, attachments: [AgentMessageAttachmentRef]? = nil, personReferences: [PersonReference] = []) async -> String? {
        await submitChat(prompt: prompt, clearComposer: clearComposer, displayPrompt: displayPrompt, attachments: attachments, personReferences: personReferences)
    }
    func exportAssistantMessageToFile(_ message: AgentChatMessagePresentation) { exportAssistantMessageToFile(message, now: Date()) }
}

@MainActor protocol ChatApprovalCommanding: AnyObject {
    var activeChatPendingApprovals: [AgentPendingApproval] { get }
    func reloadPendingApprovals()
    func loadMorePendingApprovalsIfNeeded(currentApprovalID: String)
    func approvePendingApproval(_ approval: AgentPendingApproval)
    func denyPendingApproval(_ approval: AgentPendingApproval)
    func cancelPendingApproval(_ approval: AgentPendingApproval)
    func alwaysAllowPendingApproval(_ approval: AgentPendingApproval)
}

@MainActor protocol ChatWorkspaceCommanding: AnyObject {
    func openURLInCurrentChatBrowser(_ url: URL)
    func appendSessionRecord(kind: String, title: String?, body: String?, metadata: [String: String], sessionID: String?)
}

@MainActor protocol ChatErrorReporting: AnyObject {
    var errorMessage: String? { get set }
}

@MainActor
struct ChatFeatureDependencies {
    let browser: BrowserFeatureModel
    let appSettings: AppSettingsFeatureModel
    let inputSettings: InputSettingsFeatureModel
    let userPreferences: UserPreferencesFeatureModel
    let workspaceSettings: WorkspaceSettingsFeatureModel
    let skills: SkillRuntimeFeatureModel
    let contacts: ContactsFeatureModel
    let governance: GovernanceFeatureModel
    let aiConnections: AIConnectionsFeatureModel
    let speechPlayback: ConnorSpeechPlaybackCoordinator
    let knowledgeMarketplace: CloudKnowledgeMarketplaceStore
    let sources: SourceRuntimeFeatureModel
    let permissionMode: () -> AgentPermissionMode
    let sessionHasLLMOverride: () -> Bool
}

@MainActor
final class ChatFeatureActions {
    let session: any ChatSessionCommanding
    let composer: any ChatComposerCommanding
    let run: any ChatRunCommanding
    let approval: any ChatApprovalCommanding
    let workspace: any ChatWorkspaceCommanding
    let errors: any ChatErrorReporting
    let dependencies: ChatFeatureDependencies

    init(
        session: any ChatSessionCommanding,
        composer: any ChatComposerCommanding,
        run: any ChatRunCommanding,
        approval: any ChatApprovalCommanding,
        workspace: any ChatWorkspaceCommanding,
        errors: any ChatErrorReporting,
        dependencies: ChatFeatureDependencies
    ) {
        self.session = session
        self.composer = composer
        self.run = run
        self.approval = approval
        self.workspace = workspace
        self.errors = errors
        self.dependencies = dependencies
    }
}

@MainActor
final class ClosureChatSessionPort: ChatSessionCommanding {
    let isLoading: () -> Bool
    let reloadIfNeededAction: (Bool) -> Void
    let reloadAction: (Bool) -> Void
    let loadMoreAction: (String) -> Void
    let newAction: () -> Void
    let selectAction: (String) -> Void
    let renameAction: (String, String) -> Void
    let filterAction: (AgentSessionListFilter, Bool) -> Void
    let statusAction: (AgentSessionStatus) -> Void
    let flagAction: () -> Void
    let labelAction: (String) -> Void
    var isLoadingSelectedChatSessionDetail: Bool { isLoading() }
    func reloadChatSessionsIfNeededAfterInitialLoad(restoreWorkspaceMode: Bool) { reloadIfNeededAction(restoreWorkspaceMode) }
    func reloadChatSessions(restoreWorkspaceMode: Bool) { reloadAction(restoreWorkspaceMode) }
    func loadMoreChatSessionsIfNeeded(currentSessionID: String) { loadMoreAction(currentSessionID) }
    func newChatSession() { newAction() }
    func selectChatSession(_ sessionID: String) { selectAction(sessionID) }
    func renameChatSession(_ sessionID: String, title: String) { renameAction(sessionID, title) }
    func setSessionListFilter(_ filter: AgentSessionListFilter, restoreWorkspaceMode: Bool) { filterAction(filter, restoreWorkspaceMode) }
    func setSelectedSessionStatus(_ status: AgentSessionStatus) { statusAction(status) }
    func toggleSelectedSessionFlag() { flagAction() }
    func toggleSelectedSessionLabel(_ labelID: String) { labelAction(labelID) }
    init(isLoading: @escaping () -> Bool, reloadIfNeeded: @escaping (Bool) -> Void, reload: @escaping (Bool) -> Void, loadMore: @escaping (String) -> Void, new: @escaping () -> Void, select: @escaping (String) -> Void, rename: @escaping (String, String) -> Void, filter: @escaping (AgentSessionListFilter, Bool) -> Void, status: @escaping (AgentSessionStatus) -> Void, flag: @escaping () -> Void, label: @escaping (String) -> Void) {
        self.isLoading = isLoading; reloadIfNeededAction = reloadIfNeeded; reloadAction = reload; loadMoreAction = loadMore; newAction = new; selectAction = select; renameAction = rename; filterAction = filter; statusAction = status; flagAction = flag; labelAction = label
    }
}

@MainActor
final class ClosureChatRunPort: ChatRunCommanding {
    let backgroundTasks: () -> [AppSessionBackgroundTask]
    let hasBackgroundTask: () -> Bool
    let summaryFreshness: () -> AgentSessionSummaryFreshness?
    let summaryContext: () -> String
    let submitNewChatAction: (String, String?) async -> String?
    let submitAction: (String, Bool, String?, [AgentMessageAttachmentRef]?, [PersonReference]) async -> String?
    let cancelAction: () -> Void
    let permissionAction: (AgentPermissionMode) -> Void
    let timelineAction: (AgentChatTurnProcessPresentation) async -> [AgentEventPresentation]
    let markdownAction: (String) -> AgentMarkdownPersistentCacheContext?
    let copyAction: (AgentChatMessagePresentation) -> Void
    let exportAction: (AgentChatMessagePresentation, Date) -> Void
    let downloadAction: (AttachmentPreviewModel) -> Void
    let clearOverrideAction: () -> Void
    let selectModelAction: (String, AppLLMProviderMode, String?) -> Void
    let thinkingAction: (AppLLMThinkingLevel) -> Void
    let defaultThinkingAction: (AppLLMThinkingLevel) -> Void
    let reloadModelsAction: () async -> Void
    let remoteKnowledgeAction: ([String]?) -> Void
    let mcpToolsAction: ([String]?) -> Void
    var activeSessionBackgroundTasks: [AppSessionBackgroundTask] { backgroundTasks() }
    var hasRunningActiveSessionBackgroundTask: Bool { hasBackgroundTask() }
    var latestChatSummaryFreshness: AgentSessionSummaryFreshness? { summaryFreshness() }
    var latestChatSummaryContextMessage: String { summaryContext() }
    func submitNewChat(prompt: String, displayPrompt: String?) async -> String? { await submitNewChatAction(prompt, displayPrompt) }
    func submitChat(prompt: String, clearComposer: Bool, displayPrompt: String?, attachments: [AgentMessageAttachmentRef]?, personReferences: [PersonReference]) async -> String? { await submitAction(prompt, clearComposer, displayPrompt, attachments, personReferences) }
    func cancelActiveChatRun() { cancelAction() }
    func setAgentPermissionMode(_ mode: AgentPermissionMode) { permissionAction(mode) }
    func restoredAgentEventTimeline(for process: AgentChatTurnProcessPresentation) async -> [AgentEventPresentation] { await timelineAction(process) }
    func markdownPersistentCacheContext(messageID: String) -> AgentMarkdownPersistentCacheContext? { markdownAction(messageID) }
    func copyAssistantMessageToPasteboard(_ message: AgentChatMessagePresentation) { copyAction(message) }
    func exportAssistantMessageToFile(_ message: AgentChatMessagePresentation, now: Date) { exportAction(message, now) }
    func downloadPreviewImage(_ model: AttachmentPreviewModel) { downloadAction(model) }
    func clearSessionLLMOverride() { clearOverrideAction() }
    func selectLLMModel(_ model: String, providerMode: AppLLMProviderMode, connectionID: String?) { selectModelAction(model, providerMode, connectionID) }
    func selectLLMThinkingLevel(_ level: AppLLMThinkingLevel) { thinkingAction(level) }
    func selectDefaultLLMThinkingLevel(_ level: AppLLMThinkingLevel) { defaultThinkingAction(level) }
    func reloadLLMModelConnections() async { await reloadModelsAction() }
    func setSessionRemoteKnowledgeBaseIDs(_ ids: [String]?) { remoteKnowledgeAction(ids) }
    func setSessionAllowedMCPToolNames(_ names: [String]?) { mcpToolsAction(names) }
    init(backgroundTasks: @escaping () -> [AppSessionBackgroundTask], hasBackgroundTask: @escaping () -> Bool, summaryFreshness: @escaping () -> AgentSessionSummaryFreshness?, summaryContext: @escaping () -> String, submitNewChat: @escaping (String, String?) async -> String?, submit: @escaping (String, Bool, String?, [AgentMessageAttachmentRef]?, [PersonReference]) async -> String?, cancel: @escaping () -> Void, permission: @escaping (AgentPermissionMode) -> Void, timeline: @escaping (AgentChatTurnProcessPresentation) async -> [AgentEventPresentation], markdown: @escaping (String) -> AgentMarkdownPersistentCacheContext?, copy: @escaping (AgentChatMessagePresentation) -> Void, export: @escaping (AgentChatMessagePresentation, Date) -> Void, download: @escaping (AttachmentPreviewModel) -> Void, clearOverride: @escaping () -> Void, selectModel: @escaping (String, AppLLMProviderMode, String?) -> Void, thinking: @escaping (AppLLMThinkingLevel) -> Void, defaultThinking: @escaping (AppLLMThinkingLevel) -> Void, reloadModels: @escaping () async -> Void, remoteKnowledge: @escaping ([String]?) -> Void, mcpTools: @escaping ([String]?) -> Void) {
        self.backgroundTasks = backgroundTasks; self.hasBackgroundTask = hasBackgroundTask; self.summaryFreshness = summaryFreshness; self.summaryContext = summaryContext; submitNewChatAction = submitNewChat; submitAction = submit; cancelAction = cancel; permissionAction = permission; timelineAction = timeline; markdownAction = markdown; copyAction = copy; exportAction = export; downloadAction = download; clearOverrideAction = clearOverride; selectModelAction = selectModel; thinkingAction = thinking; defaultThinkingAction = defaultThinking; reloadModelsAction = reloadModels; remoteKnowledgeAction = remoteKnowledge; mcpToolsAction = mcpTools
    }
}

@MainActor
final class ClosureChatWorkspacePort: ChatWorkspaceCommanding {
    let openAction: (URL) -> Void
    let recordAction: (String, String?, String?, [String: String], String?) -> Void
    init(open: @escaping (URL) -> Void, record: @escaping (String, String?, String?, [String: String], String?) -> Void) { openAction = open; recordAction = record }
    func openURLInCurrentChatBrowser(_ url: URL) { openAction(url) }
    func appendSessionRecord(kind: String, title: String?, body: String?, metadata: [String: String], sessionID: String?) { recordAction(kind, title, body, metadata, sessionID) }
}

@MainActor
final class ClosureChatErrorPort: ChatErrorReporting {
    let getError: () -> String?
    let setError: (String?) -> Void
    init(get: @escaping () -> String?, set: @escaping (String?) -> Void) { getError = get; setError = set }
    var errorMessage: String? { get { getError() } set { setError(newValue) } }
}
