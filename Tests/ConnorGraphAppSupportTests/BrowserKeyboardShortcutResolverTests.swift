import Foundation
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

    @Test func plainTextInputDoesNotTriggerBrowserShortcut() {
        let resolver = BrowserKeyboardShortcutResolver()

        #expect(resolver.shortcut(character: "a") == nil)
        #expect(resolver.shortcut(character: "1") == nil)
        #expect(resolver.shortcut(character: ".") == nil)
    }

    @Test func plainTextInputDoesNotTriggerBrowserShortcutWhenSelectionPopoverExists() {
        let resolver = BrowserKeyboardShortcutResolver()

        #expect(resolver.shortcut(character: "a", hasSelectionPopover: true) == nil)
        #expect(resolver.shortcut(character: "1", hasSelectionPopover: true) == nil)
    }

    @Test func customShortcutRequiresConfiguredModifiers() {
        let settings = AgentRuntimeShortcutSettings(bindings: [
            .focusBrowserAddress: AgentRuntimeKeyboardShortcut(key: "l", command: true)
        ])

        #expect(BrowserKeyboardShortcutResolver().shortcut(character: "l", settings: settings) == nil)
        #expect(BrowserKeyboardShortcutResolver().shortcut(character: "l", isCommandDown: true, settings: settings) == .focusAddress)
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

    @Test func shortcutSettingsDecodeLegacyArrayBindingsAndSkipRemovedActions() throws {
        let json = """
        {
          "bindings": [
            "focusTopSearch",
            { "command": true, "control": false, "key": "g", "option": false, "shift": false },
            "openCommandPalette",
            { "command": true, "control": false, "key": "k", "option": false, "shift": false },
            "newBrowserTab",
            { "command": true, "control": false, "key": "u", "option": false, "shift": true }
          ]
        }
        """

        let settings = try JSONDecoder().decode(AgentRuntimeShortcutSettings.self, from: Data(json.utf8))

        #expect(settings.shortcut(for: .focusTopSearch).displayText == "⌘G")
        #expect(settings.shortcut(for: .newBrowserTab).displayText == "⌘⇧U")
        #expect(settings.bindings.keys.contains(.newSession))
    }
}
