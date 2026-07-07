import SwiftUI
import ConnorGraphAgent
import ConnorGraphAppSupport

struct AgentAssistantMessageActionsPresentation: Equatable {
    var showsActions: Bool
    var copyTitle: String
    var exportTitle: String
    var copyAccessibilityLabel: String
    var exportAccessibilityLabel: String
    var copyHelp: String
    var exportHelp: String

    init(message: AgentMessage) {
        let hasContent = !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.showsActions = message.role == .assistant && hasContent
        self.copyTitle = "复制"
        self.exportTitle = "导出到文件"
        self.copyAccessibilityLabel = "复制这条助理回复"
        self.exportAccessibilityLabel = "导出这条助理回复到文件"
        self.copyHelp = "复制原始 Markdown 文本"
        self.exportHelp = "选择保存位置和文件名，导出为 Markdown 文件"
    }
}

enum AssistantMessageExportFormatter {
    private static let invalidFilenameCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")

    static func filename(for message: AgentChatMessagePresentation, date: Date, calendar: Calendar = .current) -> String {
        let turn = String(format: "%03d", max(message.turnNumber, 0))
        let timestamp = timestampFormatter(calendar: calendar).string(from: date)
        let prefix = sanitizedMessageIDPrefix(message.message.id)
        return "assistant-reply-turn-\(turn)-\(timestamp)-\(prefix).md"
    }

    private static func sanitizedMessageIDPrefix(_ id: String) -> String {
        let sanitized = id.unicodeScalars.map { scalar -> Character in
            invalidFilenameCharacters.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar) ? "-" : Character(scalar)
        }
        let prefix = String(sanitized).prefix(8)
        return prefix.isEmpty ? "message" : String(prefix)
    }

    private static func timestampFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
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

struct AgentChatUnreadMarkerRow: View {
    var unreadCount: Int

    private var title: String {
        unreadCount > 0 ? "\(unreadCount) 条未读消息" : "未读消息"
    }

    var body: some View {
        HStack(spacing: AgentChatLayout.spaceM) {
            Rectangle()
                .fill(ConnorCraftPalette.accent.opacity(0.32))
                .frame(height: 1)
            Text(title)
                .font(AgentChatTypography.microEmphasis)
                .foregroundStyle(ConnorCraftPalette.accent)
                .lineLimit(1)
                .padding(.horizontal, AgentChatLayout.spaceM)
                .padding(.vertical, AgentChatLayout.spaceXS)
                .background(
                    Capsule(style: .continuous)
                        .fill(ConnorCraftPalette.accentSubtleFill)
                )
            Rectangle()
                .fill(ConnorCraftPalette.accent.opacity(0.32))
                .frame(height: 1)
        }
        .padding(.vertical, AgentChatLayout.spaceXS)
        .accessibilityLabel(title)
    }
}

struct AgentChatDateSeparatorRow: View {
    var title: String

    var body: some View {
        Text(title)
            .font(AgentChatTypography.microEmphasis)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, AgentChatLayout.spaceM)
            .padding(.vertical, AgentChatLayout.spaceXS)
            .background(
                Capsule(style: .continuous)
                    .fill(ConnorCraftPalette.foreground.opacity(0.055))
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, AgentChatLayout.spaceXS)
            .accessibilityLabel("对话日期 \(title)")
    }
}

struct AgentChatMessageRow: View {
    var row: AgentChatMessagePresentation
    var persistentCacheContext: AgentMarkdownPersistentCacheContext? = nil
    var onPreviewAttachment: (AgentMessageAttachmentRef) -> Void = { _ in }
    var onCopyAssistantMessage: (AgentChatMessagePresentation) -> Void = { _ in }
    var onExportAssistantMessage: (AgentChatMessagePresentation) -> Void = { _ in }

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
    private var assistantActionsPresentation: AgentAssistantMessageActionsPresentation {
        AgentAssistantMessageActionsPresentation(message: row.message)
    }

