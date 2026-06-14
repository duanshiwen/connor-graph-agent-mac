import SwiftUI
import ConnorGraphAgent
import ConnorGraphAppSupport

struct AgentEventTimelineView: View {
    var events: [AgentEventPresentation]

    var body: some View {
        DisclosureGroup {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: AgentChatLayout.spaceM) {
                    ForEach(events) { event in
                        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                            HStack(spacing: AgentChatLayout.spaceS) {
                                Image(systemName: icon(for: event.severity))
                                    .foregroundStyle(color(for: event.severity))
                                Text(event.title)
                                    .font(AgentChatTypography.metaEmphasis)
                                    .lineLimit(1)
                            }
                            AgentMarkdownPreviewText(markdown: event.detail, font: AgentChatTypography.micro, lineLimit: 3)
                                .foregroundStyle(.secondary)
                                .frame(width: 220, alignment: .leading)
                            Text(event.kind)
                                .font(AgentChatTypography.monoMicro)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(AgentChatLayout.spaceM)
                        .frame(width: 250, alignment: .leading)
                        .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous)
                                .stroke(color(for: event.severity).opacity(0.28), lineWidth: 1)
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        } label: {
            Label("Agent 运行时间线（\(events.count) 个事件）", systemImage: "point.3.connected.trianglepath.dotted")
                .font(AgentChatTypography.metaEmphasis)
        }
    }

