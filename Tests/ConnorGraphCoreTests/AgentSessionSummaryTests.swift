import Foundation
import Testing
import ConnorGraphCore

@Test func agentSessionSummaryStoresSourceCoverageMetadata() {
    let createdAt = Date(timeIntervalSince1970: 1_000)
    let updatedAt = Date(timeIntervalSince1970: 2_000)

    let summary = AgentSessionSummary(
        id: "summary-1",
        sessionID: "session-1",
        content: "The session discussed graph memory and persistence.",
        createdAt: createdAt,
        updatedAt: updatedAt,
        sourceMessageCount: 4,
        lastMessageID: "message-4"
    )

    #expect(summary.id == "summary-1")
    #expect(summary.sessionID == "session-1")
    #expect(summary.content == "The session discussed graph memory and persistence.")
    #expect(summary.createdAt == createdAt)
    #expect(summary.updatedAt == updatedAt)
    #expect(summary.sourceMessageCount == 4)
    #expect(summary.lastMessageID == "message-4")
}
