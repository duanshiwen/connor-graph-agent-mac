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
