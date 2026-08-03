import AppKit
import AVKit
import ImageIO
import Observation
import SwiftUI
import ConnorGraphCore

struct ChatMediaPreviewItem: Identifiable {
    let id = UUID()
    let type: ImMessageType
    let url: URL
    let title: String
}

@MainActor
@Observable
final class ChatPreviewImageLoader {
    enum State {
        case loading
        case loaded(NSImage)
        case failed
    }

    private(set) var state: State = .loading
    private var task: Task<Void, Never>?

    func load(url: URL, maximumPixelSize: Int = 4_096) {
        task?.cancel()
        state = .loading
        task = Task { [weak self] in
            let image = await Self.loadImage(url: url, maximumPixelSize: maximumPixelSize)
            guard !Task.isCancelled else { return }
            self?.state = image.map(State.loaded) ?? .failed
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private nonisolated static func loadImage(url: URL, maximumPixelSize: Int) async -> NSImage? {
        if url.isFileURL {
            return await Task.detached(priority: .userInitiated) {
                downsampledImage(url: url, maximumPixelSize: maximumPixelSize)
            }.value
        }
        do {
            let (temporaryURL, response) = try await URLSession.shared.download(from: url)
            guard (response as? HTTPURLResponse).map({ 200..<300 ~= $0.statusCode }) ?? true else { return nil }
            return await Task.detached(priority: .userInitiated) {
                downsampledImage(url: temporaryURL, maximumPixelSize: maximumPixelSize)
            }.value
        } catch {
            return nil
        }
    }

    private nonisolated static func downsampledImage(url: URL, maximumPixelSize: Int) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

struct DownsampledImagePreview: View {
    let url: URL
    var maximumPixelSize = 4_096
    @State private var loader = ChatPreviewImageLoader()

    var body: some View {
        Group {
            switch loader.state {
            case .loading:
                ProgressView("正在加载图片")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let image):
                ZoomableImagePreview(image: image)
            case .failed:
                ContentUnavailableView("无法预览图片", systemImage: "photo.badge.exclamationmark")
            }
        }
        .task(id: url) { loader.load(url: url, maximumPixelSize: maximumPixelSize) }
        .onDisappear { loader.cancel() }
    }
}

struct ChatThumbnailImage: View {
    let url: URL
    let width: CGFloat
    let height: CGFloat
    @State private var loader = ChatPreviewImageLoader()

    var body: some View {
        Group {
            switch loader.state {
            case .loaded(let image):
                Image(nsImage: image).resizable().scaledToFill()
            case .failed:
                Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary)
            case .loading:
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .task(id: url) {
            loader.load(url: url, maximumPixelSize: Int(max(width, height) * 2))
        }
        .onDisappear { loader.cancel() }
    }
}

struct ChatMediaPreviewOverlay: View {
    let item: ChatMediaPreviewItem
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Label(typeLabel, systemImage: iconName)
                        .font(AgentChatTypography.meta.weight(.medium))
                        .padding(.horizontal, AgentChatLayout.spaceS)
                        .frame(height: AgentChatLayout.chipHeight)
                        .background(Color.clear, in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AgentChatLayout.radiusS, style: .continuous)
                                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                        )
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: AgentChatTypography.controlIconSize, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: AgentChatLayout.iconButtonSize, height: AgentChatLayout.iconButtonSize)
                    }
                    .buttonStyle(.plain)
                    .frame(width: AgentChatLayout.hitTargetSize, height: AgentChatLayout.hitTargetSize)
                    .contentShape(Rectangle())
                    .keyboardShortcut(.escape, modifiers: [])
                    .accessibilityLabel("关闭媒体预览")
                    .help("关闭预览")
                }
                .padding(AgentChatLayout.spaceM)

                VStack(alignment: .leading, spacing: AgentChatLayout.spaceL) {
                    header
                    previewBody
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

    private var header: some View {
        HStack(alignment: .top, spacing: AgentChatLayout.spaceM) {
            Image(systemName: iconName)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(ConnorCraftPalette.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: AppShellLayout.spaceXS) {
                Text(item.title)
                    .font(AgentChatTypography.sectionTitle)
                    .lineLimit(2)
                Text(subtitle)
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var previewBody: some View {
        preview
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.48), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var preview: some View {
        switch item.type {
        case .image:
            DownsampledImagePreview(url: item.url)
        case .video:
            ChatVideoPreview(url: item.url)
        case .audio:
            ChatAudioPreview(url: item.url, title: item.title)
        case .file:
            NativeFileQuickLookPreview(fileURL: item.url)
        case .text, .system:
            ContentUnavailableView("无法预览此媒体", systemImage: "nosign")
                .foregroundStyle(.white)
        }
    }

    private var iconName: String {
        switch item.type {
        case .image: return "photo"
        case .video: return "video"
        case .audio: return "waveform"
        case .file: return "doc"
        case .text, .system: return "doc.text"
        }
    }

    private var typeLabel: String {
        switch item.type {
        case .image: return "图片"
        case .video: return "视频"
        case .audio: return "语音"
        case .file: return "文件"
        case .text, .system: return "媒体"
        }
    }

    private var subtitle: String {
        switch item.type {
        case .image: return "图片预览"
        case .video: return "视频预览"
        case .audio: return "语音消息"
        case .file: return "文件预览"
        case .text, .system: return "媒体预览"
        }
    }
}

struct ChatVideoPreview: View {
    let url: URL
    @State private var player: AVPlayer?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .task(id: url) {
            let player = AVPlayer(url: url)
            self.player = player
            player.play()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player?.pause() }
        }
        .onDisappear { releasePlayer() }
    }

    private func releasePlayer() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }
}

struct ChatAudioPreview: View {
    let url: URL
    let title: String
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 88))
                .foregroundStyle(ConnorCraftPalette.accent)
            Text(title)
                .font(.title3)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .frame(width: 56, height: 56)
                    .background(ConnorCraftPalette.accent, in: Circle())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "暂停" : "播放")
        }
        .task(id: url) { player = AVPlayer(url: url) }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                player?.pause()
                isPlaying = false
            }
        }
        .onDisappear { releasePlayer() }
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    private func releasePlayer() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        isPlaying = false
    }
}
