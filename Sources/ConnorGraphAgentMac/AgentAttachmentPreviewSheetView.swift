import SwiftUI
import AppKit
import ConnorGraphAppSupport
import ConnorGraphCore

struct AgentAttachmentPreviewSheetView: View {
    var model: AttachmentPreviewModel
    var onRetryExtraction: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceL) {
            header
            previewBody
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: AgentChatLayout.spaceM) {
            Image(systemName: iconName(for: model.attachment.kind))
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(ConnorCraftPalette.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.title)
                    .font(AgentChatTypography.sectionTitle)
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
            if canRetryExtraction, let onRetryExtraction {
                Button(action: onRetryExtraction) {
                    Label("重新解析", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("重新排队解析这个附件")
            }
        }
    }

    private var canRetryExtraction: Bool {
        guard let manifest = model.manifest else { return false }
        switch manifest.kind {
        case .pdf, .document, .spreadsheet, .presentation:
            return true
        default:
            return false
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
                case .image:
                    imagePreview
                }
            }
            .padding(AgentChatLayout.spaceM)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.48), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let url = model.sourceFileURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            ContentUnavailableView(
                "无法预览图片",
                systemImage: "photo",
                description: Text(model.sourceRelativePath ?? model.attachment.displayName)
            )
            .frame(maxWidth: .infinity, minHeight: 320)
        }
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
        .padding(AgentChatLayout.spaceM)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.28), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
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
        case .image: return "photo"
        case .csv, .spreadsheet: return "tablecells"
        case .code, .json, .html: return "chevron.left.forwardslash.chevron.right"
        case .markdown, .text: return "doc.text"
        case .pdf: return "doc.richtext"
        case .document: return "doc.text"
        case .presentation: return "rectangle.on.rectangle"
        default: return "paperclip"
        }
    }
}
