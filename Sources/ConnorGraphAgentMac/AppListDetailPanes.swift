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
            case .automation, .scheduledTasks:
                CraftTaskAutomationListPane(viewModel: viewModel, kind: .scheduled)
            case .eventTriggeredTasks:
                CraftTaskAutomationListPane(viewModel: viewModel, kind: .eventTriggered)
            case .productOS:
                CraftSimpleListPane(title: "Product OS", subtitle: "本地控制面模块", rows: viewModel.productOSRegistry.sources.map(\.displayName) + viewModel.productOSRegistry.skills.map(\.displayName))
            default:
                CraftSimpleListPane(title: (selection ?? .agentChat).rawValue, subtitle: "康纳同学工作区", rows: [])
            }
        }
    }
}

private struct ListSearchFilterBanner: View {
    var query: String
    var sourceTitle: String
    var onClear: () -> Void

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        if !trimmedQuery.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("正在筛选\(sourceTitle)：")
                    .font(AppListTypography.rowCaption)
                    .foregroundStyle(.secondary)
                Text("“\(trimmedQuery)”")
                    .font(AppListTypography.rowCaptionEmphasized)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("清除筛选")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
    }
}

private func listSearchTerms(for query: String) -> [String] {
    let normalized = NativeSearchQueryNormalizer.normalize(query)
    var seen: Set<String> = []
    let terms = normalized.scoringTokens
        .map(\.value)
        .filter { !$0.isEmpty }
        .filter { $0.count >= 2 || query.count <= 2 }
        .filter { seen.insert($0).inserted }
    if !terms.isEmpty { return terms }
    return query
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        .map(String.init)
        .filter { !$0.isEmpty }
}

private func listSearchTextMatches(_ text: String, terms: [String]) -> Bool {
    let lower = text.lowercased()
    let matchedCount = terms.filter { lower.localizedCaseInsensitiveContains($0) }.count
    let requiredMatches = min(max(terms.count, 1), 2)
    return matchedCount >= requiredMatches
}

struct CraftCalendarListPane: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 24)
                Text("日历")
                    .font(AppListTypography.header)
                    .frame(maxWidth: .infinity, alignment: .center)
                Button(action: { viewModel.isPresentingAddCalendarSourceSheet = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("添加日历源")
                .accessibilityLabel("添加日历源")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)

            ListSearchFilterBanner(query: viewModel.calendarSearchQuery, sourceTitle: "日历") {
                viewModel.calendarSearchQuery = ""
            }

            if viewModel.calendarBrowserPresentation.daySections.isEmpty {
                ContentUnavailableView("还没有可显示的日程", systemImage: "calendar", description: Text("连接或同步日历后，康纳同学会把近期日程放在这里，方便你从时间安排继续展开工作。"))
                    .padding(.top, 80)
            } else if filteredCalendarSections.isEmpty {
                ContentUnavailableView("没有找到匹配的日程", systemImage: "calendar.badge.exclamationmark", description: Text("换个关键词试试，或者清除筛选查看全部日程。"))
                    .padding(.top, 80)
            } else {
                CalendarSectionScrollView(
                    sections: filteredCalendarSections,
                    selectedID: viewModel.selectedCalendarEventID,
                    onSelect: { viewModel.selectedCalendarEventID = $0 }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $viewModel.isPresentingAddCalendarSourceSheet) {
            AddCalendarSourceSheet(viewModel: viewModel)
        }
    }

    private var filteredCalendarSections: [NativeCalendarDaySectionPresentation] {
        let query = viewModel.calendarSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.calendarBrowserPresentation.daySections }
        let normalized = query.lowercased()
        return viewModel.calendarBrowserPresentation.daySections.compactMap { section in
            let events = section.events.filter { event in
                event.title.lowercased().contains(normalized)
                    || event.timeText.lowercased().contains(normalized)
                    || (event.location?.lowercased().contains(normalized) ?? false)
            }
            guard !events.isEmpty else { return nil }
            return NativeCalendarDaySectionPresentation(id: section.id, title: section.title, events: events)
        }
    }
}

