import AppKit
import Testing
@testable import ConnorGraphAgentMac

@MainActor
@Suite("Composer Input Command Router Tests")
struct ComposerInputCommandRouterTests {
    @Test func returnConfirmsPersonMentionPickerInsteadOfSubmitting() {
        var didSubmit = false
        var receivedCommand: SkillPickerKeyCommand?

        let router = ComposerInputCommandRouter()
        router.configuration = ComposerTextInputConfiguration(
            sendShortcut: "return",
            isSkillPickerPresented: false,
            isPersonMentionPickerPresented: true,
            onSubmit: { didSubmit = true },
            onImportFiles: { _ in },
            onSlashCommand: nil,
            onSkillPickerKeyCommand: nil,
            onPersonMentionPickerKeyCommand: { receivedCommand = $0 },
            onAttachmentImportError: nil
        )

        let handled = router.handleInsertNewline(currentEvent: nil)

        #expect(handled == true)
        #expect(didSubmit == false)
        #expect(receivedCommand == .confirm)
    }

    @Test func arrowAndEscapeRouteToPersonMentionPickerWhenPresented() throws {
        var didSubmit = false
        var receivedCommands: [SkillPickerKeyCommand] = []

        let router = ComposerInputCommandRouter()
        router.configuration = ComposerTextInputConfiguration(
            sendShortcut: "return",
            isSkillPickerPresented: false,
            isPersonMentionPickerPresented: true,
            onSubmit: { didSubmit = true },
            onImportFiles: { _ in },
            onSlashCommand: nil,
            onSkillPickerKeyCommand: nil,
            onPersonMentionPickerKeyCommand: { receivedCommands.append($0) },
            onAttachmentImportError: nil
        )

        let up = try #require(Self.keyEvent(keyCode: 126))
        let down = try #require(Self.keyEvent(keyCode: 125))
        let escape = try #require(Self.keyEvent(keyCode: 53))

        #expect(router.handleKeyDown(up) == true)
        #expect(router.handleKeyDown(down) == true)
        #expect(router.handleKeyDown(escape) == true)
        #expect(didSubmit == false)
        #expect(receivedCommands == [.moveUp, .moveDown, .cancel])
    }

    @Test func skillPickerKeepsPriorityOverPersonMentionPicker() {
        var skillCommands: [SkillPickerKeyCommand] = []
        var personCommands: [SkillPickerKeyCommand] = []
        var didSubmit = false

        let router = ComposerInputCommandRouter()
        router.configuration = ComposerTextInputConfiguration(
            sendShortcut: "return",
            isSkillPickerPresented: true,
            isPersonMentionPickerPresented: true,
            onSubmit: { didSubmit = true },
            onImportFiles: { _ in },
            onSlashCommand: nil,
            onSkillPickerKeyCommand: { skillCommands.append($0) },
            onPersonMentionPickerKeyCommand: { personCommands.append($0) },
            onAttachmentImportError: nil
        )

        let handled = router.handleInsertNewline(currentEvent: nil)

        #expect(handled == true)
        #expect(didSubmit == false)
        #expect(skillCommands == [.confirm])
        #expect(personCommands.isEmpty)
    }

    @Test func shiftReturnDoesNotConfirmPersonMentionPickerOrSubmit() throws {
        var personCommands: [SkillPickerKeyCommand] = []
        var didSubmit = false

        let router = ComposerInputCommandRouter()
        router.configuration = ComposerTextInputConfiguration(
            sendShortcut: "return",
            isSkillPickerPresented: false,
            isPersonMentionPickerPresented: true,
            onSubmit: { didSubmit = true },
            onImportFiles: { _ in },
            onSlashCommand: nil,
            onSkillPickerKeyCommand: nil,
            onPersonMentionPickerKeyCommand: { personCommands.append($0) },
            onAttachmentImportError: nil
        )

        let event = try #require(Self.keyEvent(keyCode: 36, modifierFlags: .shift))
        let handled = router.handleInsertNewline(currentEvent: event)

        #expect(handled == false)
        #expect(didSubmit == false)
        #expect(personCommands.isEmpty)
    }

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

    private static func keyEvent(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags = []) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )
    }
}