    private var activeSkillLabel: String? {
        guard let contextSnapshot = row.message.contextSnapshot else { return nil }
        let prefix = "Active skill:"
        guard let line = contextSnapshot
            .components(separatedBy: .newlines)
            .first(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(prefix) })
        else { return nil }
        let label = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? nil : label
    }

    private var browserPromptFoldingParts: BrowserPromptFoldingParts? {
        BrowserPromptFoldingCache.shared.parts(for: row.id, content: row.message.content)
    }

    var body: some View {
        HStack(alignment: .top) {
            if isUser { Spacer(minLength: AgentChatLayout.messageSideInset) }

            VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
                VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                    if isUser, let activeSkillLabel {
                        userActiveSkillChip(activeSkillLabel)
                    }
                    messageContent
                    if !row.attachments.isEmpty {
                        AgentMessageAttachmentRefsView(attachments: row.attachments) { attachment in
                            onPreviewAttachment(attachment)
                        }
                    }
                }
                .foregroundStyle(Color.primary)
                .padding(.horizontal, AgentChatLayout.messageBubbleHorizontalPadding)
                .padding(.vertical, AgentChatLayout.messageBubbleVerticalPadding)
                .frame(maxWidth: isUser ? AgentChatLayout.userMessageMaxWidth : .infinity, alignment: .leading)
                .background(messageBackground, in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                        .stroke(isUser ? Color.clear : Color.secondary.opacity(AgentChatLayout.hairlineOpacity), lineWidth: 1)
                )

                if assistantActionsPresentation.showsActions {
                    AgentAssistantMessageActionsView(
                        presentation: assistantActionsPresentation,
                        onCopy: { onCopyAssistantMessage(row) },
                        onExport: { onExportAssistantMessage(row) }
                    )
                    .padding(.leading, AgentChatLayout.messageBubbleHorizontalPadding + 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private func userActiveSkillChip(_ label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(AgentChatTypography.micro.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
        )
        .accessibilityLabel("本轮技能：\(label)")
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
            assistantMarkdownBody
        }
    }

    private var assistantMarkdownBody: some View {
        AgentMarkdownPreviewText(
            markdown: row.message.content,
            font: AgentChatTypography.body,
            persistentCacheContext: persistentCacheContext
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, AgentChatLayout.assistantMessageTrailingPadding)
    }

    private var messageBackground: Color {
        if isUser { return ConnorCraftPalette.userBubble }
        return Color(nsColor: .controlBackgroundColor).opacity(0.85)
    }
}

private struct AgentAssistantMessageActionsView: View {
    var presentation: AgentAssistantMessageActionsPresentation
    var onCopy: () -> Void
    var onExport: () -> Void

    var body: some View {
        HStack(spacing: AgentChatLayout.spaceXS) {
            actionButton(
                title: presentation.copyTitle,
                accessibilityLabel: presentation.copyAccessibilityLabel,
                help: presentation.copyHelp,
                action: onCopy
            )
            actionButton(
                title: presentation.exportTitle,
                accessibilityLabel: presentation.exportAccessibilityLabel,
                help: presentation.exportHelp,
                action: onExport
            )
            Spacer(minLength: 0)
        }
        .padding(.top, 1)
        .accessibilityElement(children: .contain)
    }

    private func actionButton(
        title: String,
        accessibilityLabel: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(AgentChatTypography.microEmphasis)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(
            Capsule(style: .continuous)
                .fill(ConnorCraftPalette.foreground.opacity(0.035))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(ConnorCraftPalette.foreground.opacity(0.07), lineWidth: 1)
        )
        .accessibilityLabel(accessibilityLabel)
        .help(help)
    }
}

struct AgentMessageAttachmentRefsView: View {
    var attachments: [AgentMessageAttachmentRef]
    var onPreview: (AgentMessageAttachmentRef) -> Void

    var body: some View {
        HStack(spacing: AgentChatLayout.spaceS) {
            ForEach(attachments) { attachment in
                Button {
                    onPreview(attachment)
                } label: {
                    Text("\(iconPrefix(for: attachment.kind)) \(attachment.displayName)")
                        .font(AgentChatTypography.meta)
                        .lineLimit(1)
                        .padding(.horizontal, AgentChatLayout.spaceS)
                        .padding(.vertical, 4)
                        .background(ConnorCraftPalette.accentSubtleFill, in: Capsule())
                        .overlay(Capsule().stroke(ConnorCraftPalette.accentBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("预览附件 \(attachment.displayName)")
            }
        }
        .accessibilityLabel("消息附件 \(attachments.count) 个")
    }

    private func iconPrefix(for kind: AgentAttachmentKind) -> String {
        switch kind {
        case .image: return "图片"
        case .pdf: return "PDF"
        case .csv, .spreadsheet: return "表格"
        case .code, .json, .html: return "代码"
        case .archive: return "压缩包"
        case .audio: return "音频"
        case .video: return "视频"
        default: return "附件"
        }
    }
}

/// 助理消息上方的头像 + 昵称行。
/// 现阶段固定为康纳同学。
struct AgentAssistantHeaderView: View {
    var displayName: String = "康纳同学"
    var subtitle: String = "你的主动 AI 助理"
    var slogan: String = "用知识图谱记住一切，连接日历社交，知识市场共享智慧，可靠地完成任务。"
    var avatarImage: NSImage? = nil

    var body: some View {
        HStack(alignment: .top, spacing: AgentChatLayout.spaceS) {
            avatarView
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(AgentChatTypography.microEmphasis)
                    .foregroundStyle(.primary.opacity(0.85))
                HStack(spacing: 4) {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                    Text(slogan)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let avatarImage {
            Image(nsImage: avatarImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: AgentChatLayout.avatarSize, height: AgentChatLayout.avatarSize)
                .clipShape(Circle())
        } else {
            Image("ConnorAvatar")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: AgentChatLayout.avatarSize, height: AgentChatLayout.avatarSize)
                .clipShape(Circle())
        }
    }
}

struct BrowserPromptFoldedMessageView: View {
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

