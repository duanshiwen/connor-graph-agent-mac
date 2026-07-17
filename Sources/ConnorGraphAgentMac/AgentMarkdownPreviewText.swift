import SwiftUI
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
    var monospacedFallback: Bool = false
    var lineLimit: Int? = nil
    var maxRenderedBlocks: Int? = nil
    var persistentCacheContext: AgentMarkdownPersistentCacheContext? = nil

    @MainActor
    private final class RenderCache {
        static let shared = RenderCache()
        private let documentCache = AgentMarkdownCompiledDocumentCache(limit: 600)

        func document(_ markdown: String) -> AgentMarkdownCompiledDocument {
            documentCache.document(for: markdown)
        }
    }

    private var compiledDocument: AgentMarkdownCompiledDocument {
        RenderCache.shared.document(markdown)
    }

    private var renderWindow: AgentMarkdownCompiledRenderWindow {
        AgentMarkdownCompiledRenderWindowPolicy().window(
            for: compiledDocument,
            maxRenderedBlocks: maxRenderedBlocks
        )
    }

    private var compiledInlineRendered: AttributedString {
        if let block = compiledDocument.blocks.first,
           case .paragraph(_, let inline) = block.content {
            return inline
        }
        return lightweightInlineRendered
    }

    private var lightweightInlineRendered: AttributedString {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
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
        switch renderStrategy {
        case .inlineOnly:
            Text(lightweightInlineRendered)
                .font(monospacedFallback ? AgentChatTypography.monoMeta : font)
                .lineLimit(lineLimit)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .plainText:
            Text(markdown)
                .font(AgentChatTypography.monoMeta)
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
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        case .compiledDocument:
            VStack(alignment: .leading, spacing: 7) {
                ForEach(renderWindow.blocks) { block in
                    view(for: block)
                }
                if renderWindow.omittedBlockCount > 0 {
                    omittedBlocksIndicator(count: renderWindow.omittedBlockCount)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func view(for block: AgentMarkdownCompiledBlock) -> some View {
        switch block.content {
        case .heading(let level, _, let inline):
            Text(inline)
                .font(headingFont(level))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .paragraph(_, let inline):
            Text(inline)
                .font(font)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .unorderedItem(_, let inline):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(font)
                    .frame(width: 12, alignment: .trailing)
                Text(inline)
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
                Text(inline)
                    .font(font)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 2)
        case .quote(_, let inline):
            Text(inline)
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
                Text(inline)
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
                        .font(AgentChatTypography.monoMicro.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(text)
                    .font(AgentChatTypography.monoMeta)
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
            .font(AgentChatTypography.meta)
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
        switch level {
        case 1: return AgentChatTypography.title
        case 2: return AgentChatTypography.sectionTitle
        default: return AgentChatTypography.calloutEmphasis
        }
    }

    private func renderTableCellInline(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(text)
    }

}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
