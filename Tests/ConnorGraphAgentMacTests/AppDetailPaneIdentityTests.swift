import Testing
@testable import ConnorGraphAgentMac

struct AppDetailPaneIdentityTests {
    @Test func agentChatIdentityChangesWithSelectedSession() {
        #expect(AppDetailPaneIdentity.agentChat(sessionID: "session-a") == "agent-chat-session-a")
        #expect(AppDetailPaneIdentity.agentChat(sessionID: "session-a") != AppDetailPaneIdentity.agentChat(sessionID: "session-b"))
        #expect(AppDetailPaneIdentity.agentChat(sessionID: nil) == "agent-chat-none")
    }
}
