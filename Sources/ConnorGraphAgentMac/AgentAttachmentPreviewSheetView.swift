import SwiftUI
import AppKit
import PDFKit
import QuickLookUI
import ConnorGraphAppSupport
import ConnorGraphCore

struct AgentAttachmentPreviewSheetView: View {
    var model: AttachmentPreviewModel
    var onDownloadImage: (() -> Void)? = nil
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
            VStack(alignment: .leading, spacing: AppShellLayout.spaceXS) {
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
            if canDownloadImage, let onDownloadImage {
                Button(action: onDownloadImage) {
                    Label("下载", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("下载这张图片")
                .help("将图片原件保存到你选择的位置")
            }
            if canRetryExtraction, let onRetryExtraction {
                Button(action: onRetryExtraction) {
                    Label("重新解析", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("重新排队解析这个附件")
            }
        }
    }

    private var canDownloadImage: Bool {
        AttachmentImageExportService().canExport(model)
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
        Group {
            if nativePreviewRenderer != .none, let url = model.sourceFileURL {
                nativeFilePreview(for: url)
                    .frame(maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
                    .overlay(alignment: .bottomLeading) {
                        if let error = model.errorMessage, !error.isEmpty {
                            Label(error, systemImage: "text.badge.xmark")
                                .font(AgentChatTypography.micro)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, AgentChatLayout.spaceS)
                                .padding(.vertical, AgentChatLayout.spaceXS)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
                                .padding(AgentChatLayout.spaceS)
                        }
                    }
            } else {
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.48), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private var nativePreviewRenderer: AttachmentNativePreviewRenderer {
        AttachmentPreviewPresentationPolicy.nativeRenderer(
            for: model.manifest?.kind ?? model.attachment.kind,
            hasOriginalFileURL: model.sourceFileURL != nil
        )
    }

    @ViewBuilder
    private func nativeFilePreview(for url: URL) -> some View {
        switch nativePreviewRenderer {
        case .pdfKit:
            NativeAttachmentPDFPreview(fileURL: url)
        case .quickLook:
            NativeAttachmentQuickLookPreview(fileURL: url)
        case .audioPlayer:
            ContentUnavailableView(
                "音频播放器即将可用",
                systemImage: "waveform",
                description: Text(url.lastPathComponent)
            )
        case .none:
            EmptyView()
        }
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

private struct NativeAttachmentPDFPreview: NSViewRepresentable {
    var fileURL: URL

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView(frame: .zero)
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = .clear
        pdfView.document = PDFDocument(url: fileURL)
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != fileURL {
            nsView.document = PDFDocument(url: fileURL)
        }
        nsView.autoScales = true
        nsView.displayMode = .singlePageContinuous
        nsView.displayDirection = .vertical
    }
}

private struct NativeAttachmentQuickLookPreview: NSViewRepresentable {
    var fileURL: URL

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        if let previewView = QLPreviewView(frame: .zero, style: .normal) {
            previewView.autostarts = true
            previewView.shouldCloseWithWindow = false
            previewView.previewItem = fileURL as NSURL
            previewView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(previewView)
            NSLayoutConstraint.activate([
                previewView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                previewView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                previewView.topAnchor.constraint(equalTo: container.topAnchor),
                previewView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        } else {
            let fallbackLabel = NSTextField(labelWithString: "Quick Look preview is unavailable for this file.")
            fallbackLabel.textColor = .secondaryLabelColor
            fallbackLabel.alignment = .center
            fallbackLabel.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(fallbackLabel)
            NSLayoutConstraint.activate([
                fallbackLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                fallbackLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                fallbackLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
                fallbackLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16)
            ])
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let previewView = nsView.subviews.compactMap({ $0 as? QLPreviewView }).first else { return }
        previewView.previewItem = fileURL as NSURL
        previewView.refreshPreviewItem()
    }
}
