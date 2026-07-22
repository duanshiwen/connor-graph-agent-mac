import SwiftUI
@preconcurrency import AppKit
import ConnorGraphAgent
import ConnorGraphAppSupport

enum AgentMarkdownPreviewRenderStrategy: Equatable {
    case inlineOnly
    case plainText
    case deferredPreview
    case compiledDocument

    static let deferredPreviewCharacterThreshold = 12_000

    static func strategy(lineLimit: Int?, monospacedFallback: Bool, markdownCharacterCount: Int) -> AgentMarkdownPreviewRenderStrategy {
        if lineLimit != nil { return .inlineOnly }
        if monospacedFallback { return .plainText }
        if markdownCharacterCount >= deferredPreviewCharacterThreshold { return .deferredPreview }
        return .compiledDocument
    }
}

struct AgentMarkdownPreviewText: View {
    var markdown: String
    var font: Font = AgentChatTypography.body
    var bodyPointSize: CGFloat? = nil
    var monospacedFallback: Bool = false
    var lineLimit: Int? = nil
    var maxRenderedBlocks: Int? = nil
    var persistentCacheContext: AgentMarkdownPersistentCacheContext? = nil
    @State private var loadedDocument: AgentMarkdownCompiledDocument?

    private final class RenderCache: @unchecked Sendable {
        static let shared = RenderCache()
        private let documentCache = AgentMarkdownCompiledDocumentCache(limit: 600)
        private let inlineCache: NSCache<NSString, AttributedStringBox> = {
            let cache = NSCache<NSString, AttributedStringBox>()
            cache.countLimit = 1_200
            cache.totalCostLimit = 8 * 1_024 * 1_024
            return cache
        }()

        private final class AttributedStringBox: NSObject {
            let value: AttributedString

            init(_ value: AttributedString) {
                self.value = value
            }
        }

        func document(
            _ markdown: String,
            persistentCacheContext: AgentMarkdownPersistentCacheContext?
        ) -> AgentMarkdownCompiledDocument {
            documentCache.document(
                for: markdown,
                loadBlocks: { source in
                    guard let persistentCacheContext else { return nil }
                    return try? persistentCacheContext.store.loadBlocks(
                        sessionID: persistentCacheContext.sessionID,
                        messageID: persistentCacheContext.messageID,
                        content: source
                    )
                },
                persistBlocks: { source, blocks in
                    guard let persistentCacheContext else { return }
                    try? persistentCacheContext.store.saveBlocks(
                        sessionID: persistentCacheContext.sessionID,
                        messageID: persistentCacheContext.messageID,
                        content: source,
                        blocks: blocks
                    )
                }
            )
        }

