import AppKit
import SwiftUI
import ConnorGraphAppSupport

struct WorkspaceCodePreviewTextView: NSViewRepresentable {
    var text: String
    var spans: [WorkspaceCodeHighlightSpan]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let fingerprint = "\(text.utf16.count):\(spans.count):\(text.hashValue)"
        guard context.coordinator.fingerprint != fingerprint,
              let textStorage = context.coordinator.textView?.textStorage else { return }
        context.coordinator.fingerprint = fingerprint

        let fullRange = NSRange(location: 0, length: text.utf16.count)
        textStorage.beginEditing()
        textStorage.setAttributedString(NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
        ))
        for span in spans where span.location >= 0 && span.length > 0 && NSMaxRange(NSRange(location: span.location, length: span.length)) <= fullRange.length {
            textStorage.addAttribute(.foregroundColor, value: color(for: span.kind), range: NSRange(location: span.location, length: span.length))
        }
        textStorage.endEditing()
    }

    private func color(for kind: WorkspaceCodeHighlightKind) -> NSColor {
        switch kind {
        case .comment: .secondaryLabelColor
        case .string: .systemRed
        case .keyword: .systemPurple
        case .number: .systemBlue
        }
    }

    final class Coordinator {
        weak var textView: NSTextView?
        var fingerprint = ""
    }
}
