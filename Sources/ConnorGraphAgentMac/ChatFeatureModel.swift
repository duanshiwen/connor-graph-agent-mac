import Foundation
import Observation
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphSearch

struct ChatSessionSidebarSummary: Sendable, Equatable {
    var totalCount: Int = 0
    var countsByStatus: [AgentSessionStatus: Int] = [:]
    var countsByLabelID: [String: Int] = [:]

    static func build(from sessions: [AgentSession]) -> ChatSessionSidebarSummary {
        var summary = ChatSessionSidebarSummary(totalCount: sessions.count)
        for session in sessions {
            summary.countsByStatus[session.governance.status, default: 0] += 1
            for label in session.governance.labels {
                summary.countsByLabelID[label.id, default: 0] += 1
            }
        }
        return summary
    }
}

enum ChatSessionExecutionPresentation: Sendable, Equatable {
    case idle
    case running
    case awaitingApproval

    static func resolve(isSubmitting: Bool, hasPendingApproval: Bool) -> Self {
        if hasPendingApproval { return .awaitingApproval }
        return isSubmitting ? .running : .idle
    }

    var statusText: String? {
        switch self {
        case .idle: nil
        case .running: "运行中"
        case .awaitingApproval: "请求审批"
        }
    }

    var systemImage: String? {
        switch self {
        case .idle, .running: nil
        case .awaitingApproval: "lock.fill"
        }
    }

    var helpText: String? {
        self == .awaitingApproval ? "当前会话正在等待权限审批，请前往处理" : nil
    }
}

@MainActor
@Observable
final class ChatSessionListModel {
    var sessions: [AgentSession] = [] {
        didSet {
            rowPresentationsByID = Dictionary(
                uniqueKeysWithValues: sessions.map { ($0.id, AgentChatSessionPresentation(session: $0)) }
            )
            guard allSessions.isEmpty else { return }
            sidebarSummary = .build(from: sessions)
        }
    }
    var allSessions: [AgentSession] = [] {
        didSet {
            sidebarSummary = .build(from: allSessions.isEmpty ? sessions : allSessions)
        }
    }
    private(set) var sidebarSummary = ChatSessionSidebarSummary()
    private(set) var rowPresentationsByID: [String: AgentChatSessionPresentation] = [:]
    var selectedSessionID: String?
    var loadingSessionDetailID: String?
    var presentedSessionDetailID: String?
    var readStates: [String: SessionReadState] = [:]
    var regeneratingTitleSessionIDs: Set<String> = []
    var backgroundTasksBySessionID: [String: [AppSessionBackgroundTask]] = [:]
    var isBackgroundTasksPresented = false
    var filter: AgentSessionListFilter = .all
    var searchQuery = ""
    var selectedArtifactDirectories: AgentSessionArtifactDirectories?

    func rowPresentation(for session: AgentSession) -> AgentChatSessionPresentation {
        rowPresentationsByID[session.id] ?? AgentChatSessionPresentation(session: session)
    }

    func title(for sessionID: String) -> String? {
        let title = (allSessions.first { $0.id == sessionID } ?? sessions.first { $0.id == sessionID })?
            .title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title?.isEmpty == false ? title : nil
    }

    var isWaitingForSelectedPresentation: Bool {
        guard let selectedSessionID, loadingSessionDetailID == selectedSessionID else { return false }
        return presentedSessionDetailID != selectedSessionID
    }
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
    var remoteKnowledgeBaseIDs: [String]?
    var allowedMCPToolNames: [String]?
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
    var isLoadingNextPage = false
    var nextPageCursor: String?

    func hasPendingApproval(sessionID: String) -> Bool {
        pendingApprovals.contains { $0.sessionID == sessionID }
    }
}

@MainActor
@Observable
final class ChatFeatureModel {
    let sessions = ChatSessionListModel()
    let composer = ChatComposerModel()
    let run = ChatRunModel()
    let approvals = ChatApprovalModel()
    let workspaceExplorer = WorkspaceExplorerFeatureModel()

    func shutdown() { workspaceExplorer.shutdown() }
}
