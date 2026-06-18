import AppKit

@MainActor
final class ComposerInputCommandRouter {
    var configuration: ComposerTextInputConfiguration
    var pasteboardExtractor: ComposerPasteboardAttachmentExtractor
    var temporaryAttachmentWriter: ComposerTemporaryAttachmentWriter

    init(
        configuration: ComposerTextInputConfiguration = .empty(),
        pasteboardExtractor: ComposerPasteboardAttachmentExtractor = ComposerPasteboardAttachmentExtractor(),
        temporaryAttachmentWriter: ComposerTemporaryAttachmentWriter = ComposerTemporaryAttachmentWriter()
    ) {
        self.configuration = configuration
        self.pasteboardExtractor = pasteboardExtractor
        self.temporaryAttachmentWriter = temporaryAttachmentWriter
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard configuration.isSkillPickerPresented else { return false }
        switch event.keyCode {
        case 126:
            configuration.onSkillPickerKeyCommand?(.moveUp)
            return true
        case 125:
            configuration.onSkillPickerKeyCommand?(.moveDown)
            return true
        case 36, 76:
            configuration.onSkillPickerKeyCommand?(.confirm)
            return true
        case 53:
            configuration.onSkillPickerKeyCommand?(.cancel)
            return true
        default:
            return false
        }
    }

    func handleInsertNewline(currentEvent: NSEvent?) -> Bool {
        if configuration.isSkillPickerPresented {
            configuration.onSkillPickerKeyCommand?(.confirm)
            return true
        }
        let flags = currentEvent?.modifierFlags ?? []
        if flags.contains(.shift) || flags.contains(.option) {
            return false
        }
        switch configuration.sendShortcut {
        case "cmd-return":
            guard flags.contains(.command) else { return false }
            configuration.onSubmit()
            return true
        default:
            configuration.onSubmit()
            return true
        }
    }

    func handleInsertText(_ string: Any, replacementRange: NSRange, textView: NSTextView, slashAnchorRect: () -> CGRect) -> Bool {
        guard let str = string as? NSString, str.length == 1, str.character(at: 0) == UInt16(47) else { return false }
        let currentString = textView.string as NSString
        let cursorLocation = textView.selectedRange().location
        let isStartOfLine = cursorLocation == 0 || (cursorLocation > 0 && currentString.character(at: cursorLocation - 1) == UInt16(10))
        guard isStartOfLine else { return false }
        textView.insertText(string, replacementRange: replacementRange)
        let slashLocation = max(0, textView.selectedRange().location - 1)
        configuration.onSlashCommand?(slashAnchorRect(), NSRange(location: slashLocation, length: 1))
        return true
    }

    func draggingEntered(_ pasteboard: NSPasteboard) -> NSDragOperation? {
        pasteboardExtractor.fileURLs(from: pasteboard).isEmpty ? nil : .copy
    }

    func handleDragOperation(_ pasteboard: NSPasteboard) -> Bool {
        let urls = pasteboardExtractor.fileURLs(from: pasteboard)
        guard !urls.isEmpty else { return false }
        configuration.onImportFiles(urls)
        return true
    }

    func handleReadSelection(from pasteboard: NSPasteboard) -> Bool {
        handlePasteboardImport(from: pasteboard)
    }

    func handlePaste(from pasteboard: NSPasteboard) -> Bool {
        handlePasteboardImport(from: pasteboard)
    }

    private func handlePasteboardImport(from pasteboard: NSPasteboard) -> Bool {
        let urls = pasteboardExtractor.fileURLs(from: pasteboard)
        if !urls.isEmpty {
            configuration.onImportFiles(urls)
            return true
        }
        let imageDataItems = pasteboardExtractor.imageDataItems(from: pasteboard)
        guard !imageDataItems.isEmpty else { return false }
        do {
            let imageURLs = try temporaryAttachmentWriter.writePNGImages(imageDataItems)
            configuration.onImportFiles(imageURLs)
        } catch {
            configuration.onAttachmentImportError?(error.localizedDescription)
        }
        return true
    }
}