    private func icon(for severity: AgentEventPresentationSeverity) -> String {
        switch severity {
        case .info: return "circle"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func color(for severity: AgentEventPresentationSeverity) -> Color {
        switch severity {
        case .info: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

struct AgentChatEmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: AgentChatTypography.largeIconSize))
                .foregroundStyle(.secondary)
            Text("开始基于图谱的对话")
                .font(AgentChatTypography.title)
            Text("你可以询问已导入的图谱知识。每一轮助手回复都可以展开查看提示词、上下文、Token 预算和引用。")
                .font(AgentChatTypography.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AgentMarkdownPreviewText: View {
    var markdown: String
    var font: Font = AgentChatTypography.body
    var monospacedFallback: Bool = false
    var lineLimit: Int? = nil

    @MainActor
    private final class RenderCache {
        static let shared = RenderCache()
        private var inlineCache: [String: AttributedString] = [:]
        private var blockCache: [String: [AgentMarkdownBlock]] = [:]
        private let limit = 600

        func inline(_ markdown: String) -> AttributedString {
            if let cached = inlineCache[markdown] { return cached }
            let rendered: AttributedString
            if let attributed = try? AttributedString(
                markdown: markdown,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) {
                rendered = attributed
            } else {
                rendered = AttributedString(markdown)
            }
            storeInline(rendered, for: markdown)
            return rendered
        }

        func blocks(_ markdown: String, parse: (String) -> [AgentMarkdownBlock]) -> [AgentMarkdownBlock] {
            if let cached = blockCache[markdown] { return cached }
            let parsed = parse(markdown)
            storeBlocks(parsed, for: markdown)
            return parsed
        }

        private func storeInline(_ value: AttributedString, for key: String) {
            if inlineCache.count >= limit { inlineCache.removeAll(keepingCapacity: true) }
            inlineCache[key] = value
        }

        private func storeBlocks(_ value: [AgentMarkdownBlock], for key: String) {
            if blockCache.count >= limit { blockCache.removeAll(keepingCapacity: true) }
            blockCache[key] = value
        }
    }

    private var inlineRendered: AttributedString {
        RenderCache.shared.inline(markdown)
    }

    private var blocks: [AgentMarkdownBlock] {
        RenderCache.shared.blocks(markdown) { AgentMarkdownBlockParser().parse($0) }
    }

    @ViewBuilder
    var body: some View {
        if let lineLimit {
            Text(inlineRendered)
                .font(monospacedFallback ? AgentChatTypography.monoMeta : font)
                .lineLimit(lineLimit)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if monospacedFallback {
            Text(markdown)
                .font(AgentChatTypography.monoMeta)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    view(for: block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func view(for block: AgentMarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(renderInline(text))
                .font(headingFont(level))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .paragraph(let text):
            Text(renderInline(text))
                .font(font)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .unorderedItem(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(font)
                    .frame(width: 12, alignment: .trailing)
                Text(renderInline(text))
                    .font(font)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 4)
        case .orderedItem(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).")
                    .font(font)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .trailing)
                Text(renderInline(text))
                    .font(font)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 2)
        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.28))
                    .frame(width: 3)
                Text(renderInline(text))
                    .font(font)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .taskItem(let isCompleted, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
                    .font(font)
                    .foregroundStyle(isCompleted ? .secondary : .tertiary)
                    .frame(width: 14, alignment: .center)
                Text(renderInline(text))
                    .font(font)
                    .foregroundStyle(isCompleted ? .secondary : .primary)
                    .strikethrough(isCompleted, color: .secondary)
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
        Text(renderInline(text))
            .font(isHeader ? font.weight(.semibold) : font)
            .frame(minWidth: 92, maxWidth: 220, alignment: alignment)
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

    private func renderInline(_ text: String) -> AttributedString {
        RenderCache.shared.inline(text)
    }

}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct AgentChatTurnTimestampRow: View {
    var timestamp: AgentChatTurnTimestampPresentation

    var body: some View {
        Text(timestamp.text)
            .font(AgentChatTypography.micro.weight(.medium))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel("对话时间 \(timestamp.text)")
    }
}

struct AgentChatMessageRow: View {
    var row: AgentChatMessagePresentation
    @State private var isAssistantMessageExpanded = false

    @MainActor
    private final class BrowserPromptFoldingCache {
        static let shared = BrowserPromptFoldingCache()
        private var hits: [String: BrowserPromptFoldingParts] = [:]
        private var misses = Set<String>()
        private let limit = 600

        func parts(for messageID: String, content: String) -> BrowserPromptFoldingParts? {
            if let cached = hits[messageID] { return cached }
            if misses.contains(messageID) { return nil }

            guard content.contains("网页正文：") else {
                storeMiss(messageID)
                return nil
            }

            guard let parsed = BrowserPromptFoldingParser().parse(content) else {
                storeMiss(messageID)
                return nil
            }
            storeHit(parsed, for: messageID)
            return parsed
        }

        private func storeHit(_ parts: BrowserPromptFoldingParts, for messageID: String) {
            pruneIfNeeded()
            hits[messageID] = parts
        }

        private func storeMiss(_ messageID: String) {
            pruneIfNeeded()
            misses.insert(messageID)
        }

        private func pruneIfNeeded() {
            if hits.count + misses.count >= limit {
                hits.removeAll(keepingCapacity: true)
                misses.removeAll(keepingCapacity: true)
            }
        }
    }

    private var isUser: Bool { row.message.role == .user }
    private var shouldFoldAssistantMessage: Bool {
        guard !isUser else { return false }
        let content = row.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let lineCount = content.components(separatedBy: .newlines).count
        return content.count > 1_200 || lineCount > 18
    }

    private var assistantCollapsedMaxHeight: CGFloat { 260 }

    private var browserPromptFoldingParts: BrowserPromptFoldingParts? {
        BrowserPromptFoldingCache.shared.parts(for: row.id, content: row.message.content)
    }

    var body: some View {
        HStack(alignment: .top) {
            if isUser { Spacer(minLength: AgentChatLayout.messageSideInset) }

            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                messageContent
            }
            .foregroundStyle(Color.primary)
            .padding(AgentChatLayout.spaceM)
            .frame(maxWidth: isUser ? AgentChatLayout.userMessageMaxWidth : .infinity, alignment: .leading)
            .background(messageBackground, in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                    .stroke(isUser ? Color.clear : Color.secondary.opacity(AgentChatLayout.hairlineOpacity), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    @ViewBuilder
    private var messageContent: some View {
        if isUser {
            if let browserPromptFoldingParts {
                BrowserPromptFoldedMessageView(parts: browserPromptFoldingParts)
            } else {
                AgentMarkdownPreviewText(markdown: row.message.content, font: AgentChatTypography.body)
            }
        } else {
            assistantMessageContent
        }
    }

    @ViewBuilder
    private var assistantMessageContent: some View {
        if shouldFoldAssistantMessage {
            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                if isAssistantMessageExpanded {
                    assistantMarkdownBody
                } else {
                    assistantMarkdownBody
                        .frame(maxHeight: assistantCollapsedMaxHeight, alignment: .top)
                        .clipped()
                        .overlay(alignment: .bottom) {
                            LinearGradient(
                                colors: [
                                    Color(nsColor: .controlBackgroundColor).opacity(0),
                                    Color(nsColor: .controlBackgroundColor).opacity(0.92)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 56)
                            .allowsHitTesting(false)
                        }
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isAssistantMessageExpanded.toggle()
                    }
                } label: {
                    Label(isAssistantMessageExpanded ? "收起回答" : "展开完整回答", systemImage: isAssistantMessageExpanded ? "chevron.up" : "chevron.down")
                        .font(AgentChatTypography.metaEmphasis)
                        .foregroundStyle(ConnorCraftPalette.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isAssistantMessageExpanded ? "收起助手回答" : "展开助手完整回答")
            }
        } else {
            assistantMarkdownBody
        }
    }

    private var assistantMarkdownBody: some View {
        AgentMarkdownPreviewText(markdown: row.message.content, font: AgentChatTypography.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, AgentChatLayout.spaceXS)
    }

    private var messageBackground: Color {
        if isUser { return ConnorCraftPalette.userBubble }
        return Color(nsColor: .controlBackgroundColor).opacity(0.85)
    }
}

private struct BrowserPromptFoldedMessageView: View {
    var parts: BrowserPromptFoldingParts
    @State private var isWebPageBodyExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            if !parts.leadingMarkdown.isEmpty {
                AgentMarkdownPreviewText(markdown: parts.leadingMarkdown, font: AgentChatTypography.body)
            }

            DisclosureGroup(isExpanded: $isWebPageBodyExpanded) {
                ScrollView {
                    Text(parts.webPageBody)
                        .font(AgentChatTypography.monoMeta)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AgentChatLayout.spaceS)
                }
                .frame(maxHeight: 220, alignment: .top)
                .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous))
            } label: {
                Label("网页正文", systemImage: "doc.text.magnifyingglass")
                    .font(AgentChatTypography.metaEmphasis)
            }
            .tint(.primary)

            if !parts.trailingMarkdown.isEmpty {
                AgentMarkdownPreviewText(markdown: parts.trailingMarkdown, font: AgentChatTypography.body)
            }
        }
    }
}

struct AgentChatTurnProcessRow: View {
    var process: AgentChatTurnProcessPresentation
    var events: [AgentEventPresentation]
    var onOpenDetail: (AgentEventPresentation) -> Void
    @State private var isExpanded: Bool = false
    @State private var startedAt: Date = Date()

    private var visibleEvents: [AgentEventPresentation] {
        events.isEmpty ? AgentActivityFallbackEvents.events(for: process) : events
    }

    private var summary: AgentTurnActivitySummaryPresentation {
        AgentTurnActivitySummaryBuilder().summary(process: process, events: visibleEvents)
    }

    var body: some View {
        HStack(alignment: .top, spacing: AgentChatLayout.spaceS) {
            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                Button(action: { withAnimation(.easeOut(duration: 0.16)) { isExpanded.toggle() } }) {
                    activityHeader(summary)
                }
                .buttonStyle(.plain)

                if isExpanded {
                    AgentTurnActivitySummaryDetailView(
                        summary: summary,
                        events: visibleEvents,
                        isRunning: process.state == .running,
                        startedAt: startedAt,
                        onOpenDetail: onOpenDetail
                    )
                    .padding(.leading, AgentChatLayout.iconButtonSize + AgentChatLayout.spaceM)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activityHeader(_ summary: AgentTurnActivitySummaryPresentation) -> some View {
        HStack(alignment: .top, spacing: AgentChatLayout.spaceS) {
            statusIcon(summary.state)
                .frame(width: AgentChatTypography.controlIconSize, height: AgentChatTypography.controlIconSize)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .font(AgentChatTypography.micro.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(summary.subtitle)
                    .font(AgentChatTypography.micro)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: AgentChatTypography.chevronIconSize, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 1)
        }
        .padding(.horizontal, AgentChatLayout.spaceM)
        .padding(.vertical, AgentChatLayout.spaceXS)
        .frame(minHeight: AgentChatLayout.activityRowMinHeight)
        .background(Color.clear)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func statusIcon(_ state: AgentTurnActivitySummaryState) -> some View {
        switch state {
        case .running:
            ProgressView()
                .controlSize(.small)
                .fixedSize()
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "slash.circle.fill")
                .foregroundStyle(.orange)
        case .waitingForPermission:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

private struct AgentTurnActivitySummaryDetailView: View {
    var summary: AgentTurnActivitySummaryPresentation
    var events: [AgentEventPresentation]
    var isRunning: Bool
    var startedAt: Date
    var onOpenDetail: (AgentEventPresentation) -> Void
    @State private var showsRawEvents = false

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
            if !summary.toolSummaries.isEmpty {
                detailLine(icon: "wrench.and.screwdriver", text: "工具：\(toolSummaryText)")
            }

            detailLine(icon: "checklist", text: resultText)

            if summary.hasPermissionRequest {
                detailLine(icon: "hand.raised", text: "权限：等待用户确认后继续")
            }

            if let primaryErrorMessage = summary.primaryErrorMessage {
                detailLine(icon: "exclamationmark.triangle", text: "错误：\(primaryErrorMessage)", color: .red)
            }

            if isRunning {
                AgentActivityLoadingRow(startedAt: startedAt)
                    .padding(.leading, -AgentChatLayout.spaceM)
            }

            DisclosureGroup(isExpanded: $showsRawEvents) {
                VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
                    ForEach(events) { event in
                        Button(action: { onOpenDetail(event) }) {
                            AgentActivityEventRow(event: event)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, AgentChatLayout.spaceXS)
            } label: {
                Label("查看底层事件（\(events.count)）", systemImage: "ladybug")
                    .font(AgentChatTypography.micro.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            .tint(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var toolSummaryText: String {
        summary.toolSummaries
            .map(\.compactCountText)
            .joined(separator: "、")
    }

    private var resultText: String {
        var parts: [String] = []
        if summary.toolSuccessCount > 0 {
            parts.append("成功 \(summary.toolSuccessCount) 次")
        }
        if summary.toolFailureCount > 0 {
            parts.append("失败 \(summary.toolFailureCount) 次")
        }
        if parts.isEmpty {
            parts.append(summary.statusText)
        }
        parts.append("底层事件 \(summary.eventCount) 个")
        return "结果：\(parts.joined(separator: "，"))"
    }

    private func detailLine(icon: String, text: String, color: Color = .secondary) -> some View {
        Label {
            Text(text)
                .font(AgentChatTypography.micro)
                .foregroundStyle(color)
                .lineLimit(2)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: AgentChatTypography.smallIconSize, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, AgentChatLayout.spaceM)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, minHeight: AgentChatLayout.activityRowMinHeight, alignment: .leading)
    }
}

struct AgentActivityLoadingRow: View {
    var startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            HStack(spacing: AgentChatLayout.spaceS) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: AgentChatTypography.controlIconSize, height: AgentChatTypography.controlIconSize)
                    .fixedSize()
                Text("忙碌中…")
                    .font(AgentChatTypography.micro.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(Self.elapsedText(from: startedAt, to: context.date))
                    .font(AgentChatTypography.micro.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AgentChatLayout.spaceM)
            .padding(.vertical, 3)
            .frame(minHeight: AgentChatLayout.activityRowMinHeight)
            .contentShape(RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
        }
    }

    private static func elapsedText(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        let minutes = seconds / 60
        let remainder = seconds % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let minuteRemainder = minutes % 60
            return "\(hours):\(String(format: "%02d", minuteRemainder)):\(String(format: "%02d", remainder))"
        }
        return "\(minutes):\(String(format: "%02d", remainder))"
    }
}

struct AgentActivityEventRow: View {
    var event: AgentEventPresentation

    var body: some View {
        HStack(spacing: AgentChatLayout.spaceS) {
            Image(systemName: icon)
                .font(.system(size: AgentChatTypography.chevronIconSize, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: AgentChatTypography.controlIconSize)
            Text(event.title)
                .font(AgentChatTypography.micro.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            AgentMarkdownPreviewText(markdown: event.detail, font: AgentChatTypography.micro, lineLimit: 1)
                .foregroundStyle(.tertiary)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Text(event.kind)
                .font(AgentChatTypography.monoMicro)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Image(systemName: "arrow.up.right")
                .font(.system(size: AgentChatTypography.smallIconSize, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, AgentChatLayout.spaceM)
        .padding(.vertical, 2)
        .frame(minHeight: AgentChatLayout.activityRowMinHeight)
        .contentShape(RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
    }

    private var icon: String {
        switch event.severity {
        case .info: return "circle.dashed"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        }
    }

    private var color: Color {
        switch event.severity {
        case .info: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

enum AgentActivityFallbackEvents {
    static func events(for process: AgentChatTurnProcessPresentation) -> [AgentEventPresentation] {
        var items: [AgentEventPresentation] = []
        if let request = process.currentRequest, !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(AgentEventPresentation(kind: "user_input", title: "User prompt", detail: request, severity: .info, runID: nil, sessionID: nil))
        }
        if !process.expandedContextItems.isEmpty {
            items.append(AgentEventPresentation(kind: "context", title: "Context assembled", detail: "使用了 \(process.expandedContextItems.count) 个图谱上下文项", severity: .info, runID: nil, sessionID: nil))
        }
        if !process.citationIDs.isEmpty {
            items.append(AgentEventPresentation(kind: "citations", title: "Citations attached", detail: process.citationIDs.joined(separator: ", "), severity: .success, runID: nil, sessionID: nil))
        }
        if let prompt = process.promptSnapshotText, !prompt.isEmpty {
            items.append(AgentEventPresentation(kind: "prompt_snapshot", title: "Prompt snapshot", detail: prompt, severity: .info, runID: nil, sessionID: nil))
        }
        if let response = process.assistantResponse, !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(AgentEventPresentation(kind: "assistant_response", title: "Answer completed", detail: response, severity: .success, runID: nil, sessionID: nil))
        }
        if items.isEmpty {
            items.append(AgentEventPresentation(kind: "activity", title: process.state == .running ? "Processing" : "Activity", detail: process.summary, severity: process.state == .running ? .info : .success, runID: nil, sessionID: nil))
        }
        return items
    }
}

struct AgentActivityDetailOverlay: View {
    var event: AgentEventPresentation
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Label("Activity", systemImage: "info.circle")
                        .font(AgentChatTypography.meta.weight(.medium))
                        .padding(.horizontal, AgentChatLayout.spaceS)
                        .frame(height: AgentChatLayout.chipHeight)
                        .background(Color.clear, in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous)
                                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                        )
                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: AgentChatTypography.controlIconSize, weight: .semibold))
                            .frame(width: AgentChatLayout.iconButtonSize, height: AgentChatLayout.iconButtonSize)
                    }
                    .buttonStyle(.plain)
                    .frame(width: AgentChatLayout.hitTargetSize, height: AgentChatLayout.hitTargetSize)
                    .contentShape(Rectangle())
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .padding(AgentChatLayout.spaceM)

                Spacer(minLength: 0)

                ScrollView {
                    VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
                        HStack(spacing: AgentChatLayout.spaceS) {
                            Text(event.title)
                                .font(AgentChatTypography.sectionTitle)
                            Text(event.kind)
                                .font(AgentChatTypography.monoMicro)
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                        AgentMarkdownPreviewText(markdown: event.detail, font: AgentChatTypography.body)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: 900, alignment: .leading)
                    .padding(AgentChatLayout.spaceXL)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.48), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                    )
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: 0)
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.96), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusXL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusXL, style: .continuous)
                    .stroke(Color.secondary.opacity(0.20), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 14)
            .padding(AgentChatLayout.spaceXL)
        }
    }
}

private struct AgentChatPendingAssistantRow: View {
    var pending: AgentChatPendingAssistantPresentation

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
                HStack(spacing: AgentChatLayout.spaceS) {
                    Text("助手")
                        .font(AgentChatTypography.metaEmphasis)
                        .foregroundStyle(.secondary)
                    Text("第 \(pending.turnNumber) 轮")
                        .font(AgentChatTypography.micro)
                        .foregroundStyle(.secondary)
                    ProgressView()
                        .controlSize(.regular)
                        .frame(width: 14, height: 14)
                        .fixedSize()
                    Text(pending.title)
                        .font(AgentChatTypography.meta)
                        .foregroundStyle(.secondary)
                }

                ThinkingDotsView()

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                        Label(pending.processingSummary, systemImage: "magnifyingglass")
                        Label("正在组装近期对话和可选会话摘要", systemImage: "text.bubble")
                        Label("正在调用已配置的模型提供方", systemImage: "network")
                    }
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                } label: {
                    Text("处理中")
                        .font(AgentChatTypography.metaEmphasis)
                }
                .font(AgentChatTypography.meta)
            }
            .padding(AgentChatLayout.spaceM)
            .frame(maxWidth: AgentChatLayout.messageMaxWidth, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                    .stroke(Color.secondary.opacity(AgentChatLayout.hairlineOpacity), lineWidth: 1)
            )

            Spacer(minLength: AgentChatLayout.messageSideInset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ThinkingDotsView: View {
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary.opacity(0.65))
                    .frame(width: 6, height: 6)
                    .opacity(index == 0 ? 1.0 : 0.45)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.18), in: Capsule())
    }
}

private struct AgentChatTurnInspectorView: View {
    var row: AgentChatMessagePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            if let summary = row.turnMetadataSummary {
                HStack(spacing: AgentChatLayout.spaceS) {
                    Image(systemName: "info.circle")
                    AgentMarkdownPreviewText(markdown: summary, font: AgentChatTypography.meta, lineLimit: 1)
                    Spacer(minLength: 0)
                }
                .font(AgentChatTypography.meta)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            DisclosureGroup {
                VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
                    if let request = row.currentRequest {
                        MetadataBlock(title: "当前请求", text: request)
                    }

                    if !row.citationIDs.isEmpty {
                        MetadataChips(title: "引用", values: row.citationIDs)
                    }

                    if !row.expandedContextItems.isEmpty {
                        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                            Text("引用的图谱上下文")
                                .font(AgentChatTypography.metaEmphasis)
                                .foregroundStyle(.secondary)
                            ForEach(row.expandedContextItems) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.sourceID)
                                        .font(AgentChatTypography.metaEmphasis)
                                    AgentMarkdownPreviewText(markdown: item.content, font: AgentChatTypography.meta)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }

                    if let prompt = row.promptSnapshotText, !prompt.isEmpty {
                        MetadataBlock(title: "提示词快照", text: prompt, monospaced: true)
                    } else if row.message.promptInspection != nil {
                        Text("本轮没有保存渲染后的提示词快照。")
                            .font(AgentChatTypography.meta)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("轮次信息")
                    .font(AgentChatTypography.metaEmphasis)
            }
            .font(AgentChatTypography.meta)
        }
    }
}

private struct MetadataBlock: View {
    var title: String
    var text: String
    var monospaced: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(AgentChatTypography.metaEmphasis)
                .foregroundStyle(.secondary)
            AgentMarkdownPreviewText(markdown: text, font: AgentChatTypography.meta, monospacedFallback: monospaced)
                .padding(8)
                .background(.quaternary.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct MetadataChips: View {
    var title: String
    var values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            Text(title)
                .font(AgentChatTypography.metaEmphasis)
                .foregroundStyle(.secondary)
            FlowLikeChips(values: values)
        }
    }
}

struct FlowLikeChips: View {
    var values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(AgentChatTypography.micro)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
        }
    }
}
