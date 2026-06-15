import SwiftUI
import ConnorGraphAppSupport

enum BrowserFloatingTypography {
    // Browser chrome follows a compact macOS semantic scale: clear hierarchy,
    // consistent controls, and legible 12–14 pt text instead of one-off sizes.
    static let popoverTitle: Font = .system(size: 14, weight: .semibold)
    static let pageTitle: Font = .system(size: 13, weight: .semibold)
    static let pageURL: Font = .system(size: 12, weight: .regular)
    static let selectedText: Font = .system(size: 13, weight: .regular)
    static let input: Font = .system(size: 13, weight: .regular)
    static let hint: Font = .system(size: 12, weight: .regular)
    static let messageRole: Font = .system(size: 12, weight: .semibold)
    static let messageBody: Font = .system(size: 13, weight: .regular)
    static let askButton: Font = .system(size: 13, weight: .semibold)
    static let askButtonIcon: Font = .system(size: 13, weight: .semibold)
    static let quickAction: Font = .system(size: 12, weight: .medium)
    static let quickActionIcon: Font = .system(size: 12, weight: .semibold)
    static let loadingOverlay: Font = .system(size: 12, weight: .medium)
    static let toolbarIcon: Font = .system(size: 13, weight: .medium)
    static let tabTitle: Font = .system(size: 12, weight: .regular)
    static let tabTitleSelected: Font = .system(size: 12, weight: .semibold)
    static let tabIcon: Font = .system(size: 12, weight: .regular)
    static let tabCloseIcon: Font = .system(size: 10, weight: .semibold)
}

struct BrowserSelectionPopover: View {
    var popover: BrowserSelectionPopoverState
    var thread: BrowserSelectionThread?
    @Binding var question: String
    var isSubmitting: Bool
    var onAsk: () -> Void
    var onSummarizePage: () -> Void
    var onCancel: () -> Void
    var onClose: () -> Void

    static let quickPageSummaryPrompt = "总结此网页，提取概括网页主要内容、论点论据、观点或故事，信息"

