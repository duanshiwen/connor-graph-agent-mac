import AppKit
import SwiftUI
import ConnorGraphAppSupport

struct WorkspaceCodePreviewTextView: NSViewRepresentable {
    var contentID: String
    var text: String
    var spans: [WorkspaceCodeHighlightSpan]
    var canLoadMore: Bool
    var onApproachEnd: () -> Void

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
        context.coordinator.scrollView = scrollView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let fingerprint = contentID
        context.coordinator.canLoadMore = canLoadMore
        context.coordinator.onApproachEnd = onApproachEnd
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
        context.coordinator.scheduleContinuationEvaluation()
    }

    private func color(for kind: WorkspaceCodeHighlightKind) -> NSColor {
        switch kind {
        case .comment: .secondaryLabelColor
        case .string: .systemRed
        case .keyword: .systemPurple
        case .number: .systemBlue
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var fingerprint = ""
        var canLoadMore = false
        var onApproachEnd: () -> Void = {}
        private var lastTriggeredFingerprint = ""

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc func scrollBoundsDidChange() {
            evaluateContinuation()
        }

        func scheduleContinuationEvaluation() {
            DispatchQueue.main.async { [weak self] in
                self?.evaluateContinuation()
            }
        }

        func evaluateContinuation() {
            guard canLoadMore,
                  fingerprint != lastTriggeredFingerprint,
                  let scrollView,
                  let documentView = scrollView.documentView else { return }
            let visibleBottom = scrollView.contentView.bounds.maxY
            let contentBottom = documentView.bounds.maxY
            guard contentBottom - visibleBottom <= 400 else { return }
            lastTriggeredFingerprint = fingerprint
            onApproachEnd()
        }
    }
}
