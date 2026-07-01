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

    func handleInsertText(_ string: Any, replacementRange: NSRange, textView: NSTextView, slashAnchorRect: @escaping () -> CGRect) -> Bool {
        guard let str = string as? NSString, str.length == 1, str.character(at: 0) == UInt16(47) else { return false }
        let slashLocation = textView.selectedRange().location
        guard slashLocation != NSNotFound else { return false }
        let onSlashCommand = configuration.onSlashCommand

        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            let currentString = textView.string as NSString
            guard slashLocation < currentString.length,
                  currentString.character(at: slashLocation) == UInt16(47)
            else { return }
            onSlashCommand?(slashAnchorRect(), NSRange(location: slashLocation, length: 1))
        }

        return false
    }

    func draggingEntered(_ pasteboard: NSPasteboard) -> NSDragOperation? {
        pasteboardExtractor.fileURLs(from: pasteboard).isEmpty ? nil : .copy
    }

    func handleDragOperation(_ pasteboard: NSPasteboard) -> Bool {
        let urls = pasteboardExtractor.fileURLs(from: pasteboard)
        guard !urls.isEmpty else { return false }

        if configuration.isNoteMode {
            // Note mode: text files → extract content; images → import; others → ignore
            let textFiles = urls.filter { isPlainTextFile($0) }
            let imageFiles = urls.filter { isImageFile($0) }
            let otherFiles = urls.filter { !isPlainTextFile($0) && !isImageFile($0) }

            if !textFiles.isEmpty {
                let contents: [String] = textFiles.compactMap { url in
                    guard url.startAccessingSecurityScopedResource() else { return nil }
                    defer { url.stopAccessingSecurityScopedResource() }
                    return try? String(contentsOf: url, encoding: .utf8)
                }
                let combined = contents.joined(separator: "\n\n---\n\n")
                if !combined.isEmpty {
                    configuration.onTextFileDropped?(combined)
                }
            }

            if !imageFiles.isEmpty {
                configuration.onImportFiles(imageFiles)
            }

            return !textFiles.isEmpty || !imageFiles.isEmpty
        }

        // Normal mode: keep existing behavior
        configuration.onImportFiles(urls)
        return true
    }

    private func isPlainTextFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["txt", "md", "markdown", "text", "json", "yaml", "yml", "csv", "log", "xml"].contains(ext)
    }

    private func isImageFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "tif", "heic", "heif"].contains(ext)
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
