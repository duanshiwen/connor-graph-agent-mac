import SwiftUI
import WebKit
import ConnorGraphCore
import ConnorGraphAppSupport

struct MailBodyDisplayPresentation: Equatable {
    enum Kind: Equatable {
        case loading
        case html
        case plainText
        case fallback
        case error
    }

    var kind: Kind
    var text: String
    var html: String?

    init(kind: Kind, text: String, html: String? = nil) {
        self.kind = kind
        self.text = text
        self.html = html?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? html : nil
    }

    init(detail: MailMessageDetail) {
        let plain = detail.body?.plainText?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let html = detail.body?.htmlText?.text
        let trimmedHTML = html?.trimmingCharacters(in: .whitespacesAndNewlines)
        let redacted = detail.body?.redactedPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet = detail.summary.snippet.trimmingCharacters(in: .whitespacesAndNewlines)

        if let html, trimmedHTML?.isEmpty == false {
            let recovered = Self.recoverCachedHTMLIfNeeded(html, fallback: plain ?? redacted ?? snippet)
            self.init(kind: .html, text: recovered.plainText, html: recovered.html)
        } else if let plain, !plain.isEmpty {
            self.init(kind: .plainText, text: plain)
        } else if let redacted, !redacted.isEmpty {
            self.init(kind: .fallback, text: redacted)
        } else if !snippet.isEmpty {
            self.init(kind: .fallback, text: snippet)
        } else {
            self.init(kind: .fallback, text: "（暂无可显示正文）")
        }
    }

    static let loading = MailBodyDisplayPresentation(kind: .loading, text: "正在加载邮件正文…")

    private static func recoverCachedHTMLIfNeeded(_ html: String, fallback: String) -> (html: String, plainText: String) {
        let parser = MailMIMEParser()
        let result = parser.parseBodyWithHTML(
            rawData: Data(html.utf8),
            fallbackString: fallback,
            charset: "utf-8",
            transferEncoding: nil,
            contentType: "text/html; charset=utf-8",
            boundary: nil
        )
        return (result.htmlText ?? html, result.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : result.plainText)
    }

    static func error(_ message: String, fallback: String) -> MailBodyDisplayPresentation {
        let fallbackText = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return MailBodyDisplayPresentation(kind: .error, text: fallbackText.isEmpty ? message : "\(message)\n\n\(fallbackText)")
    }
}

struct MailSettingsSummaryPresentation: Equatable {
    var presentation: NativeMailBrowserPresentation
    var accountCount: Int
    var mailboxCount: Int
    var messageCount: Int
    var unreadCount: Int
    var lastSyncedAt: Date?

    init(presentation: NativeMailBrowserPresentation) {
        self.presentation = presentation
        accountCount = presentation.accounts.count
        mailboxCount = presentation.mailboxes.count
        messageCount = presentation.totalMessageCount
        unreadCount = presentation.totalUnreadCount
        lastSyncedAt = presentation.mailboxes
            .compactMap(\.status.lastSyncedAt)
            .max()
    }

    var accountCountText: String { "\(accountCount) 个" }
    var mailboxCountText: String { "\(mailboxCount) 个" }
    var messageCountText: String { "\(messageCount) 封" }
    var unreadCountText: String { "\(unreadCount) 未读" }
    var credentialStorageText: String { "Connor 本地加密凭据库" }

    var lastSyncedText: String? {
        lastSyncedAt?.connorLocalFormatted(date: .medium, time: .short)
    }

    var emptyStateTitle: String? {
        accountCount == 0 ? "暂无邮件账户" : nil
    }

    var emptyStateMessage: String? {
        accountCount == 0 ? "添加 IMAP/SMTP 账户后，康纳同学会同步最近邮件并创建定时刷新任务。" : nil
    }

    func defaultSendAccountText(preferences: MailPreferences) -> String {
        guard let accountID = preferences.defaultSendAccountID,
              let account = presentation.account(id: accountID) else { return "尚未设置" }
        let email = account.identities.first?.address.email ?? account.id.rawValue
        return "\(account.displayName) <\(email)>"
    }

    func defaultSendIdentityText(preferences: MailPreferences) -> String {
        guard let accountID = preferences.defaultSendAccountID,
              let account = presentation.account(id: accountID) else { return "尚未设置" }
        let identity = preferences.defaultSendIdentityID.flatMap { identityID in
            account.identities.first(where: { $0.id == identityID })
        } ?? account.identities.first(where: \.canSend)
        guard let identity else { return "尚未设置" }
        return "\(identity.displayName) <\(identity.address.email)>"
    }
}

struct SettingsMailSection: View {
    @ObservedObject var viewModel: AppViewModel

    private var presentation: NativeMailBrowserPresentation {
        viewModel.mailBrowserPresentation
    }

