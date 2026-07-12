import AppKit
import ImageIO
import SwiftUI
import ConnorGraphCore

struct AgentInlineAttachmentLayout: Equatable {
    var maxWidth: CGFloat = 420
    var maxHeight: CGFloat = 320
    var minimumPlaceholderHeight: CGFloat = 120
}

@MainActor
@Observable
final class AgentImageThumbnailLoader {
    enum State {
        case idle
        case loading
        case loaded(NSImage)
        case failed
    }

    private(set) var state: State = .idle
    private var task: Task<Void, Never>?

    func load(url: URL, maximumPixelSize: Int) {
        task?.cancel()
        state = .loading
        task = Task { [weak self] in
            let image = await Task.detached(priority: .utility) {
                Self.downsampledImage(url: url, maximumPixelSize: maximumPixelSize)
            }.value
            guard !Task.isCancelled else { return }
            self?.state = image.map(State.loaded) ?? .failed
        }
    }

    private nonisolated static func downsampledImage(url: URL, maximumPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

struct AgentInlineAttachmentView: View {
    var attachment: AgentMessageAttachmentRef
    var localFileURL: URL?
    var layout = AgentInlineAttachmentLayout()
    var onPreview: () -> Void

    var body: some View {
        switch attachment.kind {
        case .image:
            AgentInlineImageAttachmentView(
                attachment: attachment,
                localFileURL: localFileURL,
                layout: layout,
                onPreview: onPreview
            )
        default:
            AgentAttachmentChip(attachment: attachment, onPreview: onPreview)
        }
    }
}

private struct AgentInlineImageAttachmentView: View {
    var attachment: AgentMessageAttachmentRef
    var localFileURL: URL?
    var layout: AgentInlineAttachmentLayout
    var onPreview: () -> Void
    @State private var loader = AgentImageThumbnailLoader()

    var body: some View {
        Button(action: onPreview) {
            Group {
                switch loader.state {
                case .loaded(let image):
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: layout.maxWidth, maxHeight: layout.maxHeight)
                case .failed:
                    placeholder(title: "无法加载图片", systemImage: "photo.badge.exclamationmark")
                case .idle, .loading:
                    placeholder(title: "正在加载图片", systemImage: "photo")
                        .overlay { if case .loading = loader.state { ProgressView().controlSize(.small) } }
                }
            }
            .frame(maxWidth: layout.maxWidth, minHeight: layout.minimumPlaceholderHeight)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AgentChatLayout.radiusM, style: .continuous).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("预览图片附件 \(attachment.displayName)")
        .task(id: localFileURL) {
            guard let localFileURL else { return }
            loader.load(url: localFileURL, maximumPixelSize: Int(max(layout.maxWidth, layout.maxHeight) * 2))
        }
    }

    private func placeholder(title: String, systemImage: String) -> some View {
        VStack(spacing: AgentChatLayout.spaceS) {
            Image(systemName: systemImage)
                .font(.title2)
            Text(title)
                .font(AgentChatTypography.meta)
            Text(attachment.displayName)
                .font(AgentChatTypography.micro)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: layout.minimumPlaceholderHeight)
    }
}

struct AgentAttachmentChip: View {
    var attachment: AgentMessageAttachmentRef
    var onPreview: () -> Void

    var body: some View {
        Button(action: onPreview) {
            Text("\(iconPrefix) \(attachment.displayName)")
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

    private var iconPrefix: String {
        switch attachment.kind {
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
