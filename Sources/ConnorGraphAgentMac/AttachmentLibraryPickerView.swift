import SwiftUI
import UniformTypeIdentifiers
import ConnorGraphCore
import ConnorGraphAppSupport

/// 附件库选择面板的展示模型：最近附件列表 + 关键词/类型筛选 + 分页加载。
@MainActor
final class AttachmentLibraryPickerModel: ObservableObject, Identifiable {
    let id = UUID()

    enum KindFilter: String, CaseIterable, Identifiable {
        case all, image, video, audio, pdf, document, spreadsheet, presentation, archive, text
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "全部"
            case .image: return "图片"
            case .video: return "视频"
            case .audio: return "音频"
            case .pdf: return "PDF"
            case .document: return "文档"
            case .spreadsheet: return "表格"
            case .presentation: return "演示"
            case .archive: return "压缩包"
            case .text: return "文本"
            }
        }
        /// 该筛选命中的附件类型集合；`nil` 表示不过滤（全部）。
        /// 「文本」覆盖 txt/md/json/csv/html 等可读文本类文件。
        var kinds: Set<AgentAttachmentKind>? {
            switch self {
            case .all: return nil
            case .image: return [.image]
            case .video: return [.video]
            case .audio: return [.audio]
            case .pdf: return [.pdf]
            case .document: return [.document]
            case .spreadsheet: return [.spreadsheet]
            case .presentation: return [.presentation]
            case .archive: return [.archive]
            case .text: return [.text, .markdown, .json, .csv, .html]
            }
        }

        /// 空结果时的空状态文案与图标。
        var emptyState: (title: String, systemImage: String, description: String) {
            switch self {
            case .all:
                return ("附件库是空的", "tray", "把文件发给康纳同学或导入到附件库后，会出现在这里。")
            case .image:
                return ("没有找到图片附件", "photo", "把图片发给康纳同学或导入到附件库后，会出现在这里。")
            case .video:
                return ("没有找到视频附件", "film", "把视频发给康纳同学或导入到附件库后，会出现在这里。")
            case .audio:
                return ("没有找到音频附件", "waveform", "把音频发给康纳同学或导入到附件库后，会出现在这里。")
            case .pdf:
                return ("没有找到 PDF 附件", "doc.richtext", "把 PDF 发给康纳同学或导入到附件库后，会出现在这里。")
            case .document:
                return ("没有找到文档附件", "doc.text", "把文档发给康纳同学或导入到附件库后，会出现在这里。")
            case .spreadsheet:
                return ("没有找到表格附件", "tablecells", "把表格发给康纳同学或导入到附件库后，会出现在这里。")
            case .presentation:
                return ("没有找到演示附件", "chart.bar", "把演示文稿发给康纳同学或导入到附件库后，会出现在这里。")
            case .archive:
                return ("没有找到压缩包附件", "archivebox", "把压缩包发给康纳同学或导入到附件库后，会出现在这里。")
            case .text:
                return ("没有找到文本附件", "doc.plaintext", "把文本文件（txt/md/json/csv/html 等）发给康纳同学或导入到附件库后，会出现在这里。")
            }
        }
    }

    let store: FileArtifactStore
    let allowsMultipleSelection: Bool
    let pageSize: Int

    @Published var query = ""
    @Published var kindFilter: KindFilter = .all
    @Published private(set) var items: [FileArtifactRecord] = []
    @Published private(set) var total = 0
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasLoadedOnce = false
    @Published var selectedIDs: Set<String> = []

    private var page = 0

    init(store: FileArtifactStore, allowsMultipleSelection: Bool, pageSize: Int = 30, presetKind: KindFilter = .all) {
        self.store = store
        self.allowsMultipleSelection = allowsMultipleSelection
        self.pageSize = pageSize
        self.kindFilter = presetKind
    }

    var hasMore: Bool { items.count < total }

    func reload() {
        page = 0
        items = []
        total = 0
        selectedIDs = []
        loadMore()
    }

    /// 滚动到底自动加载下一页（分页懒加载）。
    func loadMoreIfNeeded(current item: FileArtifactRecord) {
        if item.fileID == items.last?.fileID, hasMore { loadMore() }
    }

    func loadMore() {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = store.list(
            query: needle.isEmpty ? nil : needle,
            kinds: kindFilter.kinds,
            page: page,
            pageSize: pageSize
        )
        items.append(contentsOf: result.items)
        total = result.total
        page += 1
        hasLoadedOnce = true
    }

    func localURL(for record: FileArtifactRecord) -> URL {
        store.paths.filesDirectory.appendingPathComponent(record.storedRelativePath)
    }

    func toggle(_ record: FileArtifactRecord) {
        if allowsMultipleSelection {
            if selectedIDs.contains(record.fileID) { selectedIDs.remove(record.fileID) }
            else { selectedIDs.insert(record.fileID) }
        } else {
            selectedIDs = [record.fileID]
        }
    }
}

