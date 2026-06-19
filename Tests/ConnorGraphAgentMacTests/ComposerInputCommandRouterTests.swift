import AppKit
import Testing
@testable import ConnorGraphAgentMac

@MainActor
@Suite("Composer Input Command Router Tests")
struct ComposerInputCommandRouterTests {
    @Test func slashAtAnyPositionDoesNotConsumeTextInsertionOrInvokeSynchronously() async throws {
        var didInvokeSlashCommand = false
        let textView = NSTextView()
        textView.string = "hello"
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        let router = ComposerInputCommandRouter()
        router.configuration = ComposerTextInputConfiguration(
            sendShortcut: "return",
            isSkillPickerPresented: false,
            onSubmit: {},
            onImportFiles: { _ in },
            onSlashCommand: { _, _ in didInvokeSlashCommand = true },
            onSkillPickerKeyCommand: nil,
            onAttachmentImportError: nil
        )

        let handled = router.handleInsertText(
            "/" as NSString,
            replacementRange: NSRange(location: NSNotFound, length: 0),
            textView: textView,
            slashAnchorRect: { CGRect(x: 0, y: 0, width: 1, height: 18) }
        )

        #expect(handled == false)
        #expect(didInvokeSlashCommand == false)
    }

    @Test func slashWithNSNotFoundReplacementRangeDoesNotCrashOrConsumeInsertion() async throws {
        var didInvokeSlashCommand = false
        let textView = NSTextView()
        textView.string = ""
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        let router = ComposerInputCommandRouter()
        router.configuration = ComposerTextInputConfiguration(
            sendShortcut: "return",
            isSkillPickerPresented: false,
            onSubmit: {},
            onImportFiles: { _ in },
            onSlashCommand: { _, _ in didInvokeSlashCommand = true },
            onSkillPickerKeyCommand: nil,
            onAttachmentImportError: nil
        )

        let handled = router.handleInsertText(
            "/" as NSString,
            replacementRange: NSRange(location: NSNotFound, length: 0),
            textView: textView,
            slashAnchorRect: { CGRect(x: 0, y: 0, width: 1, height: 18) }
        )

        #expect(handled == false)
        #expect(didInvokeSlashCommand == false)
    }

    @Test func slashTriggersCommandAfterAppKitInsertion() async throws {
        var invokedRange: NSRange?
        let textView = NSTextView()
        textView.string = "hello"
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        let router = ComposerInputCommandRouter()
        router.configuration = ComposerTextInputConfiguration(
            sendShortcut: "return",
            isSkillPickerPresented: false,
            onSubmit: {},
            onImportFiles: { _ in },
            onSlashCommand: { _, range in invokedRange = range },
            onSkillPickerKeyCommand: nil,
            onAttachmentImportError: nil
        )

        let handled = router.handleInsertText(
            "/" as NSString,
            replacementRange: NSRange(location: NSNotFound, length: 0),
            textView: textView,
            slashAnchorRect: { CGRect(x: 0, y: 0, width: 1, height: 18) }
        )

        #expect(handled == false)
        textView.string = "hello/"
        textView.setSelectedRange(NSRange(location: 6, length: 0))

        try await Task.sleep(for: .milliseconds(50))

        #expect(invokedRange == NSRange(location: 5, length: 1))
    }

    @Test func nonSlashInputDoesNotTriggerSlashCommand() async throws {
        var didInvokeSlashCommand = false
        let textView = NSTextView()
        textView.string = "hello"
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        let router = ComposerInputCommandRouter()
        router.configuration = ComposerTextInputConfiguration(
            sendShortcut: "return",
            isSkillPickerPresented: false,
            onSubmit: {},
            onImportFiles: { _ in },
            onSlashCommand: { _, _ in didInvokeSlashCommand = true },
            onSkillPickerKeyCommand: nil,
            onAttachmentImportError: nil
        )

        let handled = router.handleInsertText(
            "a" as NSString,
            replacementRange: NSRange(location: NSNotFound, length: 0),
            textView: textView,
            slashAnchorRect: { CGRect(x: 0, y: 0, width: 1, height: 18) }
        )

        #expect(handled == false)
        #expect(didInvokeSlashCommand == false)
    }
}
