import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

struct CraftListPaneView: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var selection: SidebarItem?

    var body: some View {
        VStack(spacing: 0) {
            switch selection ?? .agentChat {
            case .agentChat:
                CraftSessionListPane(viewModel: viewModel)
            case .llmSettings:
                CraftSettingsListPane(viewModel: viewModel, selection: $selection)
            case .mail:
                CraftMailListPane(viewModel: viewModel)
            case .calendar:
                CraftCalendarListPane(viewModel: viewModel)
            case .contacts:
                CraftContactsListPane(viewModel: viewModel)
            case .rss:
                CraftRSSListPane(viewModel: viewModel)
            case .sources:
                CraftSourceListPane(viewModel: viewModel)
            case .skills:
                CraftSkillListPane(viewModel: viewModel)
            case .automation:
                CraftSimpleListPane(title: "自动化", subtitle: "事件触发与执行历史", rows: viewModel.automationConfig.rules.map(\.name))
            case .productOS:
                CraftSimpleListPane(title: "Product OS", subtitle: "本地控制面模块", rows: viewModel.productOSRegistry.sources.map(\.displayName) + viewModel.productOSRegistry.skills.map(\.displayName))
            default:
                CraftSimpleListPane(title: (selection ?? .agentChat).rawValue, subtitle: "康纳同学工作区", rows: [])
            }
        }
    }
}

struct CraftSessionListPane: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            Text(sessionListTitle)
                .font(AppListTypography.header)
                .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)

            if filteredSessions.isEmpty {
                if viewModel.sessionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView("暂无会话", systemImage: "bubble.left", description: Text("点击左上角新建会话开始。"))
                        .padding(.top, 80)
                } else {
                    ContentUnavailableView("没有匹配的会话", systemImage: "magnifyingglass", description: Text("搜索会匹配会话标题和消息内容。"))
                        .padding(.top, 80)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredSessions) { session in
                            CraftSessionRow(
                                row: AgentChatSessionPresentation(session: session),
                                readState: viewModel.sessionReadStates[session.id],
                                isSelected: session.id == viewModel.selectedChatSessionID,
                                isRunning: viewModel.isChatSessionSubmitting(session.id),
                                isRegeneratingTitle: viewModel.regeneratingTitleSessionIDs.contains(session.id),
                                hasRunningBackgroundTask: !viewModel.canDeleteChatSession(session.id),
                                labelDefinitions: viewModel.governanceConfig.labels,
                                onSelect: {
                                    var transaction = Transaction()
                                    transaction.disablesAnimations = true
                                    withTransaction(transaction) {
                                        viewModel.selectChatSession(session.id)
                                    }
                                },
                                onRename: { title in viewModel.renameChatSession(session.id, title: title) },
                                onSetStatus: { status in viewModel.setChatSessionStatus(session.id, status: status) },
                                onToggleLabel: { labelID in viewModel.toggleChatSessionLabel(session.id, labelID: labelID) },
                                onRegenerateTitle: { viewModel.regenerateChatSessionTitle(session.id) },
                                onDelete: { viewModel.deleteChatSession(session.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { viewModel.reloadChatSessions() }
    }

    private var filteredSessions: [AgentSession] {
        AgentSessionTextSearchFilter().filter(viewModel.chatSessions, query: viewModel.sessionSearchQuery)
    }

    private var sessionListTitle: String {
        switch viewModel.sessionListFilter {
        case .all: "全部会话"
        case .status(let status): status.displayName
        case .label(let labelID): viewModel.governanceConfig.labels.first(where: { $0.id == labelID })?.name ?? labelID
        }
    }
}

struct CraftMailListPane: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var searchQuery: String = ""

    private var presentation: NativeMailBrowserPresentation {
        viewModel.mailBrowserPresentation
    }

    private var visibleMessages: [MailMessageSummary] {
        presentation.messages(accountID: nil, mailboxID: nil, query: searchQuery)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("邮件系统")
                    .font(AppListTypography.header)
                    .frame(maxWidth: .infinity, alignment: .center)
                Button(action: { viewModel.isPresentingAddMailAccountSheet = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("添加邮件帐户")
                .accessibilityLabel("添加邮件帐户")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)

            if !presentation.messages.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("筛选标题、正文或发件人", text: $searchQuery)
                        .textFieldStyle(.plain)
                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.62), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppShellColors.hairline, lineWidth: 1)
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }

            if presentation.accounts.isEmpty {
                ContentUnavailableView("暂无邮件账户", systemImage: "envelope.badge", description: Text("点击右上角 + 添加邮件账户。"))
                    .padding(.top, 80)
            } else if presentation.messages.isEmpty {
                ContentUnavailableView("尚未同步邮件", systemImage: "tray", description: Text("账户已添加，但当前 Mail Runtime 尚未完成远端邮箱发现和邮件拉取。同步完成后邮件会按时间显示在这里。"))
                    .padding(.top, 80)
            } else if visibleMessages.isEmpty {
                ContentUnavailableView("没有匹配的邮件", systemImage: "magnifyingglass", description: Text("筛选会匹配标题、正文摘要和发件人。"))
                    .padding(.top, 80)
            } else {
                List(visibleMessages) { message in
                    MailMessageListRow(
                        message: message,
                        account: presentation.account(id: message.accountID),
                        mailbox: presentation.mailbox(id: message.mailboxID),
                        isSelected: message.id == viewModel.selectedMailMessageID,
                        onSelect: { selectMessage(message) }
                    )
                    .mailListRowStyle()
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.top, 6, for: .scrollContent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func selectMessage(_ message: MailMessageSummary) {
        viewModel.selectedMailAccountID = message.accountID
        viewModel.selectedMailMailboxID = message.mailboxID
        viewModel.selectedMailMessageID = message.id
    }
}

private extension View {
    func mailListRowStyle() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}


private enum RSSSourcePreset: String, CaseIterable, Identifiable {
    case appleDeveloper
    case swiftBlog
    case hackerNews
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleDeveloper: "Apple Developer"
        case .swiftBlog: "Swift.org Blog"
        case .hackerNews: "Hacker News"
        case .custom: "自定义"
        }
    }

    var subtitle: String {
        switch self {
        case .appleDeveloper: "官方平台动态"
        case .swiftBlog: "Swift 语言与工具链更新"
        case .hackerNews: "技术社区热点"
        case .custom: "添加任意 RSS / Atom / JSON Feed"
        }
    }

    var feedURLString: String {
        switch self {
        case .appleDeveloper: "https://developer.apple.com/news/rss/news.rss"
        case .swiftBlog: "https://www.swift.org/blog/feed.xml"
        case .hackerNews: "https://hnrss.org/frontpage"
        case .custom: ""
        }
    }

    var guidance: String {
        switch self {
        case .appleDeveloper:
            "适合跟踪 Apple 平台、SDK、审核与生态变化。Connor 仅保存订阅源、抓取游标和本地阅读状态。"
        case .swiftBlog:
            "适合跟踪 Swift 语言、并发、Package Manager 和工具链公告。正文读取仍需显式工具调用。"
        case .hackerNews:
            "适合发现技术趋势。进入 Graph Memory 前必须先生成 evidence candidate 并人工审查。"
        case .custom:
            "输入自定义 feed URL。同步、状态变更、OPML 导入导出都经过 Connor Policy Engine 和 audit trail。"
        }
    }
}