/// 附件库选择面板：最近附件列表（可搜索/按类型筛选/分页），
/// 底部提供「从文件夹选择…」回退。多选时点「确定」返回所选文件 URL。
struct AttachmentLibraryPickerView: View {
    @ObservedObject var model: AttachmentLibraryPickerModel
    var title = "附件库"
    var onPick: ([URL]) -> Void
    var onPickFromFolder: () -> Void
    /// 内嵌子页面形态下隐藏内置头部（由外层面板提供“返回”按钮）。
    var showsHeader: Bool = true
    /// 高度：弹窗形态 540，内嵌子页面形态由外层面板传入更小的高度。
    var preferredHeight: CGFloat = 540
    /// 内嵌形态下点击关闭/返回时调用；缺省时走系统 dismiss（弹窗形态）。
    var onCollapse: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var previewTarget: AttachmentLibraryPreviewTarget?

    private var selectedURLs: [URL] {
        model.items.filter { model.selectedIDs.contains($0.fileID) }.map { model.localURL(for: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                header
                Divider()
            }
            searchAndFilters
            Divider()
            list
            Divider()
            footer
        }
        // 宽度自适应：窄窗口下跟随窗口宽度收缩，常规宽度上限 600，高度保持稳定。
        .frame(maxWidth: 600)
        .frame(height: preferredHeight)
        .onAppear { if !model.hasLoadedOnce { model.reload() } }
        .sheet(item: $previewTarget) { target in
            AttachmentLibraryQuickPreviewSheet(url: target.url, title: target.title)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.full")
                .font(.system(size: 20, weight: .medium)).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text("最近使用的附件，按时间排序").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                if let onCollapse {
                    onCollapse()
                } else {
                    if !model.allowsMultipleSelection, let first = model.selectedIDs.first,
                       let record = model.items.first(where: { $0.fileID == first }) {
                        onPick([model.localURL(for: record)])
                    } else {
                        dismiss()
                    }
                }
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(onCollapse == nil ? "关闭" : "收起附件选择")
        }
        .padding(16)
    }

