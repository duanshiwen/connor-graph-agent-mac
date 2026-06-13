import Testing
import ConnorGraphAppSupport

@Suite("Chat Session Workspace Mode Tests")
struct ChatSessionWorkspaceModeTests {
    @Test func defaultsNewSessionsToConversationMode() {
        let store = ChatSessionWorkspaceModeStore()

        #expect(store.mode(for: "new-session") == .conversation)
    }

    @Test func restoresLastBrowserModeForSession() {
        var store = ChatSessionWorkspaceModeStore()

        store.setMode(.browser, for: "session-a")
        store.setMode(.conversation, for: "session-b")

        #expect(store.mode(for: "session-a") == .browser)
        #expect(store.mode(for: "session-b") == .conversation)
    }

    @Test func ignoresEmptySessionIDs() {
        var store = ChatSessionWorkspaceModeStore()

        store.setMode(.browser, for: "   ")

        #expect(store.mode(for: "   ") == .conversation)
    }
}
