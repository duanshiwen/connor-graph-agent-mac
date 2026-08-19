import SwiftUI
import ConnorGraphCore
import ConnorGraphAppSupport

struct AgentAttachmentShelfView: View {
    var attachments: [AgentMessageAttachmentRef]
    var rejections: [String: AttachmentImportRejectionReason] = [:]
    var onPreview: (AgentMessageAttachmentRef) -> Void = { _ in }
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
        let rejection = rejections[attachment.id]
        return HStack(spacing: AgentChatLayout.spaceS) {
            Button {
                onPreview(attachment)
            } label: {
                HStack(spacing: AgentChatLayout.spaceS) {
                    Image(systemName: rejection == nil ? iconName(for: attachment.kind) : "exclamationmark.triangle.fill")
                        .font(.system(size: AgentChatTypography.smallIconSize, weight: .medium))
                        .foregroundStyle(rejection == nil ? ConnorCraftPalette.accent : Color.red)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(attachment.displayName)
                            .font(AgentChatTypography.microEmphasis)
                            .lineLimit(1)
                        Text(rejection.map { shortLabel(for: $0) } ?? statusText(for: attachment))
                            .font(AgentChatTypography.micro)
                            .foregroundStyle(rejection == nil ? Color.secondary : Color.red)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("预览附件 \(attachment.displayName)")
            .help(rejection?.userMessage ?? (attachment.previewText ?? attachment.displayName))

            Button {
                onRemove(attachment.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(rejection == nil ? Color.secondary : Color.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("移除附件 \(attachment.displayName)")
        }
        .padding(.horizontal, AgentChatLayout.spaceS)
        .padding(.vertical, 5)
        .frame(maxWidth: 220, minHeight: 30)
        .background(rejection == nil ? ConnorCraftPalette.accentSubtleFill : Color.red.opacity(0.08), in: Capsule())
        .overlay(Capsule().stroke(rejection == nil ? ConnorCraftPalette.accentBorder : Color.red.opacity(0.35), lineWidth: 1))
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

    private func shortLabel(for reason: AttachmentImportRejectionReason) -> String {
        switch reason {
        case .totalAttachmentBudgetExceeded:
            return "未发送 · 内容超出本次上限"
        case .contentTooLargeForExtraction:
            return "未发送 · 内容过大无法解析"
        case .extractionFailed:
            return "未发送 · 解析失败"
        default:
            return "未发送 · 不满足发送条件"
        }
    }
}
