import Foundation
import Observation
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphSearch

@MainActor
@Observable
final class ChatSessionListModel {
    var sessions: [AgentSession] = []
    var allSessions: [AgentSession] = []
    var selectedSessionID: String?
    var loadingSessionDetailID: String?
    var readStates: [String: SessionReadState] = [:]
    var regeneratingTitleSessionIDs: Set<String> = []
    var backgroundTasksBySessionID: [String: [AppSessionBackgroundTask]] = [:]
    var isBackgroundTasksPresented = false
    var filter: AgentSessionListFilter = .all
    var searchQuery = ""
    var selectedArtifactDirectories: AgentSessionArtifactDirectories?

}

@MainActor
@Observable
final class ChatComposerModel {
    var input = "" { didSet { if !isApplyingInput { onInputChanged(input) } } }
    var pendingAttachmentRefs: [AgentMessageAttachmentRef] = []
    var attachmentPreviewModel: AttachmentPreviewModel?
    var attachmentToast: AgentChatToast?
    var speechTranscriptionStatus: SessionSpeechTranscriptionStatus = .idle
    var speechProvisionalTranscript: String?
    var activeSkillSlug: String?
    var activeSkillDisplayName: String?
    @ObservationIgnored private var isApplyingInput = false
    @ObservationIgnored var onInputChanged: (String) -> Void = { _ in }

    func applyInput(_ value: String) { isApplyingInput = true; input = value; isApplyingInput = false }
}

@MainActor
@Observable
final class ChatRunModel {
    var transcript: [AgentMessage] = []
    var transcriptRevision = 0
    var lastContext: AgentContext?
    var lastPromptInspection: AgentChatPromptInspection?
    var submittingSessionIDs: Set<String> = []
    var isSubmitting = false
    var eventTimeline: [AgentEventPresentation] = []
    var latestSummary: AgentSessionSummary?
    var isSummarizing = false
    var summaryMessage: String?
}

@MainActor
@Observable
final class ChatApprovalModel {
    var pendingApprovals: [AgentPendingApproval] = []
    var lastResultSummary: String?
}

@MainActor
@Observable
final class ChatFeatureModel {
    let sessions = ChatSessionListModel()
    let composer = ChatComposerModel()
    let run = ChatRunModel()
    let approvals = ChatApprovalModel()

    func shutdown() {}
}