struct AddRSSSourceSheet: View {
    private enum Layout {
        static let sheetWidth: CGFloat = 680
        static let sheetHeight: CGFloat = 520
        static let labelWidth: CGFloat = 118
        static let presetControlWidth: CGFloat = 260
        static let compactControlWidth: CGFloat = 180
    }

    private let source: RSSSource?
    var onSave: (URL, String?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPreset: RSSSourcePreset
    @State private var feedURLString: String
    @State private var displayName: String
    @State private var intervalMinutes: Int = 30
    @State private var isSaving = false
    @State private var saveMessage: String?

    init(source: RSSSource? = nil, onSave: @escaping (URL, String?) async throws -> Void) {
        self.source = source
        self.onSave = onSave
        self._selectedPreset = State(initialValue: source == nil ? .appleDeveloper : .custom)
        self._feedURLString = State(initialValue: source?.feedURL.absoluteString ?? RSSSourcePreset.appleDeveloper.feedURLString)
        self._displayName = State(initialValue: source?.displayName ?? "")
    }

    private var trimmedFeedURLString: String {
        feedURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var feedURL: URL? {
        guard let components = URLComponents(string: trimmedFeedURLString),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host?.isEmpty == false else { return nil }
        return components.url
    }

    private var saveDisabled: Bool { feedURL == nil || isSaving }
    private var isEditing: Bool { source != nil }

    private var normalizedDisplayName: String? {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dialogHeader

            Divider()
                .padding(.top, AppShellLayout.spaceL)

            ScrollView {
                VStack(alignment: .leading, spacing: AppShellLayout.spaceL) {
                    RSSSetupSection(title: "订阅源", systemImage: "dot.radiowaves.left.and.right") {
                        RSSSetupRow("预设", labelWidth: Layout.labelWidth) {
                            Picker("预设", selection: $selectedPreset) {
                                ForEach(RSSSourcePreset.allCases) { preset in
                                    Text(preset.title).tag(preset)
                                }
                            }
                            .labelsHidden()
                            .frame(width: Layout.presetControlWidth, alignment: .leading)
                            .onChange(of: selectedPreset) { _, newValue in
                                if !newValue.feedURLString.isEmpty { feedURLString = newValue.feedURLString }
                            }
                        }

                        RSSSetupRow("Feed URL", labelWidth: Layout.labelWidth) {
                            VStack(alignment: .leading, spacing: AppShellLayout.spaceXS) {
                                TextField("https://example.com/feed.xml", text: $feedURLString)
                                    .textFieldStyle(.roundedBorder)
                                if !trimmedFeedURLString.isEmpty && feedURL == nil {
                                    Text("请输入以 http:// 或 https:// 开头的有效 feed 地址。")
                                        .font(SettingsListTypography.rowCaption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }

                        RSSSetupRow("显示名称", labelWidth: Layout.labelWidth) {
                            TextField("可选；留空时使用 feed 标题", text: $displayName)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    RSSSetupSection(title: "抓取策略", systemImage: "clock.arrow.circlepath") {
                        RSSSetupRow("抓取间隔", labelWidth: Layout.labelWidth) {
                            Picker("抓取间隔", selection: $intervalMinutes) {
                                Text("15 分钟").tag(15)
                                Text("30 分钟").tag(30)
                                Text("1 小时").tag(60)
                                Text("6 小时").tag(360)
                            }
                            .labelsHidden()
                            .frame(width: Layout.compactControlWidth, alignment: .leading)
                        }
                        RSSSetupHint(isEditing ? "保存后会保留源 ID 和治理记录；如果修改 Feed URL，会清理旧文章缓存并等待下次同步。" : "首次添加后会立刻抓取一次。阅读时默认使用 Connor 阅读器；原网页/外部浏览器属于后续文章操作，不在添加订阅源时选择。")
                    }

                    RSSHintCard(title: selectedPreset.subtitle, guidance: selectedPreset.guidance)

                    if let saveMessage {
                        RSSSetupHint(saveMessage, color: .red)
                    }
                }
                .padding(.vertical, AppShellLayout.spaceL)
            }
            .scrollIndicators(.visible)

            Divider()

            dialogFooter
        }
        .padding(AppShellLayout.spaceXL)
        .frame(width: Layout.sheetWidth, height: Layout.sheetHeight)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var dialogHeader: some View {
        HStack(alignment: .top, spacing: AppShellLayout.spaceM) {
            ZStack {
                RoundedRectangle(cornerRadius: AppShellLayout.radiusM, style: .continuous)
                    .fill(Color.orange.opacity(0.13))
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(SettingsListTypography.largeIcon)
                    .foregroundStyle(.orange)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: AppShellLayout.spaceXS) {
                Text(isEditing ? "修改 RSS 订阅源" : "添加 RSS 订阅源")
                    .font(.system(size: 26, weight: .semibold))
                Text(isEditing ? "更新显示名称或 Feed URL。源注册、缓存清理和审计继续由 Native RSS Runtime 托管。" : "支持 RSS 2.0、Atom 与 JSON Feed。订阅、同步和状态变更继续由 Native RSS Runtime 与 Policy Engine 托管。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("关闭")
            .accessibilityLabel("关闭添加 RSS 订阅源")
        }
    }

    private var dialogFooter: some View {
        HStack(alignment: .center, spacing: AppShellLayout.spaceM) {
            Spacer()

            Button("取消") { dismiss() }
                .disabled(isSaving)
            Button {
                save()
            } label: {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(isEditing ? "保存修改" : "添加并抓取")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(saveDisabled)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.top, AppShellLayout.spaceM)
    }

    private func save() {
        guard let feedURL else { return }
        isSaving = true
        saveMessage = nil
        Task {
            do {
                try await onSave(feedURL, normalizedDisplayName)
                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    saveMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct RSSSetupSection<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppShellLayout.spaceS) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(spacing: AppShellLayout.spaceS) {
                content
            }
            .padding(AppShellLayout.spaceM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppShellColors.subtleCardBackground, in: RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous)
                    .stroke(AppShellColors.hairline, lineWidth: 1)
            }
        }
    }
}

private struct RSSSetupRow<Content: View>: View {
    var label: String
    var labelWidth: CGFloat
    var alignment: VerticalAlignment
    @ViewBuilder var content: Content

    init(_ label: String, labelWidth: CGFloat, alignment: VerticalAlignment = .firstTextBaseline, @ViewBuilder content: () -> Content) {
        self.label = label
        self.labelWidth = labelWidth
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: AppShellLayout.spaceM) {
            Text("\(label):")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .trailing)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .controlSize(.regular)
    }
}

private struct RSSSetupHint: View {
    var text: String
    var color: Color

    init(_ text: String, color: Color = .secondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(SettingsListTypography.rowCaption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 118 + AppShellLayout.spaceM)
    }
}

private struct RSSHintCard: View {
    var title: String
    var guidance: String

    var body: some View {
        HStack(alignment: .top, spacing: AppShellLayout.spaceM) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: AppShellLayout.spaceXS) {
                Text(title)
                    .font(SettingsListTypography.rowTitleSelected)
                Text(guidance)
                    .font(SettingsListTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppShellLayout.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        }
    }
}

struct CraftRSSListPane: View {
    @ObservedObject var viewModel: AppViewModel

    private var presentation: NativeRSSBrowserPresentation { viewModel.rssBrowserPresentation }
    private var visibleItems: [RSSItemSummary] { presentation.items(sourceID: nil, query: "") }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("RSS 阅读")
                    .font(AppListTypography.header)
                    .frame(maxWidth: .infinity, alignment: .center)
                Button(action: { viewModel.isPresentingAddRSSSourceSheet = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("添加订阅源")
                .accessibilityLabel("添加订阅源")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)


            if presentation.sources.isEmpty {
                ContentUnavailableView("暂无 RSS 订阅源", systemImage: "dot.radiowaves.left.and.right", description: Text("点击右上角 + 添加 RSS / Atom / JSON Feed。"))
                    .padding(.top, 80)
            } else if presentation.items.isEmpty {
                ContentUnavailableView("暂无文章", systemImage: "newspaper", description: Text("订阅源同步后的文章会在这里按时间显示。"))
                    .padding(.top, 80)
            } else {
                List(visibleItems) { item in
                    RSSItemListRow(
                        item: item,
                        source: presentation.source(id: item.sourceID),
                        isSelected: item.id == viewModel.selectedRSSItemID,
                        onSelect: { selectItem(item) }
                    )
                    .mailListRowStyle()
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.top, 6, for: .scrollContent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $viewModel.isPresentingAddRSSSourceSheet) {
            AddRSSSourceSheet { feedURL, displayName in
                try await viewModel.addRSSSourceAndSync(feedURL: feedURL, displayName: displayName)
            }
        }
    }

    private func selectItem(_ item: RSSItemSummary) {
        viewModel.selectedRSSSourceID = item.sourceID
        viewModel.selectedRSSItemID = item.id
        guard !item.state.isRead else { return }
        viewModel.markRSSItemsRead([item.id], isRead: true)
    }
}

private struct RSSItemListRow: View {
    var item: RSSItemSummary
    var source: RSSSource?
    var isSelected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(item.state.isRead ? Color.secondary.opacity(0.24) : Color.orange)
                    .frame(width: 8, height: 8)
                    .padding(.top, 7)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(item.state.isRead ? AppListTypography.rowTitle : AppListTypography.rowTitleSelected)
                            .lineLimit(1)
                        if item.state.isStarred {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.yellow)
                        }
                    }
                    Text(source?.displayName ?? item.sourceID.rawValue)
                        .font(AppListTypography.rowCaptionEmphasized)
                        .lineLimit(1)
                    Text(contextText)
                        .font(AppListTypography.rowCaption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Text(item.snippet)
                        .font(AppListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.orange.opacity(0.14) : Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var contextText: String {
        [item.author, item.publishedAt.formatted(date: .abbreviated, time: .shortened)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

private struct MailAccountListRow: View {
    var account: MailAccount
    var isSelected: Bool
    var showsDisclosure: Bool = false
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon(for: account.provider))
                    .foregroundStyle(isSelected ? .accentColor : color(for: account.health.status))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(account.displayName)
                            .font(isSelected ? AppListTypography.rowTitleSelected : AppListTypography.rowTitle)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Circle()
                            .fill(color(for: account.health.status))
                            .frame(width: 7, height: 7)
                    }
                    Text(account.identities.map { $0.address.email }.joined(separator: ", "))
                        .font(AppListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func icon(for provider: MailProviderKind) -> String {
        switch provider {
        case .gmail: "g.circle.fill"
        case .microsoft365: "m.circle.fill"
        case .jmap: "j.circle.fill"
        case .genericIMAPSMTP: "envelope"
        case .localFixture: "shippingbox"
        }
    }

    private func color(for status: MailAccountHealthStatus) -> Color {
        switch status {
        case .ready: .green
        case .degraded: .orange
        case .blocked, .unauthenticated: .red
        case .unknown: .secondary
        }
    }
}

private struct MailMailboxListRow: View {
    var mailbox: MailMailbox
    var isSelected: Bool
    var showsDisclosure: Bool = false
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: icon(for: mailbox.role))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(mailbox.name)
                        .font(isSelected ? AppListTypography.rowTitleSelected : AppListTypography.rowTitle)
                        .lineLimit(1)
                    Text("\(mailbox.status.messageCount) 封 · \(mailbox.status.unreadCount) 未读")
                        .font(AppListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if mailbox.status.unreadCount > 0 {
                    Text("\(mailbox.status.unreadCount)")
                        .font(AppListTypography.rowCaptionEmphasized)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(Color.accentColor, in: Capsule())
                }
                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func icon(for role: MailMailboxRole) -> String {
        switch role {
        case .inbox: "tray"
        case .sent: "paperplane"
        case .drafts: "doc.text"
        case .archive: "archivebox"
        case .trash: "trash"
        case .spam: "exclamationmark.octagon"
        case .custom: "folder"
        }
    }
}

private struct MailMessageListRow: View {
    var message: MailMessageSummary
    var account: MailAccount?
    var mailbox: MailMailbox?
    var isSelected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(message.flags.isRead ? Color.secondary.opacity(0.24) : Color.accentColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 7)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(message.subject)
                            .font(message.flags.isRead ? AppListTypography.rowTitle : AppListTypography.rowTitleSelected)
                            .lineLimit(1)
                        if message.hasAttachments {
                            Image(systemName: "paperclip")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(message.from.name ?? message.from.email)
                        .font(AppListTypography.rowCaptionEmphasized)
                        .lineLimit(1)
                    Text(contextText)
                        .font(AppListTypography.rowCaption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Text(message.snippet)
                        .font(AppListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var contextText: String {
        [account?.displayName, mailbox?.name]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

private struct MailSmallUnavailableRow: View {
    var text: String

    var body: some View {
        Text(text)
            .font(AppListTypography.rowSubtitle)
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CraftDetailPaneView: View {
    @ObservedObject var viewModel: AppViewModel
    var selection: SidebarItem

    var body: some View {
        Group {
            switch selection {
            case .entities:
                GraphEntitiesView(entities: viewModel.entities, statements: viewModel.statements, episodes: viewModel.episodes)
            case .search:
                SearchView(viewModel: viewModel)
            case .observeLog:
                ObserveLogView(entries: viewModel.observeLogEntries)
            case .agentChat:
                AgentChatView(viewModel: viewModel)
            case .promotionQueue:
                PromotionQueueView(viewModel: viewModel)
            case .graphWriteCandidates:
                GraphWriteCandidateReviewView(viewModel: viewModel)
            case .pendingApprovals:
                AgentPendingApprovalReviewView(viewModel: viewModel)
            case .memoryChangeLog:
                MemoryChangeLogView(viewModel: viewModel)
            case .extractionDiagnostics:
                GraphExtractionDiagnosticsView(viewModel: viewModel)
            case .automation:
                AutomationRuntimePanelView(viewModel: viewModel)
            case .productOS:
                ProductOSRegistryView(viewModel: viewModel)
            case .mail:
                MailSourceSettingsView(viewModel: viewModel)
            case .calendar:
                CalendarSourceSettingsView(viewModel: viewModel)
            case .contacts:
                ContactsSourceSettingsView(viewModel: viewModel)
            case .rss:
                RSSSourceSettingsView(viewModel: viewModel)
            case .sources:
                SourceRuntimePanelView(viewModel: viewModel)
            case .skills:
                SkillRuntimePanelView(viewModel: viewModel)
            case .llmSettings:
                ConnorSettingsDetailView(viewModel: viewModel)
            }
        }
    }
}


struct RSSSourceSettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    private var presentation: NativeRSSBrowserPresentation { viewModel.rssBrowserPresentation }
    private var selectedSource: RSSSource? { presentation.source(id: viewModel.selectedRSSSourceID) }
    private var selectedItem: RSSItemSummary? { presentation.item(id: viewModel.selectedRSSItemID) }

    var body: some View {
        Group {
            if let selectedItem {
                RSSItemDetailPane(
                    source: selectedSource ?? presentation.source(id: selectedItem.sourceID),
                    item: selectedItem,
                    onFollow: { viewModel.followRSSItemInNewSession(selectedItem) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppShellColors.detailBackground)
        .sheet(isPresented: $viewModel.isPresentingAddRSSSourceSheet) {
            AddRSSSourceSheet { feedURL, displayName in
                try await viewModel.addRSSSourceAndSync(feedURL: feedURL, displayName: displayName)
            }
        }
    }
}

private struct RSSItemDetailPane: View {
    var source: RSSSource?
    var item: RSSItemSummary
    var onFollow: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentChatLayout.spaceL) {
                RSSItemHero(source: source, item: item)
                RSSInfoSection(title: "文章摘要", systemImage: "doc.text.magnifyingglass") {
                    Text(item.snippet.isEmpty ? "暂无摘要。" : item.snippet)
                        .font(AgentChatTypography.body)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                RSSInfoSection(title: "来源信息", systemImage: "dot.radiowaves.left.and.right") {
                    VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                        RSSMetadataLine(label: "来源", value: source?.displayName ?? item.sourceID.rawValue)
                        RSSMetadataLine(label: "作者", value: item.author ?? "未知")
                        RSSLinkMetadataLine(url: item.link, onOpen: onFollow)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, AgentChatLayout.spaceXL)
            .padding(.vertical, AgentChatLayout.spaceL)
            .frame(maxWidth: AgentChatLayout.chatContentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.12))
    }
}

private struct RSSItemHero: View {
    var source: RSSSource?
    var item: RSSItemSummary

    var body: some View {
        HStack(alignment: .top, spacing: AgentChatLayout.spaceM) {
            ZStack {
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
                Image(systemName: item.state.isRead ? "newspaper" : "newspaper.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                HStack(alignment: .firstTextBaseline, spacing: AgentChatLayout.spaceS) {
                    Text(item.title)
                        .font(AgentChatTypography.title)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    RSSStatusPill(status: item.state.isRead ? "已读" : "未读", color: item.state.isRead ? .secondary : .blue)
                    if item.state.isStarred { RSSStatusPill(status: "收藏", color: .yellow, systemImage: "star.fill") }
                }
                Text(source?.displayName ?? item.sourceID.rawValue)
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: AgentChatLayout.spaceS) {
                    RSSStatusPill(status: item.publishedAt.formatted(date: .abbreviated, time: .shortened), color: .secondary, systemImage: "clock")
                    RSSStatusPill(status: item.author ?? "未知作者", color: .secondary, systemImage: "person")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AgentChatLayout.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous).stroke(Color.secondary.opacity(AgentChatLayout.hairlineOpacity), lineWidth: 1))
    }
}

private struct RSSInfoSection<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: AgentChatLayout.spaceM) {
            Label(title, systemImage: systemImage)
                .font(AgentChatTypography.metaEmphasis)
                .foregroundStyle(.primary)
            content
        }
        .padding(AgentChatLayout.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous).stroke(Color.secondary.opacity(AgentChatLayout.hairlineOpacity), lineWidth: 1))
    }
}

private struct RSSMetadataLine: View {
    var label: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(AgentChatTypography.microEmphasis)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(AgentChatTypography.meta)
                .textSelection(.enabled)
        }
    }
}

private struct RSSLinkMetadataLine: View {
    var url: URL?
    var onOpen: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("链接")
                .font(AgentChatTypography.microEmphasis)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            if let url {
                Button(action: onOpen) {
                    HStack(spacing: 5) {
                        Text(url.absoluteString)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .font(AgentChatTypography.meta)
                }
                .buttonStyle(.link)
                .textSelection(.enabled)
                .help("新建关注会话，并在会话浏览器中打开此链接")
            } else {
                Text("无")
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct RSSStatusPill: View {
    var status: String
    var color: Color
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(status)
        }
        .font(AgentChatTypography.microEmphasis)
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(color.opacity(0.12), in: Capsule())
    }
}


private struct SessionCardAttentionStyle {
    var dotColor: Color?
    var backgroundColor: Color
    var borderColor: Color
    var borderWidth: CGFloat
    var leadingBarColor: Color?
    var leadingBarWidth: CGFloat
    var titleWeight: Font.Weight
    var shadowColor: Color
    var shadowRadius: CGFloat

    init(level: SessionAttentionLevel, isSelected: Bool) {
        if isSelected {
            let color = Self.attentionColor
            dotColor = level >= .emphasized ? .white.opacity(0.86) : (level == .none ? nil : color)
            backgroundColor = level >= .emphasized ? color : Color.accentColor.opacity(0.14)
            borderColor = level >= .emphasized ? Color.white.opacity(0.24) : Color.clear
            borderWidth = level >= .emphasized ? 1 : 0
            leadingBarColor = nil
            leadingBarWidth = 0
            titleWeight = level == .none ? .semibold : .bold
            shadowColor = .clear
            shadowRadius = 0
            return
        }

        switch level {
        case .none:
            dotColor = nil
            backgroundColor = Color(nsColor: .windowBackgroundColor)
            borderColor = Color.clear
            borderWidth = 0
            leadingBarColor = nil
            leadingBarWidth = 0
            titleWeight = .regular
            shadowColor = .clear
            shadowRadius = 0
        case .unread:
            let color = Self.attentionColor
            dotColor = color
            backgroundColor = color.opacity(0.045)
            borderColor = Color.clear
            borderWidth = 0
            leadingBarColor = nil
            leadingBarWidth = 0
            titleWeight = .semibold
            shadowColor = .clear
            shadowRadius = 0
        case .emphasized:
            let color = Self.attentionColor
            dotColor = .white.opacity(0.86)
            backgroundColor = color
            borderColor = Color.white.opacity(0.18)
            borderWidth = 1
            leadingBarColor = nil
            leadingBarWidth = 0
            titleWeight = .semibold
            shadowColor = color.opacity(0.16)
            shadowRadius = 5
        case .actionable:
            let color = Self.attentionColor
            dotColor = .white.opacity(0.92)
            backgroundColor = color
            borderColor = Color.white.opacity(0.26)
            borderWidth = 1
            leadingBarColor = nil
            leadingBarWidth = 0
            titleWeight = .bold
            shadowColor = color.opacity(0.22)
            shadowRadius = 7
        case .interruptive:
            let color = Self.attentionColor
            dotColor = .white
            backgroundColor = color
            borderColor = Color.white.opacity(0.34)
            borderWidth = 1.2
            leadingBarColor = nil
            leadingBarWidth = 0
            titleWeight = .bold
            shadowColor = color.opacity(0.28)
            shadowRadius = 9
        }
    }

    private static var attentionColor: Color { ConnorCraftPalette.accent }
}

struct CraftSessionRow: View {
    var row: AgentChatSessionPresentation
    var readState: SessionReadState?
    var isSelected: Bool
    var isRunning: Bool
    var isRegeneratingTitle: Bool
    var hasRunningBackgroundTask: Bool
    var labelDefinitions: [AgentSessionLabelDefinition]
    var onSelect: () -> Void
    var onRename: (String) -> Void
    var onSetStatus: (AgentSessionStatus) -> Void
    var onToggleLabel: (String) -> Void
    var onRegenerateTitle: () -> Void
    var onDelete: () -> Void

    @State private var isEditingTitle: Bool = false
    @State private var titleDraft: String = ""
    @State private var isDeleteConfirmationPresented: Bool = false
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        rowContent
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    onRegenerateTitle()
                } label: {
                    Label("重设标题", systemImage: "sparkles")
                }
                .disabled(isRegeneratingTitle)
                .tint(.orange)

                Button(role: .destructive) {
                    isDeleteConfirmationPresented = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(hasRunningBackgroundTask)
            }
            .contextMenu { contextMenuItems }
            .onChange(of: row.title) { _, newTitle in
            guard !isEditingTitle else { return }
            titleDraft = newTitle
        }
            .onAppear { titleDraft = row.title }
            .confirmationDialog("删除这个会话？", isPresented: $isDeleteConfirmationPresented, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: onDelete)
                .disabled(hasRunningBackgroundTask)
            Button("取消", role: .cancel) {}
            } message: {
                Text(hasRunningBackgroundTask ? "此会话仍有后台任务正在运行,请等待任务结束后再删除。" : "删除后会话将从列表中移除。")
            }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Menu {
            ForEach(AgentSessionStatus.allCases.filter { $0 != .archived }, id: \.self) { status in
                Button {
                    onSetStatus(status)
                } label: {
                    Label(status.displayName, systemImage: status == row.status ? "checkmark.circle.fill" : icon(for: status))
                }
            }
        } label: {
            Label("更改状态", systemImage: "circle.dashed")
        }

        Menu {
            if labelDefinitions.isEmpty {
                Button {} label: {
                    Label("暂无可切换标签", systemImage: "tag.slash")
                }
                .disabled(true)
            } else {
                ForEach(labelDefinitions) { definition in
                    Button {
                        onToggleLabel(definition.id)
                    } label: {
                        Label(definition.name, systemImage: row.labels.contains(where: { $0.id == definition.id }) ? "checkmark.circle.fill" : "tag")
                    }
                }
            }
        } label: {
            Label("标签", systemImage: "tag")
        }

        Divider()

        Button {
            beginTitleEdit()
        } label: {
            Label("重命名", systemImage: "pencil")
        }

        Button {
            onRegenerateTitle()
        } label: {
            Label("重设标题", systemImage: "sparkles")
        }
        .disabled(isRegeneratingTitle)

        Divider()

        Button(role: .destructive) {
            isDeleteConfirmationPresented = true
        } label: {
            Label("删除", systemImage: "trash")
        }
        .disabled(hasRunningBackgroundTask)
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 10) {
            attentionIndicator
            leadingSessionIcon
            sessionTextContent
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackgroundColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(cardStyle.borderColor, lineWidth: cardStyle.borderWidth)
        )
        .shadow(color: cardStyle.shadowColor, radius: cardStyle.shadowRadius, x: 0, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            if !isEditingTitle { onSelect() }
        }
        .onChange(of: isTitleFocused) { _, focused in
            if !focused, isEditingTitle { commitTitleEdit() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var leadingSessionIcon: some View {
        if isRunning || isRegeneratingTitle {
            ProgressView()
                .controlSize(.small)
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: row.isFlagged ? "pin.fill" : icon(for: row.status))
                .foregroundStyle(leadingIconColor)
                .frame(width: 18)
        }
    }

    private var sessionTextContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if isEditingTitle {
                    TextField("会话标题", text: $titleDraft)
                        .textFieldStyle(.plain)
                        .font(isSelected ? AppListTypography.rowTitleSelected : AppListTypography.rowTitle)
                        .foregroundStyle(primaryTextColor)
                        .focused($isTitleFocused)
                        .lineLimit(1)
                        .onSubmit { commitTitleEdit() }
                } else {
                    Text(row.title)
                        .font(isSelected ? AppListTypography.rowTitleSelected : AppListTypography.rowTitle)
                        .fontWeight(cardStyle.titleWeight)
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(1)
                        .onTapGesture(count: 2) { beginTitleEdit() }
                }
                Spacer(minLength: 4)
                trailingSessionStatusText
            }

            HStack(spacing: 6) {
                Text(row.statusText)
                    .font(AppListTypography.rowCaptionEmphasized)
                    .foregroundStyle(statusPillForegroundColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusPillBackgroundColor, in: Capsule())
                Text("\(row.messageCount) 条消息")
                    .font(AppListTypography.rowCaption)
                    .foregroundStyle(secondaryTextColor)
            }

            if !row.labels.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(row.labels.prefix(3)), id: \.id) { label in
                        Text(label.id)
                            .font(AppListTypography.rowCaption)
                            .foregroundStyle(labelForegroundColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(labelBackgroundColor, in: Capsule())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var trailingSessionStatusText: some View {
        if isRunning {
            Text("运行中")
                .font(AppListTypography.rowCaptionEmphasized)
                .foregroundStyle(activeMetaTextColor)
        } else if isRegeneratingTitle {
            Text("生成中")
                .font(AppListTypography.rowCaptionEmphasized)
                .foregroundStyle(activeMetaTextColor)
        } else {
            Text(row.relativeUpdatedTime)
                .font(AppListTypography.rowCaption)
                .foregroundStyle(secondaryTextColor)
        }
    }

    @ViewBuilder
    private var attentionIndicator: some View {
        if let dotColor = cardStyle.dotColor {
            VStack(spacing: 4) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                Text("NEW")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(Color.yellow)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.red, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.yellow, lineWidth: 1)
                    )
            }
            .frame(width: 34)
            .padding(.top, 5)
        }
    }

    private var usesFilledAttentionStyle: Bool {
        attentionLevel >= .emphasized
    }

    private var primaryTextColor: Color {
        usesFilledAttentionStyle ? .white : .primary
    }

    private var secondaryTextColor: Color {
        usesFilledAttentionStyle ? .white.opacity(0.72) : .secondary
    }

    private var activeMetaTextColor: Color {
        usesFilledAttentionStyle ? .white.opacity(0.86) : Color.accentColor
    }

    private var leadingIconColor: Color {
        if row.isFlagged { return usesFilledAttentionStyle ? .white.opacity(0.88) : .orange }
        if usesFilledAttentionStyle { return .white.opacity(0.78) }
        return isSelected ? .accentColor : .secondary
    }

    private var statusPillForegroundColor: Color {
        usesFilledAttentionStyle ? .white : statusColor(row.status)
    }

    private var statusPillBackgroundColor: Color {
        usesFilledAttentionStyle ? Color.white.opacity(0.18) : statusColor(row.status).opacity(0.14)
    }

    private var labelForegroundColor: Color {
        usesFilledAttentionStyle ? .white.opacity(0.86) : .primary
    }

    private var labelBackgroundColor: Color {
        usesFilledAttentionStyle ? Color.white.opacity(0.14) : Color.purple.opacity(0.10)
    }

    private var attentionLevel: SessionAttentionLevel {
        readState?.highestLevel ?? .none
    }

    private var cardStyle: SessionCardAttentionStyle {
        SessionCardAttentionStyle(level: attentionLevel, isSelected: isSelected)
    }

    private var rowBackgroundColor: Color {
        cardStyle.backgroundColor
    }


    private func beginTitleEdit() {
        titleDraft = row.title
        isEditingTitle = true
        isTitleFocused = true
    }

    private func commitTitleEdit() {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditingTitle = false
        isTitleFocused = false
        guard !trimmed.isEmpty, trimmed != row.title else {
            titleDraft = row.title
            return
        }
        onRename(trimmed)
    }


    private func icon(for status: AgentSessionStatus) -> String {
        switch status {
        case .todo: "circle"
        case .inProgress: "play.circle"
        case .waiting: "clock"
        case .needsReview: "exclamationmark.bubble"
        case .done: "checkmark.circle.fill"
        case .blocked: "nosign"
        case .cancelled: "xmark.circle"
        case .archived: "archivebox"
        }
    }

    private func statusColor(_ status: AgentSessionStatus) -> Color {
        switch status {
        case .todo: .secondary
        case .inProgress: .blue
        case .waiting: .orange
        case .needsReview: .purple
        case .done: .green
        case .blocked: .red
        case .cancelled: .gray
        case .archived: .gray
        }
    }
}


struct CraftSettingsListPane: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var selection: SidebarItem?

    var body: some View {
        VStack(spacing: 0) {
            Text("设置")
                .font(AppListTypography.header)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            VStack(spacing: 0) {
                ForEach(ConnorSettingsSection.allCases) { section in
                    SettingsCategoryRow(
                        title: section.title,
                        subtitle: section.subtitle,
                        systemImage: section.systemImage,
                        isSelected: viewModel.selectedSettingsSection == section
                    ) {
                        selection = .llmSettings
                        viewModel.selectSettingsSection(section)
                    }
                }
            }
            .padding(10)
            Spacer()
        }
    }
}

struct SettingsCategoryRow: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(AppListTypography.rowTitleSelected)
                    Text(subtitle).font(AppListTypography.rowSubtitle).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct CraftSimpleListPane: View {
    var title: String
    var subtitle: String
    var rows: [String]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 3) {
                Text(title).font(AppListTypography.header)
                Text(subtitle).font(AppListTypography.rowSubtitle).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(rows.isEmpty ? ["在右侧查看详情"] : rows, id: \.self) { row in
                        Text(row)
                            .font(AppListTypography.rowTitle)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(10)
            }
        }
    }
}
