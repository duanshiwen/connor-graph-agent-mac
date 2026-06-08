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

@Test func agentSessionSummaryFreshnessIsFreshWhenAllMessagesAreCovered() {
    let summary = AgentSessionSummary(
        id: "summary-1",
        sessionID: "session-1",
        content: "Covered summary",
        sourceMessageCount: 2,
        lastMessageID: "message-2"
    )
    let session = AgentSession(
        id: "session-1",
        messages: [
            AgentMessage(id: "message-1", role: .user, content: "First"),
            AgentMessage(id: "message-2", role: .assistant, content: "Second")
        ]
    )

    let freshness: AgentSessionSummaryFreshness = summary.freshness(for: session)

    #expect(freshness.coveredMessageCount == 2)
    #expect(freshness.currentMessageCount == 2)
    #expect(freshness.uncoveredMessageCount == 0)
    #expect(freshness.isFresh)
}

@Test func agentSessionSummaryFreshnessIsStaleWhenMessagesAreUncovered() {
    let summary = AgentSessionSummary(
        id: "summary-1",
        sessionID: "session-1",
        content: "Partial summary",
        sourceMessageCount: 2,
        lastMessageID: "message-2"
    )
    let session = AgentSession(
        id: "session-1",
        messages: [
            AgentMessage(id: "message-1", role: .user, content: "First"),
            AgentMessage(id: "message-2", role: .assistant, content: "Second"),
            AgentMessage(id: "message-3", role: .user, content: "Third"),
            AgentMessage(id: "message-4", role: .assistant, content: "Fourth"),
            AgentMessage(id: "message-5", role: .user, content: "Fifth")
        ]
    )

    let freshness: AgentSessionSummaryFreshness = summary.freshness(for: session)

    #expect(freshness.coveredMessageCount == 2)
    #expect(freshness.currentMessageCount == 5)
    #expect(freshness.uncoveredMessageCount == 3)
    #expect(!freshness.isFresh)
}