struct AddCalendarSourceSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    private static let supportedProviders: [CalendarProviderProfile] =
        CalendarProviderProfile.catalog.filter(\.isUserConfigurable)

    @State private var selectedProvider: CalendarSourceKind = .macOSEventKit
    @State private var displayName: String = ""
    @State private var subscriptionURL: String = ""
    @State private var serverURL: String = ""
    @State private var username: String = ""
    @State private var appPassword: String = ""
    @State private var isSyncingLocal = false
    @State private var isSubmitting = false
    @State private var feedbackMessage: String?
    @State private var feedbackError: String?

    private var selectedProfile: CalendarProviderProfile {
        Self.supportedProviders.first { $0.sourceKind == selectedProvider }
            ?? CalendarProviderProfile.catalog[0]
    }

    private var isFormValid: Bool {
        switch selectedProvider {
        case .macOSEventKit:
            return true
        case .icsSubscription:
            return !subscriptionURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .genericCalDAV, .appleICloudCalDAV, .fastmailCalDAV, .nextcloudCalDAV:
            return !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !appPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceL) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: SettingsListLayout.spaceM) {
                    providerSection
                    configurationForm
                    hintCard
                    feedbackView
                }
            }

            footer
        }
        .padding(SettingsListLayout.spaceXL)
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: 520)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: SettingsListLayout.spaceM) {
            ZStack {
                RoundedRectangle(cornerRadius: SettingsListLayout.radiusM, style: .continuous)
                    .fill(Color.accentColor.opacity(0.13))
                Image(systemName: "calendar.badge.plus")
                    .font(SettingsListTypography.largeIcon)
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: SettingsListLayout.spaceXS) {
                Text("添加日历源")
                    .font(SettingsListTypography.header)
                Text("选择服务商并填写配置信息。添加后康纳同学会自动发现日历并开始同步日程。所有远程日历均为只读同步。")
                    .font(SettingsListTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Provider Picker

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceS) {
            Text("服务商")
                .font(SettingsListTypography.rowTitle)

            Picker("服务商", selection: $selectedProvider) {
                ForEach(Self.supportedProviders) { profile in
                    Text(profile.displayName).tag(profile.sourceKind)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: selectedProvider) { _, _ in
                feedbackMessage = nil
                feedbackError = nil
            }
        }
    }

    // MARK: - Configuration Form

    @ViewBuilder
    private var configurationForm: some View {
        switch selectedProvider {
        case .macOSEventKit:
            eventKitForm
        case .icsSubscription:
            icsForm
        case .genericCalDAV, .appleICloudCalDAV, .fastmailCalDAV, .nextcloudCalDAV:
            calDAVForm
        default:
            EmptyView()
        }
    }

    private var eventKitForm: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceS) {
            Text("本机日历")
                .font(SettingsListTypography.rowTitle)
            Text("点击「同步本机日历」后，系统会弹出日历权限请求。授权后，康纳同学会读取未来 90 天和过去 7 天的事件。")
                .font(SettingsListTypography.rowCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("本机日历只读取 macOS 已授权可见的日历。如需连接其他服务，可先在 macOS 系统设置 → 互联网账户中添加账户，Connor 会通过 EventKit 读取。")
                .font(SettingsListTypography.rowCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SettingsListLayout.spaceL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppShellColors.hairline, lineWidth: 1))
    }

    private var icsForm: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceS) {
            Text("订阅 URL")
                .font(SettingsListTypography.rowTitle)
            TextField("https://example.com/calendar.ics", text: $subscriptionURL)
                .textFieldStyle(.roundedBorder)
            Text("输入 ICS / Webcal 订阅链接地址。支持 http、https 和 webcal 协议。")
                .font(SettingsListTypography.rowCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SettingsListLayout.spaceL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppShellColors.hairline, lineWidth: 1))
    }

    private var calDAVForm: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceS) {
            calDAVField("服务器 URL", text: $serverURL, placeholder: serverURLPlaceholder)
            calDAVField("用户名", text: $username, placeholder: "user@example.com")
            calDAVField("应用密码", text: $appPassword, placeholder: "App Password", isSecure: true)
        }
        .padding(SettingsListLayout.spaceL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppShellColors.hairline, lineWidth: 1))
    }

    private func calDAVField(_ title: String, text: Binding<String>, placeholder: String, isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(SettingsListTypography.rowCaption)
                .foregroundStyle(.secondary)
            if isSecure {
                SecureField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var serverURLPlaceholder: String {
        switch selectedProvider {
        case .appleICloudCalDAV: return "https://caldav.icloud.com"
        case .fastmailCalDAV: return "https://caldav.fastmail.com"
        case .nextcloudCalDAV: return "https://your-nextcloud.com/dav"
        default: return "https://caldav.example.com"
        }
    }

    // MARK: - Hint Card

    private var hintCard: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceS) {
            Label(selectedProfile.displayName, systemImage: "info.circle")
                .font(SettingsListTypography.rowCaptionEmphasized)
                .foregroundStyle(.secondary)
            Text(selectedProfile.helpText)
                .font(SettingsListTypography.rowCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(SettingsListLayout.spaceL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.accentColor.opacity(0.15), lineWidth: 1))
    }

    // MARK: - Feedback

    @ViewBuilder
    private var feedbackView: some View {
        if let error = feedbackError {
            Text(error)
                .font(SettingsListTypography.rowCaption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        } else if let message = feedbackMessage {
            Text(message)
                .font(SettingsListTypography.rowCaption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: SettingsListLayout.spaceL) {
            if selectedProvider == .macOSEventKit {
                Button("前往日历设置") {
                    viewModel.selectSettingsSection(.calendar)
                    viewModel.isPresentingAddCalendarSourceSheet = false
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            Button("取消") { dismiss() }
                .buttonStyle(.bordered)
                .disabled(isSubmitting || isSyncingLocal)

            if selectedProvider == .macOSEventKit {
                Button {
                    isSyncingLocal = true
                    feedbackMessage = "正在请求日历权限并同步…"
                    Task { @MainActor in
                        let succeeded = await viewModel.syncSystemCalendarNow()
                        feedbackMessage = viewModel.calendarSyncMessage
                        isSyncingLocal = false
                        if succeeded { dismiss() }
                    }
                } label: {
                    if isSyncingLocal {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("同步本机日历", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSyncingLocal)
                .keyboardShortcut(.defaultAction)
            } else {
                Button {
                    submitWizardAccount()
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("添加并同步", systemImage: "plus")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isFormValid || isSubmitting)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Submit

    private func submitWizardAccount() {
        guard isFormValid else { return }
        isSubmitting = true
        feedbackError = nil
        feedbackMessage = nil

        do {
            let wizard = CalendarSourceWizardState(
                provider: selectedProvider,
                displayName: displayName,
                subscriptionURLString: subscriptionURL,
                serverURLString: serverURL,
                username: username,
                appPassword: appPassword
            )
            let account = try wizard.buildAccount(existingAccountCount: viewModel.calendarAccounts.count)
            viewModel.addCalendarSourceFromWizard(account: account, credential: appPassword)
            isSubmitting = false
        } catch {
            isSubmitting = false
            feedbackError = "配置无效：\(error.localizedDescription)"
        }
    }
}

private struct CalendarSectionScrollView: View {
    var sections: [NativeCalendarDaySectionPresentation]
    var selectedID: CalendarEventID?
    var onSelect: (CalendarEventID) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(AppListTypography.rowCaption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                        ForEach(section.events) { event in
                            CalendarEventButton(row: event, isSelected: event.id == selectedID, onSelect: { onSelect(event.id) })
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .scrollContentBackground(.hidden)
    }
}

private struct CalendarEventButton: View {
    var row: NativeCalendarEventRowPresentation
    var isSelected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 8) {
                Text(row.timeText)
                    .font(AppListTypography.rowCaption)
                    .foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title)
                        .font(AppListTypography.rowTitle)
                        .foregroundStyle(.primary)
                    if let location = row.location, !location.isEmpty {
                        Text(location)
                            .font(AppListTypography.rowSubtitle)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct CraftContactsListPane: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            Text("联系人")
                .font(AppListTypography.header)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)

            if viewModel.contactsBrowserPresentation.rows.isEmpty {
                ContentUnavailableView("还没有可显示的联系人", systemImage: "person.crop.circle.badge", description: Text("连接通讯录后，康纳同学会把可用联系人整理在这里，方便之后检索和关联会话。"))
                    .padding(.top, 80)
            } else {
                ContactsRowsScrollView(rows: viewModel.contactsBrowserPresentation.rows, selectedID: viewModel.selectedContactID, onSelect: { viewModel.selectedContactID = $0 })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct ContactsRowsScrollView: View {
    var rows: [NativeContactRowPresentation]
    var selectedID: ContactID?
    var onSelect: (ContactID) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(rows) { row in
                    ContactRowButton(row: row, isSelected: row.id == selectedID, onSelect: { onSelect(row.id) })
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .scrollContentBackground(.hidden)
    }
}

private struct ContactRowButton: View {
    var row: NativeContactRowPresentation
    var isSelected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.displayName)
                    .font(AppListTypography.rowTitle)
                    .foregroundStyle(.primary)
                Text(row.primaryEmail ?? row.organizationName ?? "无联系方式")
                    .font(AppListTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
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

            ListSearchFilterBanner(query: viewModel.sessionSearchQuery, sourceTitle: "对话历史") {
                viewModel.sessionSearchQuery = ""
            }

            if visibleSessions.isEmpty {
                ContentUnavailableView(sessionEmptyTitle, systemImage: "bubble.left", description: Text(sessionEmptyDescription))
                    .padding(.top, 80)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(visibleSessions) { session in
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
                            .id(session.id)
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

    private var visibleSessions: [AgentSession] {
        let query = viewModel.sessionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.chatSessions }
        let terms = listSearchTerms(for: query)
        guard !terms.isEmpty else { return viewModel.chatSessions }
        return viewModel.chatSessions.filter { session in
            listSearchTextMatches(session.title, terms: terms)
                || session.messages.contains { listSearchTextMatches($0.content, terms: terms) }
        }
    }

    private var sessionEmptyTitle: String {
        viewModel.sessionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "暂无会话" : "没有匹配的对话"
    }

    private var sessionEmptyDescription: String {
        viewModel.sessionSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "点击左上角新建会话开始。" : "清除筛选后可查看全部对话。"
    }

    private var sessionListTitle: String {
        switch viewModel.sessionListFilter {
        case .all: "全部会话"
        case .status(let status): status.displayName
        case .label(let labelID): viewModel.governanceConfig.labels.first(where: { $0.id == labelID })?.name ?? labelID
        }
    }
}

private extension View {
    func nativeListRowStyle() -> some View {
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
            "适合发现技术趋势。投影到 Memory OS 前必须先生成 evidence candidate 并人工审查。"
        case .custom:
            "输入自定义 feed URL。同步和状态变更都经过 Connor Policy Engine 和 audit trail。"
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

private enum TaskAutomationKind {
    case scheduled
    case eventTriggered

    var title: String {
        switch self {
        case .scheduled: "定时任务"
        case .eventTriggered: "事件触发"
        }
    }

    var emptyTitle: String {
        switch self {
        case .scheduled: "暂无定时任务"
        case .eventTriggered: "暂无事件触发任务"
        }
    }

    var emptyDescription: String {
        switch self {
        case .scheduled: "系统任务会在启动时自动补齐；用户和 AI 任务可按时间或周期新建会话并发送消息。"
        case .eventTriggered: "用户或 AI 可创建：当会话状态变为特定状态后，向 AI 发送指定内容。"
        }
    }

    var systemImage: String {
        switch self {
        case .scheduled: "clock"
        case .eventTriggered: "dot.radiowaves.left.and.right"
        }
    }

    var createButtonHelp: String {
        switch self {
        case .scheduled: "新建定时任务"
        case .eventTriggered: "新建事件触发任务"
        }
    }

    func cards(from presentation: TaskManagementUIPresentation) -> [TaskManagementUICard] {
        switch self {
        case .scheduled: presentation.scheduledTasks
        case .eventTriggered: presentation.eventTriggeredTasks
        }
    }
}

private struct CraftTaskAutomationListPane: View {
    @ObservedObject var viewModel: AppViewModel
    var kind: TaskAutomationKind
    @State private var isPresentingCreateSheet = false

    private var cards: [TaskManagementUICard] {
        kind.cards(from: viewModel.taskManagementPresentation)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(kind.title)
                    .font(AppListTypography.header)
                    .frame(maxWidth: .infinity, alignment: .center)
                Button(action: { isPresentingCreateSheet = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12.5, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(kind.createButtonHelp)
                .accessibilityLabel(kind.createButtonHelp)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)

            if cards.isEmpty {
                ContentUnavailableView(kind.emptyTitle, systemImage: kind.systemImage, description: Text("\(kind.emptyDescription) 点击右上角 + 新建。"))
                    .padding(.top, 80)
            } else {
                List(cards) { card in
                    TaskAutomationListRow(
                        card: card,
                        isSelected: card.id == viewModel.selectedTaskAutomationID,
                        onSelect: { viewModel.selectedTaskAutomationID = card.id }
                    )
                    .nativeListRowStyle()
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .contentMargins(.top, 6, for: .scrollContent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $isPresentingCreateSheet) {
            AddTaskAutomationSheet(kind: kind, governanceConfig: viewModel.governanceConfig) { request in
                switch request.kind {
                case .scheduled:
                    try viewModel.createScheduledSessionMessageTask(
                        name: request.name,
                        runAt: request.runAt,
                        recurrence: request.recurrence,
                        message: request.message,
                        title: request.sessionTitle,
                        rationale: request.rationale
                    )
                case .eventTriggered:
                    try viewModel.createSessionStatusMessageTask(
                        name: request.name,
                        toStatus: request.toStatus,
                        message: request.message,
                        sessionID: nil,
                        rationale: request.rationale
                    )
                }
            }
        }
        .task {
            viewModel.reloadTaskManagementPresentation()
        }
    }
}

private struct TaskAutomationListRow: View {
    var card: TaskManagementUICard
    var isSelected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(severityColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 7)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(card.title)
                            .font(isSelected ? AppListTypography.rowTitleSelected : AppListTypography.rowTitle)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(card.originBadge)
                            .font(AppListTypography.rowCaption)
                            .foregroundStyle(.secondary)
                    }
                    Text(card.targetLabel)
                        .font(AppListTypography.rowCaptionEmphasized)
                        .lineLimit(1)
                    Text(contextText)
                        .font(AppListTypography.rowCaption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        TaskAutomationChip(text: card.triggerLabel)
                        TaskAutomationChip(text: card.statusLabel)
                        if let reason = card.deleteDisabledReason, !reason.isEmpty {
                            TaskAutomationChip(text: reason)
                        }
                    }
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
        [
            card.nextRunLabel.isEmpty ? nil : "下次：\(card.nextRunLabel)",
            card.lastRunLabel.isEmpty ? nil : "上次：\(card.lastRunLabel)",
            card.lastErrorLabel.isEmpty ? nil : "错误：\(card.lastErrorLabel)"
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private var severityColor: Color {
        switch card.severity {
        case .info: .blue
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}

private struct TaskAutomationChip: View {
    var text: String

    var body: some View {
        Text(text)
            .font(AppListTypography.rowCaption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.10), in: Capsule())
            .lineLimit(1)
    }
}

private struct AddTaskAutomationRequest {
    var kind: TaskAutomationKind
    var name: String
    var runAt: Date
    var recurrence: ConnorTaskRecurrence
    var toStatus: String
    var message: String
    var sessionTitle: String
    var rationale: String?
}

private struct AddTaskAutomationSheet: View {
    private enum Layout {
        static let sheetWidth: CGFloat = 700
        static let sheetHeight: CGFloat = 620
        static let labelWidth: CGFloat = 122
        static let compactControlWidth: CGFloat = 220
    }

    var kind: TaskAutomationKind
    var governanceConfig: AppSessionGovernanceConfig
    var onCreate: (AddTaskAutomationRequest) throws -> String

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var runAt: Date = Date().addingTimeInterval(3600)
    @State private var recurrence: ConnorTaskRecurrence = .once
    @State private var toStatus: String = AgentSessionStatus.done.rawValue
    @State private var message: String = ""
    @State private var sessionTitle: String = ""
    @State private var rationale: String = ""
    @State private var isSaving = false
    @State private var saveMessage: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedMessage: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var normalizedTitle: String { sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var normalizedRationale: String? {
        let value = rationale.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private var saveDisabled: Bool {
        trimmedName.isEmpty || trimmedMessage.isEmpty || isSaving
    }

    private var selectableRecurrences: [ConnorTaskRecurrence] {
        [.once, .daily, .weekly, .monthly]
    }

    private var selectableStatuses: [AgentSessionStatusDefinition] {
        let configured = governanceConfig.statuses
            .filter { $0.id != AgentSessionStatus.archived.rawValue }
            .filter { AgentSessionStatus(rawValue: $0.id) != nil }
            .sorted { $0.sortOrder < $1.sortOrder }
        if configured.isEmpty {
            return AgentSessionStatusDefinition.defaults
                .filter { $0.id != AgentSessionStatus.archived.rawValue }
                .sorted { $0.sortOrder < $1.sortOrder }
        }
        return configured
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dialogHeader

            Divider()
                .padding(.top, AppShellLayout.spaceL)

            ScrollView {
                VStack(alignment: .leading, spacing: AppShellLayout.spaceL) {
                    RSSSetupSection(title: "基础信息", systemImage: kind.systemImage) {
                        RSSSetupRow("任务名称", labelWidth: Layout.labelWidth) {
                            TextField(kind == .scheduled ? "例如：每日复盘" : "例如：完成后总结", text: $name)
                                .textFieldStyle(.roundedBorder)
                        }

                        if kind == .scheduled {
                            RSSSetupRow("首次运行", labelWidth: Layout.labelWidth) {
                                DatePicker("首次运行", selection: $runAt, displayedComponents: [.date, .hourAndMinute])
                                    .labelsHidden()
                                    .frame(width: Layout.compactControlWidth, alignment: .leading)
                            }
                            RSSSetupRow("重复", labelWidth: Layout.labelWidth) {
                                Picker("重复", selection: $recurrence) {
                                    ForEach(selectableRecurrences, id: \.self) { recurrence in
                                        Text(label(for: recurrence)).tag(recurrence)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: Layout.compactControlWidth, alignment: .leading)
                            }
                            RSSSetupRow("会话标题", labelWidth: Layout.labelWidth) {
                                TextField("可选；留空时由会话自动命名", text: $sessionTitle)
                                    .textFieldStyle(.roundedBorder)
                            }
                        } else {
                            RSSSetupRow("触发状态", labelWidth: Layout.labelWidth) {
                                Picker("触发状态", selection: $toStatus) {
                                    ForEach(selectableStatuses) { definition in
                                        Label(definition.name, systemImage: definition.systemImage)
                                            .tag(definition.id)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: Layout.compactControlWidth, alignment: .leading)
                            }
                        }
                    }

                    RSSSetupSection(title: kind == .scheduled ? "发送给新会话" : "发送给当前会话", systemImage: "paperplane") {
                        RSSSetupRow("消息", labelWidth: Layout.labelWidth, alignment: .top) {
                            TextEditor(text: $message)
                                .font(AgentChatTypography.body)
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .frame(minHeight: 118)
                                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: AppShellLayout.radiusM, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: AppShellLayout.radiusM, style: .continuous).stroke(AppShellColors.hairline, lineWidth: 1))
                        }
                        RSSSetupHint(kind == .scheduled ? "到达时间后，Connor 会创建一个新会话并发送这段消息。" : "当会话状态切换到所选状态时，Connor 会向该会话发送这段消息。")
                    }

                    RSSSetupSection(title: "治理备注", systemImage: "checkmark.shield") {
                        RSSSetupRow("备注", labelWidth: Layout.labelWidth) {
                            TextField("可选；说明为什么需要这个任务", text: $rationale)
                                .textFieldStyle(.roundedBorder)
                        }
                        RSSSetupHint("任务会以“用户”来源创建，可在详情页暂停、恢复或删除；系统保护任务不受此表单影响，且不可暂停、恢复或删除。")
                    }

                    RSSHintCard(title: hintTitle, guidance: hintGuidance)

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
        .onAppear {
            if let first = selectableStatuses.first, !selectableStatuses.contains(where: { $0.id == toStatus }) {
                toStatus = first.id
            }
        }
    }

    private var dialogHeader: some View {
        HStack(alignment: .top, spacing: AppShellLayout.spaceM) {
            ZStack {
                RoundedRectangle(cornerRadius: AppShellLayout.radiusM, style: .continuous)
                    .fill(Color.orange.opacity(0.13))
                Image(systemName: kind.systemImage)
                    .font(SettingsListTypography.largeIcon)
                    .foregroundStyle(.orange)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: AppShellLayout.spaceXS) {
                Text(kind.createButtonHelp)
                    .font(.system(size: 26, weight: .semibold))
                Text(kind == .scheduled ? "创建一个按时间触发的用户任务，到点后新建会话并发送消息。" : "创建一个由会话状态变化触发的用户任务，状态命中后向该会话发送消息。")
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
            .accessibilityLabel("关闭新建任务")
        }
    }

    private var dialogFooter: some View {
        HStack(spacing: AppShellLayout.spaceM) {
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
                    Text("创建任务")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(saveDisabled)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.top, AppShellLayout.spaceM)
    }

    private var hintTitle: String {
        switch kind {
        case .scheduled: "定时任务只负责触发，不绕过权限"
        case .eventTriggered: "事件触发任务跟随会话治理状态"
        }
    }

    private var hintGuidance: String {
        switch kind {
        case .scheduled:
            "任务运行时仍会走 Connor 的会话、审计和工具权限机制。建议把消息写成清晰的目标，而不是隐藏复杂策略。"
        case .eventTriggered:
            "当前支持 session.status.changed 事件。任务只在状态命中时发送消息，不直接修改会话内容或绕过审批。"
        }
    }

    private func save() {
        isSaving = true
        saveMessage = nil
        do {
            _ = try onCreate(AddTaskAutomationRequest(
                kind: kind,
                name: trimmedName,
                runAt: runAt,
                recurrence: recurrence,
                toStatus: toStatus,
                message: trimmedMessage,
                sessionTitle: normalizedTitle,
                rationale: normalizedRationale
            ))
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            saveMessage = errorMessage(for: error)
        }
    }

    private func label(for recurrence: ConnorTaskRecurrence) -> String {
        switch recurrence {
        case .once: "仅一次"
        case .daily: "每天"
        case .weekly: "每周"
        case .monthly: "每月"
        case .interval: "固定间隔"
        }
    }

    private func errorMessage(for error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            return localized
        }
        return String(describing: error)
    }
}

struct CraftRSSListPane: View {
    @ObservedObject var viewModel: AppViewModel

    private var presentation: NativeRSSBrowserPresentation { viewModel.rssBrowserPresentation }
    private var visibleItems: [RSSItemSummary] { presentation.items(sourceID: nil, query: viewModel.rssSearchQuery) }

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

            ListSearchFilterBanner(query: viewModel.rssSearchQuery, sourceTitle: "RSS") {
                viewModel.rssSearchQuery = ""
            }

            if presentation.sources.isEmpty {
                ContentUnavailableView("还没有添加 RSS 源", systemImage: "dot.radiowaves.left.and.right", description: Text("点击右上角 + 添加 RSS、Atom 或 JSON Feed。康纳同学会把订阅文章放进本地资料流。"))
                    .padding(.top, 80)
            } else if presentation.items.isEmpty {
                ContentUnavailableView("还没有同步到文章", systemImage: "newspaper", description: Text("订阅源添加后，康纳同学会在同步完成时把文章按时间放在这里。"))
                    .padding(.top, 80)
            } else if visibleItems.isEmpty {
                ContentUnavailableView("没有找到匹配的 RSS 文章", systemImage: "newspaper", description: Text("换个关键词试试，或者清除筛选查看全部订阅文章。"))
                    .padding(.top, 80)
            } else {
                List(visibleItems) { item in
                    RSSItemListRow(
                        item: item,
                        source: presentation.source(id: item.sourceID),
                        isSelected: item.id == viewModel.selectedRSSItemID,
                        onSelect: { selectItem(item) }
                    )
                    .nativeListRowStyle()
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

enum AppDetailPaneIdentity {
    static func agentChat(sessionID: String?) -> String {
        "agent-chat-\(sessionID ?? "none")"
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
                if viewModel.selectedChatSessionID == nil {
                    AgentChatNoSelectionDetailView()
                } else {
                    AgentChatView(viewModel: viewModel)
                        .id(AppDetailPaneIdentity.agentChat(sessionID: viewModel.selectedChatSessionID))
                }
            case .promotionQueue:
                PromotionQueueView(viewModel: viewModel)
            case .pendingApprovals:
                AgentPendingApprovalReviewView(viewModel: viewModel)
            case .automation, .scheduledTasks:
                TaskAutomationDetailPane(viewModel: viewModel, kind: .scheduled)
            case .eventTriggeredTasks:
                TaskAutomationDetailPane(viewModel: viewModel, kind: .eventTriggered)
            case .productOS:
                ProductOSRegistryView(viewModel: viewModel)
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

private struct AgentChatNoSelectionDetailView: View {
    var body: some View {
        VStack(alignment: .center, spacing: AppShellLayout.spaceL) {
            Spacer(minLength: 80)
            ContentUnavailableView(
                "未选择会话",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("从当前会话列表选择一个会话查看详情。")
            )
            .frame(maxWidth: .infinity)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppShellColors.detailBackground)
    }
}

struct CalendarSourceSettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Group {
            if let selectedEvent {
                CalendarEventDetailPane(
                    event: selectedEvent,
                    row: selectedEventRow,
                    calendarName: calendarName(for: selectedEvent.calendarID),
                    accountName: accountName(for: selectedEvent.calendarID)
                )
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppShellColors.detailBackground)
    }

    private var selectedEvent: CalendarEvent? {
        guard let id = viewModel.selectedCalendarEventID else { return nil }
        return viewModel.calendarEvents.first { $0.id == id }
    }

    private var selectedEventRow: NativeCalendarEventRowPresentation? {
        guard let id = viewModel.selectedCalendarEventID else { return nil }
        return viewModel.calendarBrowserPresentation.daySections.flatMap(\.events).first { $0.id == id }
    }

    private func calendarName(for calendarID: CalendarID) -> String? {
        viewModel.calendarCollections.first { $0.id == calendarID }?.displayName
    }

    private func accountName(for calendarID: CalendarID) -> String? {
        guard let collection = viewModel.calendarCollections.first(where: { $0.id == calendarID }) else { return nil }
        return viewModel.calendarAccounts.first { $0.id == collection.accountID }?.displayName
    }
}

private struct CalendarEventDetailPane: View {
    var event: CalendarEvent
    var row: NativeCalendarEventRowPresentation?
    var calendarName: String?
    var accountName: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AgentChatLayout.spaceL) {
                CalendarEventHero(event: event, row: row, calendarName: calendarName)

                if let notes = trimmed(event.notes), !notes.isEmpty {
                    CalendarDetailSection(title: "备注", systemImage: "note.text") {
                        Text(notes)
                            .font(AgentChatTypography.body)
                            .lineSpacing(2)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if !event.attendees.isEmpty {
                    CalendarDetailSection(title: "参与人", systemImage: "person.2") {
                        VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                            ForEach(event.attendees, id: \.id) { attendee in
                                CalendarAttendeeRow(attendee: attendee)
                            }
                        }
                    }
                }

                CalendarDetailSection(title: "来源信息", systemImage: "calendar") {
                    VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                        CalendarMetadataLine(label: "日历", value: calendarName ?? event.calendarID.rawValue)
                        if let accountName, !accountName.isEmpty {
                            CalendarMetadataLine(label: "账户", value: accountName)
                        }
                        CalendarMetadataLine(label: "更新", value: event.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        if let recurrence = event.recurrenceSummary?.ruleDescription, !recurrence.isEmpty {
                            CalendarMetadataLine(label: "重复", value: recurrence)
                        }
                        if let url = event.url {
                            CalendarMetadataLinkLine(url: url)
                        }
                    }
                }
            }
            .padding(.horizontal, AgentChatLayout.spaceXL)
            .padding(.vertical, AgentChatLayout.spaceL)
            .frame(maxWidth: AgentChatLayout.chatContentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func trimmed(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct CalendarEventHero: View {
    var event: CalendarEvent
    var row: NativeCalendarEventRowPresentation?
    var calendarName: String?

    var body: some View {
        HStack(alignment: .top, spacing: AgentChatLayout.spaceM) {
            ZStack {
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
                Image(systemName: event.isAllDay ? "calendar" : "calendar.badge.clock")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                Text(event.title)
                    .font(.system(size: 24, weight: .semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                Text(primaryTimeText)
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack(spacing: AgentChatLayout.spaceS) {
                    CalendarStatusPill(status: event.isAllDay ? "全天" : "已排期", color: .orange, systemImage: event.isAllDay ? "sun.max" : "clock")
                    if let calendarName, !calendarName.isEmpty {
                        CalendarStatusPill(status: calendarName, color: .secondary, systemImage: "calendar")
                    }
                }

                if let location = row?.location ?? event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(AgentChatTypography.meta)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AgentChatLayout.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous).stroke(Color.secondary.opacity(AgentChatLayout.hairlineOpacity), lineWidth: 1))
    }

    private var primaryTimeText: String {
        if event.isAllDay {
            return event.start.date.formatted(date: .complete, time: .omitted)
        }
        let start = event.start.date.formatted(date: .complete, time: .shortened)
        let end = event.end.date.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}

private struct CalendarDetailSection<Content: View>: View {
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

private struct CalendarMetadataLine: View {
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

private struct CalendarMetadataLinkLine: View {
    var url: URL

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("链接")
                .font(AgentChatTypography.microEmphasis)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Link(destination: url) {
                HStack(spacing: 5) {
                    Text(url.absoluteString)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 10, weight: .semibold))
                }
                .font(AgentChatTypography.meta)
            }
        }
    }
}

private struct CalendarAttendeeRow: View {
    var attendee: CalendarAttendee

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AgentChatLayout.spaceS) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(AgentChatTypography.meta)
                    .textSelection(.enabled)
                if let email = attendee.email, !email.isEmpty, email != displayName {
                    Text(email)
                        .font(AgentChatTypography.micro)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 8)
            CalendarStatusPill(status: attendee.responseStatus.displayTitle, color: attendee.responseStatus.displayColor)
        }
    }

    private var displayName: String {
        if let name = attendee.name, !name.isEmpty { return name }
        if let email = attendee.email, !email.isEmpty { return email }
        return attendee.id.rawValue
    }
}

private struct CalendarStatusPill: View {
    var status: String
    var color: Color
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(status)
                .font(AgentChatTypography.microEmphasis)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.10), in: Capsule())
    }
}

private extension CalendarAttendeeResponseStatus {
    var displayTitle: String {
        switch self {
        case .needsAction: "待回应"
        case .accepted: "已接受"
        case .declined: "已拒绝"
        case .tentative: "暂定"
        case .delegated: "已委派"
        case .unknown: "未知"
        }
    }

    var displayColor: Color {
        switch self {
        case .accepted: .green
        case .declined: .red
        case .tentative, .delegated: .orange
        case .needsAction, .unknown: .secondary
        }
    }
}

struct ContactsSourceSettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Group {
            if let selected = selectedContactRow {
                VStack(alignment: .leading, spacing: AppShellLayout.spaceL) {
                    CalendarContactsDetailHeader(title: "联系人", subtitle: "轻量联系人数据源：列表和详情，不做 CRM。")
                    Divider().opacity(0.6)
                    VStack(alignment: .leading, spacing: AppShellLayout.spaceM) {
                        Label(selected.displayName, systemImage: "person.crop.circle")
                            .font(AgentChatTypography.title)
                        if let email = selected.primaryEmail {
                            Text(email).font(AgentChatTypography.meta).textSelection(.enabled)
                        }
                        if let organization = selected.organizationName {
                            Text(organization).font(AgentChatTypography.meta).foregroundStyle(.secondary)
                        }
                    }
                    .padding(AppShellLayout.spaceXL)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppShellColors.detailBackground)
    }

    private var selectedContactRow: NativeContactRowPresentation? {
        guard let id = viewModel.selectedContactID else { return nil }
        return viewModel.contactsBrowserPresentation.rows.first { $0.id == id }
    }
}

private struct CalendarContactsDetailHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppShellLayout.spaceXS) {
                Text(title).font(.system(size: 24, weight: .semibold))
                Text(subtitle).font(AgentChatTypography.meta).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, AppShellLayout.spaceXL)
        .padding(.vertical, AppShellLayout.spaceL)
    }
}

private struct TaskAutomationDetailPane: View {
    @ObservedObject var viewModel: AppViewModel
    var kind: TaskAutomationKind

    private var cards: [TaskManagementUICard] {
        kind.cards(from: viewModel.taskManagementPresentation)
    }

    private var selectedCard: TaskManagementUICard? {
        guard let selectedID = viewModel.selectedTaskAutomationID else { return nil }
        return cards.first { $0.id == selectedID }
    }

    var body: some View {
        Group {
            if let selectedCard {
                ScrollView {
                    VStack(alignment: .leading, spacing: AgentChatLayout.spaceL) {
                        TaskAutomationHero(card: selectedCard)
                        TaskAutomationDetailSection(title: "运行信息", systemImage: "clock.arrow.circlepath") {
                            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                                TaskAutomationMetadataLine(label: "下次", value: selectedCard.nextRunLabel.isEmpty ? "无" : selectedCard.nextRunLabel)
                                TaskAutomationMetadataLine(label: "上次", value: selectedCard.lastRunLabel.isEmpty ? "无" : selectedCard.lastRunLabel)
                                if !selectedCard.lastErrorLabel.isEmpty {
                                    TaskAutomationMetadataLine(label: "错误", value: selectedCard.lastErrorLabel, valueColor: .red)
                                }
                            }
                        }
                        TaskAutomationDetailSection(title: "目标", systemImage: "scope") {
                            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                                TaskAutomationMetadataLine(label: "目标", value: selectedCard.targetLabel)
                                if !selectedCard.rationaleLabel.isEmpty {
                                    TaskAutomationMetadataLine(label: "原因", value: selectedCard.rationaleLabel)
                                }
                            }
                        }
                        TaskAutomationDetailSection(title: "治理", systemImage: "shield.checkered") {
                            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                                TaskAutomationMetadataLine(label: "来源", value: selectedCard.originBadge)
                                TaskAutomationMetadataLine(label: "触发", value: selectedCard.triggerLabel)
                                TaskAutomationMetadataLine(label: "状态", value: selectedCard.statusLabel)
                                if let reason = selectedCard.deleteDisabledReason, !reason.isEmpty {
                                    TaskAutomationMetadataLine(label: "保护", value: reason)
                                }
                            }
                        }
                        TaskAutomationActionSection(card: selectedCard, viewModel: viewModel)
                    }
                    .padding(.horizontal, AgentChatLayout.spaceXL)
                    .padding(.vertical, AgentChatLayout.spaceL)
                    .frame(maxWidth: AgentChatLayout.chatContentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .scrollContentBackground(.hidden)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppShellColors.detailBackground)
        .task { viewModel.reloadTaskManagementPresentation() }
    }
}

private struct TaskAutomationHero: View {
    var card: TaskManagementUICard

    var body: some View {
        HStack(alignment: .top, spacing: AgentChatLayout.spaceM) {
            ZStack {
                RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous)
                    .fill(severityColor.opacity(0.12))
                Image(systemName: card.triggerLabel == "定时" ? "clock" : "dot.radiowaves.left.and.right")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(severityColor)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: AgentChatLayout.spaceS) {
                Text(card.title)
                    .font(.system(size: 24, weight: .semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Text(card.targetLabel)
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                HStack(spacing: AgentChatLayout.spaceS) {
                    TaskAutomationStatusPill(status: card.triggerLabel, color: severityColor, systemImage: card.triggerLabel == "定时" ? "clock" : "dot.radiowaves.left.and.right")
                    TaskAutomationStatusPill(status: card.statusLabel, color: statusColor)
                    TaskAutomationStatusPill(status: card.originBadge, color: .secondary, systemImage: "person.badge.key")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AgentChatLayout.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AgentChatLayout.radiusL, style: .continuous).stroke(Color.secondary.opacity(AgentChatLayout.hairlineOpacity), lineWidth: 1))
    }

    private var severityColor: Color {
        switch card.severity {
        case .info: .blue
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }

    private var statusColor: Color {
        switch card.statusLabel {
        case "active": .green
        case "stopped": .orange
        case "failed": .red
        default: .secondary
        }
    }
}

private struct TaskAutomationDetailSection<Content: View>: View {
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

private struct TaskAutomationMetadataLine: View {
    var label: String
    var value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(AgentChatTypography.microEmphasis)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(AgentChatTypography.meta)
                .foregroundStyle(valueColor)
                .textSelection(.enabled)
        }
    }
}

private struct TaskAutomationActionSection: View {
    var card: TaskManagementUICard
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        TaskAutomationDetailSection(title: "操作", systemImage: "slider.horizontal.3") {
            HStack(spacing: AgentChatLayout.spaceS) {
                if card.canStop {
                    TaskAutomationActionButton(title: "暂停", systemImage: "pause.fill") {
                        viewModel.stopTask(card.id)
                    }
                }
                if card.canRestore {
                    TaskAutomationActionButton(title: "恢复", systemImage: "play.fill") {
                        viewModel.restoreTask(card.id)
                    }
                }
                if card.canDelete {
                    TaskAutomationActionButton(title: "删除", systemImage: "trash", role: .destructive) {
                        viewModel.deleteTask(card.id)
                    }
                }
                if !card.canStop && !card.canRestore && !card.canDelete {
                    Text(card.deleteDisabledReason ?? "当前任务无需手动操作。")
                        .font(AgentChatTypography.meta)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct TaskAutomationActionButton: View {
    var title: String
    var systemImage: String
    var role: ButtonRole?
    var action: () -> Void

    init(title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(AgentChatTypography.microEmphasis)
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(title)
    }
}

private struct TaskAutomationStatusPill: View {
    var status: String
    var color: Color
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(status)
                .font(AgentChatTypography.microEmphasis)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.10), in: Capsule())
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
        let color = Self.attentionColor
        leadingBarColor = nil
        leadingBarWidth = 0
        shadowColor = .clear
        shadowRadius = 0

        guard level > .none else {
            dotColor = nil
            backgroundColor = isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .windowBackgroundColor)
            borderColor = Color.clear
            borderWidth = 0
            titleWeight = isSelected ? .semibold : .regular
            return
        }

        dotColor = level == .unread ? color : nil
        backgroundColor = level == .unread
            ? (isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .windowBackgroundColor))
            : color.opacity(level == .interruptive ? 0.14 : 0.10)
        borderColor = level == .unread ? Color.clear : color.opacity(level == .interruptive ? 0.42 : (isSelected ? 0.22 : 0.14))
        borderWidth = level == .interruptive ? 1.6 : (level >= .emphasized ? 1 : 0)
        titleWeight = level >= .actionable ? .bold : .semibold
        shadowColor = level == .interruptive ? color.opacity(0.18) : .clear
        shadowRadius = level == .interruptive ? 8 : 0
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
    @State private var isAttentionPulseOn: Bool = false
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
            .onAppear {
                titleDraft = row.title
            }
            .task(id: attentionPulseTaskID) {
                await runAttentionPulseLoop()
            }
            .onDisappear {
                resetAttentionPulse()
            }
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
        .shadow(color: cardStyle.shadowColor, radius: cardStyle.shadowRadius, x: 0, y: 2)
        .scaleEffect(attentionLevel == .interruptive && isAttentionPulseOn ? 1.012 : 1)
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
        } else if cardStyle.dotColor == nil {
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


            if row.kind == .note {
                HStack(spacing: 4) {
                    Text("📝 笔记")
                        .font(AppListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.10))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.accentColor.opacity(0.20), lineWidth: 1)
                        )
                }
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
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .frame(width: 18)
                .padding(.top, 5)
        }
    }

    private var usesFilledAttentionStyle: Bool {
        false
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
        guard shouldPulseAttention else { return cardStyle.backgroundColor }
        if attentionLevel == .interruptive {
            return ConnorCraftPalette.accent.opacity(isAttentionPulseOn ? 0.24 : 0.10)
        }
        return ConnorCraftPalette.accent.opacity(isAttentionPulseOn ? 0.18 : 0.07)
    }

    private var shouldPulseAttention: Bool {
        attentionLevel >= .emphasized
    }

    private var attentionPulseTaskID: String {
        shouldPulseAttention ? "\(row.id)-\(attentionLevel.rawValue)" : "\(row.id)-none"
    }

    @MainActor
    private func resetAttentionPulse() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isAttentionPulseOn = false
        }
    }

    @MainActor
    private func runAttentionPulseLoop() async {
        guard shouldPulseAttention else {
            resetAttentionPulse()
            return
        }

        resetAttentionPulse()

        while !Task.isCancelled && shouldPulseAttention {
            withAnimation(.easeInOut(duration: 0.9)) {
                isAttentionPulseOn.toggle()
            }

            do {
                try await Task.sleep(for: .milliseconds(900))
            } catch {
                break
            }
        }

        if !shouldPulseAttention || Task.isCancelled {
            resetAttentionPulse()
        }
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
