import SwiftUI
import ConnorGraphCore

enum ForwardDestinationKind: String, Hashable {
    case agent
    case peer
    case group
}

struct ForwardDestination: Identifiable, Hashable {
    var id: String { key }
    var key: String
    var targetID: String
    var title: String
    var subtitle: String
    var kind: ForwardDestinationKind
    var updatedAt: TimeInterval? = nil
}

/// 列表项（邮件 / RSS / 日历）右键菜单「转发到…」所需的运行上下文：
/// 目标列表来自康纳会话与 IM 联系人，发送复用 IM 的转发链路。
struct ListItemForwardingContext {
    var makePager: @MainActor () -> ForwardDestinationPager
    var send: @MainActor (ForwardedChatBundle, Set<String>) async throws -> Void
}

func sortForwardDestinationsByRecency(_ destinations: [ForwardDestination]) -> [ForwardDestination] {
    destinations.sorted {
        if $0.updatedAt == $1.updatedAt { return $0.key < $1.key }
        return ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0)
    }
}


/// 转发目标「康纳会话」分页加载器：给定游标返回一页目的地与下一个游标。
typealias ForwardDestinationSessionPageLoader = @MainActor (String?, Int) async throws -> (items: [ForwardDestination], nextCursor: String?)

/// 转发目标分页加载器：把「康纳会话 + IM 会话」两路数据源按最近活跃归并、逐页取回。
/// 两路都取尽后 loadNextPage 返回空数组，表示已经取到全部目标。
@MainActor
final class ForwardDestinationPager {
    typealias PageLoader = @MainActor (String?, Int) async throws -> (items: [ForwardDestination], nextCursor: String?)

    private let sessionsLoader: PageLoader
    private let conversationsLoader: PageLoader
    private let pageSize: Int

    private var sessionCursor: String?
    private var conversationCursor: String?
    private var sessionBuffer: [ForwardDestination] = []
    private var conversationBuffer: [ForwardDestination] = []
    private var sessionsExhausted = false
    private var conversationsExhausted = false

    init(
        sessionsLoader: @escaping PageLoader,
        conversationsLoader: @escaping PageLoader,
        pageSize: Int = 50
    ) {
        self.sessionsLoader = sessionsLoader
        self.conversationsLoader = conversationsLoader
        self.pageSize = min(max(pageSize, 1), 100)
    }

    /// 是否还有未取回的目标。
    var hasMore: Bool {
        !sessionsExhausted || !conversationsExhausted || !sessionBuffer.isEmpty || !conversationBuffer.isEmpty
    }

    /// 取回下一页；两路数据源均取尽后返回空数组。
    func loadNextPage() async throws -> [ForwardDestination] {
        var page: [ForwardDestination] = []
        page.reserveCapacity(pageSize)
        while page.count < pageSize, let next = try await nextDestination() {
            page.append(next)
        }
        return page
    }

    /// 一次性取回全部目标（搜索等需要全量匹配的场景使用）。使用独立实例，
    /// 不影响当前分页浏览的游标状态。
    func loadAll() async throws -> [ForwardDestination] {
        let fresh = ForwardDestinationPager(
            sessionsLoader: sessionsLoader,
            conversationsLoader: conversationsLoader,
            pageSize: pageSize
        )
        var all: [ForwardDestination] = []
        while let next = try await fresh.nextDestination() {
            all.append(next)
        }
        return all
    }

    private func nextDestination() async throws -> ForwardDestination? {
        try await fillSessionBufferIfNeeded()
        try await fillConversationBufferIfNeeded()
        switch (sessionBuffer.first, conversationBuffer.first) {
        case let (session?, conversation?):
            return isMoreRecent(session, than: conversation)
                ? sessionBuffer.removeFirst()
                : conversationBuffer.removeFirst()
        case (_?, nil):
            return sessionBuffer.removeFirst()
        case (nil, _?):
            return conversationBuffer.removeFirst()
        case (nil, nil):
            return nil
        }
    }

    private func fillSessionBufferIfNeeded() async throws {
        guard sessionBuffer.isEmpty, !sessionsExhausted else { return }
        let (items, nextCursor) = try await sessionsLoader(sessionCursor, pageSize)
        sessionBuffer = items
        sessionCursor = nextCursor
        if nextCursor == nil { sessionsExhausted = true }
    }