    var body: some View {
        let isPageQuestion = popover.context.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(isPageQuestion ? "问一问 AI" : "网页选择", systemImage: isPageQuestion ? "sparkles" : "selection.pin.in.out")
                    .font(BrowserFloatingTypography.popoverTitle)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(BrowserFloatingTypography.toolbarIcon)
                }
                .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 4) {
                if !popover.context.page.title.isEmpty {
                    Text(popover.context.page.title)
                        .font(BrowserFloatingTypography.pageTitle)
                        .lineLimit(1)
                }
                if !popover.context.page.url.isEmpty {
                    Text(popover.context.page.url)
                        .font(BrowserFloatingTypography.pageURL)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if !isPageQuestion {
                Text(popover.context.selectedText)
                    .font(BrowserFloatingTypography.selectedText)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            BrowserSelectionThreadList(messages: thread?.messages ?? [], isPageQuestion: isPageQuestion)
                .frame(maxHeight: 360)

            if isPageQuestion {
                HStack(spacing: 8) {
                    Button(action: onSummarizePage) {
                        BrowserQuickActionBadge(title: "总结网页主要内容", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                    .help(Self.quickPageSummaryPrompt)

                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 8) {
                TextField(isPageQuestion ? "基于当前网页提问…" : "基于选中文本提问…", text: $question, axis: .vertical)
                    .font(BrowserFloatingTypography.input)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .onSubmit(onAsk)

                AgentSendControlButton(
                    isSubmitting: isSubmitting,
                    isDisabled: !isSubmitting && question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    action: {
                        if isSubmitting {
                            onCancel()
                        } else {
                            onAsk()
                        }
                    }
                )
            }

            Text("发送后浮窗保持打开")
                .font(BrowserFloatingTypography.hint)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
    }
}

struct BrowserSelectionThreadList: View {
    var messages: [BrowserSelectionThreadMessage]
    var isPageQuestion: Bool = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if messages.isEmpty {
                    Text(isPageQuestion ? "这个网页还没有提问记录。" : "这个网页选择还没有提问记录。")
                        .font(BrowserFloatingTypography.messageBody)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    ForEach(messages) { message in
                        HStack(alignment: .top, spacing: 6) {
                            Text(message.role == .user ? "你" : "AI")
                                .font(BrowserFloatingTypography.messageRole)
                                .foregroundStyle(message.role == .user ? ConnorCraftPalette.accent : Color.secondary)
                                .frame(width: 28, alignment: .leading)
                            if message.isPending {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                        .scaleEffect(0.62)
                                    Text("正在生成回复…")
                                        .font(BrowserFloatingTypography.messageBody)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else if message.role == .assistant {
                                AgentMarkdownPreviewText(markdown: message.text, font: BrowserFloatingTypography.messageBody)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Text(message.text)
                                    .font(BrowserFloatingTypography.messageBody)
                                    .foregroundStyle(.primary)
                                    .lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct BrowserQuickActionBadge: View {
    var title: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(BrowserFloatingTypography.quickActionIcon)
            Text(title)
                .font(BrowserFloatingTypography.quickAction)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .frame(height: 26)
        .foregroundStyle(Color.secondary)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct BrowserTabChip: View {
    var title: String
    var url: String
    var width: CGFloat
    var isSelected: Bool
    var isLoading: Bool
    var onSelect: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isLoading ? "arrow.triangle.2.circlepath" : "globe")
                .font(BrowserFloatingTypography.tabIcon)
                .foregroundStyle(.secondary.opacity(isSelected ? 0.85 : 0.65))

            Text(title)
                .font(isSelected ? BrowserFloatingTypography.tabTitleSelected : BrowserFloatingTypography.tabTitle)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(BrowserFloatingTypography.tabCloseIcon)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary.opacity(0.72))
            .help("关闭标签页")
        }
        .padding(.leading, 8)
        .padding(.trailing, 5)
        .padding(.vertical, 4)
        .frame(width: width, height: 25)
        .background(tabBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(tabBorder, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onTapGesture(perform: onSelect)
        .help(url)
    }

    private var tabBackground: Color { isSelected ? Color(nsColor: .controlBackgroundColor) : Color.secondary.opacity(0.045) }
    private var tabBorder: Color { isSelected ? Color.secondary.opacity(0.18) : Color.secondary.opacity(0.07) }
}

struct BrowserAskAIButtonLabel: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(BrowserFloatingTypography.askButtonIcon)
            Text("问一问 AI")
                .font(BrowserFloatingTypography.askButton)
        }
        .foregroundStyle(ConnorCraftPalette.accent)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            LinearGradient(
                colors: [ConnorCraftPalette.accent.opacity(0.18), ConnorCraftPalette.accentSubtleFill],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Capsule()
        )
        .overlay(Capsule().stroke(ConnorCraftPalette.accentBorder, lineWidth: 1))
        .shadow(color: ConnorCraftPalette.accent.opacity(0.16), radius: 8, x: 0, y: 3)
        .contentShape(Capsule())
    }
}

struct BrowserLoadingOverlay: View {
    var message: String
    var systemImage: String = "arrow.triangle.2.circlepath"

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(BrowserFloatingTypography.loadingOverlay)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.secondary.opacity(0.18), lineWidth: 1))
    }
}

struct WebNavigationState: Equatable {
    var canGoBack: Bool
    var canGoForward: Bool
    var title: String
    var url: String
    var isLoading: Bool = false
    var errorMessage: String? = nil
}

// MARK: - Browser History Panel

struct BrowserHistoryPanel: View {
    let entries: [BrowserHistoryEntry]
    @Binding var searchText: String
    var onSelect: (BrowserHistoryEntry) -> Void
    var onNavigateToSession: (BrowserHistoryEntry) -> Void
    var onClose: () -> Void

    private var filteredEntries: [BrowserHistoryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = query.isEmpty ? entries : entries.filter {
            $0.title.lowercased().contains(query) ||
            $0.url.lowercased().contains(query) ||
            $0.sessionTitle.lowercased().contains(query)
        }
        return filtered.sorted { $0.visitedAt > $1.visitedAt }
    }

    private var groupedByDay: [(String, [BrowserHistoryEntry])] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)

        let today = Calendar.current.startOfDay(for: Date())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        var groups: [(String, [BrowserHistoryEntry])] = []
        var grouped: [String: [BrowserHistoryEntry]] = [:]
        var order: [String] = []

        for entry in filteredEntries {
            let day = Calendar.current.startOfDay(for: entry.visitedAt)
            let key: String
            if day == today {
                key = "今天"
            } else if day == yesterday {
                key = "昨天"
            } else {
                formatter.dateFormat = "M月d日"
                key = formatter.string(from: entry.visitedAt)
            }
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(entry)
        }

        for key in order {
            if let items = grouped[key] {
                groups.append((key, items))
            }
        }
        return groups
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("浏览历史")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("搜索历史", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            Divider()

            // List
            if filteredEntries.isEmpty {
                Spacer()
                Text(searchText.isEmpty ? "暂无浏览记录" : "无匹配结果")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(groupedByDay, id: \.0) { dayLabel, items in
                            Section {
                                ForEach(items) { entry in
                                    BrowserHistoryRow(entry: entry)
                                        .contentShape(Rectangle())
                                        .onTapGesture { onSelect(entry) }
                                        .contextMenu {
                                            Button("跳转到会话: \(entry.sessionTitle)") {
                                                onNavigateToSession(entry)
                                            }
                                            Divider()
                                            Button("在新标签页打开") { onSelect(entry) }
                                        }
                                }
                            } header: {
                                HStack {
                                    Text(dayLabel)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(width: 280)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            Rectangle()
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 1),
            alignment: .trailing
        )
    }
}

private struct BrowserHistoryRow: View {
    let entry: BrowserHistoryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.isEmpty ? entry.url : entry.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                Text(displayURL(entry.url))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(timeString)
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(entry.sessionTitle)
                        .font(.system(size: 10))
                        .foregroundStyle(ConnorCraftPalette.accent.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: entry.visitedAt)
    }

    private func displayURL(_ url: String) -> String {
        guard let parsed = URL(string: url), let host = parsed.host else { return url }
        let path = parsed.path
        if path.isEmpty || path == "/" { return host }
        return host + (path.count > 30 ? String(path.prefix(30)) + "…" : path)
    }
}