    private var summary: MailSettingsSummaryPresentation {
        MailSettingsSummaryPresentation(presentation: presentation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceXL) {
            header
            accountsSection
            sendingSection
            syncSection
            securitySection
            protocolSection
        }
        .sheet(isPresented: $viewModel.isPresentingAddMailAccountSheet) {
            AddMailAccountSheet(viewModel: viewModel)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceXS) {
            Text("邮件系统")
                .font(SettingsListTypography.header)
            Text("管理 IMAP / SMTP 账户、本地同步、读取安全和发送审批。")
                .font(SettingsListTypography.rowSubtitle)
                .foregroundStyle(.secondary)
        }
    }

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceXL) {
            if presentation.accounts.isEmpty {
                MailSettingsEmptyStateCard(onAdd: { viewModel.presentAddMailAccountSheet() })
            } else {
                VStack(spacing: 0) {
                    ForEach(presentation.accounts) { account in
                        MailSettingsAccountRow(
                            account: account,
                            mailboxCount: presentation.mailboxes(accountID: account.id).count,
                            unreadCount: presentation.mailboxes(accountID: account.id).reduce(0) { $0 + $1.status.unreadCount },
                            onAdd: { viewModel.presentAddMailAccountSheet() }
                        )
                        if account.id != presentation.accounts.last?.id {
                            Divider().padding(.leading, 32)
                        }
                    }
                }
                .padding(.horizontal, SettingsListLayout.spaceL)
                .padding(.vertical, SettingsListLayout.spaceS)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: SettingsListLayout.radiusL, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: SettingsListLayout.radiusL, style: .continuous).stroke(Color.secondary.opacity(SettingsListLayout.hairlineOpacity), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)

                Button(action: { viewModel.presentAddMailAccountSheet() }) {
                    Label("添加邮件账户", systemImage: "plus")
                        .font(SettingsListTypography.actionTitle)
                        .padding(.horizontal, SettingsListLayout.spaceM)
                        .padding(.vertical, SettingsListLayout.spaceXS)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var sendingSection: some View {
        SettingsGroup(title: "发信设置") {
            if presentation.accounts.isEmpty {
                SettingsValueRow(title: "默认发信账户", value: summary.defaultSendAccountText(preferences: viewModel.mailPreferences))
            } else {
                MailDefaultSendAccountRow(
                    accounts: presentation.accounts,
                    selectedAccountID: viewModel.mailPreferences.defaultSendAccountID ?? presentation.defaultAccountID(),
                    titleFor: defaultAccountPickerTitle(for:),
                    onSelect: { accountID in Task { @MainActor in await viewModel.setDefaultMailSendAccount(accountID) } }
                )
                Divider()
                SettingsValueRow(title: "默认发件身份", value: summary.defaultSendIdentityText(preferences: viewModel.mailPreferences))
                Divider()
                SettingsValueRow(title: "发送确认", value: "Compose 审批卡会显示实际 From，允许后才发送")
            }
        }
    }

    private func defaultAccountPickerTitle(for account: MailAccount) -> String {
        let email = account.identities.first?.address.email ?? account.id.rawValue
        return "\(account.displayName) <\(email)>"
    }

    private var syncSection: some View {
        SettingsGroup(title: "同步") {
            SettingsValueRow(title: "账户", value: summary.accountCountText)
            Divider()
            SettingsValueRow(title: "文件夹", value: summary.mailboxCountText)
            Divider()
            SettingsValueRow(title: "已同步邮件", value: summary.messageCountText)
            Divider()
            SettingsValueRow(title: "未读邮件", value: summary.unreadCountText)
            if let lastSyncedText = summary.lastSyncedText {
                Divider()
                SettingsValueRow(title: "最近同步", value: lastSyncedText)
            }
            Divider()
            SettingsValueRow(title: "默认策略", value: "添加后立即同步最近 50 封，后台定时刷新")
            if let message = viewModel.mailSyncMessage {
                Divider()
                Text(message)
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var securitySection: some View {
        SettingsGroup(title: "安全与隐私") {
            SettingsValueRow(title: "凭据存储", value: summary.credentialStorageText)
            Divider()
            SettingsValueRow(title: "读取语义", value: "查看详情不会自动改变已读状态")
            Divider()
            SettingsValueRow(title: "HTML 正文", value: "不执行 JavaScript，不主动加载远程资源")
            Divider()
            SettingsValueRow(title: "发送保护", value: "发送邮件需要权限审批")
            Divider()
            SettingsValueRow(title: "本地治理", value: "邮件索引和正文缓存保存在本地")
        }
    }

    private var protocolSection: some View {
        SettingsGroup(title: "协议与能力") {
            SettingsValueRow(title: "收件协议", value: "IMAP over TLS")
            Divider()
            SettingsValueRow(title: "发件协议", value: "SMTP STARTTLS 587（真实发送）；隐式 TLS 465 暂未启用")
            Divider()
            SettingsValueRow(title: "支持账户", value: "iCloud、QQ、网易、自定义 IMAP/SMTP")
            Divider()
            SettingsValueRow(title: "正文解析", value: "纯文本 / HTML 安全渲染")
            Divider()
            SettingsValueRow(title: "后续扩展", value: "Google / Microsoft OAuth、附件预览")
        }
    }
}

private struct MailDefaultSendAccountRow: View {
    var accounts: [MailAccount]
    var selectedAccountID: MailAccountID?
    var titleFor: (MailAccount) -> String
    var onSelect: (MailAccountID) -> Void

    private var selectedAccount: MailAccount? {
        accounts.first { $0.id == selectedAccountID } ?? accounts.first
    }

    private var selectedTitle: String {
        selectedAccount.map(titleFor) ?? "尚未设置"
    }

    var body: some View {
        HStack(alignment: .center, spacing: SettingsListLayout.spaceM) {
            VStack(alignment: .leading, spacing: SettingsListLayout.spaceXS) {
                Text("默认发信账户")
                    .font(SettingsListTypography.rowTitleSelected)
                Text("普通发信默认使用此账户；审批卡仍会显示实际 From。")
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: SettingsListLayout.spaceM)

            Menu {
                ForEach(accounts) { account in
                    Button {
                        onSelect(account.id)
                    } label: {
                        HStack {
                            Text(titleFor(account))
                            if account.id == selectedAccount?.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selectedTitle)
                        .font(SettingsListTypography.rowTitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.secondary.opacity(0.08), in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).stroke(Color.secondary.opacity(0.10), lineWidth: 1))
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .frame(maxWidth: 360, alignment: .trailing)
            .accessibilityLabel("默认发信账户")
            .accessibilityValue(selectedTitle)
        }
        .frame(minHeight: SettingsListLayout.rowMinHeight)
    }
}

struct MailSourceDetailView: View {
    @ObservedObject var viewModel: AppViewModel

    private var presentation: NativeMailBrowserPresentation {
        viewModel.mailBrowserPresentation
    }

    private var selectedAccount: MailAccount? {
        presentation.account(id: viewModel.selectedMailAccountID)
    }

    private var selectedMailbox: MailMailbox? {
        presentation.mailbox(id: viewModel.selectedMailMailboxID)
    }

    private var selectedMessage: MailMessageSummary? {
        presentation.message(id: viewModel.selectedMailMessageID)
    }

    var body: some View {
        Group {
            if let selectedMessage {
                MailMessageDetailPane(account: selectedAccount, mailbox: selectedMailbox, message: selectedMessage, viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                MailDetailEmptyState(onAdd: { viewModel.presentAddMailAccountSheet() })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppShellColors.detailBackground)
        .sheet(isPresented: $viewModel.isPresentingAddMailAccountSheet) {
            AddMailAccountSheet(viewModel: viewModel)
        }
    }
}

private struct MailSettingsEmptyStateCard: View {
    var onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceM) {
            HStack(alignment: .top, spacing: SettingsListLayout.spaceM) {
                ZStack {
                    RoundedRectangle(cornerRadius: SettingsListLayout.radiusM, style: .continuous)
                        .fill(Color.accentColor.opacity(0.13))
                    Image(systemName: "envelope.badge")
                        .font(SettingsListTypography.largeIcon)
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: SettingsListLayout.spaceXS) {
                    Text("暂无邮件账户")
                        .font(SettingsListTypography.rowTitleSelected)
                    Text("添加 IMAP/SMTP 账户后，康纳同学会同步最近邮件并创建定时刷新任务。")
                        .font(SettingsListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: onAdd) {
                Label("添加邮件账户", systemImage: "plus")
                    .font(SettingsListTypography.actionTitle)
                    .padding(.horizontal, SettingsListLayout.spaceM)
                    .padding(.vertical, SettingsListLayout.spaceXS)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(SettingsListLayout.spaceL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: SettingsListLayout.radiusL, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SettingsListLayout.radiusL, style: .continuous).stroke(Color.secondary.opacity(SettingsListLayout.hairlineOpacity), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

private struct MailSettingsAccountRow: View {
    var account: MailAccount
    var mailboxCount: Int
    var unreadCount: Int
    var onAdd: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: SettingsListLayout.spaceM) {
            Image(systemName: statusIcon)
                .font(SettingsListTypography.icon)
                .foregroundStyle(statusColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(account.displayName)
                    .font(SettingsListTypography.rowTitleSelected)
                Text("\(primaryEmail) · \(providerName) · \(mailboxCount) 个文件夹 · \(account.health.summary)")
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Text(unreadCount > 0 ? "\(unreadCount) 未读" : statusTitle)
                .font(SettingsListTypography.rowCaptionEmphasized)
                .foregroundStyle(statusColor)
            Button(action: onAdd) {
                Label("添加", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("添加另一个邮件账户")
            .accessibilityLabel("添加另一个邮件账户")
        }
        .frame(minHeight: SettingsListLayout.prominentRowMinHeight, alignment: .center)
    }

    private var primaryEmail: String {
        account.identities.first?.address.email ?? account.id.rawValue
    }

    private var providerName: String {
        switch account.provider {
        case .genericIMAPSMTP: "IMAP/SMTP"
        case .gmail: "Gmail（旧账户）"
        case .microsoft365: "Microsoft 365（旧账户）"
        case .jmap: "JMAP"
        case .localFixture: "本地测试账户"
        }
    }

    private var statusTitle: String {
        switch account.health.status {
        case .ready: "正常"
        case .degraded: "降级"
        case .blocked: "阻止"
        case .unauthenticated: "需认证"
        case .unknown: "未知"
        }
    }

    private var statusIcon: String {
        switch account.health.status {
        case .ready: "checkmark.seal"
        case .degraded: "exclamationmark.triangle"
        case .blocked, .unauthenticated: "lock.trianglebadge.exclamationmark"
        case .unknown: "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch account.health.status {
        case .ready: .green
        case .degraded: .orange
        case .blocked, .unauthenticated: .red
        case .unknown: .secondary
        }
    }
}

private struct MailDetailEmptyState: View {
    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: AppShellLayout.spaceM) {
            Image(systemName: "envelope.open")
                .font(.system(size: 42, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("选择一封邮件")
                .font(AgentChatTypography.title)
            Text("从左侧邮件列表选择邮件查看详情，或添加新的 IMAP/SMTP 账户开始同步。")
                .font(AgentChatTypography.meta)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button(action: onAdd) {
                Label("添加邮件账户", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppShellLayout.spaceXL)
    }
}

struct MailHTMLBodyLoadState: Equatable {
    private(set) var lastLoadedHTML: String?

    mutating func shouldReload(html: String) -> Bool {
        guard lastLoadedHTML != html else { return false }
        lastLoadedHTML = html
        return true
    }
}

struct MailBodyLoadToken: Equatable {
    var messageID: MailMessageID
    var generation: Int
}

struct MailBodyLoadRequestGate: Equatable {
    private(set) var activeToken: MailBodyLoadToken?
    private var nextGeneration = 0

    mutating func begin(messageID: MailMessageID) -> MailBodyLoadToken {
        nextGeneration += 1
        let token = MailBodyLoadToken(messageID: messageID, generation: nextGeneration)
        activeToken = token
        return token
    }

    func shouldCommit(_ token: MailBodyLoadToken) -> Bool {
        activeToken == token
    }
}

struct MailHTMLBodyLayout: Equatable {
    enum Mode: Equatable {
        case inline
        case scrollable
    }

    var mode: Mode
    var height: CGFloat
    var documentHeight: CGFloat

    static let initial = MailHTMLBodyLayout(mode: .inline, height: 200, documentHeight: 200)
}

struct MailHTMLBodyScrollPolicy: Equatable {
    var isInternalScrollingEnabled: Bool
    var forwardsWheelEventsToParent: Bool

    static let pageScrolling = MailHTMLBodyScrollPolicy(
        isInternalScrollingEnabled: false,
        forwardsWheelEventsToParent: true
    )
}

struct MailHTMLBodyHeightStabilizer: Equatable {
    var minimumHeight: CGFloat = 200
    var inlineHeightLimit: CGFloat = 5_000
    var scrollableViewportHeight: CGFloat = 640
    var bottomPadding: CGFloat = 12
    var significantDelta: CGFloat = 4

    func stabilizedLayout(current: MailHTMLBodyLayout, measuredDocumentHeight: CGFloat) -> MailHTMLBodyLayout? {
        let padded = measuredDocumentHeight + bottomPadding
        let next = MailHTMLBodyLayout(
            mode: .inline,
            height: max(padded, minimumHeight),
            documentHeight: measuredDocumentHeight
        )
        guard next.mode != current.mode
            || abs(next.height - current.height) >= significantDelta
            || abs(next.documentHeight - current.documentHeight) >= significantDelta else { return nil }
        return next
    }
}

private final class MailHTMLPassthroughScrollWebView: WKWebView {
    var forwardsScrollWheelToParent = false

    override func scrollWheel(with event: NSEvent) {
        guard forwardsScrollWheelToParent else {
            super.scrollWheel(with: event)
            return
        }
        nextResponder?.scrollWheel(with: event)
    }
}

/// WKWebView wrapper for rendering email HTML bodies with image support.
private struct MailHTMLBodyView: NSViewRepresentable {
    var htmlContent: String
    var scrollPolicy: MailHTMLBodyScrollPolicy
    @Binding var layout: MailHTMLBodyLayout

    func makeCoordinator() -> Coordinator {
        Coordinator(layout: $layout)
    }

    func makeNSView(context: Context) -> MailHTMLPassthroughScrollWebView {
        let config = WKWebViewConfiguration()
        // Disable JavaScript for security (email HTML should not execute scripts)
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = false
        config.defaultWebpagePreferences = preferences
        let view = MailHTMLPassthroughScrollWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        view.isHidden = true
        configureScrolling(for: view)
        return view
    }

    func updateNSView(_ nsView: MailHTMLPassthroughScrollWebView, context: Context) {
        context.coordinator.layout = $layout
        configureScrolling(for: nsView)
        guard context.coordinator.shouldReload(html: htmlContent) else { return }
        nsView.isHidden = true
        nsView.loadHTMLString(htmlContent, baseURL: nil)
    }

    private func configureScrolling(for view: MailHTMLPassthroughScrollWebView) {
        view.forwardsScrollWheelToParent = scrollPolicy.forwardsWheelEventsToParent
        view.enclosingScrollView?.hasVerticalScroller = scrollPolicy.isInternalScrollingEnabled
        view.enclosingScrollView?.verticalScrollElasticity = scrollPolicy.isInternalScrollingEnabled ? .automatic : .none
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var layout: Binding<MailHTMLBodyLayout>
        private var loadState = MailHTMLBodyLoadState()
        private let heightStabilizer = MailHTMLBodyHeightStabilizer()
        private var measurementGeneration = 0

        init(layout: Binding<MailHTMLBodyLayout>) {
            self.layout = layout
        }

        func shouldReload(html: String) -> Bool {
            guard loadState.shouldReload(html: html) else { return false }
            measurementGeneration += 1
            return true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.isHidden = false
            scheduleHeightMeasurements(for: webView, generation: measurementGeneration)
        }

        private func scheduleHeightMeasurements(for webView: WKWebView, generation: Int) {
            measureHeight(of: webView, generation: generation)
            for delayNanoseconds in [150_000_000, 400_000_000, 900_000_000] {
                Task { @MainActor [weak self, weak webView] in
                    try? await Task.sleep(nanoseconds: UInt64(delayNanoseconds))
                    guard let self, let webView else { return }
                    self.measureHeight(of: webView, generation: generation)
                }
            }
        }

        private func measureHeight(of webView: WKWebView, generation: Int) {
            let script = """
            Math.max(
                document.body ? document.body.scrollHeight : 0,
                document.documentElement ? document.documentElement.scrollHeight : 0,
                200
            )
            """
            webView.evaluateJavaScript(script) { [weak self] value, _ in
                guard let self else { return }
                Task { @MainActor in
                    guard generation == self.measurementGeneration else { return }
                    guard let numericHeight = Self.numericHeight(from: value) else { return }
                    guard let stabilized = self.heightStabilizer.stabilizedLayout(current: self.layout.wrappedValue, measuredDocumentHeight: numericHeight) else { return }
                    self.layout.wrappedValue = stabilized
                }
            }
        }

        private static func numericHeight(from value: Any?) -> CGFloat? {
            if let doubleValue = value as? Double {
                return CGFloat(doubleValue)
            } else if let intValue = value as? Int {
                return CGFloat(intValue)
            } else if let number = value as? NSNumber {
                return CGFloat(truncating: number)
            } else {
                return nil
            }
        }
    }
}

private struct MailMessageDetailPane: View {
    var account: MailAccount?
    var mailbox: MailMailbox?
    var message: MailMessageSummary
    @ObservedObject var viewModel: AppViewModel
    @State private var bodyDisplay: MailBodyDisplayPresentation = .loading
    @State private var bodyWebLayout: MailHTMLBodyLayout = .initial
    @State private var allowRemoteImagesForMessage = false
    @State private var bodyLoadGate = MailBodyLoadRequestGate()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppShellLayout.spaceL) {
                MailMessageHero(account: account, mailbox: mailbox, message: message)
                MailInfoSection(title: "邮件正文", systemImage: "doc.text.magnifyingglass") {
                    if bodyDisplay.kind == .html, let bodyHTML = bodyDisplay.html {
                        let sanitized = MailHTMLBodySanitizer().prepareHTML(
                            bodyHTML,
                            policy: MailHTMLDisplayPolicy(remoteContentMode: allowRemoteImagesForMessage ? .allowForMessage : .block)
                        )
                        if sanitized.blockedRemoteImageCount > 0 {
                            MailRemoteImagesBlockedBanner(blockedCount: sanitized.blockedRemoteImageCount) {
                                bodyWebLayout = .initial
                                allowRemoteImagesForMessage = true
                            }
                        }
                        MailHTMLBodyView(
                            htmlContent: sanitized.html,
                            scrollPolicy: .pageScrolling,
                            layout: $bodyWebLayout
                        )
                        .frame(height: bodyWebLayout.height)
                        .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text(bodyDisplay.text)
                            .font(AgentChatTypography.meta)
                            .foregroundStyle(bodyDisplay.kind == .error ? .secondary : .primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                MailInfoSection(title: "收件人", systemImage: "person.2") {
                    VStack(alignment: .leading, spacing: AppShellLayout.spaceS) {
                        MailAddressLine(label: "发件人", values: [message.from])
                        MailAddressLine(label: "收件人", values: message.to)
                        if !message.cc.isEmpty {
                            MailAddressLine(label: "抄送", values: message.cc)
                        }
                    }
                }
            }
            .padding(AppShellLayout.spaceXL)
            .frame(maxWidth: AppShellLayout.contentMaxWidth, alignment: .leading)
        }
        .task(id: message.id) {
            let token = bodyLoadGate.begin(messageID: message.id)
            allowRemoteImagesForMessage = false
            bodyWebLayout = .initial
            bodyDisplay = .loading
            let display = await viewModel.loadMailBodyDisplay(for: token.messageID)
            guard !Task.isCancelled else { return }
            guard bodyLoadGate.shouldCommit(token) else { return }
            bodyDisplay = display
        }
    }
}

private struct MailRemoteImagesBlockedBanner: View {
    var blockedCount: Int
    var onLoadRemoteImages: () -> Void

    var body: some View {
        HStack(spacing: AppShellLayout.spaceS) {
            Image(systemName: "eye.slash")
                .foregroundStyle(.secondary)
            Text("已阻止 \(blockedCount) 张远程图片以保护隐私")
                .font(AgentChatTypography.micro)
                .foregroundStyle(.secondary)
            Spacer(minLength: AppShellLayout.spaceS)
            Button("加载此邮件的远程图片", action: onLoadRemoteImages)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(AppShellLayout.spaceS)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct MailMessageHero: View {
    var account: MailAccount?
    var mailbox: MailMailbox?
    var message: MailMessageSummary

    var body: some View {
        HStack(alignment: .top, spacing: AppShellLayout.spaceL) {
            ZStack {
                RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: message.flags.isRead ? "envelope.open" : "envelope.badge")
                    .font(.system(size: 24, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: AppShellLayout.spaceS) {
                HStack(alignment: .firstTextBaseline, spacing: AppShellLayout.spaceS) {
                    Text(message.subject)
                        .font(AgentChatTypography.title)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    MailStatusPill(status: message.flags.isRead ? "已读" : "未读", color: message.flags.isRead ? .secondary : .blue)
                    if message.hasAttachments {
                        MailStatusPill(status: "附件", color: .teal, systemImage: "paperclip")
                    }
                }
                Text("From \(message.from.name ?? message.from.email) · \(message.from.email)")
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack(spacing: AppShellLayout.spaceS) {
                    MailStatusPill(status: account?.displayName ?? "未选择账户", color: .secondary, systemImage: "person.crop.circle")
                    MailStatusPill(status: mailbox?.name ?? "未选择文件夹", color: .secondary, systemImage: "folder")
                    MailStatusPill(status: message.date.connorLocalFormatted(date: .medium, time: .short), color: .secondary, systemImage: "clock")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(AppShellLayout.spaceL)
        .background(AppShellColors.cardBackground, in: RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous)
                .stroke(AppShellColors.hairline, lineWidth: 1)
        )
    }
}

private struct MailAddressLine: View {
    var label: String
    var values: [MailAddress]

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: AppShellLayout.spaceL, verticalSpacing: AppShellLayout.spaceS) {
            GridRow {
                Text(label)
                    .font(AgentChatTypography.microEmphasis)
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)
                Text(values.map(display).joined(separator: ", "))
                    .font(AgentChatTypography.meta)
                    .textSelection(.enabled)
            }
        }
    }

    private func display(_ address: MailAddress) -> String {
        if let name = address.name, !name.isEmpty {
            return "\(name) <\(address.email)>"
        }
        return address.email
    }
}

struct AddMailAccountSheet: View {
    private enum Layout {
        static let sheetWidth: CGFloat = 640
        static let iconSize: CGFloat = 44
        static let labelColumnWidth: CGFloat = 108
        static let menuWidth: CGFloat = 188
        static let portFieldWidth: CGFloat = 92
    }

    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedPreset: MailAccountProviderPreset = .apple
    @State private var displayName: String = ""
    @State private var email: String = ""
    @State private var credential: String = ""
    @State private var lastAutofilledDisplayName: String = ""
    @State private var incomingHost: String = MailAccountProviderPreset.apple.incomingHost
    @State private var incomingPort: Int = MailAccountProviderPreset.apple.incomingPort
    @State private var outgoingHost: String = MailAccountProviderPreset.apple.outgoingHost
    @State private var outgoingPort: Int = MailAccountProviderPreset.apple.outgoingPort
    @State private var isSubmitting: Bool = false
    @State private var setupMessage: String?
    @State private var setupError: String?
    @State private var isAutoconfigLoading: Bool = false
    @State private var autoconfigResult: MailAutoconfigResult?
    @State private var isTestingConnection: Bool = false
    @State private var testResult: MailConnectionTestResult?

    private var isManualPreset: Bool {
        selectedPreset == .other
    }

    private var saveDisabled: Bool {
        email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || incomingHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || outgoingHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceXL) {
            header
            formContent
            MailAccountSetupHintCard(
                title: selectedPreset.subtitle,
                guidance: selectedPreset.guidance
            )
            setupFeedback
            footer
        }
        .padding(SettingsListLayout.spaceXL)
        .frame(width: Layout.sheetWidth)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { applyPreset(selectedPreset) }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: SettingsListLayout.spaceM) {
            ZStack {
                RoundedRectangle(cornerRadius: SettingsListLayout.radiusM, style: .continuous)
                    .fill(Color.accentColor.opacity(0.13))
                Image(systemName: "envelope.badge")
                    .font(SettingsListTypography.largeIcon)
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: Layout.iconSize, height: Layout.iconSize)

            VStack(alignment: .leading, spacing: SettingsListLayout.spaceXS) {
                Text("添加邮件账户")
                    .font(SettingsListTypography.header)
                Text("选择服务商后，康纳同学会预填常见 IMAP/SMTP 配置。添加后会创建账户并开始准备同步。")
                    .font(SettingsListTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceM) {
            MailAccountSetupSection(title: "账户信息") {
                MailAccountSetupRow("服务商", labelWidth: Layout.labelColumnWidth) {
                    Picker("服务商", selection: $selectedPreset) {
                        ForEach(MailAccountProviderPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.regular)
                    .frame(width: Layout.menuWidth, alignment: .leading)
                    .onChange(of: selectedPreset) { _, preset in applyPreset(preset) }
                }

                Divider().padding(.leading, Layout.labelColumnWidth + SettingsListLayout.spaceM)

                MailAccountSetupRow("显示名称", labelWidth: Layout.labelColumnWidth) {
                    TextField("例如 Apple iCloud", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }

                MailAccountSetupRow("邮箱地址", labelWidth: Layout.labelColumnWidth) {
                    HStack(spacing: 8) {
                        TextField("name@example.com", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.emailAddress)

                        Button {
                            Task { await runAutoconfig() }
                        } label: {
                            if isAutoconfigLoading {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("自动检测")
                            }
                        }
                        .disabled(isAutoconfigLoading || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                MailAccountSetupRow("授权凭据", labelWidth: Layout.labelColumnWidth) {
                    VStack(alignment: .leading, spacing: SettingsListLayout.spaceXS) {
                        SecureField("授权码 / App Password", text: $credential)
                            .textFieldStyle(.roundedBorder)
                        Text("请使用服务商生成的授权码 / App Password；QQ、网易等通常不能使用网页登录密码。")
                            .font(SettingsListTypography.rowCaption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

            }

            MailAccountSetupSection(title: "服务器预设") {
                MailAccountSetupRow("收件服务器", labelWidth: Layout.labelColumnWidth) {
                    TextField("imap.example.com", text: $incomingHost)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!isManualPreset)
                        .opacity(isManualPreset ? 1 : 0.68)
                }

                MailAccountSetupRow("收件端口", labelWidth: Layout.labelColumnWidth) {
                    TextField("993", value: $incomingPort, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: Layout.portFieldWidth, alignment: .leading)
                        .disabled(!isManualPreset)
                        .opacity(isManualPreset ? 1 : 0.68)
                }

                MailAccountSetupRow("发件服务器", labelWidth: Layout.labelColumnWidth) {
                    TextField("smtp.example.com", text: $outgoingHost)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!isManualPreset)
                        .opacity(isManualPreset ? 1 : 0.68)
                }

                MailAccountSetupRow("发件端口", labelWidth: Layout.labelColumnWidth) {
                    VStack(alignment: .leading, spacing: SettingsListLayout.spaceXS) {
                        TextField("587", value: $outgoingPort, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: Layout.portFieldWidth, alignment: .leading)
                            .disabled(!isManualPreset)
                            .opacity(isManualPreset ? 1 : 0.68)
                        Text("发送通道目前使用 SMTP STARTTLS，推荐端口 587；465 隐式 TLS 会在发送时提示暂未支持。")
                            .font(SettingsListTypography.rowCaption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var setupFeedback: some View {
        if let testResult {
            VStack(alignment: .leading, spacing: 4) {
                Text("连接测试结果")
                    .font(SettingsListTypography.rowCaptionEmphasized)
                    .foregroundStyle(.secondary)
                Text(testResult.summary)
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(testResult.isSuccess ? .green : .red)
                    .textSelection(.enabled)
            }
        } else if let setupError {
            Text(setupError)
                .font(SettingsListTypography.rowCaption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        } else if let setupMessage {
            Text(setupMessage)
                .font(SettingsListTypography.rowCaption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack(spacing: SettingsListLayout.spaceS) {
            Button {
                Task { await runConnectionTest() }
            } label: {
                if isTestingConnection {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("测试连接")
                }
            }
            .disabled(isTestingConnection || email.isEmpty || credential.isEmpty)

            Spacer()

            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isSubmitting)
            Button {
                Task { await submitAccountSetup() }
            } label: {
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("添加账户")
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(saveDisabled || isSubmitting)
        }
    }

    @MainActor
    private func submitAccountSetup() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        setupError = nil
        setupMessage = "正在添加账户…"
        do {
            try await viewModel.addMailAccountAndPrepareSync(
                preset: selectedPreset,
                displayName: displayName,
                email: email,
                credential: credential,
                incomingHost: incomingHost,
                incomingPort: incomingPort,
                outgoingHost: outgoingHost,
                outgoingPort: outgoingPort
            )
            dismiss()
        } catch {
            setupError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            setupMessage = nil
            isSubmitting = false
        }
    }

    private func applyPreset(_ preset: MailAccountProviderPreset) {
        incomingHost = preset.incomingHost
        incomingPort = preset.incomingPort
        outgoingHost = preset.outgoingHost
        outgoingPort = preset.outgoingPort
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || displayName == lastAutofilledDisplayName {
            displayName = preset.title
            lastAutofilledDisplayName = preset.title
        }
    }

    @MainActor
    private func runAutoconfig() async {
        let emailValue = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard emailValue.contains("@"), emailValue.contains(".") else { return }

        isAutoconfigLoading = true
        setupMessage = "正在自动检测服务器配置…"
        setupError = nil

        let service = MailAutoconfigService()
        if let result = try? await service.discover(email: emailValue) {
            autoconfigResult = result
            incomingHost = result.incomingHost
            incomingPort = result.incomingPort
            outgoingHost = result.outgoingHost
            outgoingPort = result.outgoingPort
            setupMessage = "已自动检测到服务器配置"
            selectedPreset = .other
        } else {
            setupMessage = nil
            setupError = "未找到自动配置，请手动填写服务器信息"
        }

        isAutoconfigLoading = false
    }

    @MainActor
    private func runConnectionTest() async {
        let emailValue = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let credentialValue = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !emailValue.isEmpty, !credentialValue.isEmpty else {
            setupError = "请先填写邮箱地址和授权凭据"
            return
        }

        isTestingConnection = true
        setupMessage = "正在测试连接…"
        setupError = nil
        testResult = nil

        let service = MailConnectionTestService()
        do {
            let result = try await service.testConnection(
                email: emailValue,
                credential: credentialValue,
                incomingHost: incomingHost,
                incomingPort: incomingPort,
                incomingSecurity: .tls,
                outgoingHost: outgoingHost,
                outgoingPort: outgoingPort,
                outgoingSecurity: .startTLS
            )
            testResult = result
            if result.isSuccess {
                setupMessage = "连接测试通过"
            } else {
                setupError = "连接测试失败，请检查配置"
            }
        } catch {
            setupError = "测试失败: \(error.localizedDescription)"
        }

        isTestingConnection = false
    }
}

private struct MailAccountSetupSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceS) {
            Text(title)
                .font(SettingsListTypography.rowCaptionEmphasized)
                .foregroundStyle(.secondary)
            VStack(spacing: SettingsListLayout.spaceXS) {
                content
            }
            .padding(.horizontal, SettingsListLayout.spaceL)
            .padding(.vertical, SettingsListLayout.spaceM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppShellColors.cardBackground, in: RoundedRectangle(cornerRadius: SettingsListLayout.radiusL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsListLayout.radiusL, style: .continuous)
                    .stroke(Color.secondary.opacity(SettingsListLayout.hairlineOpacity), lineWidth: 1)
            )
        }
    }
}

private struct MailAccountSetupRow<Content: View>: View {
    var title: String
    var labelWidth: CGFloat
    @ViewBuilder var content: Content

    init(_ title: String, labelWidth: CGFloat, @ViewBuilder content: () -> Content) {
        self.title = title
        self.labelWidth = labelWidth
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SettingsListLayout.spaceM) {
            Text(title)
                .font(SettingsListTypography.rowTitleSelected)
                .foregroundStyle(.primary)
                .frame(width: labelWidth, alignment: .trailing)
            content
                .font(SettingsListTypography.rowTitle)
                .frame(maxWidth: .infinity, minHeight: SettingsListLayout.fieldHeight, alignment: .leading)
        }
        .frame(minHeight: SettingsListLayout.fieldHeight)
    }
}

private struct MailAccountSetupHintCard: View {
    var title: String
    var guidance: String

    var body: some View {
        HStack(alignment: .top, spacing: SettingsListLayout.spaceM) {
            Image(systemName: "lock.shield")
                .font(SettingsListTypography.icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: SettingsListLayout.spaceXS) {
                Text(title)
                    .font(SettingsListTypography.rowTitleSelected)
                Text(guidance)
                    .font(SettingsListTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("添加后会创建本地账户并尝试首次同步。请使用服务商提供的授权码或 App Password；Connor 不保存邮箱主密码。")
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SettingsListLayout.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppShellColors.subtleCardBackground, in: RoundedRectangle(cornerRadius: SettingsListLayout.radiusM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsListLayout.radiusM, style: .continuous)
                .stroke(Color.secondary.opacity(SettingsListLayout.hairlineOpacity), lineWidth: 1)
        )
    }
}

private struct MailInfoSection<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppShellLayout.spaceM) {
            Label(title, systemImage: systemImage)
                .font(AppListTypography.header)
                .foregroundStyle(.primary)
            content
        }
        .padding(AppShellLayout.spaceL)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(AppShellColors.cardBackground, in: RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous)
                .stroke(AppShellColors.hairline, lineWidth: 1)
        )
    }
}



private struct MailStatusPill: View {
    var status: String
    var color: Color
    var systemImage: String? = nil

    var body: some View {
        Label {
            Text(status)
                .lineLimit(1)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10.5, weight: .semibold))
            }
        }
        .font(AppListTypography.rowCaptionEmphasized)
        .foregroundStyle(color)
        .padding(.horizontal, AppShellLayout.spaceS)
        .frame(height: 23)
        .background(color.opacity(0.12), in: Capsule())
    }
}
