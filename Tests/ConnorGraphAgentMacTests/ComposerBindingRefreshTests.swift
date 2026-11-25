import AppKit
import SwiftUI
import Testing
@testable import ConnorGraphAgentMac

@MainActor
@Suite("Composer binding refresh")
struct ComposerBindingRefreshTests {
    @Test func editingAfterViewReuseUpdatesCurrentDraftAndSelection() {
        var oldDraft = "queued message"
        var currentDraft = ""
        let oldTracker = ComposerTextSelectionTracker()
        let currentTracker = ComposerTextSelectionTracker()
        let coordinator = SafeChatComposerTextView.Coordinator(
            text: Binding(get: { oldDraft }, set: { oldDraft = $0 }), selectionTracker: oldTracker)
        coordinator.update(text: Binding(get: { currentDraft }, set: { currentDraft = $0 }), selectionTracker: currentTracker)
        let editor = NSTextView()
        editor.string = "new instruction"
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: editor))
        #expect(currentDraft == "new instruction")
        #expect(oldDraft == "queued message")
        #expect(currentTracker.selectedRange == NSRange(location: 3, length: 0))
        #expect(oldTracker.selectedRange == nil)
    }
}
