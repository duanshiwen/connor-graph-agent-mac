import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

enum SettingsListTypography {
    // Mirror the chat detail typography scale so settings feels like part of the
    // same macOS app. Apple HIG recommends preserving hierarchy with size,
    // weight, and color while keeping macOS body text legible around 13 pt+.
    static let header: Font = AgentChatTypography.title
    static let rowTitle: Font = AgentChatTypography.body
    static let rowTitleSelected: Font = AgentChatTypography.bodyEmphasis
    static let rowSubtitle: Font = AgentChatTypography.meta
    static let rowCaption: Font = AgentChatTypography.micro
    static let rowCaptionEmphasized: Font = AgentChatTypography.microEmphasis
    static let actionTitle: Font = AgentChatTypography.callout
    static let icon: Font = .system(size: AgentChatTypography.controlIconSize, weight: .medium)
    static let largeIcon: Font = .system(size: 22, weight: .semibold)
}

enum SettingsListLayout {
    static let spaceXS = AgentChatLayout.spaceXS
    static let spaceS = AgentChatLayout.spaceS
    static let spaceM = AgentChatLayout.spaceM
    static let spaceL = AgentChatLayout.spaceL
    static let spaceXL = AgentChatLayout.spaceXL

    static let radiusS = AgentChatLayout.radiusS
    static let radiusM = AgentChatLayout.radiusM
    static let radiusL = AgentChatLayout.radiusL
    static let hairlineOpacity = AgentChatLayout.hairlineOpacity

    static let contentMaxWidth = AgentChatLayout.chatContentMaxWidth
    static let formMaxWidth: CGFloat = 560
    static let rowMinHeight = AgentChatLayout.hitTargetSize
    static let compactRowMinHeight: CGFloat = 38
    static let prominentRowMinHeight: CGFloat = 58
    static let fieldHeight = AgentChatLayout.hitTargetSize
    static let pickerControlWidth: CGFloat = 260
    static let compactPickerControlWidth: CGFloat = 220
    static let iconButtonSize = AgentChatLayout.iconButtonSize
    static let optionIconSize = AgentChatLayout.primaryButtonSize
}

struct ConnorSettingsDetailView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(viewModel.selectedSettingsSection.title)
                    .font(SettingsListTypography.header)
                    .frame(maxWidth: .infinity, alignment: .center)

                Group {
                    switch viewModel.selectedSettingsSection {
                    case .app:
                        SettingsAppSection(viewModel: viewModel)
                    case .ai:
                        SettingsAISection(viewModel: viewModel)
                    case .calendar:
                        SettingsCalendarSection(viewModel: viewModel)
                    case .rss:
                        SettingsRSSSection(viewModel: viewModel)
                    case .mail:
                        MailSourceSettingsView(viewModel: viewModel)
                    case .permissions:
                        SettingsPermissionsSection(viewModel: viewModel)
                    case .labels:
                        SettingsLabelsSection(viewModel: viewModel)
                    case .statuses:
                        SettingsStatusesSection(viewModel: viewModel)
                    case .shortcuts:
                        SettingsShortcutsSection(viewModel: viewModel)
                    case .preferences:
                        SettingsPreferencesSection(viewModel: viewModel)
                    }
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .center)

                if let message = viewModel.settingsMessage(for: viewModel.selectedSettingsSection) {
                    Text(message)
                        .font(SettingsListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 760, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(SettingsListTypography.rowCaption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: 760, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 18)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.12))
        .task {
            viewModel.loadRuntimeSettings()
        }
    }
}

