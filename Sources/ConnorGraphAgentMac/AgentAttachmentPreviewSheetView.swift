import SwiftUI
import ConnorGraphAppSupport
import ConnorGraphCore

struct AgentAttachmentPreviewSheetView: View {
    var model: AttachmentPreviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceL) {
            header
            Divider()
            previewBody
            Divider()
            footer
        }
        .padding(AgentChatLayout.spaceL)
        .frame(minWidth: 680, minHeight: 560)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: AgentChatLayout.spaceM) {
            Image(systemName: iconName(for: model.attachment.kind))
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(ConnorCraftPalette.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text(model.subtitle)
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(AgentChatTypography.meta)
                        .foregroundStyle(.orange)
                        .padding(.top, 2)
                }
            }
            Spacer()
        }
    }

    private var previewBody: some View {
        ScrollView {
            Group {
                switch model.bodyMode {
                case .markdown:
                    AgentMarkdownPreviewText(markdown: model.body)
                case .monospaced:
                    Text(model.body)
                        .font(AgentChatTypography.monoMeta)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .plain:
                    Text(model.body)
                        .font(AgentChatTypography.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(AgentChatLayout.spaceM)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous)
                .stroke(Color.secondary.opacity(AgentChatLayout.hairlineOpacity), lineWidth: 1)
        )
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceXS) {
            keyValue("Attachment ID", model.attachment.id)
            keyValue("Manifest", model.attachment.manifestRelativePath)
            if let manifest = model.manifest {
                keyValue("Stored", manifest.storedRelativePath)
            }
            if let sourceRelativePath = model.sourceRelativePath {
                keyValue("Preview source", sourceRelativePath)
            }
        }
    }

    private func keyValue(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: AgentChatLayout.spaceS) {
            Text(key)
                .font(AgentChatTypography.metaEmphasis)
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)
            Text(value)
                .font(AgentChatTypography.meta)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func iconName(for kind: AgentAttachmentKind) -> String {
        switch kind {
        case .csv, .spreadsheet: return "tablecells"
        case .code, .json, .html: return "chevron.left.forwardslash.chevron.right"
        case .markdown, .text: return "doc.text"
        default: return "paperclip"
        }
    }
}