        func inlineRendered(_ markdown: String, attributed: AttributedString? = nil) -> AttributedString {
            let cacheKey = markdown as NSString
            if let cached = inlineCache.object(forKey: cacheKey) {
                return cached.value
            }

            let parsed = attributed ?? (try? AttributedString(
                markdown: markdown,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(markdown)
            inlineCache.setObject(
                AttributedStringBox(parsed),
                forKey: cacheKey,
                cost: max(markdown.utf8.count, 1)
            )
            return parsed
        }
    }

    private var documentLoadID: String {
        let contentID = AgentMarkdownDocumentCompiler.stableFingerprint(markdown)
        guard let persistentCacheContext else { return contentID }
        return "\(persistentCacheContext.sessionID)|\(persistentCacheContext.messageID)|\(contentID)"
    }

    private func renderWindow(for document: AgentMarkdownCompiledDocument) -> AgentMarkdownCompiledRenderWindow {
        AgentMarkdownCompiledRenderWindowPolicy().window(
            for: document,
            maxRenderedBlocks: maxRenderedBlocks
        )
    }

    private var lightweightInlineRendered: AttributedString {
        RenderCache.shared.inlineRendered(markdown)
    }

    private var renderStrategy: AgentMarkdownPreviewRenderStrategy {
        AgentMarkdownPreviewRenderStrategy.strategy(
            lineLimit: lineLimit,
            monospacedFallback: monospacedFallback,
            markdownCharacterCount: markdown.count
        )
    }

    @ViewBuilder
    var body: some View {
        Group {
            switch renderStrategy {
            case .inlineOnly:
                inlineText(
                    lightweightInlineRendered,
                    font: monospacedFallback ? monospacedBodyFont : font,
                    nativeFont: monospacedFallback ? monospacedBodyNSFont : bodyNSFont
                )
                    .lineLimit(lineLimit)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .plainText:
                Text(markdown)
                    .font(monospacedBodyFont)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .deferredPreview:
                VStack(alignment: .leading, spacing: 7) {
                    inlineText(lightweightInlineRendered, font: font, nativeFont: bodyNSFont)
                        .lineLimit(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("内容较长，已先显示轻量预览以保持界面响应。")
                        .font(secondaryFont)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            case .compiledDocument:
                if let loadedDocument, loadedDocument.source == markdown {
                    compiledDocumentView(loadedDocument)
                } else {
                    Color.clear
                        .frame(height: bodyPointSize ?? 17)
                        .accessibilityHidden(true)
                }
            }
        }
        .task(id: documentLoadID) {
            guard renderStrategy == .compiledDocument else { return }
            let source = markdown
            let cacheContext = persistentCacheContext
            let loadTask = Task.detached(priority: .utility) {
                RenderCache.shared.document(source, persistentCacheContext: cacheContext)
            }
            let document = await withTaskCancellationHandler {
                await loadTask.value
            } onCancel: {
                loadTask.cancel()
            }
            guard !Task.isCancelled, document.source == markdown else { return }
            loadedDocument = document
        }
    }

    private func compiledDocumentView(_ document: AgentMarkdownCompiledDocument) -> some View {
        let window = renderWindow(for: document)
        return VStack(alignment: .leading, spacing: 7) {
            ForEach(window.blocks) { block in
                view(for: block)
            }
            if window.omittedBlockCount > 0 {
                omittedBlocksIndicator(count: window.omittedBlockCount)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: AgentMarkdownCompiledBlock) -> some View {
        switch block.content {
        case .heading(let level, let text, let inline):
            inlineText(
                RenderCache.shared.inlineRendered(text, attributed: inline),
                font: headingFont(level),
                nativeFont: headingNSFont(level)
            )
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .paragraph(let text, let inline):
            inlineText(RenderCache.shared.inlineRendered(text, attributed: inline), font: font, nativeFont: bodyNSFont)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .unorderedItem(let text, let inline):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(font)
                    .frame(width: 12, alignment: .trailing)
                inlineText(RenderCache.shared.inlineRendered(text, attributed: inline), font: font, nativeFont: bodyNSFont)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 4)
        case .orderedItem(let number, let text, let inline):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).")
                    .font(font)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .trailing)
                inlineText(RenderCache.shared.inlineRendered(text, attributed: inline), font: font, nativeFont: bodyNSFont)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 2)
        case .quote(let text, let inline):
            inlineText(
                RenderCache.shared.inlineRendered(text, attributed: inline),
                font: font,
                nativeFont: bodyNSFont,
                nativeColor: .secondaryLabelColor
            )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.28))
                    .frame(width: 3)
                }
        case .taskItem(let isCompleted, let text, let inline):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
                    .font(font)
                    .foregroundStyle(isCompleted ? .secondary : .tertiary)
                    .frame(width: 14, alignment: .center)
                inlineText(
                    RenderCache.shared.inlineRendered(text, attributed: inline),
                    font: font,
                    nativeFont: bodyNSFont,
                    nativeColor: isCompleted ? .secondaryLabelColor : .labelColor,
                    strikethrough: isCompleted
                )
                    .foregroundStyle(isCompleted ? .secondary : .primary)
                    .strikethrough(isCompleted, color: .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 4)
        case .code(let language, let text):
            VStack(alignment: .leading, spacing: 6) {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(monospacedLabelFont)
                        .foregroundStyle(.secondary)
                }
                Text(text)
                    .font(monospacedBodyFont)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        case .table(let table):
            markdownTableView(table)
        case .horizontalRule:
            Rectangle()
                .fill(Color.secondary.opacity(0.24))
                .frame(height: 1)
                .padding(.vertical, 6)
        case .spacer:
            Color.clear.frame(height: 4)
        }
    }

    private func omittedBlocksIndicator(count: Int) -> some View {
        Text("已暂缓渲染后续 \(count) 个 Markdown 块，展开后完整显示")
            .font(secondaryFont)
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func markdownTableView(_ table: AgentMarkdownTable) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.headers.enumerated()), id: \.offset) { index, header in
                        tableCell(header, isHeader: true, alignment: alignment(for: table.alignments[safe: index] ?? .leading))
                    }
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(table.headers.indices), id: \.self) { index in
                            tableCell(row[safe: index] ?? "", isHeader: false, alignment: alignment(for: table.alignments[safe: index] ?? .leading))
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tableCell(_ text: String, isHeader: Bool, alignment: Alignment) -> some View {
        inlineText(
            renderTableCellInline(text),
            font: isHeader ? font.weight(.semibold) : font,
            nativeFont: isHeader ? NSFontManager.shared.convert(bodyNSFont, toHaveTrait: .boldFontMask) : bodyNSFont
        )
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 92, maxWidth: .infinity, alignment: alignment)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isHeader ? Color.secondary.opacity(0.10) : Color.clear)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.14))
                    .frame(height: 1)
            }
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 1)
            }
    }

    private func alignment(for tableAlignment: AgentMarkdownTableAlignment) -> Alignment {
        switch tableAlignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func headingFont(_ level: Int) -> Font {
        guard let bodyPointSize else {
            switch level {
            case 1: return AgentChatTypography.title
            case 2: return AgentChatTypography.sectionTitle
            default: return AgentChatTypography.calloutEmphasis
            }
        }

        let systemBodySize = NSFont.preferredFont(forTextStyle: .body).pointSize
        let semanticSize: CGFloat
        switch level {
        case 1: semanticSize = NSFont.preferredFont(forTextStyle: .title3).pointSize
        case 2: semanticSize = NSFont.preferredFont(forTextStyle: .headline).pointSize
        default: semanticSize = NSFont.preferredFont(forTextStyle: .callout).pointSize
        }
        return .system(size: max(10, bodyPointSize + semanticSize - systemBodySize), weight: .semibold)
    }

    private func headingNSFont(_ level: Int) -> NSFont {
        let size: CGFloat
        if let bodyPointSize {
            let systemBodySize = NSFont.preferredFont(forTextStyle: .body).pointSize
            let semanticSize: CGFloat
            switch level {
            case 1: semanticSize = NSFont.preferredFont(forTextStyle: .title3).pointSize
            case 2: semanticSize = NSFont.preferredFont(forTextStyle: .headline).pointSize
            default: semanticSize = NSFont.preferredFont(forTextStyle: .callout).pointSize
            }
            size = max(10, bodyPointSize + semanticSize - systemBodySize)
        } else {
            switch level {
            case 1: size = NSFont.preferredFont(forTextStyle: .title3).pointSize
            case 2: size = NSFont.preferredFont(forTextStyle: .headline).pointSize
            default: size = NSFont.preferredFont(forTextStyle: .callout).pointSize
            }
        }
        return NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    private var secondaryFont: Font {
        guard let bodyPointSize else { return AgentChatTypography.meta }
        return .system(size: max(10, bodyPointSize - 1))
    }

    private var monospacedBodyFont: Font {
        guard let bodyPointSize else { return AgentChatTypography.monoMeta }
        return .system(size: max(10, bodyPointSize - 1), design: .monospaced)
    }

    private var bodyNSFont: NSFont {
        .systemFont(ofSize: bodyPointSize ?? NSFont.preferredFont(forTextStyle: .body).pointSize)
    }

    private var monospacedBodyNSFont: NSFont {
        .monospacedSystemFont(ofSize: bodyPointSize.map { max(10, $0 - 1) } ?? NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
    }

    private var monospacedLabelFont: Font {
        guard let bodyPointSize else { return AgentChatTypography.monoMicro.weight(.semibold) }
        return .system(size: max(9, bodyPointSize - 2), weight: .semibold, design: .monospaced)
    }

    private func renderTableCellInline(_ text: String) -> AttributedString {
        RenderCache.shared.inlineRendered(text)
    }

    @ViewBuilder
    private func inlineText(
        _ attributed: AttributedString,
        font: Font,
        nativeFont: NSFont,
        nativeColor: NSColor = .labelColor,
        strikethrough: Bool = false
    ) -> some View {
        if attributed.runs.contains(where: { $0.link != nil }) {
            AgentMarkdownLinkText(
                attributed: attributed,
                baseFont: nativeFont,
                baseColor: nativeColor,
                strikethrough: strikethrough
            )
        } else {
            Text(attributed).font(font)
        }
    }

}

private struct AgentMarkdownLinkText: NSViewRepresentable {
    var attributed: AttributedString
    var baseFont: NSFont
    var baseColor: NSColor
    var strikethrough: Bool

    @Environment(\.openURL) private var openURL

    func makeCoordinator() -> Coordinator {
        Coordinator(openURL: openURL)
    }

    func makeNSView(context: Context) -> LinkTextView {
        let textView = LinkTextView()
        textView.delegate = context.coordinator
        return textView
    }

    func updateNSView(_ textView: LinkTextView, context: Context) {
        context.coordinator.openURL = openURL
        let rendered = Self.renderedAttributedString(
            attributed,
            baseFont: baseFont,
            baseColor: baseColor,
            strikethrough: strikethrough
        )
        if !textView.attributedString().isEqual(to: rendered) {
            textView.textStorage?.setAttributedString(rendered)
            textView.window?.invalidateCursorRects(for: textView)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LinkTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0,
              let textContainer = nsView.textContainer,
              let layoutManager = nsView.layoutManager else { return nil }
        textContainer.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let height = ceil(layoutManager.usedRect(for: textContainer).height)
        return CGSize(width: width, height: max(height, baseFont.ascender - baseFont.descender))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var openURL: OpenURLAction

        init(openURL: OpenURLAction) {
            self.openURL = openURL
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url: URL?
            switch link {
            case let value as URL: url = value
            case let value as String: url = URL(string: value)
            default: url = nil
            }
            guard let url else { return false }
            openURL(url)
            return true
        }
    }

    final class LinkTextView: NSTextView {
        init() {
            let storage = NSTextStorage()
            let layoutManager = NSLayoutManager()
            let container = NSTextContainer(size: .zero)
            storage.addLayoutManager(layoutManager)
            layoutManager.addTextContainer(container)
            super.init(frame: .zero, textContainer: container)

            drawsBackground = false
            isEditable = false
            isSelectable = true
            isRichText = true
            isHorizontallyResizable = false
            isVerticallyResizable = true
            textContainerInset = .zero
            container.lineFragmentPadding = 0
            container.widthTracksTextView = true
            linkTextAttributes = [
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func resetCursorRects() {
            super.resetCursorRects()
            guard let textStorage, let layoutManager, let textContainer else { return }
            layoutManager.ensureLayout(for: textContainer)
            let origin = textContainerOrigin
            let fullRange = NSRange(location: 0, length: textStorage.length)
            textStorage.enumerateAttribute(.link, in: fullRange) { value, characterRange, _ in
                guard value != nil else { return }
                let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
                layoutManager.enumerateEnclosingRects(
                    forGlyphRange: glyphRange,
                    withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                    in: textContainer
                ) { rect, _ in
                    let cursorRect = rect
                        .offsetBy(dx: origin.x, dy: origin.y)
                        .intersection(self.visibleRect)
                    guard !cursorRect.isNull, !cursorRect.isEmpty else { return }
                    self.addCursorRect(cursorRect, cursor: .pointingHand)
                }
            }
        }
    }

    private static func renderedAttributedString(
        _ attributed: AttributedString,
        baseFont: NSFont,
        baseColor: NSColor,
        strikethrough: Bool
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in attributed.runs {
            let text = String(attributed[run.range].characters)
            var font = baseFont
            if let intent = run.inlinePresentationIntent {
                var traits: NSFontTraitMask = []
                if intent.contains(.stronglyEmphasized) { traits.insert(.boldFontMask) }
                if intent.contains(.emphasized) { traits.insert(.italicFontMask) }
                if !traits.isEmpty { font = NSFontManager.shared.convert(font, toHaveTrait: traits) }
                if intent.contains(.code) {
                    font = .monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
                }
            }

            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: baseColor
            ]
            if let link = run.link {
                attributes[.link] = link
                attributes[.foregroundColor] = NSColor.linkColor
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if strikethrough || run.inlinePresentationIntent?.contains(.strikethrough) == true {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            result.append(NSAttributedString(string: text, attributes: attributes))
        }
        return result
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
