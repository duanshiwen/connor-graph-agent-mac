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

    @Test func customShortcutSettingsDriveBrowserResolver() {
        let settings = AgentRuntimeShortcutSettings(bindings: [
            .newBrowserTab: AgentRuntimeKeyboardShortcut(key: "u", command: true, shift: true)
        ])

        #expect(BrowserKeyboardShortcutResolver().shortcut(character: "u", isCommandDown: true, isShiftDown: true, settings: settings) == .newTab)
        #expect(BrowserKeyboardShortcutResolver().shortcut(character: "t", isCommandDown: true, settings: settings) == nil)
    }

    @Test func shortcutSettingsMergeDefaultsWhenPartiallyConfigured() {
        let settings = AgentRuntimeShortcutSettings(bindings: [
            .focusTopSearch: AgentRuntimeKeyboardShortcut(key: "j")
        ])

        #expect(settings.shortcut(for: .focusTopSearch).displayText == "⌘J")
        #expect(settings.shortcut(for: .closeBrowserTab).displayText == "⌘W")
    }
}
