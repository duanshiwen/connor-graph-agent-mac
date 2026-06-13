import Testing
import ConnorGraphAppSupport

@Suite("Browser Workspace Session Binding Tests")
struct BrowserWorkspaceSessionBindingTests {
    @Test func openingBrowserBindsCurrentSessionAndReturnRestoresThatSession() {
        var binding = BrowserWorkspaceSessionBinding()

        binding.bindBrowserWorkspace(to: "session-a")
        let target = binding.sessionIDForReturningFromBrowser(currentSelectedSessionID: "session-b")

        #expect(target == "session-a")
    }

    @Test func returnFallsBackToCurrentSessionWhenBrowserWasOpenedWithoutSession() {
        let binding = BrowserWorkspaceSessionBinding()

        let target = binding.sessionIDForReturningFromBrowser(currentSelectedSessionID: "session-current")

        #expect(target == "session-current")
    }
}