    private func fillConversationBufferIfNeeded() async throws {
        guard conversationBuffer.isEmpty, !conversationsExhausted else { return }
        let (items, nextCursor) = try await conversationsLoader(conversationCursor, pageSize)
        conversationBuffer = items
        conversationCursor = nextCursor
        if nextCursor == nil { conversationsExhausted = true }
    }

    private func isMoreRecent(_ a: ForwardDestination, than b: ForwardDestination) -> Bool {
        if a.updatedAt == b.updatedAt { return a.key < b.key }
        return (a.updatedAt ?? 0) > (b.updatedAt ?? 0)
    }
}

struct ForwardDestinationSheet: View {
    var bundle: ForwardedChatBundle
    var pager: ForwardDestinationPager
    var isSending: Bool
    var onCancel: () -> Void
    var onSend: (String, Set<String>) async -> Void
    @Environment(\.windowWidthClass) private var windowWidthClass

    @State private var searchText = ""
    @State private var caption = ""
    @State private var selectedKeys: Set<String> = []
    @State private var kindFilter: ForwardDestinationKind? = nil

    @State private var loadedDestinations: [ForwardDestination] = []
    @State private var isLoadingPage = false
    @State private var hasMore = true
    @State private var loadFailed = false
    /// 非空表示处于搜索模式：一次取回全部目标，保证匹配结果完整。
    @State private var searchMatches: [ForwardDestination]? = nil

    private static let newSessionDestination = ForwardDestination(
        key: "agent:new",
        targetID: "",
        title: "新建与康纳的会话",
        subtitle: "创建后保存聊天记录",
        kind: .agent
    )

