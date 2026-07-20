import SwiftUI
import ConnorGraphAppSupport

struct WorkspaceFilePreviewOverlay: View {
    var model: WorkspaceFilePreviewModel?
    var isLoading: Bool
    var onLoadMore: () -> Void
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Label("工作区文件", systemImage: "doc")
                        .font(AgentChatTypography.meta.weight(.medium))
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: AgentChatTypography.controlIconSize, weight: .semibold))
                            .frame(width: AgentChatLayout.iconButtonSize, height: AgentChatLayout.iconButtonSize)
                    }
                    .buttonStyle(.plain)
                    .frame(width: AgentChatLayout.hitTargetSize, height: AgentChatLayout.hitTargetSize)
                    .keyboardShortcut(.escape, modifiers: [])
                    .help("关闭预览")
                    .accessibilityLabel("关闭文件预览")
                }
                .padding(AgentChatLayout.spaceM)

                Group {
                    if model == nil {
                        ProgressView("正在加载预览...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let model {
                        preview(model)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isLoading, model != nil {
                        ProgressView()
                            .controlSize(.small)
                            .padding(AgentChatLayout.spaceM)
                    }
                }
                .frame(maxWidth: 900, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, AgentChatLayout.spaceXL)
                .padding(.bottom, AgentChatLayout.spaceXL)
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.96), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusXL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusXL, style: .continuous)
                    .stroke(Color.secondary.opacity(0.20), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 14)
            .padding(AgentChatLayout.spaceXL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func preview(_ model: WorkspaceFilePreviewModel) -> some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceL) {
            HStack(spacing: AgentChatLayout.spaceM) {
                Image(systemName: iconName(for: model.renderer))
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(ConnorCraftPalette.accent)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: AppShellLayout.spaceXS) {
                    Text(model.node.name)
                        .font(AgentChatTypography.sectionTitle)
                        .lineLimit(2)
                    Text(model.subtitle)
                        .font(AgentChatTypography.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if let encodingName = model.encodingName {
                        Text(encodingName.uppercased())
                            .font(AgentChatTypography.micro)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if model.isTruncated {
                    Button(action: onLoadMore) {
                        Label("继续加载", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading)
                    .help("再加载 2 MB 文本")
                }
            }

            if let message = model.message, !message.isEmpty {
                Label(message, systemImage: model.isTruncated ? "text.append" : "info.circle")
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
            }

            previewBody(model)
                .frame(maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.48), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func previewBody(_ model: WorkspaceFilePreviewModel) -> some View {
        switch model.renderer {
        case .markdown:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AgentChatLayout.spaceL) {
                    AgentMarkdownPreviewText(markdown: model.body)
                    continuationControl(model, automaticallyLoadWhenVisible: true)
                }
                    .padding(AgentChatLayout.spaceM)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .monospacedText:
            VStack(spacing: 0) {
                WorkspaceCodePreviewTextView(
                    contentID: "\(model.node.id):\(model.loadedByteCount)",
                    text: model.body,
                    spans: model.codeHighlightSpans,
                    canLoadMore: model.isTruncated && !isLoading,
                    onApproachEnd: onLoadMore
                )
                continuationControl(model, automaticallyLoadWhenVisible: false)
                    .padding(.horizontal, AgentChatLayout.spaceM)
            }
        case .plainText:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AgentChatLayout.spaceL) {
                    Text(model.body)
                        .font(AgentChatTypography.body)
                        .textSelection(.enabled)
                    continuationControl(model, automaticallyLoadWhenVisible: true)
                }
                    .padding(AgentChatLayout.spaceM)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .pdf:
            NativeFilePDFPreview(fileURL: model.node.url)
        case .quickLook:
            NativeFileQuickLookPreview(fileURL: model.node.url)
        case .html:
            ContentUnavailableView("将在浏览器中预览", systemImage: "globe", description: Text(model.node.relativePath))
        case .unsupported:
            ContentUnavailableView(
                "无法在应用内预览",
                systemImage: "doc.badge.ellipsis",
                description: Text(model.message ?? model.node.relativePath)
            )
        }
    }

    @ViewBuilder
    private func continuationControl(
        _ model: WorkspaceFilePreviewModel,
        automaticallyLoadWhenVisible: Bool
    ) -> some View {
        if model.isTruncated {
            HStack {
                Spacer()
                Button(action: onLoadMore) {
                    Label("继续加载下一段", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
                Spacer()
            }
            .padding(.vertical, AgentChatLayout.spaceS)
            .id(model.loadedByteCount)
            .onAppear {
                guard automaticallyLoadWhenVisible, !isLoading else { return }
                onLoadMore()
            }
        }
    }

    private func iconName(for renderer: WorkspaceFilePreviewRenderer) -> String {
        switch renderer {
        case .markdown, .plainText: "doc.text"
        case .monospacedText: "chevron.left.forwardslash.chevron.right"
        case .pdf: "doc.richtext"
        case .quickLook: "doc"
        case .html: "globe"
        case .unsupported: "doc.badge.ellipsis"
        }
    }
}
