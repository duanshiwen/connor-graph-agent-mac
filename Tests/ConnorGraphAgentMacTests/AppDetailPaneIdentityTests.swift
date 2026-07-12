import Testing
@testable import ConnorGraphAgentMac

struct AppDetailPaneIdentityTests {
    @Test func chatDataSetIdentityOwnsSessionIsolationWithoutDetailPaneIdentity() {
        let first = ChatViewportDataSetID.agentChatSession(sessionID: "session-a")
        let second = ChatViewportDataSetID.agentChatSession(sessionID: "session-b")

        #expect(first != second)
        #expect(first.namespacedElementID("message-1") != second.namespacedElementID("message-1"))
    }
}
