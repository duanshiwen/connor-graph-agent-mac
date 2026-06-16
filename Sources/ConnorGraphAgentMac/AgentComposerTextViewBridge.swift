import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphSearch
import ConnorGraphAppSupport

struct SafeChatComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isSpellCheckEnabled: Bool
    var sendShortcut: String
    var onSubmit: () -> Void
    var onImportFiles: ([URL]) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = SubmitAwareTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.onImportFiles = onImportFiles
        textView.sendShortcut = sendShortcut
        textView.placeholderString = placeholder
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
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SubmitAwareTextView else { return }
        textView.onSubmit = onSubmit
        textView.onImportFiles = onImportFiles
        textView.sendShortcut = sendShortcut
        textView.placeholderString = placeholder
        textView.font = AgentChatTypography.composerNSFont
        if textView.string != text {
            textView.string = text
        }
        textView.isContinuousSpellCheckingEnabled = isSpellCheckEnabled
        textView.enabledTextCheckingTypes = isSpellCheckEnabled ? NSTextCheckingResult.CheckingType.spelling.rawValue : 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            self._text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

final class SubmitAwareTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onImportFiles: (([URL]) -> Void)?
    var sendShortcut: String = "return"
    var placeholderString: String = "" {
        didSet { needsDisplay = true }
    }

    override var string: String {
        didSet { needsDisplay = true }
    }

    override func insertNewline(_ sender: Any?) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if flags.contains(.shift) || flags.contains(.option) {
            super.insertNewline(sender)
            return
        }
        switch sendShortcut {
        case "cmd-return":
            flags.contains(.command) ? onSubmit?() : super.insertNewline(sender)
        default:
            onSubmit?()
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(from: sender.draggingPasteboard).isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        onImportFiles?(urls)
        return true
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        let urls = fileURLs(from: pboard)
        guard urls.isEmpty else {
            onImportFiles?(urls)
            return true
        }
        return super.readSelection(from: pboard, type: type)
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) ?? []
        return objects.compactMap { object in
            guard let nsURL = object as? NSURL, let url = nsURL as URL? else { return nil }
            return url.isFileURL ? url : nil
        }
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
