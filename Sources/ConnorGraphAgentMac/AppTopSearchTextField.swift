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
    @Binding var isFocused: Bool
    var placeholder: String
    var focusRequestID: UUID?
    var onSubmit: (() -> Void)? = nil
    var onMoveUp: (() -> Void)? = nil
    var onMoveDown: (() -> Void)? = nil
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
        context.coordinator.isFocused = $isFocused
        let fieldEditor = nsView.currentEditor()
        let hasAppKitFocus = nsView.window?.firstResponder === nsView || nsView.window?.firstResponder === fieldEditor
        if !isFocused, hasAppKitFocus {
            DispatchQueue.main.async {
                guard nsView.window?.firstResponder === nsView || nsView.window?.firstResponder === nsView.currentEditor() else { return }
                nsView.window?.makeFirstResponder(nil)
            }
        } else if isFocused, !hasAppKitFocus {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
        if context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            guard focusRequestID != nil else { return }
            DispatchQueue.main.async {
                context.coordinator.shouldSelectAllOnNextFocus = true
                context.coordinator.isFocused.wrappedValue = true
                nsView.window?.makeFirstResponder(nsView)
                if let editor = nsView.currentEditor() as? NSTextView, !editor.hasMarkedText() {
                    nsView.selectText(nil)
                    context.coordinator.shouldSelectAllOnNextFocus = false
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, onSubmit: onSubmit, onMoveUp: onMoveUp, onMoveDown: onMoveDown, onCancel: onCancel, onFocus: onFocus, onBlur: onBlur)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var isFocused: Binding<Bool>
        var lastFocusRequestID: UUID?
        var shouldSelectAllOnNextFocus = false
        var onSubmit: (() -> Void)?
        var onMoveUp: (() -> Void)?
        var onMoveDown: (() -> Void)?
        var onCancel: (() -> Void)?
        var onFocus: (() -> Void)?
        var onBlur: (() -> Void)?

        init(text: Binding<String>, isFocused: Binding<Bool>, onSubmit: (() -> Void)?, onMoveUp: (() -> Void)?, onMoveDown: (() -> Void)?, onCancel: (() -> Void)?, onFocus: (() -> Void)?, onBlur: (() -> Void)?) {
            _text = text
            self.isFocused = isFocused
            self.onSubmit = onSubmit
            self.onMoveUp = onMoveUp
            self.onMoveDown = onMoveDown
            self.onCancel = onCancel
            self.onFocus = onFocus
            self.onBlur = onBlur
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isFocused.wrappedValue = true
            onFocus?()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            isFocused.wrappedValue = false
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
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                onMoveUp?()
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                onMoveDown?()
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

