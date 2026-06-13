import Testing
import ConnorGraphAppSupport

@Suite("Browser Popover Dismissal Policy Tests")
struct BrowserPopoverDismissalPolicyTests {
    @Test func escapeDismissalPreservesDraftQuestion() {
        #expect(BrowserPopoverDismissalPolicy.escape.shouldPreserveDraftQuestion)
    }

    @Test func explicitCloseClearsDraftQuestion() {
        #expect(!BrowserPopoverDismissalPolicy.explicitClose.shouldPreserveDraftQuestion)
    }
}