    private var searchAndFilters: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索文件名、类型或说明", text: $model.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(model.reload)
                if !model.query.isEmpty {
                    Button {
                        model.query = ""
                        model.reload()
                    } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(AttachmentLibraryPickerModel.KindFilter.allCases) { filter in
                        filterChip(filter)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func filterChip(_ filter: AttachmentLibraryPickerModel.KindFilter) -> some View {
        Button {
            model.kindFilter = filter
            model.reload()
        } label: {
            Text(filter.title)
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(
                    model.kindFilter == filter ? Color.accentColor : Color.secondary.opacity(0.12),
                    in: Capsule()
                )
                .foregroundStyle(model.kindFilter == filter ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private var list: some View {
        Group {
            if model.items.isEmpty {
                if model.isLoadingMore {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    emptyStateView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.items) { record in
                            row(record)
                            Divider().padding(.leading, 44)
                        }
                        paginationFooter
                    }
                }
            }
        }
    }

    /// 空结果提示：搜索无结果、按类型筛选无结果、附件库本身为空，三种情况文案不同。
    private var emptyStateView: some View {
        let state: (title: String, systemImage: String, description: String)
        if !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state = ("没有找到匹配的附件", "magnifyingglass", "试试其他关键词，或切换到其他筛选条件。")
        } else if model.hasLoadedOnce {
            state = model.kindFilter.emptyState
        } else {
            state = ("正在加载附件库…", "tray", "")
        }
        return ContentUnavailableView(
            state.title,
            systemImage: state.systemImage,
            description: Text(state.description)
        )
    }

    /// 列表底部分页状态：加载更多中 / 已显示部分 / 已全部加载。
    private var paginationFooter: some View {
        HStack(spacing: 8) {
            if model.isLoadingMore {
                ProgressView().controlSize(.small)
                Text("正在加载更多…").font(.caption).foregroundStyle(.secondary)
            } else if model.hasMore {
                Text("已显示 \(model.items.count) / \(model.total) 项，继续滚动加载更多")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("已显示全部 \(model.total) 项")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func row(_ record: FileArtifactRecord) -> some View {
        let isSelected = model.selectedIDs.contains(record.fileID)
        return HStack(spacing: 0) {
            Button {
                model.toggle(record)
                if !model.allowsMultipleSelection {
                    onPick([model.localURL(for: record)])
                }
            } label: {
                HStack(spacing: 10) {
                    if model.allowsMultipleSelection {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    }
                    Image(systemName: Self.systemImage(for: record.kind))
                        .foregroundStyle(.tint)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.originalName).lineLimit(1).truncationMode(.middle)
                        if let summary = record.summary, !summary.isEmpty {
                            Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        HStack(spacing: 8) {
                            Text(Self.byteCountText(record.byteCount))
                            Text(Self.dateText(record.lastSeenAt))
                            Text(record.source.title)
                        }
                        .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .background(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
            }
            .buttonStyle(.plain)

            Button {
                previewTarget = AttachmentLibraryPreviewTarget(
                    url: model.localURL(for: record),
                    title: record.originalName
                )
            } label: {
                Image(systemName: "eye")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("预览附件")
            .accessibilityLabel("预览附件 \(record.originalName)")
            .padding(.trailing, 12)
        }
        .onAppear { model.loadMoreIfNeeded(current: record) }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if model.allowsMultipleSelection {
                Text("已选 \(model.selectedIDs.count) 项").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("从文件夹选择…") {
                onPickFromFolder()
            }
            Button("确定") {
                if !selectedURLs.isEmpty { onPick(selectedURLs) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectedURLs.isEmpty)
        }
        .padding(14)
    }

    private static func systemImage(for kind: AgentAttachmentKind) -> String {
        switch kind {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .pdf: return "doc.richtext"
        case .document: return "doc.text"
        case .spreadsheet: return "tablecells"
        case .presentation: return "chart.bar"
        case .archive: return "archivebox"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .markdown: return "text.document"
        case .json: return "curlybraces"
        case .csv: return "tablecells"
        case .html: return "globe"
        case .text: return "doc.plaintext"
        default: return "doc"
        }
    }

    private static func byteCountText(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// 内嵌式附件选择面板：作为聊天输入区的展开子页面展示，支持一键收起返回。
struct AttachmentLibraryPickerPanel: View {
    @ObservedObject var model: AttachmentLibraryPickerModel
    var onPick: ([URL]) -> Void
    var onPickFromFolder: () -> Void
    var onCollapse: () -> Void
    @Environment(\.windowWidthClass) private var windowWidthClass

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onCollapse) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("返回")
                            .font(AppTypography.callout)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help("收起附件选择，返回对话")
                .accessibilityLabel("收起附件选择，返回对话")

                Spacer(minLength: 0)

                Label("附件库", systemImage: "tray.full")
                    .font(AppTypography.calloutEmphasis)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button(action: onCollapse) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("收起附件选择")
                .accessibilityLabel("收起附件选择")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            AttachmentLibraryPickerView(
                model: model,
                onPick: onPick,
                onPickFromFolder: onPickFromFolder,
                showsHeader: false,
                preferredHeight: windowWidthClass.usesStackedPanes ? 240 : 340,
                onCollapse: onCollapse
            )
        }
        .frame(maxHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
    }
}

private extension FileArtifactSource {
    var title: String {
        switch self {
        case .session: return "会话"
        case .imported: return "导入"
        case .generated: return "生成"
        case .forwarded: return "转发"
        case .other: return "其他"
        }
    }
}

/// 发送附件时自动登记进附件库（“最近附件”语义，类似微信）：
/// 用户发给 LLM / 真人 / 群聊的文件会出现在附件库里，之后可再次选用。
enum AttachmentLibraryRegistration {
    static func register(urls: [URL], paths: AppStoragePaths? = nil) {
        guard let paths = paths ?? (try? AppStoragePaths.live()) else { return }
        let store = FileArtifactStore(paths: paths)
        for url in urls {
            _ = try? store.register(from: url, source: .session)
        }
    }

    /// 单聊/群聊只把文件与视频纳入附件库；图片与语音不进（避免图片/录音刷屏附件库）。
    static func shouldRegister(imMessageType: ImMessageType) -> Bool {
        imMessageType != .image && imMessageType != .audio
    }
}

/// 附件库预览目标：从列表行点击“预览”时暂存，供 sheet 展示。
private struct AttachmentLibraryPreviewTarget: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

/// 附件库内嵌的附件预览窗口：使用系统 Quick Look 渲染任意可预览文件。
private struct AttachmentLibraryQuickPreviewSheet: View {
    let url: URL
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "eye")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("关闭预览")
            }
            .padding(12)
            Divider()
            NativeFileQuickLookPreview(fileURL: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 520, minHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
