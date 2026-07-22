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
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed.withLinkCursor()
        }
        return AttributedString(markdown)
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
                Text(lightweightInlineRendered)
                    .font(monospacedFallback ? monospacedBodyFont : font)
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
                    Text(lightweightInlineRendered)
                        .font(font)
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
        case .heading(let level, _, let inline):
            Text(inline.withLinkCursor())
                .font(headingFont(level))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .paragraph(_, let inline):
            Text(inline.withLinkCursor())
                .font(font)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .unorderedItem(_, let inline):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(font)
                    .frame(width: 12, alignment: .trailing)
                Text(inline.withLinkCursor())
                    .font(font)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 4)
        case .orderedItem(let number, _, let inline):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).")
                    .font(font)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .trailing)
                Text(inline.withLinkCursor())
                    .font(font)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 2)
        case .quote(_, let inline):
            Text(inline.withLinkCursor())
                .font(font)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.28))
                    .frame(width: 3)
                }
        case .taskItem(let isCompleted, _, let inline):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
                    .font(font)
                    .foregroundStyle(isCompleted ? .secondary : .tertiary)
                    .frame(width: 14, alignment: .center)
                Text(inline.withLinkCursor())
                    .font(font)
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
        Text(renderTableCellInline(text))
            .font(isHeader ? font.weight(.semibold) : font)
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

    private var secondaryFont: Font {
        guard let bodyPointSize else { return AgentChatTypography.meta }
        return .system(size: max(10, bodyPointSize - 1))
    }

    private var monospacedBodyFont: Font {
        guard let bodyPointSize else { return AgentChatTypography.monoMeta }
        return .system(size: max(10, bodyPointSize - 1), design: .monospaced)
    }

    private var monospacedLabelFont: Font {
        guard let bodyPointSize else { return AgentChatTypography.monoMicro.weight(.semibold) }
        return .system(size: max(9, bodyPointSize - 2), weight: .semibold, design: .monospaced)
    }

    private func renderTableCellInline(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed.withLinkCursor()
        }
        return AttributedString(text)
    }

}

private extension AttributedString {
    func withLinkCursor() -> AttributedString {
        let result = NSMutableAttributedString(self)
        let fullRange = NSRange(location: 0, length: result.length)
        result.enumerateAttribute(.link, in: fullRange) { value, range, _ in
            guard value != nil else { return }
            result.addAttribute(.cursor, value: NSCursor.pointingHand, range: range)
        }
        return AttributedString(result)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
