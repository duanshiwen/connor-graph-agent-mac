import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

struct TopSearchTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var focusRequestID: UUID?
    var onSubmit: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    var onFocus: (() -> Void)? = nil
    var onBlur: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSTextField {
        let textField = TopSearchSelectAllOnFocusTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.font = .systemFont(ofSize: 13)
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.sendsActionOnEndEditing = false
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text, !context.coordinator.isComposingText(in: nsView) {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
        if context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            guard focusRequestID != nil else { return }
            DispatchQueue.main.async {
                context.coordinator.shouldSelectAllOnNextFocus = true
                nsView.window?.makeFirstResponder(nsView)
                if let editor = nsView.currentEditor() as? NSTextView, !editor.hasMarkedText() {
                    nsView.selectText(nil)
                    context.coordinator.shouldSelectAllOnNextFocus = false
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onCancel: onCancel, onFocus: onFocus, onBlur: onBlur)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var lastFocusRequestID: UUID?
        var shouldSelectAllOnNextFocus = false
        var onSubmit: (() -> Void)?
        var onCancel: (() -> Void)?
        var onFocus: (() -> Void)?
        var onBlur: (() -> Void)?

        init(text: Binding<String>, onSubmit: (() -> Void)?, onCancel: (() -> Void)?, onFocus: (() -> Void)?, onBlur: (() -> Void)?) {
            _text = text
            self.onSubmit = onSubmit
            self.onCancel = onCancel
            self.onFocus = onFocus
            self.onBlur = onBlur
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            onFocus?()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            onBlur?()
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text = field.stringValue
        }

        @MainActor func isComposingText(in field: NSTextField) -> Bool {
            guard let editor = field.currentEditor() as? NSTextView else { return false }
            return editor.hasMarkedText()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit?()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                onCancel?()
                return true
            }
            return false
        }
    }
}

final class TopSearchSelectAllOnFocusTextField: NSTextField {}

