import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore

@Test func appPendingApprovalPresentationSummarizesApprovalForNativeUI() {
    let approval = AgentPendingApproval(
        id: "approval-1",
        requestID: "permission-tool-1",
        runID: "run-1",
        sessionID: "session-1",
        capability: .readSession,
        toolName: "Read",
        payloadJSON: "{ \"file_path\" : \"README.md\" }",
        status: .pending,
        createdAt: Date(timeIntervalSince1970: 1_000),
        updatedAt: Date(timeIntervalSince1970: 1_000)
    )

    let row = AppAgentPendingApprovalPresentation(approval)

    #expect(row.id == "approval-1")
    #expect(row.requestID == "permission-tool-1")
    #expect(row.title == "Permission requested: readSession")
    #expect(row.detail == "Request permission-tool-1 · Tool: Read · Payload: {\"file_path\":\"README.md\"}")
    #expect(row.statusLabel == "pending")
    #expect(row.severity == .warning)
    #expect(row.createdAt == Date(timeIntervalSince1970: 1_000))
}

@Test func appPendingApprovalPresentationMapsResolvedStatusesForNativeUI() {
    let statuses: [AgentPendingApprovalStatus] = [.pending, .approved, .denied, .cancelled]

    let severities = statuses.map { status in
        AppAgentPendingApprovalPresentation(AgentPendingApproval(
            requestID: "request-\(status.rawValue)",
            runID: "run-1",
            sessionID: "session-1",
            capability: .externalNetwork,
            status: status
        )).severity
    }

    #expect(severities == [.warning, .success, .error, .cancelled])
}