struct SettingsCalendarSection: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceL) {
            SettingsGroup(title: "日历能力") {
                SettingsValueRow(title: "定位", value: "独立日历数据源")
                SettingsValueRow(title: "已添加源", value: "\(viewModel.calendarAccounts.count) 个")
                SettingsValueRow(title: "日历", value: "\(viewModel.calendarCollections.count) 个")
                SettingsValueRow(title: "当前事件", value: "\(viewModel.calendarBrowserPresentation.eventCount) 个")
                Text("支持本机日历（EventKit）、ICS/Webcal 订阅、CalDAV（通用、iCloud、Fastmail、Nextcloud）只读同步。Google 和 Microsoft 365 将通过 OAuth 接入。所有日历源暂不支持事件写入。")
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: SettingsListLayout.spaceS) {
                    Button(action: { viewModel.syncSystemCalendar() }) {
                        Label(viewModel.isSyncingSystemCalendar ? "同步中…" : "同步本机日历", systemImage: "arrow.triangle.2.circlepath")
                            .font(SettingsListTypography.actionTitle)
                            .padding(.horizontal, SettingsListLayout.spaceM)
                            .padding(.vertical, SettingsListLayout.spaceXS)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isSyncingSystemCalendar)

                    Button(action: { viewModel.isPresentingAddCalendarSourceSheet = true }) {
                        Label("添加日历源", systemImage: "plus")
                            .font(SettingsListTypography.actionTitle)
                            .padding(.horizontal, SettingsListLayout.spaceM)
                            .padding(.vertical, SettingsListLayout.spaceXS)
                    }
                    .buttonStyle(.bordered)
                }
                if let message = viewModel.calendarSyncMessage {
                    Text(message)
                        .font(SettingsListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            SettingsGroup(title: "已添加日历源") {
                if viewModel.calendarAccounts.isEmpty {
                    Text("暂无日历源。点击“添加日历源”开始。")
                        .font(SettingsListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(viewModel.calendarAccounts) { account in
                        CalendarSourceSettingsRow(
                            account: account,
                            calendarCount: viewModel.calendarCollections.filter { $0.accountID == account.id }.count,
                            onDelete: { viewModel.deleteCalendarSource(account) }
                        )
                        if account.id != viewModel.calendarAccounts.last?.id {
                            Divider().opacity(0.6)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.isPresentingAddCalendarSourceSheet) {
            AddCalendarSourceSheet(viewModel: viewModel)
        }
    }
}

private struct CalendarSourceSettingsRow: View {
    var account: CalendarAccount
    var calendarCount: Int
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: SettingsListLayout.spaceM) {
            Image(systemName: iconName)
                .font(SettingsListTypography.largeIcon)
                .foregroundStyle(.orange)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(account.displayName)
                    .font(SettingsListTypography.rowTitle)
                Text("\(providerName) · \(calendarCount) 个日历 · \(account.health.summary)")
                    .font(SettingsListTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Label("删除", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("删除日历源")
            .accessibilityLabel("删除 \(account.displayName)")
        }
        .frame(minHeight: SettingsListLayout.prominentRowMinHeight)
    }

    private var providerName: String {
        switch account.provider {
        case .appleICloud: "Apple iCloud"
        case .microsoft365, .google: "已停止支持的旧账户"
        case .qq: "QQ"
        case .netEase: "网易"
        case .genericIMAPSMTP: "自定义 IMAP/SMTP"
        case .genericCalDAVCardDAV: "自定义 CalDAV / CardDAV"
        case .localFixture: "本机日历"
        }
    }

    private var iconName: String {
        switch account.provider {
        case .appleICloud: "icloud"
        case .microsoft365, .google: "exclamationmark.triangle"
        case .localFixture: "calendar"
        default: "calendar"
        }
    }
}

struct SettingsAppSection: View {
    @ObservedObject var viewModel: AppViewModel

    private var appVersionDisplay: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let shortVersion = (info["CFBundleShortVersionString"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let build = (info["CFBundleVersion"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (shortVersion?.isEmpty == false ? shortVersion : nil, build?.isEmpty == false ? build : nil) {
        case let (version?, build?):
            return "\(version) (\(build))"
        case let (version?, nil):
            return version
        case let (nil, build?):
            return "Build \(build)"
        default:
            return "开发版本"
        }
    }

    private var bundleIdentifierDisplay: String {
        Bundle.main.bundleIdentifier ?? "未知"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: "通知") {
                SettingsToggleRow(title: "桌面通知", subtitle: "允许会话新消息发送 macOS 通知。", isOn: $viewModel.desktopNotificationsEnabled)
                Divider()
                SettingsPickerRow(
                    title: "会话新消息",
                    subtitle: "Connor 当前只保留这一种通知语义：当不可见会话产生新消息时如何提醒。",
                    selection: $viewModel.sessionNewMessageNotificationLevel
                ) {
                    ForEach(SessionAttentionLevel.allCases) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                Divider()
                HStack {
                    Spacer()
                    Button(action: viewModel.resetSessionNotificationSettings) {
                        Label("恢复默认", systemImage: "arrow.counterclockwise")
                            .font(SettingsListTypography.rowCaptionEmphasized)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
            SettingsGroup(title: "电源") {
                SettingsToggleRow(title: "保持屏幕常亮", subtitle: "会话运行时防止屏幕关闭。", isOn: $viewModel.keepScreenAwake)
            }
            SettingsGroup(title: "输入") {
                SettingsToggleRow(
                    title: "会话页语音转文字",
                    subtitle: "在会话输入栏启用按住说话；关闭后置灰快捷录音入口并停止监听 Option 语音输入。",
                    isOn: $viewModel.sessionSpeechTranscriptionEnabled
                )
            }
            SettingsGroup(title: "搜索") {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("默认搜索引擎")
                            .font(SettingsListTypography.rowTitleSelected)
                        Text("浏览器地址栏关键词搜索和统一搜索框的 Web 搜索都会使用此搜索引擎。")
                            .font(SettingsListTypography.rowCaption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("默认搜索引擎", selection: $viewModel.defaultSearchEngine) {
                        ForEach(DefaultSearchEngine.allCases) { engine in
                            Text(engine.displayName).tag(engine)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.large)
                    .frame(width: SettingsListLayout.pickerControlWidth, alignment: .trailing)
                }
                .frame(minHeight: SettingsListLayout.rowMinHeight)
            }
            SettingsGroup(title: "页面显示主题") {
                SettingsAppearanceModeRow(selection: $viewModel.appearanceMode)
            }
            SettingsGroup(title: "网络") {
                SettingsToggleRow(title: "HTTP 代理", subtitle: "通过代理服务器路由网络流量。", isOn: $viewModel.httpProxyEnabled)
                if viewModel.httpProxyEnabled {
                    Divider()
                    SettingsTextFieldRow(title: "代理地址", subtitle: "例如 http://127.0.0.1:7890", text: $viewModel.httpProxyURLString)
                }
            }
            SettingsGroup(title: "关于") {
                SettingsValueRow(title: "当前版本", value: appVersionDisplay)
                Divider()
                SettingsValueRow(title: "应用标识", value: bundleIdentifierDisplay)
            }
        }
    }
}

struct SettingsRSSSection: View {
    @ObservedObject var viewModel: AppViewModel

    private var presentation: NativeRSSBrowserPresentation { viewModel.rssBrowserPresentation }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceXL) {
            sourceConnections
            fetchPolicy
        }
        .sheet(isPresented: $viewModel.isPresentingAddRSSSourceSheet) {
            AddRSSSourceSheet { feedURL, displayName in
                try await viewModel.addRSSSourceAndSync(feedURL: feedURL, displayName: displayName)
            }
        }
        .sheet(item: $viewModel.editingRSSSource) { source in
            AddRSSSourceSheet(source: source) { feedURL, displayName in
                try await viewModel.updateRSSSource(sourceID: source.id, feedURL: feedURL, displayName: displayName)
            }
        }
        .confirmationDialog(
            "删除 RSS 订阅源？",
            isPresented: Binding(
                get: { viewModel.pendingRSSSourceDeletion != nil },
                set: { if !$0 { viewModel.pendingRSSSourceDeletion = nil } }
            ),
            presenting: viewModel.pendingRSSSourceDeletion
        ) { source in
            Button("删除订阅源", role: .destructive) {
                viewModel.deleteRSSSource(source)
            }
            Button("取消", role: .cancel) {
                viewModel.pendingRSSSourceDeletion = nil
            }
        } message: { source in
            Text("将删除“\(source.displayName)”及其本地文章缓存。")
        }
    }

    private var sourceConnections: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceXL) {
            VStack(alignment: .leading, spacing: SettingsListLayout.spaceXS) {
                Text("订阅源")
                    .font(SettingsListTypography.header)
                Text("管理 RSS / Atom / JSON Feed 连接。")
                    .font(SettingsListTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
            }

            if !presentation.sources.isEmpty {
                VStack(spacing: 0) {
                    ForEach(presentation.sources) { source in
                        RSSSettingsSourceRow(
                            source: source,
                            unreadCount: presentation.unreadCount(sourceID: source.id),
                            onEdit: { viewModel.editingRSSSource = source },
                            onDelete: { viewModel.pendingRSSSourceDeletion = source }
                        )
                        if source.id != presentation.sources.last?.id { Divider().padding(.leading, 32) }
                    }
                }
                .padding(.horizontal, SettingsListLayout.spaceL)
                .padding(.vertical, SettingsListLayout.spaceS)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: SettingsListLayout.radiusL, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: SettingsListLayout.radiusL, style: .continuous).stroke(Color.secondary.opacity(SettingsListLayout.hairlineOpacity), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
            }

            Button(action: { viewModel.isPresentingAddRSSSourceSheet = true }) {
                Label("添加订阅源", systemImage: "plus")
                    .font(SettingsListTypography.actionTitle)
                    .padding(.horizontal, SettingsListLayout.spaceM)
                    .padding(.vertical, SettingsListLayout.spaceXS)
            }
            .buttonStyle(.bordered)
        }
    }

    private var fetchPolicy: some View {
        SettingsGroup(title: "抓取策略") {
            SettingsValueRow(title: "默认抓取间隔", value: "30 分钟")
            Divider()
            SettingsValueRow(title: "支持格式", value: "RSS 2.0 / Atom / JSON Feed")
            Divider()
            SettingsValueRow(title: "正文安全", value: "不执行脚本，不主动加载远程资源")
        }
    }

}

private struct RSSSettingsSourceRow: View {
    var source: RSSSource
    var unreadCount: Int
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: SettingsListLayout.spaceM) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(SettingsListTypography.icon)
                .foregroundStyle(statusColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(source.displayName)
                    .font(SettingsListTypography.rowTitleSelected)
                Text(source.feedURL.absoluteString)
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(unreadCount > 0 ? "\(unreadCount) 未读" : statusTitle)
                .font(SettingsListTypography.rowCaptionEmphasized)
                .foregroundStyle(statusColor)
            HStack(spacing: SettingsListLayout.spaceXS) {
                Button(action: onEdit) {
                    Label("修改", systemImage: "pencil")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("修改订阅源")
                .accessibilityLabel("修改 \(source.displayName)")

                Button(role: .destructive, action: onDelete) {
                    Label("删除", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("删除订阅源")
                .accessibilityLabel("删除 \(source.displayName)")
            }
        }
        .frame(minHeight: SettingsListLayout.prominentRowMinHeight, alignment: .center)
    }

    private var statusTitle: String {
        switch source.health.status {
        case .ready: "正常"
        case .degraded: "降级"
        case .blocked: "阻止"
        case .unknown: "未知"
        }
    }

    private var statusColor: Color {
        switch source.health.status {
        case .ready: .green
        case .degraded: .orange
        case .blocked: .red
        case .unknown: .secondary
        }
    }
}

struct SettingsAISection: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isShowingAddConnectionGuide = false
    @State private var setupOption: AIConnectionOnboardingOption?
    @State private var renamingConnection: AppLLMConnectionConfig?
    @State private var renameDraft = ""

    var body: some View {
        Group {
            if let setupOption {
                AIConnectionSetupView(
                    viewModel: viewModel,
                    option: setupOption,
                    complete: { addConnection(from: setupOption) },
                    back: { self.setupOption = nil },
                    cancel: {
                        self.setupOption = nil
                        isShowingAddConnectionGuide = false
                    }
                )
            } else if isShowingAddConnectionGuide {
                AIConnectionOnboardingView(
                    choose: beginConnectionSetup(from:),
                    cancel: { isShowingAddConnectionGuide = false }
                )
            } else {
                connectionList
            }
        }
        .alert("更改连接名称", isPresented: renameAlertBinding) {
            TextField("连接名称", text: $renameDraft)
            Button("取消", role: .cancel) {
                renamingConnection = nil
                renameDraft = ""
            }
            Button("保存") {
                commitConnectionRename()
            }
            .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("只会更改连接在列表中显示的名称，不会读取或修改已保存的 API Key。")
        }
    }

    private var connectionList: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceXL) {
            VStack(alignment: .leading, spacing: SettingsListLayout.spaceXS) {
                Text("连接")
                    .font(SettingsListTypography.header)
                Text("管理 AI 提供商连接。")
                    .font(SettingsListTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(viewModel.llmConnectionConfigs) { connection in
                    AIConnectionEntryRow(
                        connection: connection,
                        isDefault: connection.id == viewModel.llmDefaultConnectionID,
                        canDelete: viewModel.llmConnectionConfigs.count > 1,
                        select: { viewModel.selectDefaultLLMConnection(connection.id) },
                        makeDefault: { viewModel.selectDefaultLLMConnection(connection.id) },
                        rename: { beginConnectionRename(connection) },
                        delete: {
                            viewModel.selectDefaultLLMConnection(connection.id)
                            viewModel.deleteSelectedLLMConnection()
                        }
                    )
                    if connection.id != viewModel.llmConnectionConfigs.last?.id {
                        Divider()
                            .padding(.leading, 32)
                    }
                }
            }
            .padding(.horizontal, SettingsListLayout.spaceL)
            .padding(.vertical, SettingsListLayout.spaceS)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: SettingsListLayout.radiusL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsListLayout.radiusL, style: .continuous)
                    .stroke(Color.secondary.opacity(SettingsListLayout.hairlineOpacity), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)

            VStack(alignment: .leading, spacing: SettingsListLayout.spaceS) {
                Button(action: { isShowingAddConnectionGuide = true }) {
                    Label("添加连接", systemImage: "plus")
                        .font(SettingsListTypography.actionTitle)
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, SettingsListLayout.spaceM)
                        .padding(.vertical, SettingsListLayout.spaceXS)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Label("为保护 API Key 安全，我们暂时不支持编辑一个连接；如需更改，请删除后重建。", systemImage: "lock.shield")
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renamingConnection != nil },
            set: { isPresented in
                if !isPresented {
                    renamingConnection = nil
                    renameDraft = ""
                }
            }
        )
    }

    private func beginConnectionRename(_ connection: AppLLMConnectionConfig) {
        renamingConnection = connection
        renameDraft = connection.name
    }

    private func commitConnectionRename() {
        guard let connection = renamingConnection else { return }
        viewModel.renameLLMConnection(connection.id, name: renameDraft)
        renamingConnection = nil
        renameDraft = ""
    }

    private func beginConnectionSetup(from option: AIConnectionOnboardingOption) {
        setupOption = option
    }

    private func addConnection(from option: AIConnectionOnboardingOption) {
        setupOption = nil
        isShowingAddConnectionGuide = false
    }
}

enum AIConnectionAuthenticationKind: Equatable {
    case browserCallback
    case deviceCode(code: String, verificationURL: String)
    case direct
}

enum AIConnectionCustomProtocol: String, CaseIterable, Equatable {
    case openAICompatible
    case anthropicCompatible

    var title: String {
        switch self {
        case .openAICompatible: "OpenAI Compatible"
        case .anthropicCompatible: "Anthropic Compatible"
        }
    }

    var modelValidationEndpointDescription: String {
        switch self {
        case .openAICompatible: "OpenAI 兼容连接测试"
        case .anthropicCompatible: "Anthropic 兼容连接测试"
        }
    }
}

struct AIConnectionProviderPreset: Identifiable, Equatable {
    var id: String
    var title: String
    var endpoint: String
    var defaultModel: String
    var supportedModels: [String] = []
    var keyPlaceholder: String
    var protocolKind: AIConnectionCustomProtocol
    var authHeaderKind: AnthropicCompatibleAuthHeaderKind = .xAPIKey
    var openAIAPIKeyHeaderKind: OpenAICompatibleAPIKeyHeaderKind = .bearer
    var hidesEndpoint: Bool = false
    /// Models in this list default to vision support enabled (explicitVisionSupport = true) when selected.
    var defaultVisionModels: [String] = []

    var availableModels: [String] {
        if !supportedModels.isEmpty { return supportedModels }
        return defaultModel.isEmpty ? [] : [defaultModel]
    }

    static let chinaProviderPresetIDs: Set<String> = [
        "deepseek", "xiaomi-mimo", "qwen", "doubao", "moonshot", "zhipu", "minimax", "stepfun", "zai"
    ]

    static var chinaProviderPresets: [AIConnectionProviderPreset] {
        otherProviderPresets.filter { chinaProviderPresetIDs.contains($0.id) }
    }

    static let otherProviderPresets: [AIConnectionProviderPreset] = [
        AIConnectionProviderPreset(id: "openai", title: "OpenAI", endpoint: "https://api.openai.com/v1", defaultModel: "gpt-4o-mini", keyPlaceholder: "sk-...", protocolKind: .openAICompatible, hidesEndpoint: true),
        AIConnectionProviderPreset(id: "openai-eu", title: "OpenAI EU", endpoint: "https://eu.api.openai.com/v1", defaultModel: "gpt-4o-mini", keyPlaceholder: "sk-...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "openai-us", title: "OpenAI US", endpoint: "https://us.api.openai.com/v1", defaultModel: "gpt-4o-mini", keyPlaceholder: "sk-...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "google", title: "Google AI Studio", endpoint: "https://generativelanguage.googleapis.com/v1beta/openai", defaultModel: "gemini-2.5-flash", keyPlaceholder: "AIza...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "openrouter", title: "OpenRouter", endpoint: "https://openrouter.ai/api/v1", defaultModel: "openai/gpt-4o-mini", keyPlaceholder: "sk-or-...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "groq", title: "Groq", endpoint: "https://api.groq.com/openai/v1", defaultModel: "llama-3.3-70b-versatile", keyPlaceholder: "gsk_...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "mistral", title: "Mistral", endpoint: "https://api.mistral.ai/v1", defaultModel: "mistral-large-latest", keyPlaceholder: "Paste your key here...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "deepseek", title: "DeepSeek", endpoint: "https://api.deepseek.com", defaultModel: "deepseek-v4-flash", supportedModels: ["deepseek-v4-flash", "deepseek-v4-pro"], keyPlaceholder: "sk-...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "xiaomi-mimo", title: "Xiaomi MiMo", endpoint: "https://api.xiaomimimo.com/v1", defaultModel: "mimo-v2.5-pro", supportedModels: ["mimo-v2.5-pro", "mimo-v2.5", "mimo-v2.5-asr", "mimo-v2.5-tts-voiceclone", "mimo-v2.5-tts-voicedesign", "mimo-v2.5-tts", "mimo-v2-pro", "mimo-v2-omni", "mimo-v2-tts"], keyPlaceholder: "MIMO_API_KEY", protocolKind: .openAICompatible, openAIAPIKeyHeaderKind: .apiKey, defaultVisionModels: ["mimo-v2.5", "mimo-v2-omni"]),
        AIConnectionProviderPreset(id: "qwen", title: "阿里百炼 · Qwen", endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1", defaultModel: "qwen-plus", supportedModels: ["qwen-plus", "qwen-max", "qwen-turbo", "qwen-long", "qwen3.5-plus", "qwen3.5-flash", "qwen3-max", "qwen3-coder-plus", "qwen3-vl-plus", "qwen3-vl-flash", "qwen3-omni-flash", "qwen3-asr-flash", "qwen3-tts-flash", "qwen-image-plus", "qwen-image-edit"], keyPlaceholder: "sk-...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "doubao", title: "火山方舟 · 豆包", endpoint: "https://ark.cn-beijing.volces.com/api/v3", defaultModel: "doubao-seed-1-6", supportedModels: ["doubao-seed-1-6", "doubao-seed-1-6-thinking", "doubao-seed-1-6-flash", "doubao-seed-1-6-vision", "doubao-seed-1-6-embedding", "doubao-1-5-pro-32k"], keyPlaceholder: "Paste your ARK_API_KEY...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "moonshot", title: "Moonshot · Kimi", endpoint: "https://api.moonshot.cn/v1", defaultModel: "kimi-k2.6", supportedModels: ["kimi-k2.7-code", "kimi-k2.7-code-highspeed", "kimi-k2.6", "kimi-k2.5", "moonshot-v1-8k", "moonshot-v1-32k", "moonshot-v1-128k", "moonshot-v1-8k-vision-preview", "moonshot-v1-32k-vision-preview", "moonshot-v1-128k-vision-preview"], keyPlaceholder: "sk-...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "zhipu", title: "智谱 GLM", endpoint: "https://open.bigmodel.cn/api/paas/v4", defaultModel: "glm-5.1", supportedModels: ["glm-5.2", "glm-5.1", "glm-5", "glm-5-turbo", "glm-4.7", "glm-4.7-flashx", "glm-4.6", "glm-4.5", "glm-4.5-air", "glm-4.5-airx", "glm-4-long", "glm-4-flashx-250414", "glm-4.7-flash", "glm-4.5-flash", "glm-4-flash-250414", "glm-4-plus", "glm-4-flash", "glm-z1-air", "glm-4.5v", "glm-5v-turbo", "glm-4.6v", "glm-ocr", "glm-realtime", "glm-4-voice", "glm-tts", "glm-tts-clone", "glm-asr-2512", "embedding-2"], keyPlaceholder: "Paste your key here...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "minimax", title: "MiniMax", endpoint: "https://api.minimax.chat/v1", defaultModel: "MiniMax-M3", supportedModels: ["MiniMax-M3", "MiniMax-M2.7", "MiniMax-M2.7-highspeed", "MiniMax-M2.5", "MiniMax-M2.5-highspeed", "MiniMax-M2.1", "MiniMax-M2.1-highspeed", "MiniMax-M2", "M2-her", "MiniMax-M1", "MiniMax-Text-01", "MiniMax-VL-01", "abab6.5s-chat", "abab6.5g-chat", "abab6.5t-chat"], keyPlaceholder: "Paste your key here...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "stepfun", title: "阶跃星辰 StepFun", endpoint: "https://api.stepfun.com/v1", defaultModel: "step3.7-flash", supportedModels: ["step3.7-flash", "step3.5-flash", "step-2-mini", "step-2-16k", "step-1-8k", "step-1-32k", "step-1-128k"], keyPlaceholder: "Paste your key here...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "xai", title: "xAI (Grok)", endpoint: "https://api.x.ai/v1", defaultModel: "grok-3-mini", keyPlaceholder: "xai-...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "cerebras", title: "Cerebras", endpoint: "https://api.cerebras.ai/v1", defaultModel: "llama3.1-8b", keyPlaceholder: "csk-...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "zai", title: "z.ai (GLM)", endpoint: "https://api.z.ai/api/paas/v4", defaultModel: "glm-4.5", supportedModels: ["glm-4.5", "glm-4.5-air", "glm-4.5-flash", "glm-4-plus", "glm-4-flash"], keyPlaceholder: "Paste your key here...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "huggingface", title: "Hugging Face", endpoint: "https://router.huggingface.co/v1", defaultModel: "openai/gpt-oss-120b", keyPlaceholder: "hf_...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "anthropic", title: "Anthropic API", endpoint: "https://api.anthropic.com", defaultModel: "claude-sonnet-4-5", keyPlaceholder: "sk-ant-...", protocolKind: .anthropicCompatible, authHeaderKind: .xAPIKey),
        AIConnectionProviderPreset(id: "openrouter-anthropic", title: "OpenRouter · Anthropic", endpoint: "https://openrouter.ai/api/v1", defaultModel: "anthropic/claude-sonnet-4.5", keyPlaceholder: "sk-or-...", protocolKind: .openAICompatible, openAIAPIKeyHeaderKind: .bearer),
        AIConnectionProviderPreset(id: "vercel-anthropic", title: "Vercel AI Gateway · Anthropic", endpoint: "https://ai-gateway.vercel.sh/v1", defaultModel: "anthropic/claude-sonnet-4", keyPlaceholder: "vck_...", protocolKind: .anthropicCompatible, authHeaderKind: .bearer),
        AIConnectionProviderPreset(id: "custom", title: "Custom", endpoint: "", defaultModel: "", keyPlaceholder: "Paste your key here...", protocolKind: .openAICompatible)
    ]
}

struct AIConnectionOnboardingOption: Identifiable, Equatable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var tint: Color
    var providerMode: AppLLMProviderMode
    var connectionName: String
    var baseURLString: String
    var model: String
    var selectedModel: String
    var supportedModels: [String] = []
    var setupTitle: String
    var setupSubtitle: String
    var setupInstruction: String
    var loginButtonTitle: String
    var authURLString: String
    var authenticationKind: AIConnectionAuthenticationKind

    var requiresWebAuthentication: Bool { authenticationKind != .direct }

    var modelOptionsFallback: [String] {
        if !supportedModels.isEmpty { return supportedModels }
        let parsed = model.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !parsed.isEmpty { return parsed }
        return selectedModel.isEmpty ? [] : [selectedModel]
    }

    static let all: [AIConnectionOnboardingOption] = [
        AIConnectionOnboardingOption(
            id: "deepseek",
            title: "DeepSeek",
            subtitle: "使用 DeepSeek API，适合国内开发、Agent 和高性价比推理。",
            systemImage: "bolt.horizontal.circle",
            tint: .blue,
            providerMode: .openAICompatible,
            connectionName: "DeepSeek",
            baseURLString: "https://api.deepseek.com",
            model: "deepseek-v4-flash",
            selectedModel: "deepseek-v4-flash",
            supportedModels: ["deepseek-v4-flash", "deepseek-v4-pro"],
            setupTitle: "连接 DeepSeek",
            setupSubtitle: "使用 DeepSeek OpenAI Compatible API 驱动康纳同学。",
            setupInstruction: "选择 DeepSeek 模型并填写 API Key。接口地址已按官方文档预设。",
            loginButtonTitle: "继续",
            authURLString: "",
            authenticationKind: .direct
        ),
        AIConnectionOnboardingOption(
            id: "xiaomi-mimo",
            title: "Xiaomi MiMo",
            subtitle: "使用小米 MiMo API，专为 Agent 与软件工程模型场景准备。",
            systemImage: "sparkle.magnifyingglass",
            tint: .orange,
            providerMode: .openAICompatible,
            connectionName: "Xiaomi MiMo",
            baseURLString: "https://api.xiaomimimo.com/v1",
            model: "mimo-v2.5-pro",
            selectedModel: "mimo-v2.5-pro",
            supportedModels: ["mimo-v2.5-pro", "mimo-v2.5", "mimo-v2.5-asr", "mimo-v2.5-tts-voiceclone", "mimo-v2.5-tts-voicedesign", "mimo-v2.5-tts", "mimo-v2-pro", "mimo-v2-omni", "mimo-v2-tts"],
            setupTitle: "连接 Xiaomi MiMo",
            setupSubtitle: "使用小米 MiMo OpenAI Compatible API 驱动康纳同学。",
            setupInstruction: "选择 MiMo 使用方式、模型并填写对应 API Key。sk-... 使用按量付费 endpoint；tp-... 使用 Token Plan endpoint。",
            loginButtonTitle: "继续",
            authURLString: "",
            authenticationKind: .direct
        ),
        AIConnectionOnboardingOption(
            id: "china-provider",
            title: "中国常用模型",
            subtitle: "接入 Qwen、豆包、Kimi、GLM、MiniMax、阶跃等国内常用 API。",
            systemImage: "globe.asia.australia",
            tint: .red,
            providerMode: .openAICompatible,
            connectionName: "阿里百炼 · Qwen",
            baseURLString: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            model: "qwen-plus",
            selectedModel: "qwen-plus",
            setupTitle: "连接中国常用模型",
            setupSubtitle: "从国内常用模型 API 中选择一个兼容服务。",
            setupInstruction: "选择服务商和模型并填写 API Key。接口地址已按常用兼容服务预设。",
            loginButtonTitle: "继续",
            authURLString: "",
            authenticationKind: .direct
        ),
        AIConnectionOnboardingOption(
            id: "openai-responses-api",
            title: "OpenAI API",
            subtitle: "使用 OpenAI API Key 通过 Connor 原生 Responses 管线驱动康纳同学。",
            systemImage: "sparkles",
            tint: .primary,
            providerMode: .openAIResponses,
            connectionName: "OpenAI Responses",
            baseURLString: "https://api.openai.com/v1",
            model: "gpt-4.1",
            selectedModel: "gpt-4.1",
            setupTitle: "连接 OpenAI API",
            setupSubtitle: "使用 API Key 连接 OpenAI Responses API。",
            setupInstruction: "填写 OpenAI API Key、接口地址和模型名称。康纳同学会用这组信息连接模型服务。",
            loginButtonTitle: "验证并添加连接",
            authURLString: "https://platform.openai.com/api-keys",
            authenticationKind: .direct
        ),
        AIConnectionOnboardingOption(
            id: "anthropic-claude-api",
            title: "Anthropic / Claude API",
            subtitle: "使用 Anthropic API Key 通过 Connor 原生 Messages 管线驱动康纳同学。",
            systemImage: "sparkles.rectangle.stack",
            tint: .orange,
            providerMode: .anthropicMessages,
            connectionName: "Anthropic / Claude",
            baseURLString: "https://api.anthropic.com/v1",
            model: "claude-sonnet-4-5",
            selectedModel: "claude-sonnet-4-5",
            setupTitle: "连接 Anthropic / Claude",
            setupSubtitle: "使用 API Key 连接 Claude。",
            setupInstruction: "填写 Anthropic API Key、接口地址和模型名称。康纳同学会用这组信息连接模型服务。",
            loginButtonTitle: "验证并添加连接",
            authURLString: "https://console.anthropic.com/settings/keys",
            authenticationKind: .direct
        ),
        AIConnectionOnboardingOption(
            id: "codex-chatgpt-plus",
            title: "Codex · ChatGPT Plus",
            subtitle: "已经有 ChatGPT Plus？用 Codex 模式连接康纳同学。",
            systemImage: "sparkles",
            tint: .primary,
            providerMode: .openAICompatible,
            connectionName: "Codex · ChatGPT Plus",
            baseURLString: "https://api.openai.com/v1",
            model: "gpt-4o-mini",
            selectedModel: "gpt-4o-mini",
            setupTitle: "连接 ChatGPT",
            setupSubtitle: "使用 ChatGPT Plus 订阅驱动康纳同学。",
            setupInstruction: "点击下方按钮使用 OpenAI 账号登录。登录完成后，康纳同学会自动验证并保存连接。",
            loginButtonTitle: "使用 ChatGPT 登录",
            authURLString: "https://auth.openai.com/oauth/authorize",
            authenticationKind: .browserCallback
        ),
        AIConnectionOnboardingOption(
            id: "github-copilot",
            title: "GitHub Copilot",
            subtitle: "已经有 GitHub Copilot？用它作为康纳同学的模型入口。",
            systemImage: "face.smiling.inverse",
            tint: .primary,
            providerMode: .openAICompatible,
            connectionName: "GitHub Copilot",
            baseURLString: "",
            model: "gpt-4.1",
            selectedModel: "gpt-4.1",
            setupTitle: "连接 GitHub Copilot",
            setupSubtitle: "使用 GitHub Copilot 订阅驱动康纳同学。",
            setupInstruction: "在 GitHub 页面输入此代码以授权。系统默认浏览器会打开 github.com/login/device。",
            loginButtonTitle: "打开 GitHub 授权页",
            authURLString: "https://github.com/login/device",
            authenticationKind: .deviceCode(code: "B3D1-87D5", verificationURL: "https://github.com/login/device")
        ),
        AIConnectionOnboardingOption(
            id: "other-provider",
            title: "使用其他提供商",
            subtitle: "接入 Anthropic、AWS Bedrock、OpenRouter、Google 或其他兼容服务。",
            systemImage: "key",
            tint: .secondary,
            providerMode: .openAICompatible,
            connectionName: "其他提供商",
            baseURLString: "https://api.openai.com/v1",
            model: "gpt-4o-mini",
            selectedModel: "gpt-4o-mini",
            setupTitle: "连接其他提供商",
            setupSubtitle: "接入 Anthropic、AWS Bedrock、OpenRouter、Google 或其他兼容服务。",
            setupInstruction: "下一步将填写接口地址、模型和 API Key。",
            loginButtonTitle: "继续",
            authURLString: "",
            authenticationKind: .direct
        ),
        AIConnectionOnboardingOption(
            id: "local-model",
            title: "本地模型",
            subtitle: "通过 Ollama 等本地服务，让康纳同学在你的电脑上运行模型。",
            systemImage: "desktopcomputer",
            tint: .secondary,
            providerMode: .openAICompatible,
            connectionName: "本地模型",
            baseURLString: "http://localhost:11434/v1",
            model: "llama3.2",
            selectedModel: "llama3.2",
            setupTitle: "连接本地模型",
            setupSubtitle: "通过 Ollama 等本地服务，让康纳同学在你的电脑上运行模型。",
            setupInstruction: "下一步将检查本地模型服务地址。",
            loginButtonTitle: "继续",
            authURLString: "",
            authenticationKind: .direct
        )
    ]
}

struct AIConnectionSetupView: View {
    @ObservedObject var viewModel: AppViewModel
    var option: AIConnectionOnboardingOption
    var complete: () -> Void
    var back: () -> Void
    var cancel: () -> Void

    @State private var didOpenBrowser = false
    @State private var isAuthenticating = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var githubDeviceCode: AppLLMGitHubDeviceCode?
    @State private var connectionName = ""
    @State private var baseURLString = ""
    @State private var model = ""
    @State private var selectedModel = ""
    @State private var selectedModelIDs: Set<String> = []
    @State private var apiKey = ""
    @State private var showAPIKey = false
    @State private var selectedProviderPresetID = "openai"
    @State private var customProtocol: AIConnectionCustomProtocol = .openAICompatible
    @State private var xiaomiMiMoConnectionMode: XiaomiMiMoConnectionModePreset = .payAsYouGo
    @State private var showsAdvancedConnectionSettings = false
    @State private var visionSupportOverride: Bool? = nil // nil = auto-detect, true = force enable, false = force disable

    var body: some View {
        ScrollView {
            VStack(spacing: SettingsListLayout.spaceXL) {
                setupHero

                setupContent
                    .frame(maxWidth: SettingsListLayout.formMaxWidth)

                setupFeedback

                setupActionBar
                    .frame(maxWidth: SettingsListLayout.formMaxWidth)
            }
            .padding(.top, 56)
            .padding(.bottom, 72)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 760)
        .onAppear(perform: initializeDrafts)
    }

    private var setupHero: some View {
        VStack(spacing: SettingsListLayout.spaceM) {
            ZStack {
                Circle()
                    .fill(option.tint.opacity(0.12))
                    .frame(width: 58, height: 58)
                Image(systemName: option.systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(option.tint)
            }
            .accessibilityHidden(true)

            VStack(spacing: SettingsListLayout.spaceS) {
                Text(option.setupTitle)
                    .font(SettingsListTypography.header)
                    .multilineTextAlignment(.center)
                Text(option.setupSubtitle)
                    .font(SettingsListTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: SettingsListLayout.formMaxWidth)
    }

    @ViewBuilder
    private var setupFeedback: some View {
        if let statusMessage {
            Text(statusMessage)
                .font(SettingsListTypography.rowSubtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: SettingsListLayout.formMaxWidth)
        }

        if let errorMessage {
            Text(errorMessage)
                .font(SettingsListTypography.rowSubtitle)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SettingsListLayout.spaceL)
                .padding(.vertical, SettingsListLayout.spaceM)
                .frame(maxWidth: SettingsListLayout.formMaxWidth)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: SettingsListLayout.radiusM, style: .continuous))
        }
    }

    private var setupActionBar: some View {
        HStack(spacing: SettingsListLayout.spaceL) {
            Button(action: back) {
                Text("返回")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button(action: primaryAction) {
                Label(primaryButtonTitle, systemImage: primaryButtonIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(isPrimaryButtonDisabled || isAuthenticating)
        }
        .padding(SettingsListLayout.spaceS)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SettingsListLayout.radiusL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsListLayout.radiusL, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var setupContent: some View {
        switch option.authenticationKind {
        case .browserCallback:
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(option.tint)
                    Text(option.setupInstruction)
                        .font(SettingsListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                if didOpenBrowser {
                    Text("系统默认浏览器已打开。完成网页认证后，康纳同学会自动验证并保存连接。")
                        .font(SettingsListTypography.header)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        case .deviceCode:
            VStack(spacing: 24) {
                Text(option.setupInstruction)
                    .font(SettingsListTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if option.id == "github-copilot" {
                    githubCopilotAutomaticConfigurationSummary
                } else {
                    openAICompatibleFields(includeAPIKey: false)
                }
                if let githubDeviceCode {
                    Text(githubDeviceCode.userCode)
                        .font(.system(size: 38, weight: .bold, design: .monospaced))
                        .kerning(4)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 18)
                        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
                        )
                        .textSelection(.enabled)
                    Text(didOpenBrowser ? "系统默认浏览器已打开 \(displayURL(githubDeviceCode.verificationURI))" : "点击下方按钮用系统默认浏览器打开 \(displayURL(githubDeviceCode.verificationURI))")
                        .font(SettingsListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                } else {
                    Text("点击下方按钮获取 GitHub 授权码。")
                        .font(SettingsListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                }
            }
        case .direct:
            if usesAPIKeyFirstPresetFlow {
                presetProviderAPIKeyFirstFields
            } else if option.id == "other-provider" {
                otherProviderAPIFields
            } else {
                directConnectionFields(includeAPIKey: true)
            }
        }
    }

    private func directConnectionFields(includeAPIKey: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            aiConnectionInstructionCard
            aiConnectionCard {
                VStack(alignment: .leading, spacing: SettingsListLayout.spaceL) {
                    aiConnectionSettingsRow(title: "连接名称") {
                        aiConnectionTextField(option.connectionName, text: $connectionName)
                    }
                    aiConnectionSettingsRow(title: "接口地址", help: localEndpointHelpText) {
                        aiConnectionTextField("http://localhost:11434/v1", text: $baseURLString)
                    }
                    aiConnectionSettingsRow(title: "模型", help: modelFieldHelpText) {
                        aiConnectionTextField("llama3.2", text: $model)
                    }
                    aiConnectionSettingsRow(title: "默认模型", help: "默认模型用于新会话默认选择；连接校验始终使用模型列表中的第一个有效模型。") {
                        aiConnectionTextField("llama3.2", text: $selectedModel)
                    }
                    if includeAPIKey {
                        aiConnectionSettingsRow(title: "API Key", help: apiKeyHelpText) {
                            apiKeyInput(placeholder: option.id == "local-model" ? "本地模型可留空" : "API Key")
                        }
                    }
                }
            }
        }
    }

    private var aiConnectionInstructionCard: some View {
        HStack(alignment: .top, spacing: SettingsListLayout.spaceM) {
            Image(systemName: "checklist.checked")
                .font(SettingsListTypography.largeIcon)
                .foregroundStyle(option.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(option.setupInstruction)
                    .font(SettingsListTypography.rowTitleSelected)
                    .foregroundStyle(.primary)
                Text("按 Tab 键会依次移动到下一个字段；验证成功后，凭据只保存到本机。")
                    .font(SettingsListTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SettingsListLayout.spaceL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppShellColors.hairline, lineWidth: 1))
    }

    private var localEndpointHelpText: String {
        if option.id == "local-model" {
            return "Ollama 默认地址通常是 http://localhost:11434/v1；本地回环地址允许不填写 API Key。"
        }
        return "填写兼容服务的 /v1 endpoint。"
    }

    private var apiKeyHelpText: String {
        if option.id == "local-model" {
            return "本地模型通常可以留空；如果你的本地网关启用了认证，再填写对应 Key。"
        }
        return "API Key 会保存到本机 credential store，不会写入普通配置文件。"
    }

    private var githubCopilotAutomaticConfigurationSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(option.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("自动配置 GitHub Copilot")
                        .font(SettingsListTypography.header)
                    Text("授权成功后，康纳同学会自动选择正确的连接地址，不需要手动填写接口地址或 API Key。")
                        .font(SettingsListTypography.rowTitle)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                Text("连接名称")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(connectionName)
            }
            HStack {
                Text("连接地址")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("由 Copilot 授权自动派生")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("默认模型")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? model : selectedModel)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private var presetProviderAPIKeyFirstFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            providerSummaryCard

            if option.id == "china-provider" || option.id == "other-provider" {
                presetProviderPickerRow
            }

            if isXiaomiMiMoOption {
                xiaomiMiMoConnectionModeCard
            }

            primaryAPIKeyEntryCard(placeholder: apiKeyPlaceholderForCurrentPreset)

            advancedConnectionDisclosure
        }
    }

    private var advancedConnectionDisclosure: some View {
        DisclosureGroup(isExpanded: $showsAdvancedConnectionSettings) {
            VStack(alignment: .leading, spacing: SettingsListLayout.spaceM) {
                aiConnectionSettingsRow(title: "连接名称") {
                    aiConnectionTextField("Anthropic / Claude", text: $connectionName)
                }
                aiConnectionSettingsRow(title: "接口地址") {
                    aiConnectionTextField("https://api.example.com/v1", text: $baseURLString)
                }
                aiConnectionSettingsRow(title: "模型") {
                    aiConnectionTextField("claude-sonnet-4-5", text: $model)
                }
                aiConnectionSettingsRow(title: "默认模型", help: "默认模型用于新会话默认选择；连接校验始终使用模型列表中的第一个有效模型。") {
                    aiConnectionTextField("claude-sonnet-4-5", text: $selectedModel)
                }
                aiConnectionSettingsRow(title: "视觉输入", help: "默认自动检测模型是否支持图片。如果自动检测不准（如新模型），可手动覆盖。") {
                    aiConnectionInputContainer {
                        Picker("视觉输入", selection: $visionSupportOverride) {
                            Text("自动检测").tag(nil as Bool?)
                            Text("强制开启").tag(true as Bool?)
                            Text("强制关闭").tag(false as Bool?)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }
                }
            }
            .padding(.top, SettingsListLayout.spaceM)
        } label: {
            Text("高级设置（通常不需要修改）")
                .font(SettingsListTypography.rowTitleSelected)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, SettingsListLayout.spaceL)
        .padding(.vertical, SettingsListLayout.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppShellColors.hairline, lineWidth: 1))
    }

    private var providerSummaryCard: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceM) {
            HStack(alignment: .top, spacing: SettingsListLayout.spaceM) {
                Image(systemName: option.systemImage)
                    .font(SettingsListTypography.largeIcon)
                    .foregroundStyle(option.tint)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(connectionName)
                        .font(SettingsListTypography.rowTitleSelected)
                    Text("已为你预设接口地址和兼容模式；首次验证会使用推荐模型，通常只需要填写 API Key。")
                        .font(SettingsListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider().opacity(0.6)

            providerSummaryRow(title: "接口地址", value: baseURLString)
            providerSummaryRow(title: "默认模型", value: selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? model : selectedModel)
            providerSummaryRow(title: "兼容模式", value: compatibilitySummaryTitle)
        }
        .padding(SettingsListLayout.spaceL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppShellColors.hairline, lineWidth: 1))
    }

    private func providerSummaryRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsListLayout.spaceM) {
            Text(title)
                .font(SettingsListTypography.rowCaptionEmphasized)
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .leading)
            Text(value.isEmpty ? "未设置" : value)
                .font(SettingsListTypography.rowCaption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private var xiaomiMiMoConnectionModeCard: some View {
        aiConnectionCard {
            VStack(alignment: .leading, spacing: SettingsListLayout.spaceM) {
                HStack(spacing: SettingsListLayout.spaceS) {
                    Image(systemName: "switch.2")
                        .foregroundStyle(option.tint)
                    Text("使用方式")
                        .font(SettingsListTypography.header)
                }

                Picker("使用方式", selection: $xiaomiMiMoConnectionMode) {
                    ForEach(XiaomiMiMoConnectionModePreset.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.large)
                .onChange(of: xiaomiMiMoConnectionMode) { _, _ in applyXiaomiMiMoConnectionMode() }

                Text(xiaomiMiMoConnectionMode.subtitle)
                    .font(SettingsListTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("当前接口地址：\(xiaomiMiMoConnectionMode.openAIEndpoint)")
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func primaryAPIKeyEntryCard(placeholder: String) -> some View {
        aiConnectionCard {
            VStack(alignment: .leading, spacing: SettingsListLayout.spaceM) {
                HStack(spacing: SettingsListLayout.spaceS) {
                    Image(systemName: "key")
                        .foregroundStyle(option.tint)
                    Text("API Key")
                        .font(SettingsListTypography.header)
                }
                apiKeyInput(placeholder: placeholder)
                Text(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "填写 API Key 后即可验证并添加连接。" : "API Key 只会保存到本机 credential store，不会写入普通配置文件。")
                    .font(SettingsListTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let warning = xiaomiMiMoKeyEndpointMismatchWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(SettingsListTypography.rowSubtitle)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func aiConnectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(SettingsListLayout.spaceL)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(AppShellColors.hairline, lineWidth: 1))
    }

    private var presetProviderPickerRow: some View {
        aiConnectionSettingsRow(title: "服务商") {
            Picker("服务商", selection: $selectedProviderPresetID) {
                ForEach(option.id == "china-provider" ? chinaProviderPresets : AIConnectionProviderPreset.otherProviderPresets) { preset in
                    Text(preset.title).tag(preset.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.large)
            .frame(width: SettingsListLayout.pickerControlWidth, alignment: .leading)
            .onChange(of: selectedProviderPresetID) { _, _ in applySelectedProviderPreset() }
        }
    }

    private var curatedChinaProviderAPIFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(option.setupInstruction)
                .font(SettingsListTypography.rowSubtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            HStack(alignment: .center, spacing: SettingsListLayout.spaceL) {
                Text("服务商")
                    .font(SettingsListTypography.header)
                Spacer(minLength: SettingsListLayout.spaceL)
                Picker("服务商", selection: $selectedProviderPresetID) {
                    ForEach(chinaProviderPresets) { preset in
                        Text(preset.title).tag(preset.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.large)
                .frame(width: SettingsListLayout.pickerControlWidth, alignment: .trailing)
                .onChange(of: selectedProviderPresetID) { _, _ in applySelectedProviderPreset() }
            }
            .frame(maxWidth: .infinity, minHeight: SettingsListLayout.rowMinHeight)

            modelMultiSelect(title: "启用模型", models: activeProviderPreset.availableModels)
            apiKeyField(placeholder: activeProviderPreset.keyPlaceholder)
        }
    }

    private var otherProviderAPIFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            aiConnectionCard {
                VStack(alignment: .leading, spacing: SettingsListLayout.spaceL) {
                    HStack(spacing: SettingsListLayout.spaceS) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(option.tint)
                        Text("自定义连接")
                            .font(SettingsListTypography.header)
                    }
                    aiConnectionSettingsRow(title: "服务商") {
                        Picker("服务商", selection: $selectedProviderPresetID) {
                            ForEach(AIConnectionProviderPreset.otherProviderPresets) { preset in
                                Text(preset.title).tag(preset.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .controlSize(.large)
                        .frame(width: SettingsListLayout.pickerControlWidth, alignment: .leading)
                        .onChange(of: selectedProviderPresetID) { _, _ in applySelectedProviderPreset() }
                    }

                    if selectedProviderPresetID == "custom" {
                        aiConnectionSettingsRow(title: "接口地址") {
                            aiConnectionTextField("https://your-api-endpoint.com", text: $baseURLString)
                        }

                        aiConnectionSettingsRow(title: "兼容模式", help: compatibilityModeHelpText) {
                            Picker("兼容模式", selection: $customProtocol) {
                                ForEach(AIConnectionCustomProtocol.allCases, id: \.self) { protocolKind in
                                    Text(protocolKind.title).tag(protocolKind)
                                }
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    aiConnectionSettingsRow(title: "模型", help: modelFieldHelpText) {
                        if selectedProviderPresetID != "custom" && !activeProviderPreset.supportedModels.isEmpty {
                            modelMultiSelect(title: "", models: activeProviderPreset.availableModels)
                        } else {
                            aiConnectionTextField("例如 deepseek-v4-flash；多个模型可用逗号分隔", text: $model)
                        }
                    }
                }
            }

            primaryAPIKeyEntryCard(placeholder: activeProviderPreset.keyPlaceholder)
        }
    }

    private func apiKeyField(placeholder: String) -> some View {
        aiConnectionSettingsRow(title: "API Key") {
            apiKeyInput(placeholder: placeholder)
        }
    }

    private func apiKeyInput(placeholder: String) -> some View {
        aiConnectionInputContainer {
            Group {
                if showAPIKey {
                    TextField(placeholder, text: $apiKey)
                } else {
                    SecureField(placeholder, text: $apiKey)
                }
            }
            .textFieldStyle(.plain)
            .font(SettingsListTypography.rowTitle)

            Button(action: { showAPIKey.toggle() }) {
                Image(systemName: showAPIKey ? "eye.slash" : "eye")
                    .font(SettingsListTypography.icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showAPIKey ? "隐藏 API Key" : "显示 API Key")
            .help(showAPIKey ? "隐藏 API Key" : "显示 API Key")
        }
    }

    private func aiConnectionSettingsRow<Content: View>(title: String, help: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: SettingsListLayout.spaceL) {
            Text(title)
                .font(SettingsListTypography.header)
                .frame(width: 104, alignment: .leading)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: SettingsListLayout.spaceS) {
                content()
                if let help, !help.isEmpty {
                    aiConnectionHelpText(help)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func aiConnectionFormRow<Content: View>(title: String, help: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceS) {
            Text(title)
                .font(SettingsListTypography.header)
            content()
            if let help, !help.isEmpty {
                aiConnectionHelpText(help)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func aiConnectionInputContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: SettingsListLayout.spaceS) {
            content()
        }
        .padding(.horizontal, SettingsListLayout.spaceL)
        .frame(minHeight: SettingsListLayout.fieldHeight)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: SettingsListLayout.radiusM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsListLayout.radiusM, style: .continuous)
                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
        )
    }

    private func aiConnectionTextField(_ placeholder: String, text: Binding<String>) -> some View {
        aiConnectionInputContainer {
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(SettingsListTypography.rowTitle)
                .lineLimit(1)
                .textSelection(.enabled)
        }
    }

    private func aiConnectionHelpText(_ text: String) -> some View {
        Text(text)
            .font(SettingsListTypography.rowTitle)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func modelMultiSelect(title: String, models: [String]) -> some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceM) {
            if !title.isEmpty {
                Text(title)
                    .font(SettingsListTypography.header)
            }
            VStack(alignment: .leading, spacing: SettingsListLayout.spaceS) {
                ForEach(models, id: \.self) { modelID in
                    Toggle(isOn: Binding(
                        get: { selectedModelIDs.contains(modelID) },
                        set: { isOn in updateSelectedModels(modelID: modelID, isSelected: isOn, availableModels: models) }
                    )) {
                        HStack {
                            Text(modelID)
                            Spacer()
                            if selectedModel == modelID {
                                Text("默认")
                                    .font(SettingsListTypography.rowCaptionEmphasized)
                                    .foregroundStyle(option.tint)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .padding(.horizontal, SettingsListLayout.spaceL)
            .padding(.vertical, SettingsListLayout.spaceM)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: SettingsListLayout.radiusM, style: .continuous))

            HStack {
                Text("默认模型")
                    .font(SettingsListTypography.rowTitle)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("默认模型", selection: $selectedModel) {
                    ForEach(enabledModels(in: models), id: \.self) { modelID in
                        Text(modelID).tag(modelID)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.large)
                .frame(width: SettingsListLayout.pickerControlWidth, alignment: .trailing)
                .onChange(of: selectedModel) { _, newValue in
                    if !selectedModelIDs.contains(newValue) { selectedModelIDs.insert(newValue) }
                    syncModelListFromSelection(fallbackModels: models)
                    // Auto-suggest vision support when a known vision model is selected
                    let preset = activeProviderPreset
                    if !preset.defaultVisionModels.isEmpty {
                        visionSupportOverride = preset.defaultVisionModels.contains(newValue) ? true : nil
                    }
                }
            }
            Text("可启用多个模型；测试连接时会使用当前可用的模型之一，新会话仍会使用你选择的默认模型。")
                .font(SettingsListTypography.rowTitle)
                .foregroundStyle(.secondary)
        }
    }

    private var activeProviderPreset: AIConnectionProviderPreset {
        let presets = option.id == "china-provider" ? AIConnectionProviderPreset.chinaProviderPresets : AIConnectionProviderPreset.otherProviderPresets
        return presets.first { $0.id == selectedProviderPresetID } ?? presets[0]
    }

    private var usesAPIKeyFirstPresetFlow: Bool {
        guard option.authenticationKind == .direct else { return false }
        if option.id == "local-model" { return false }
        if option.id == "other-provider" { return selectedProviderPresetID != "custom" }
        return true
    }

    private var apiKeyPlaceholderForCurrentPreset: String {
        if isXiaomiMiMoOption { return xiaomiMiMoConnectionMode.keyPlaceholder }
        if option.id == "china-provider" || option.id == "other-provider" { return activeProviderPreset.keyPlaceholder }
        if option.providerMode == .anthropicMessages { return "sk-ant-..." }
        return "sk-..."
    }

    private var xiaomiMiMoKeyEndpointMismatchWarning: String? {
        guard isXiaomiMiMoOption else { return nil }
        return xiaomiMiMoConnectionMode.keyEndpointMismatchWarning(for: apiKey)
    }

    private var compatibilitySummaryTitle: String {
        if option.providerMode == .anthropicMessages { return "Anthropic Messages" }
        if option.id == "china-provider" || option.id == "other-provider" { return activeProviderPreset.protocolKind.title }
        switch option.providerMode {
        case .openAIResponses: return "OpenAI Responses"
        case .openAICompatible: return "OpenAI Compatible"
        case .anthropicMessages: return "Anthropic Messages"
        }
    }

    private var chinaProviderPresets: [AIConnectionProviderPreset] {
        AIConnectionProviderPreset.chinaProviderPresets
    }

    private func openAICompatibleFields(includeAPIKey: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("连接名称", text: $connectionName)
                .textFieldStyle(.roundedBorder)
            TextField("接口地址", text: $baseURLString)
                .textFieldStyle(.roundedBorder)
            TextField("模型", text: $model)
                .textFieldStyle(.roundedBorder)
            TextField("默认模型", text: $selectedModel)
                .textFieldStyle(.roundedBorder)
            if includeAPIKey {
                SecureField(option.id == "local-model" ? "API Key（本地模型可留空）" : "API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var primaryButtonTitle: String {
        if isAuthenticating { return "正在认证…" }
        switch option.authenticationKind {
        case .browserCallback:
            return option.loginButtonTitle
        case .deviceCode:
            return githubDeviceCode == nil ? option.loginButtonTitle : "等待授权…"
        case .direct:
            return "验证并添加连接"
        }
    }

    private var primaryButtonIcon: String {
        if isAuthenticating { return "hourglass" }
        switch option.authenticationKind {
        case .browserCallback:
            return "arrow.up.right.square"
        case .deviceCode:
            return githubDeviceCode == nil ? "arrow.up.right.square" : "circle.grid.3x3"
        case .direct:
            return "arrow.right"
        }
    }

    private var isPrimaryButtonDisabled: Bool {
        switch option.authenticationKind {
        case .direct:
            return connectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || effectiveModelListForSubmit().isEmpty
                || (apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoopbackEndpoint(baseURLString))
        default:
            return false
        }
    }

    private func primaryAction() {
        switch option.authenticationKind {
        case .browserCallback:
            authenticateChatGPTAndAddConnection()
        case .deviceCode:
            authenticateGitHubCopilotAndAddConnection()
        case .direct:
            setupDirectOpenAICompatibleConnection()
        }
    }

    private func authenticateChatGPTAndAddConnection() {
        isAuthenticating = true
        didOpenBrowser = true
        statusMessage = "正在用系统默认浏览器打开 ChatGPT 登录页，并等待浏览器回调…"
        errorMessage = nil
        Task {
            do {
                let result = try await AppLLMOAuthService.shared.authenticateChatGPT { url in
                    Task { @MainActor in
                        viewModel.openURLInSystemDefaultBrowser(url)
                    }
                }
                let input = AppLLMConnectionSetupInput(
                    id: stableConnectionID,
                    kind: .chatGPTCodex,
                    name: connectionName,
                    baseURLString: baseURLString,
                    model: model,
                    selectedModel: selectedModel,
                    apiKey: result.apiKey,
                    oauthTokens: result.tokens
                )
                _ = try await viewModel.setupLLMConnection(input)
                await MainActor.run {
                    isAuthenticating = false
                    complete()
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    statusMessage = nil
                    errorMessage = displayError(error)
                }
            }
        }
    }

    private func authenticateGitHubCopilotAndAddConnection() {
        isAuthenticating = true
        statusMessage = githubDeviceCode == nil ? "正在向 GitHub 申请设备码…" : "正在等待 GitHub 授权完成…"
        errorMessage = nil
        Task {
            do {
                let code = try await AppLLMOAuthService.shared.startGitHubCopilotDeviceFlow()
                await MainActor.run {
                    githubDeviceCode = code
                    didOpenBrowser = true
                    if let url = URL(string: code.verificationURI) {
                        viewModel.openURLInSystemDefaultBrowser(url)
                    }
                    statusMessage = "在系统默认浏览器的 GitHub 页面输入授权码后，康纳同学会自动继续。"
                }
                let tokens = try await AppLLMOAuthService.shared.pollGitHubCopilotTokens(deviceCode: code)
                let input = AppLLMConnectionSetupInput(
                    id: stableConnectionID,
                    kind: .githubCopilot,
                    name: connectionName,
                    baseURLString: "",
                    model: model,
                    selectedModel: selectedModel,
                    apiKey: tokens.accessToken,
                    oauthTokens: tokens
                )
                _ = try await viewModel.setupLLMConnection(input)
                await MainActor.run {
                    isAuthenticating = false
                    complete()
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    statusMessage = nil
                    errorMessage = displayError(error)
                }
            }
        }
    }

    private func setupDirectOpenAICompatibleConnection() {
        isAuthenticating = true
        statusMessage = "正在验证连接…"
        errorMessage = nil
        Task {
            do {
                let usesProviderPreset = option.id == "other-provider" || option.id == "china-provider"
                let connectionKind: AppLLMConnectionKind = option.providerMode == .openAIResponses ? .openAIResponses : (option.providerMode == .anthropicMessages || (usesProviderPreset && customProtocol == .anthropicCompatible) ? .anthropicCompatible : .openAICompatible)
                let submittedModelList = persistedModelListForSubmit()
                let submittedSelectedModel = persistedSelectedModelForSubmit(modelList: submittedModelList)
                let submittedName = submittedConnectionNameForSubmit()
                let input = AppLLMConnectionSetupInput(
                    id: nil,
                    kind: connectionKind,
                    name: submittedName,
                    baseURLString: baseURLString,
                    model: submittedModelList,
                    selectedModel: submittedSelectedModel,
                    validationModel: healthCheckModelForSubmit,
                    apiKey: apiKey,
                    anthropicAuthHeaderKind: activeProviderPreset.authHeaderKind,
                    openAIAPIKeyHeaderKind: openAIAPIKeyHeaderKindForCurrentDraft(),
                    explicitVisionSupport: visionSupportOverride
                )
                _ = try await viewModel.setupLLMConnection(input)
                await MainActor.run {
                    isAuthenticating = false
                    complete()
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    statusMessage = nil
                    errorMessage = displayError(error)
                }
            }
        }
    }

    private func initializeDrafts() {
        guard connectionName.isEmpty else { return }
        baseURLString = option.baseURLString
        connectionName = defaultDraftConnectionName(endpoint: option.baseURLString, fallback: option.connectionName)
        model = option.model
        selectedModel = option.selectedModel
        selectedModelIDs = Set(option.modelOptionsFallback)
        if selectedModelIDs.isEmpty, !selectedModel.isEmpty { selectedModelIDs = [selectedModel] }
        if option.id == "other-provider" {
            selectedProviderPresetID = "openai"
            applySelectedProviderPreset()
        }
        if option.id == "china-provider" {
            selectedProviderPresetID = "qwen"
            applySelectedProviderPreset()
        }
        if isXiaomiMiMoOption {
            applyXiaomiMiMoConnectionMode()
        }
        if option.id == "claude-pro-max" {
        }
    }

    private func applyXiaomiMiMoConnectionMode() {
        guard isXiaomiMiMoOption else { return }
        baseURLString = xiaomiMiMoConnectionMode.openAIEndpoint
        connectionName = defaultDraftConnectionName(endpoint: baseURLString, fallback: option.connectionName)
    }

    private func applySelectedProviderPreset() {
        let preset = activeProviderPreset
        if preset.id != "custom" {
            baseURLString = preset.endpoint
            connectionName = defaultDraftConnectionName(endpoint: preset.endpoint, fallback: preset.title)
            model = preset.availableModels.joined(separator: ",")
            selectedModel = preset.defaultModel
            selectedModelIDs = Set(preset.availableModels)
            customProtocol = preset.protocolKind
        } else {
            baseURLString = ""
            connectionName = option.connectionName
            model = ""
            selectedModel = ""
            selectedModelIDs = []
            customProtocol = .openAICompatible
        }
    }

    private func updateSelectedModels(modelID: String, isSelected: Bool, availableModels: [String]) {
        if isSelected {
            selectedModelIDs.insert(modelID)
            if selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { selectedModel = modelID }
        } else {
            selectedModelIDs.remove(modelID)
            if selectedModelIDs.isEmpty, let fallback = availableModels.first {
                selectedModelIDs.insert(fallback)
            }
            if selectedModel == modelID || !selectedModelIDs.contains(selectedModel) {
                selectedModel = enabledModels(in: availableModels).first ?? ""
            }
        }
        syncModelListFromSelection(fallbackModels: availableModels)
    }

    private func enabledModels(in availableModels: [String]) -> [String] {
        let selected = availableModels.filter { selectedModelIDs.contains($0) }
        return selected.isEmpty ? Array(availableModels.prefix(1)) : selected
    }

    private func syncModelListFromSelection(fallbackModels: [String]) {
        let models = enabledModels(in: fallbackModels)
        model = models.joined(separator: ",")
        if selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !models.contains(selectedModel) {
            selectedModel = models.first ?? ""
        }
    }

    private func submittedConnectionNameForSubmit() -> String {
        let trimmedName = connectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { return trimmedName }
        return defaultDraftConnectionName(endpoint: baseURLString, fallback: option.connectionName)
    }

    private func defaultDraftConnectionName(endpoint: String, fallback: String) -> String {
        AppLLMEndpointDisplayName.defaultConnectionName(from: endpoint, fallback: fallback)
    }

    private func effectiveModelListForSubmit() -> String {
        if !selectedModelIDs.isEmpty {
            let sourceModels = currentPresetModelOptions()
            let enabled = sourceModels.filter { selectedModelIDs.contains($0) }
            if !enabled.isEmpty { return enabled.joined(separator: ",") }
        }
        return model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func persistedModelListForSubmit() -> String {
        effectiveModelListForSubmit()
    }

    private func persistedSelectedModelForSubmit(modelList: String) -> String {
        let selected = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let configuredModels = modelIDs(in: modelList)
        guard !configuredModels.isEmpty else { return selected }
        if !selected.isEmpty && configuredModels.contains(selected) { return selected }
        return configuredModels[0]
    }

    private var healthCheckModelForSubmit: String {
        let firstConfiguredModel = firstConfiguredModelForSubmit()
        if !firstConfiguredModel.isEmpty { return firstConfiguredModel }
        let selected = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selected.isEmpty { return selected }
        return "未选择模型"
    }

    private var modelFieldHelpText: String {
        let modelList = modelIDs(in: effectiveModelListForSubmit())
        let endpointDescription = selectedProviderPresetID == "custom" ? customProtocol.modelValidationEndpointDescription : "连接校验"
        if modelList.count > 1 {
            return "使用服务商自己的模型 ID。已填写多个模型时，康纳同学会使用其中一个模型进行\(endpointDescription)，保存后可在会话中切换其他模型。"
        }
        return "使用服务商自己的模型 ID。康纳同学会用该模型进行\(endpointDescription)。"
    }

    private func firstConfiguredModelForSubmit() -> String {
        firstConfiguredModel(in: effectiveModelListForSubmit())
    }

    private func firstConfiguredModel(in modelList: String) -> String {
        modelIDs(in: modelList).first ?? ""
    }

    private func modelIDs(in modelList: String) -> [String] {
        modelList
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var compatibilityModeHelpText: String {
        switch customProtocol {
        case .openAICompatible:
            return "适用于 OpenAI-compatible /v1/chat/completions 接口，例如 vLLM、Ollama、DashScope、DeepSeek、MiMo 等服务。"
        case .anthropicCompatible:
            return "适用于 Anthropic Messages /v1/messages 接口，例如 Anthropic API 或明确提供 Anthropic Skin 的网关。"
        }
    }

    private var isXiaomiMiMoOption: Bool {
        option.id == "xiaomi-mimo"
    }

    private func currentPresetModelOptions() -> [String] {
        if option.id == "deepseek" || option.id == "xiaomi-mimo" {
            return option.supportedModels.isEmpty ? [option.selectedModel] : option.supportedModels
        }
        if option.id == "china-provider" || (option.id == "other-provider" && selectedProviderPresetID != "custom") {
            return activeProviderPreset.availableModels
        }
        return model.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func openAIAPIKeyHeaderKindForCurrentDraft() -> OpenAICompatibleAPIKeyHeaderKind {
        if option.id == "xiaomi-mimo" { return .apiKey }
        if option.id == "other-provider" || option.id == "china-provider" { return activeProviderPreset.openAIAPIKeyHeaderKind }
        return .bearer
    }

    private func isLoopbackEndpoint(_ rawValue: String) -> Bool {
        guard let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private var stableConnectionID: String {
        switch option.id {
        case "codex-chatgpt-plus": "codex-chatgpt-plus"
        case "github-copilot": "github-copilot"
        default: option.id
        }
    }

    private func displayError(_ error: Error) -> String {
        AppLLMProviderHealthChecker.userFacingMessage(for: error)
    }

    private func displayURL(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

struct AIConnectionOnboardingView: View {
    var choose: (AIConnectionOnboardingOption) -> Void
    var cancel: () -> Void
    var showBackButton: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            if showBackButton {
                HStack {
                    Button(action: cancel) {
                        Label("返回", systemImage: "chevron.left")
                            .font(SettingsListTypography.rowTitleSelected)
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .background(.quaternary.opacity(0.28), in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                    )
                    .help("返回上一页")
                    Spacer()
                }
                .padding(.top, 6)
            }

            Spacer(minLength: 42)

            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    ConnorConnectionMark()
                    VStack(spacing: 14) {
                        Text("欢迎使用康纳同学")
                            .font(SettingsListTypography.header)
                        Text("先选择一种连接方式，康纳同学会在下一步帮你完成配置。")
                            .font(SettingsListTypography.rowSubtitle)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }

                VStack(spacing: 14) {
                    ForEach(AIConnectionOnboardingOption.all) { option in
                        AIConnectionOnboardingOptionRow(option: option) {
                            choose(option)
                        }
                    }
                }
                .frame(maxWidth: 760)
            }

            Spacer(minLength: 56)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 760)
    }
}

struct ConnorConnectionMark: View {
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 82, height: 82)
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
            .accessibilityLabel("康纳同学应用图标")
    }
}

struct AIConnectionOnboardingOptionRow: View {
    var option: AIConnectionOnboardingOption
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.09))
                    Image(systemName: option.systemImage)
                        .font(SettingsListTypography.icon)
                        .foregroundStyle(option.tint)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title)
                        .font(SettingsListTypography.rowTitleSelected)
                        .foregroundStyle(.primary)
                    Text(option.subtitle)
                        .font(SettingsListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct AIConnectionEntryRow: View {
    var connection: AppLLMConnectionConfig
    var isDefault: Bool
    var canDelete: Bool
    var select: () -> Void
    var makeDefault: () -> Void
    var rename: () -> Void
    var delete: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: providerSystemImage)
                    .font(SettingsListTypography.icon)
                    .foregroundStyle(providerTint)
                    .frame(width: 18, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(connection.name)
                            .font(isDefault ? SettingsListTypography.rowTitleSelected : SettingsListTypography.rowTitle)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if isDefault {
                            Text("默认")
                                .font(SettingsListTypography.rowCaptionEmphasized)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.10), in: Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(SettingsListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 16)

                Menu {
                    Button(action: makeDefault) {
                        Label("设为默认", systemImage: "checkmark.circle")
                    }
                    .disabled(isDefault)
                    Button(action: rename) {
                        Label("更改名称", systemImage: "pencil")
                    }
                    Divider()
                    Button(role: .destructive, action: delete) {
                        Label("删除连接", systemImage: "trash")
                    }
                    .disabled(!canDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(SettingsListTypography.icon)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)
                .help("更多")
            }
            .contentShape(Rectangle())
            .frame(minHeight: 58)
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        "\(providerDisplayName) · \(endpointDisplayName)"
    }

    private var providerDisplayName: String {
        switch connection.providerMode {
        case .openAIResponses:
            return "OpenAI Responses"
        case .openAICompatible:
            return "OpenAI Compatible"
        case .anthropicMessages:
            return "Anthropic Messages"
        }
    }

    private var endpointDisplayName: String {
        switch connection.providerMode {
        case .openAIResponses, .openAICompatible, .anthropicMessages:
            return AppLLMEndpointDisplayName.host(from: connection.baseURLString)
        }
    }

    private var providerSystemImage: String {
        switch connection.providerMode {
        case .openAIResponses:
            return "sparkles"
        case .openAICompatible:
            return "sparkles"
        case .anthropicMessages:
            return "sparkles.rectangle.stack"
        }
    }

    private var providerTint: Color {
        switch connection.providerMode {
        case .openAIResponses:
            return .primary
        case .openAICompatible:
            return .primary
        case .anthropicMessages:
            return .purple
        }
    }

}

struct SettingsPermissionsSection: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isShowingPolicyDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsHeroHeader(
                title: "权限",
                subtitle: "控制新会话默认能做什么。运行中的会话仍可在输入框下方临时切换权限；项目目录在每个会话顶部的“当前会话 Workspace”中配置。",
                systemImage: "checkmark.shield"
            ) {
                EmptyView()
            }

            SettingsGroup(title: "新会话默认权限") {
                PermissionModePickerRow(selection: $viewModel.defaultPermissionMode)
                Divider()
                PermissionModeSummaryRow(mode: viewModel.defaultPermissionMode)
            }

            SettingsGroup(title: "生效范围") {
                PermissionBoundaryRow(systemImage: "checkmark.shield", title: "权限模式会影响新会话", message: "这里选择的模式会作为之后新建会话的默认权限。已有会话可以在输入框下方临时切换。")
                Divider()
                PermissionBoundaryRow(systemImage: "network", title: "网络访问默认不单独审批", message: "在“询问”和“执行”模式下，普通网络访问默认允许；只读模式会限制外部网络访问。")
                Divider()
                PermissionBoundaryRow(systemImage: "terminal", title: "命令行操作按风险级别处理", message: "安全读取可直接执行，高风险或破坏性操作需要确认。")
            }

            SettingsGroup(title: "安全边界") {
                PermissionBoundaryRow(systemImage: "lock.shield", title: "不提供全部允许", message: "不会开放不受限制的权限模式。需要高风险操作时，康纳同学会先请求确认。")
                Divider()
                PermissionBoundaryRow(systemImage: "folder", title: "工作目录按会话设置", message: "主目录和其他工作目录在会话顶部设置，不在全局权限页管理。")
                Divider()
                PermissionBoundaryRow(systemImage: "person.crop.circle.badge.xmark", title: "本地单用户边界", message: "当前版本面向单人本机使用，暂不支持团队成员或组织角色权限。")
            }

            DisclosureGroup(isExpanded: $isShowingPolicyDetails) {
                VStack(alignment: .leading, spacing: 10) {
                    PermissionPolicyDetailRow(title: "只读", message: "允许读取会话和文件、搜索本地内容、进行模型调用和本地计算；拒绝写入、删除、外部网络和高风险命令。")
                    PermissionPolicyDetailRow(title: "询问", message: "读取、普通模型调用和外部网络默认允许；文件写入、编辑、删除、记忆写入、高成本模型调用和高风险命令需要确认。")
                    PermissionPolicyDetailRow(title: "执行", message: "文件写入、编辑和常规命令可自动执行；删除文件、删除记忆、高风险命令和高成本模型调用仍需要确认。")
                }
                .padding(.top, SettingsListLayout.spaceS)
            } label: {
                Label("查看当前策略说明", systemImage: "list.bullet.rectangle")
                    .font(SettingsListTypography.rowTitleSelected)
            }
            .padding(.horizontal, SettingsListLayout.spaceL)
            .padding(.vertical, SettingsListLayout.spaceM)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: SettingsListLayout.radiusL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsListLayout.radiusL, style: .continuous)
                    .stroke(Color.secondary.opacity(SettingsListLayout.hairlineOpacity), lineWidth: 1)
            )
        }
    }
}

struct PermissionModePickerRow: View {
    @Binding var selection: AgentPermissionMode

    private var availableModes: [AgentPermissionMode] {
        AgentPermissionMode.allCases.filter { $0 != .allowAll }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("权限模式")
                    .font(SettingsListTypography.rowTitleSelected)
                Text("作为新会话和重建会话的默认权限模式。")
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: SettingsListLayout.spaceL)

            Menu {
                ForEach(availableModes, id: \.self) { mode in
                    Button {
                        selection = mode
                    } label: {
                        Label(mode.displayName, systemImage: mode.systemImage)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Label(selection.displayName, systemImage: selection.systemImage)
                        .labelStyle(.titleAndIcon)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .font(SettingsListTypography.rowTitle)
                .padding(.horizontal, 10)
                .frame(width: 144, height: 34, alignment: .leading)
                .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(width: 160, alignment: .trailing)
            .help("选择新会话默认权限模式")
        }
        .frame(minHeight: SettingsListLayout.rowMinHeight)
    }
}

private extension AgentPermissionMode {
    var systemImage: String {
        switch self {
        case .readOnly:
            return "eye"
        case .askToWrite:
            return "questionmark.circle"
        case .trustedWrite:
            return "bolt.circle"
        case .allowAll:
            return "exclamationmark.triangle"
        }
    }
}

struct PermissionModeSummaryRow: View {
    var mode: AgentPermissionMode

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(mode.displayName)
                    .font(SettingsListTypography.rowTitleSelected)
                Text(summary)
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 52, alignment: .leading)
    }

    private var systemImage: String {
        switch mode {
        case .readOnly:
            return "eye"
        case .askToWrite:
            return "questionmark.circle"
        case .trustedWrite:
            return "bolt.circle"
        case .allowAll:
            return "exclamationmark.triangle"
        }
    }

    private var tint: Color {
        switch mode {
        case .readOnly:
            return .blue
        case .askToWrite:
            return .orange
        case .trustedWrite:
            return .green
        case .allowAll:
            return .red
        }
    }

    private var summary: String {
        switch mode {
        case .readOnly:
            return "适合探索、阅读和分析。写入、删除、网络和高风险 shell 会被拒绝。"
        case .askToWrite:
            return "适合日常协作。读取和普通工具可直接运行，写入、删除和高风险操作会先询问。"
        case .trustedWrite:
            return "适合你明确要让 Connor 连续执行修改时使用。普通写入和 workspace shell 可自动通过，删除和危险操作仍需审批。"
        case .allowAll:
            return "内部保留模式，不在产品界面中开放。"
        }
    }
}

struct PermissionNoteRow: View {
    var systemImage: String
    var title: String
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SettingsListTypography.rowCaptionEmphasized)
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PermissionBoundaryRow: View {
    var systemImage: String
    var title: String
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SettingsListTypography.rowTitleSelected)
                Text(message)
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 46, alignment: .leading)
    }
}

struct PermissionPolicyDetailRow: View {
    var title: String
    var message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(SettingsListTypography.rowCaptionEmphasized)
            Text(message)
                .font(SettingsListTypography.rowCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
