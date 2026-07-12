import Testing
@testable import ConnorGraphAgentMac

@Suite("Chat Viewport Data Set Identity Tests")
struct ChatViewportDataSetIdentityTests {
    @Test func agentChatSessionIdentityChangesWithSessionID() {
        let first = ChatViewportDataSetID.agentChatSession(sessionID: "session-a", revision: 1)
        let second = ChatViewportDataSetID.agentChatSession(sessionID: "session-b", revision: 1)

        #expect(first != second)
        #expect(first.description == "agent-chat-session:session-a:0")
        #expect(second.description == "agent-chat-session:session-b:0")
    }

    @Test func agentChatSessionIdentityRemainsStableAcrossTranscriptRevisions() {
        let initial = ChatViewportDataSetID.agentChatSession(sessionID: "session-a", revision: 1)
        let replaced = ChatViewportDataSetID.agentChatSession(sessionID: "session-a", revision: 2)

        #expect(initial == replaced)
    }

    @Test func elementIDIsNamespacedByDataSet() {
        let first = ChatViewportDataSetID.agentChatSession(sessionID: "session-a", revision: 1)
        let second = ChatViewportDataSetID.agentChatSession(sessionID: "session-b", revision: 1)

        #expect(first.namespacedElementID("date-section-2026-06-25") == "agent-chat-session:session-a:0::date-section-2026-06-25")
        #expect(first.namespacedElementID("date-section-2026-06-25") != second.namespacedElementID("date-section-2026-06-25"))
    }
}
