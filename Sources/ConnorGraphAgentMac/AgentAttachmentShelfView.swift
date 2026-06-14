import SwiftUI
import ConnorGraphCore

struct AgentAttachmentShelfView: View {
    var attachments: [AgentMessageAttachmentRef]
    var onRemove: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AgentChatLayout.spaceS) {
                ForEach(attachments) { attachment in
                    attachmentChip(attachment)
                }
            }
            .padding(.horizontal, AgentChatLayout.spaceL)
            .padding(.top, AgentChatLayout.spaceS)
            .padding(.bottom, AgentChatLayout.spaceXS)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("附件列表")
    }

    private func attachmentChip(_ attachment: AgentMessageAttachmentRef) -> some View {
        HStack(spacing: AgentChatLayout.spaceS) {
            Image(systemName: iconName(for: attachment.kind))
                .font(.system(size: AgentChatTypography.smallIconSize, weight: .medium))
                .foregroundStyle(ConnorCraftPalette.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.displayName)
                    .font(AgentChatTypography.microEmphasis)
                    .lineLimit(1)
                Text(statusText(for: attachment))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Button {
                onRemove(attachment.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("移除附件 \(attachment.displayName)")
        }
        .padding(.horizontal, AgentChatLayout.spaceS)
        .padding(.vertical, 5)
        .frame(maxWidth: 220, minHeight: 30)
        .background(ConnorCraftPalette.accentSubtleFill, in: Capsule())
        .overlay(Capsule().stroke(ConnorCraftPalette.accentBorder, lineWidth: 1))
        .help(attachment.previewText ?? attachment.displayName)
    }

    private func iconName(for kind: AgentAttachmentKind) -> String {
        switch kind {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .spreadsheet, .csv: return "tablecells"
        case .archive: return "archivebox"
        case .audio: return "waveform"
        case .video: return "film"
        case .code, .json, .html: return "chevron.left.forwardslash.chevron.right"
        default: return "paperclip"
        }
    }

    private func statusText(for attachment: AgentMessageAttachmentRef) -> String {
        let size = ByteCountFormatter.string(fromByteCount: attachment.byteCount, countStyle: .file)
        switch attachment.extractionStatus {
        case .extracted: return "已解析 · \(size)"
        case .unsupported: return "仅保存 · \(size)"
        case .skippedOversize: return "过大未解析 · \(size)"
        case .failed: return "解析失败 · \(size)"
        case .pending: return "等待解析 · \(size)"
        }
    }
}
