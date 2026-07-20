import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
@testable import ConnorGraphAgentMac

@MainActor
@Suite("Chat Feature Model Tests")
struct ChatFeatureModelTests {
    @Test func composerPublishesUserInputButNotOrchestrationInputApplication() {
        let model = ChatComposerModel()
        var changes: [String] = []
        model.onInputChanged = { changes.append($0) }

        model.input = "manual draft"
        model.applyInput("persisted draft")

        #expect(model.input == "persisted draft")
        #expect(changes == ["manual draft"])
    }

    @Test func sessionListOwnsSelectionFilteringReadAndArtifactState() {
        let model = ChatSessionListModel()
        let artifacts = AgentSessionArtifactDirectories(root: URL(fileURLWithPath: "/tmp/session"))

        model.selectedSessionID = "session-1"
        model.loadingSessionDetailID = "session-1"
        model.filter = .status(.todo)
        model.searchQuery = "planning"
        model.isBackgroundTasksPresented = true
        model.selectedArtifactDirectories = artifacts

        #expect(model.selectedSessionID == "session-1")
        #expect(model.loadingSessionDetailID == "session-1")
        #expect(model.filter == .status(.todo))
        #expect(model.searchQuery == "planning")
        #expect(model.isBackgroundTasksPresented)
        #expect(model.selectedArtifactDirectories == artifacts)
    }

    @Test func sessionListBuildsSidebarSummaryOnceFromCompleteSessionSource() {
        let todo = AgentSession(
            id: "todo",
            governance: AgentSessionGovernanceMetadata(
                status: .todo,
                labels: [AgentSessionLabel(id: "important"), AgentSessionLabel(id: "work")]
            )
        )
        let inProgress = AgentSession(
            id: "in-progress",
            governance: AgentSessionGovernanceMetadata(
                status: .inProgress,
                labels: [AgentSessionLabel(id: "important")]
            )
        )
        let model = ChatSessionListModel()

        model.sessions = [todo]
        #expect(model.sidebarSummary.totalCount == 1)
        #expect(model.sidebarSummary.countsByStatus[.todo] == 1)

        model.allSessions = [todo, inProgress]
        #expect(model.sidebarSummary.totalCount == 2)
        #expect(model.sidebarSummary.countsByStatus[.todo] == 1)
        #expect(model.sidebarSummary.countsByStatus[.inProgress] == 1)
        #expect(model.sidebarSummary.countsByLabelID["important"] == 2)
        #expect(model.sidebarSummary.countsByLabelID["work"] == 1)

        model.sessions = [inProgress]
        #expect(model.sidebarSummary.totalCount == 2)

        model.allSessions = []
        #expect(model.sidebarSummary.totalCount == 1)
        #expect(model.sidebarSummary.countsByStatus[.inProgress] == 1)
    }

    @Test func runModelOwnsTranscriptSubmissionAndSummaryLifecycle() {
        let model = ChatRunModel()
        let message = AgentMessage(role: .user, content: "hello")
        let summary = AgentSessionSummary(
            sessionID: "session-1",
            content: "summary",
            updatedAt: Date(timeIntervalSince1970: 1_000),
            sourceMessageCount: 1,
            lastMessageID: message.id
        )

        model.transcript = [message]
        model.transcriptRevision = 2
        model.submittingSessionIDs = ["session-1"]
        model.isSubmitting = true
        model.latestSummary = summary
        model.isSummarizing = true
        model.summaryMessage = "updated"

        #expect(model.transcript == [message])
        #expect(model.transcriptRevision == 2)
        #expect(model.submittingSessionIDs == ["session-1"])
        #expect(model.isSubmitting)
        #expect(model.latestSummary == summary)
        #expect(model.isSummarizing)
        #expect(model.summaryMessage == "updated")
    }

    @Test func sessionSelectionDoesNotRebuildCachedRowPresentations() {
        let session = AgentSession(
            id: "session-1",
            title: "Cached title",
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let model = ChatSessionListModel()
        model.sessions = [session]
        let cachedRows = model.rowPresentationsByID

        model.selectedSessionID = session.id
        model.loadingSessionDetailID = session.id

        #expect(model.rowPresentationsByID == cachedRows)
        #expect(model.rowPresentation(for: session).title == "Cached title")
    }

    @Test func sessionListResolvesApprovalSessionTitleFromCompleteSource() {
        let model = ChatSessionListModel()
        model.sessions = [AgentSession(id: "visible", title: "当前会话")]
        model.allSessions = [
            AgentSession(id: "visible", title: "当前会话"),
            AgentSession(id: "approval-session", title: "审批来源会话")
        ]

        #expect(model.title(for: "approval-session") == "审批来源会话")
        #expect(model.title(for: "missing") == nil)
    }

    @Test func approvalModelOwnsPendingApprovalsAndResultFeedback() {
        let model = ChatApprovalModel()
        let approval = AgentPendingApproval(
            requestID: "request-1",
            runID: "run-1",
            sessionID: "session-1",
            capability: .readSession,
            toolName: "Read",
            payloadJSON: "{}"
        )

        model.pendingApprovals = [approval]
        model.lastResultSummary = "approved"

        #expect(model.pendingApprovals == [approval])
        #expect(model.lastResultSummary == "approved")
    }

    @Test func shutdownIsSafeForStateOnlyFeatureModel() {
        let model = ChatFeatureModel()
        model.sessions.selectedSessionID = "session-1"
        model.composer.input = "draft"

        model.shutdown()

        #expect(model.sessions.selectedSessionID == "session-1")
        #expect(model.composer.input == "draft")
    }
}