    private var visibleDestinations: [ForwardDestination] {
        var result = [Self.newSessionDestination] + (searchMatches ?? loadedDestinations)
        if let kindFilter {
            result = result.filter { $0.kind == kindFilter }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return result }
        return result.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.subtitle.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        Group {
            if windowWidthClass.usesStackedPanes {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        destinationColumn
                        Divider()
                        sendColumn
                    }
                }
            } else {
                HStack(spacing: 0) {
                    destinationColumn
                    Divider()
                    sendColumn
                }
            }
        }
        .frame(maxWidth: 860)
        .frame(height: 580)
        .task {
            await loadMore()
        }
        .onChange(of: searchText) { _, newValue in
            let query = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                searchMatches = nil
                return
            }
            Task { await runSearch(query) }
        }
    }

    private var destinationColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择聊天")
                .font(.headline)
            TextField("搜索", text: $searchText)
                .textFieldStyle(.roundedBorder)
            Picker("筛选", selection: $kindFilter) {
                Text("全部").tag(Optional<ForwardDestinationKind>.none)
                Text("会话").tag(Optional<ForwardDestinationKind>.some(.agent))
                Text("联系人").tag(Optional<ForwardDestinationKind>.some(.peer))
                Text("群聊").tag(Optional<ForwardDestinationKind>.some(.group))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            destinationList
        }
        .padding(20)
        .frame(width: windowWidthClass.usesStackedPanes ? nil : 320)
    }

    private var sendColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("发送给")
                .font(.title3.weight(.semibold))
            Spacer(minLength: 8)
            ForwardedChatCard(bundle: bundle)
                .frame(maxWidth: 460)
            TextField("给对方留言（可选）", text: $caption, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button(isSending ? "发送中…" : selectedKeys.count > 1 ? "发送给 \(selectedKeys.count) 个会话" : "发送") {
                    Task { await onSend(caption, selectedKeys) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedKeys.isEmpty || isSending)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var destinationList: some View {
        if loadedDestinations.isEmpty && searchMatches == nil && isLoadingPage {
            Spacer()
            ProgressView("加载会话…")
                .frame(maxWidth: .infinity)
            Spacer()
        } else if visibleDestinations.isEmpty && !isLoadingPage {
            Spacer()
            Text("暂无可转发的会话")
                .foregroundStyle(.secondary)
            Spacer()
        } else {
            List(visibleDestinations, selection: $selectedKeys) { destination in
                HStack(spacing: 10) {
                    Image(systemName: icon(for: destination.kind))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(destination.kind == .agent ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(destination.title).lineLimit(1)
                        Text(destination.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: selectedKeys.contains(destination.key) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedKeys.contains(destination.key) ? Color.accentColor : Color.secondary.opacity(0.55))
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selectedKeys.contains(destination.key) { selectedKeys.remove(destination.key) }
                    else { selectedKeys.insert(destination.key) }
                }
                .tag(destination.key)
            }
            .listStyle(.inset)
            if searchMatches == nil {
                loadMoreFooter
            }
        }
    }

    @ViewBuilder
    private var loadMoreFooter: some View {
        if isLoadingPage {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        } else if hasMore {
            Button {
                Task { await loadMore() }
            } label: {
                Text(loadFailed ? "加载失败，点此重试" : "加载更多…")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(loadFailed ? .red : Color.accentColor)
            .padding(.vertical, 6)
            .onAppear {
                // 滚动到列表底部时自动加载下一页。
                Task { await loadMore() }
            }
        }
    }

    private func loadMore() async {
        guard !isLoadingPage, hasMore, searchMatches == nil else { return }
        isLoadingPage = true
        loadFailed = false
        defer { isLoadingPage = false }
        do {
            let next = try await pager.loadNextPage()
            loadedDestinations.append(contentsOf: next)
            hasMore = !next.isEmpty && pager.hasMore
        } catch {
            loadFailed = true
            hasMore = true
        }
    }

    private func runSearch(_ query: String) async {
        isLoadingPage = true
        defer { isLoadingPage = false }
        do {
            let all = try await pager.loadAll()
            let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
            searchMatches = all.filter {
                $0.title.localizedCaseInsensitiveContains(normalized) || $0.subtitle.localizedCaseInsensitiveContains(normalized)
            }
        } catch {
            searchMatches = []
        }
    }

    private func icon(for kind: ForwardDestinationKind) -> String {
        switch kind {
        case .agent: "sparkles"
        case .peer: "person"
        case .group: "person.3"
        }
    }
}

struct ForwardedChatCard: View {
    var bundle: ForwardedChatBundle
    var onOpen: (() -> Void)?

    var body: some View {
        Button(action: { onOpen?() }) {
            VStack(alignment: .leading, spacing: 7) {
                Text(bundle.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                ForEach(Array(bundle.previewLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !bundle.caption.isEmpty {
                    Text(bundle.caption).font(.callout).foregroundStyle(.primary).lineLimit(2)
                }
                Divider().padding(.top, 3)
                Label("聊天记录 · \(bundle.items.count) 条", systemImage: "text.bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.secondary.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(onOpen == nil)
    }
}

struct ForwardedChatDetailView: View {
    var bundle: ForwardedChatBundle
    var onClose: () -> Void
    @Environment(\.windowWidthClass) private var windowWidthClass

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(bundle.title).font(.title3.weight(.semibold))
                    Text("来自 \(bundle.sourceTitle) · \(bundle.items.count) 条").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭", systemImage: "xmark", action: onClose).labelStyle(.iconOnly).buttonStyle(.borderless)
            }
            .padding(20)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(bundle.items) { item in
                        ForwardedChatDetailItemView(item: item)
                        Divider().padding(.leading, 58)
                    }
                }
                .padding(20)
            }
        }
        .frame(
            minWidth: windowWidthClass.usesStackedPanes ? 380 : 620,
            idealWidth: 760,
            minHeight: 520,
            idealHeight: 680
        )
    }
}

private struct ForwardedChatDetailItemView: View {
    var item: ForwardedChatItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.accentColor.opacity(0.14))
                .frame(width: 42, height: 42)
                .overlay(Text(String(item.senderName.prefix(1))).font(.headline))
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(item.senderName).font(.callout.weight(.medium))
                    Spacer()
                    Text(Self.dateFormatter.string(from: Date(timeIntervalSince1970: Double(item.createdAt) / 1000)))
                        .font(.caption).foregroundStyle(.tertiary)
                }
                content
            }
        }
        .padding(.vertical, 14)
    }

    @ViewBuilder private var content: some View {
        switch item.kind.lowercased() {
        case "image":
            if let value = item.mediaUrl, let url = URL(string: value) {
                AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }
                    .frame(maxWidth: 420, maxHeight: 340).clipShape(RoundedRectangle(cornerRadius: 6))
            } else { Label("图片", systemImage: "photo") }
        case "video": Label("视频", systemImage: "play.rectangle")
        case "audio": Label("语音", systemImage: "waveform")
        default: Text(item.text).textSelection(.enabled)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let value = DateFormatter()
        value.dateStyle = .medium
        value.timeStyle = .short
        return value
    }()
}
