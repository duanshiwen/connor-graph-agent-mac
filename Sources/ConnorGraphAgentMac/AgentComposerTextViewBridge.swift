import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphSearch
import ConnorGraphAppSupport

enum SkillPickerKeyCommand {
    case moveUp
    case moveDown
    case confirm
    case cancel
}

@MainActor
final class ComposerTextSelectionTracker {
    var selectedRange: NSRange?
}

struct SafeChatComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var selectionTracker: ComposerTextSelectionTracker
    var placeholder: String
    var isSpellCheckEnabled: Bool
    var sendShortcut: String
    var isSkillPickerPresented: Bool = false
    var onSubmit: () -> Void
    var onImportFiles: ([URL]) -> Void
    var onSlashCommand: ((CGRect, NSRange) -> Void)? = nil
    var onSkillPickerKeyCommand: ((SkillPickerKeyCommand) -> Void)? = nil
    var onAttachmentImportError: ((String) -> Void)? = nil
    var onTextFileDropped: ((String) -> Void)? = nil
    var isNoteMode: Bool = false

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = SubmitAwareTextView()
        textView.delegate = context.coordinator
        textView.inputCommandRouter.configuration = textInputConfiguration
        textView.placeholderString = placeholder
        configure(textView)
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SubmitAwareTextView else { return }
        textView.inputCommandRouter.configuration = textInputConfiguration
        textView.placeholderString = placeholder
        textView.font = AgentChatTypography.composerNSFont
        if textView.string != text {
            textView.string = text
        }
        textView.isContinuousSpellCheckingEnabled = isSpellCheckEnabled
        textView.enabledTextCheckingTypes = isSpellCheckEnabled ? NSTextCheckingResult.CheckingType.spelling.rawValue : 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selectionTracker: selectionTracker)
    }

    private var textInputConfiguration: ComposerTextInputConfiguration {
        ComposerTextInputConfiguration(
            sendShortcut: sendShortcut,
            isSkillPickerPresented: isSkillPickerPresented,
            onSubmit: onSubmit,
            onImportFiles: onImportFiles,
            onSlashCommand: onSlashCommand,
            onSkillPickerKeyCommand: onSkillPickerKeyCommand,
            onAttachmentImportError: onAttachmentImportError,
            onTextFileDropped: onTextFileDropped,
            isNoteMode: isNoteMode
        )
    }

    private func configure(_ textView: SubmitAwareTextView) {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = isSpellCheckEnabled
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.enabledTextCheckingTypes = isSpellCheckEnabled ? NSTextCheckingResult.CheckingType.spelling.rawValue : 0
        textView.font = AgentChatTypography.composerNSFont
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var selectionTracker: ComposerTextSelectionTracker

        init(text: Binding<String>, selectionTracker: ComposerTextSelectionTracker) {
            self._text = text
            self.selectionTracker = selectionTracker
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            selectionTracker.selectedRange = textView.selectedRange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            selectionTracker.selectedRange = textView.selectedRange()
        }
    }
}

final class SubmitAwareTextView: NSTextView {
    let inputCommandRouter = ComposerInputCommandRouter()
    var placeholderString: String = "" {
        didSet { needsDisplay = true }
    }

    override var string: String {
        didSet { needsDisplay = true }
    }

    override func keyDown(with event: NSEvent) {
        if inputCommandRouter.handleKeyDown(event) { return }
        super.keyDown(with: event)
    }

    override func insertNewline(_ sender: Any?) {
        if inputCommandRouter.handleInsertNewline(currentEvent: NSApp.currentEvent) { return }
        super.insertNewline(sender)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if inputCommandRouter.handleInsertText(string, replacementRange: replacementRange, textView: self, slashAnchorRect: slashCommandAnchorRect) { return }
        super.insertText(string, replacementRange: replacementRange)
    }

    private func slashCommandAnchorRect() -> CGRect {
        let location = selectedRange().location
        let screenRect = firstRect(forCharacterRange: NSRange(location: location, length: 0), actualRange: nil)
        if let window {
            let windowRect = window.convertFromScreen(screenRect)
            let localRect = convert(windowRect, from: nil)
            if localRect.isNull == false, localRect.isInfinite == false {
                return localRect
            }
        }
        return CGRect(x: textContainerInset.width, y: textContainerInset.height, width: 1, height: font?.pointSize ?? 16)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        inputCommandRouter.draggingEntered(sender.draggingPasteboard) ?? super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        inputCommandRouter.handleDragOperation(sender.draggingPasteboard) || super.performDragOperation(sender)
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        inputCommandRouter.handleReadSelection(from: pboard) || super.readSelection(from: pboard, type: type)
    }

    override func paste(_ sender: Any?) {
        if inputCommandRouter.handlePaste(from: NSPasteboard.general) { return }
        super.paste(sender)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? AgentChatTypography.composerNSFont,
            .foregroundColor: NSColor.placeholderTextColor
        ]
        placeholderString.draw(
            at: NSPoint(x: textContainerInset.width + 1, y: textContainerInset.height),
            withAttributes: attributes
        )
    }
}
