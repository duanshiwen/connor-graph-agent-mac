import SwiftUI
import ConnorGraphCore

struct BrowserMediaTranscriptionPopoverView: View {
    var snapshot: BrowserMediaSourceSnapshot?
    var isScanning: Bool
    var errorMessage: String?
    var runningTask: AppSessionBackgroundTask?
    @Binding var selectedSourceIDs: Set<String>
    @Binding var mode: BrowserMediaTranscriptionMode
    @Binding var options: BrowserMediaTranscriptionOptions
    var onSelectAll: () -> Void
    var onClearSelection: () -> Void
    var onRescan: () -> Void
    var onCancel: () -> Void
    var onSubmit: () -> Void

    private var sourceOptions: [BrowserMediaTranscriptionSourceOption] {
        snapshot?.transcriptionSourceOptions ?? []
    }

    private var canSubmit: Bool {
        runningTask == nil && !isScanning && !selectedSourceIDs.isEmpty && !sourceOptions.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            pageContext

            if let runningTask {
                runningTaskCard(runningTask)
            }

            if let errorMessage, !errorMessage.isEmpty {
                diagnosticCard(title: "媒体扫描失败", message: errorMessage, systemImage: "exclamationmark.triangle")
            }

            if isScanning {
                scanningState
            } else if sourceOptions.isEmpty {
                emptyState
            } else {
                mediaSourceList
                modeSection
                advancedOptionsSection
            }

            footer
        }
        .padding(12)
        .frame(width: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
        .onChange(of: mode) { _, newMode in
            options = BrowserMediaTranscriptionOptions.defaults(for: newMode)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("网页媒体转写", systemImage: "waveform.badge.magnifyingglass")
                .font(BrowserFloatingTypography.popoverTitle)
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(BrowserFloatingTypography.toolbarIcon)
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var pageContext: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: 4) {
                if let title = snapshot.pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                    Text(title)
                        .font(BrowserFloatingTypography.pageTitle)
                        .lineLimit(1)
                }
                Text(snapshot.pageURLString)
                    .font(BrowserFloatingTypography.pageURL)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            Text("扫描当前网页中的 video/audio 与媒体 metadata。")
                .font(BrowserFloatingTypography.hint)
                .foregroundStyle(.secondary)
        }
    }

    private var scanningState: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("正在扫描当前网页媒体…")
                .font(BrowserFloatingTypography.messageBody)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var emptyState: some View {
        diagnosticCard(
            title: "未检测到可转写媒体",
            message: "当前页面暂未发现 video/audio 或公开媒体 metadata。若视频仍在加载，请先播放几秒后点击“重新扫描”。",
            systemImage: "waveform.badge.exclamationmark"
        )
    }

    private var mediaSourceList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("选择要转写的媒体")
                        .font(BrowserFloatingTypography.messageRole)
                        .foregroundStyle(.secondary)
                    Text("只会处理被勾选的 video/audio/metadata 来源。")
                        .font(BrowserFloatingTypography.hint)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text("已选 \(selectedSourceIDs.count)/\(sourceOptions.count)")
                    .font(BrowserFloatingTypography.hint)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 6) {
                Button("全选", action: onSelectAll)
                    .disabled(sourceOptions.isEmpty || selectedSourceIDs.count == sourceOptions.count || runningTask != nil)
                Button("清空", action: onClearSelection)
                    .disabled(selectedSourceIDs.isEmpty || runningTask != nil)
                Spacer()
                if sourceOptions.count > 1, selectedSourceIDs.isEmpty {
                    Label("请选择至少一个媒体", systemImage: "hand.point.up.left")
                        .font(BrowserFloatingTypography.hint)
                        .foregroundStyle(.orange)
                }
            }
            .font(BrowserFloatingTypography.quickAction)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(sourceOptions) { option in
                        BrowserMediaTranscriptionSourceRow(
                            option: option,
                            isSelected: selectedSourceIDs.contains(option.id),
                            onToggle: { toggle(option.id) }
                        )
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("处理方式")
                .font(BrowserFloatingTypography.messageRole)
                .foregroundStyle(.secondary)
            Picker("处理方式", selection: $mode) {
                ForEach(BrowserMediaTranscriptionMode.allCases) { mode in
                    Text(mode.displayTitle).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var advancedOptionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("选项")
                .font(BrowserFloatingTypography.messageRole)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Toggle("优先使用平台字幕", isOn: $options.shouldPreferPlatformSubtitles)
                Toggle("下载音频", isOn: $options.shouldDownloadAudio)
                Toggle("本地转写", isOn: $options.shouldRunLocalTranscription)
                Toggle("说话人分离", isOn: $options.shouldRunSpeakerDiarization)
                Toggle("生成章节", isOn: $options.shouldGenerateChapters)
                    .disabled(mode == .transcribeOnly || mode == .transcribeAndSummarize)
            }
            .font(BrowserFloatingTypography.hint)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: onRescan) {
                Label("重新扫描", systemImage: "arrow.clockwise")
            }
            .disabled(isScanning || runningTask != nil)

            Spacer()

            Button("取消", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Button(action: onSubmit) {
                Label(runningTask == nil ? "开始处理" : "任务进行中", systemImage: runningTask == nil ? "play.fill" : "hourglass")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSubmit)
        }
        .font(BrowserFloatingTypography.quickAction)
    }

    private func runningTaskCard(_ task: AppSessionBackgroundTask) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("媒体转写任务进行中")
                        .font(BrowserFloatingTypography.messageRole)
                    Text(task.status.displayName)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                }
                Text(task.detail)
                    .font(BrowserFloatingTypography.hint)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("完成前不能创建新的网页媒体转写任务。可在会话后台任务面板查看进度。")
                    .font(BrowserFloatingTypography.hint)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(ConnorCraftPalette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(ConnorCraftPalette.accent.opacity(0.24), lineWidth: 1)
        )
    }

    private func diagnosticCard(title: String, message: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(BrowserFloatingTypography.messageRole)
                Text(message)
                    .font(BrowserFloatingTypography.hint)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func toggle(_ id: String) {
        if selectedSourceIDs.contains(id) {
            selectedSourceIDs.remove(id)
        } else {
            selectedSourceIDs.insert(id)
        }
    }
}

