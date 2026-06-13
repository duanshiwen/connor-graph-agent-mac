import Testing
import ConnorGraphAppSupport

@Suite("Browser Keyboard Shortcut Resolver Tests")
struct BrowserKeyboardShortcutResolverTests {
    @Test func commandWClosesSelectedBrowserTab() {
        let shortcut = BrowserKeyboardShortcutResolver().shortcut(
            character: "w",
            isCommandDown: true
        )

        #expect(shortcut == .closeSelectedTab)
    }

    @Test func commandWIsCaseInsensitive() {
        let shortcut = BrowserKeyboardShortcutResolver().shortcut(
            character: "W",
            isCommandDown: true
        )

        #expect(shortcut == .closeSelectedTab)
    }

    @Test func modifiedCommandWDoesNotCloseSelectedBrowserTab() {
        let shortcut = BrowserKeyboardShortcutResolver().shortcut(
            character: "w",
            isCommandDown: true,
            isShiftDown: true
        )

        #expect(shortcut == nil)
    }

    @Test func escapeOnlyClosesSelectionPopoverWhenPopoverExists() {
        let resolver = BrowserKeyboardShortcutResolver()

        #expect(resolver.shortcut(isEscape: true, hasSelectionPopover: true) == .closeSelectionPopover)
        #expect(resolver.shortcut(isEscape: true, hasSelectionPopover: false) == nil)
    }
}