private struct BrowserMediaTranscriptionSourceRow: View {
    var option: BrowserMediaTranscriptionSourceOption
    var isSelected: Bool
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? ConnorCraftPalette.accent : Color.secondary)
                    .frame(width: 18)
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(option.title)
                            .font(BrowserFloatingTypography.messageBody.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(option.kind == .mediaElement ? "页面元素" : "Metadata")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.10), in: Capsule())
                    }
                    HStack(spacing: 8) {
                        if let duration = option.durationSeconds, duration > 0 {
                            Text(formatDuration(duration))
                        }
                        if let readyState = option.readyState {
                            Text("readyState \(readyState)")
                        }
                        if option.isPaused == false {
                            Text("播放中")
                        }
                    }
                    .font(BrowserFloatingTypography.hint)
                    .foregroundStyle(.tertiary)
                    if let url = option.sourceURLString, !url.isEmpty {
                        Text(shortURL(url))
                            .font(BrowserFloatingTypography.pageURL)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("未暴露直接媒体 URL，可能需要平台字幕或下载器解析。")
                            .font(BrowserFloatingTypography.hint)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? ConnorCraftPalette.accent.opacity(0.10) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? ConnorCraftPalette.accent.opacity(0.35) : Color.secondary.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        let lower = option.mediaKind.lowercased()
        if lower.contains("audio") { return "waveform" }
        if lower.contains("video") { return "play.rectangle" }
        return "link"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        let remaining = total % 60
        return String(format: "%d:%02d", minutes, remaining)
    }

    private func shortURL(_ raw: String) -> String {
        guard let url = URL(string: raw), let host = url.host else { return raw }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty { return host }
        return "\(host)/\(path)"
    }
}
