import SwiftUI
import ConnorGraphCore
import ConnorGraphAppSupport

struct UserIdentitySettingsView: View {
    @ObservedObject var identityStore: AppUserIdentityStore
    @ObservedObject var connectivity: AppNetworkConnectivity = .shared
    @ObservedObject var backendConnectivity: AppBackendConnectivity = .shared
    @State private var mode: AuthenticationMode = .login
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isSubmitting = false
    @State private var didAttemptSubmit = false
    @State private var didRetryStoredSession = false

    enum AuthenticationMode: String, CaseIterable, Identifiable {
        case login = "登录"
        case register = "创建账号"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceXL) {
            Group {
                switch identityStore.authenticationState {
                case .signedIn(let user): signedInContent(user)
                case .restoring: restoringView
                case .signedOut, .expired: authenticationView
                }
            }
            deviceSyncSettings
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .task(id: identityStore.currentUser?.id) {
            if connectivity.isConnected, identityStore.currentUser == nil, identityStore.hasStoredSession, !didRetryStoredSession {
                didRetryStoredSession = true
                await identityStore.restoreSession()
            }
        }
        .onChange(of: mode) { _, _ in didAttemptSubmit = false }
    }

    private var authenticationView: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceXL) {
            SettingsGroup(title: "账号访问") {
                HStack(spacing: SettingsListLayout.spaceM) {
                    ZStack {
                        Circle().fill(Color.accentColor.opacity(0.12))
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: SettingsListLayout.spaceXS) {
                        Text(mode == .login ? "登录康纳账号" : "创建康纳账号")
                            .font(SettingsListTypography.rowTitleSelected)
                        Text("登录后同步账号资料和登录状态。")
                            .font(SettingsListTypography.rowCaption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider()

                Picker("账号操作", selection: $mode) {
                    ForEach(AuthenticationMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: SettingsListLayout.pickerControlWidth)
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: SettingsListLayout.spaceM) {
                    accountField("用户名", placeholder: "请输入用户名", text: $username, systemImage: "person")
                    if mode == .register {
                        accountField("邮箱", placeholder: "name@example.com", text: $email, systemImage: "envelope")
                    }
                    accountSecureField("密码", placeholder: "请输入密码", text: $password, systemImage: "lock")
                    if mode == .register {
                        accountSecureField("确认密码", placeholder: "再次输入密码", text: $confirmation, systemImage: "lock.rotation")
                    }
                }

                if !connectivity.isConnected {
                    statusMessage("当前没有网络连接，登录和注册暂不可用。", systemImage: "wifi.slash", color: .orange)
                } else if backendConnectivity.state == .unreachable {
                    statusMessage("当前无法连接到康纳服务器，登录和注册暂不可用。", systemImage: "exclamationmark.icloud", color: .orange)
                } else if case .expired = identityStore.authenticationState {
                    statusMessage("登录已失效，请重新登录。", systemImage: "exclamationmark.circle", color: .orange)
                } else if let error = visibleError {
                    HStack(alignment: .firstTextBaseline, spacing: SettingsListLayout.spaceS) {
                        statusMessage(error, systemImage: "exclamationmark.triangle", color: .red)
                        if identityStore.hasStoredSession {
                            Button("重新连接") {
                                Task { await retryStoredSession() }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(AppButtonLayout.controlSize)
                            .disabled(isSubmitting || !canUseAccountService)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button { Task { await submit() } } label: {
                        HStack(spacing: SettingsListLayout.spaceS) {
                            if isSubmitting { ProgressView().controlSize(.small) }
                            Text(mode == .login ? "登录" : "创建账号")
                                .font(SettingsListTypography.actionTitle)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(AppButtonLayout.controlSize)
                    .disabled(isSubmitting || !canUseAccountService)
                }
            }

        }
    }

    private var restoringView: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("正在恢复康纳账号…").font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    @ViewBuilder
    private func signedInContent(_ user: ConnorRemoteUserIdentity) -> some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceXL) {
            SettingsGroup(title: "康纳账号") {
                HStack(spacing: SettingsListLayout.spaceL) {
                    IdentityAvatarView(user: user, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.displayName).font(AppTypography.pageTitle)
                        Text("@\(user.username)").foregroundStyle(.secondary)
                        Text(user.email).font(SettingsListTypography.rowSubtitle).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("退出登录", role: .destructive) { Task { await identityStore.logout() } }
                        .buttonStyle(.bordered)
                        .disabled(!canUseAccountService)
                }
                if !connectivity.isConnected {
                    statusMessage("当前没有网络连接，退出登录暂不可用。", systemImage: "wifi.slash", color: .orange)
                } else if backendConnectivity.state == .unreachable {
                    statusMessage("当前无法连接到康纳服务器，退出登录暂不可用。", systemImage: "exclamationmark.icloud", color: .orange)
                }
                Divider()
                SettingsValueRow(title: "注册时间", value: user.createdAt.formatted(date: .long, time: .omitted))
            }

        }
    }

    private func accountField(_ title: String, placeholder: String, text: Binding<String>, systemImage: String) -> some View {
        HStack(spacing: SettingsListLayout.spaceM) {
            Label(title, systemImage: systemImage)
                .font(SettingsListTypography.rowTitleSelected)
                .frame(width: 100, alignment: .leading)
            TextField(placeholder, text: text)
                .font(SettingsListTypography.rowTitle)
                .textFieldStyle(.roundedBorder)
        }
        .frame(minHeight: SettingsListLayout.fieldHeight)
    }

    private func accountSecureField(_ title: String, placeholder: String, text: Binding<String>, systemImage: String) -> some View {
        HStack(spacing: SettingsListLayout.spaceM) {
            Label(title, systemImage: systemImage)
                .font(SettingsListTypography.rowTitleSelected)
                .frame(width: 100, alignment: .leading)
            SecureField(placeholder, text: text)
                .font(SettingsListTypography.rowTitle)
                .textFieldStyle(.roundedBorder)
        }
        .frame(minHeight: SettingsListLayout.fieldHeight)
    }

    private func statusMessage(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(SettingsListTypography.rowCaption).foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accountCapabilityRow(systemImage: String, title: String, subtitle: String) -> some View {
        HStack(spacing: SettingsListLayout.spaceM) {
            Image(systemName: systemImage)
                .font(SettingsListTypography.icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: SettingsListLayout.spaceXS) {
                Text(title).font(SettingsListTypography.rowTitleSelected)
                Text(subtitle).font(SettingsListTypography.rowCaption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(minHeight: SettingsListLayout.rowMinHeight)
    }

    private var deviceSyncSettings: some View {
        SettingsGroup(title: "设备间同步") {
            HStack(spacing: SettingsListLayout.spaceM) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(SettingsListTypography.icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: SettingsListLayout.spaceXS) {
                    Text("在不同客户端同步我的数据")
                        .font(SettingsListTypography.rowTitleSelected)
                    Text("同步账号资料、设置和会话；本机数据仍可离线使用。")
                        .font(SettingsListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(
                    "在不同客户端同步我的数据",
                    isOn: Binding(
                        get: { identityStore.isDeviceSyncEnabled },
                        set: { identityStore.setDeviceSyncEnabled($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }
            .frame(minHeight: SettingsListLayout.rowMinHeight)

            Divider()

            HStack(spacing: SettingsListLayout.spaceM) {
                let presentation = syncStatusPresentation
                Image(systemName: presentation.systemImage)
                    .font(SettingsListTypography.icon)
                    .foregroundStyle(presentation.color)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: SettingsListLayout.spaceXS) {
                    Text("同步状态")
                        .font(SettingsListTypography.rowTitleSelected)
                    Text(presentation.text)
                        .font(SettingsListTypography.rowCaption)
                        .foregroundStyle(presentation.color)
                }
                Spacer()
                if identityStore.isDeviceSyncEnabled, identityStore.currentUser != nil {
                    Button("立即同步") { identityStore.syncNow() }
                        .buttonStyle(.bordered)
                        .controlSize(AppButtonLayout.controlSize)
                        .disabled(!canUseAccountService || isSyncing)
                }
            }
            .frame(minHeight: SettingsListLayout.rowMinHeight)
        }
    }

    private var isSyncing: Bool {
        if case .syncing = identityStore.deviceSyncStatus { return true }
        if case .connecting = identityStore.deviceSyncStatus { return true }
        return false
    }

    private var syncStatusPresentation: (text: String, systemImage: String, color: Color) {
        guard identityStore.isDeviceSyncEnabled else {
            return ("已关闭，不会上传或下载设备数据。", "pause.circle", .secondary)
        }
        guard identityStore.currentUser != nil else {
            return ("登录康纳账号后可以开启同步。", "person.crop.circle.badge.questionmark", .secondary)
        }
        guard connectivity.isConnected else {
            return ("当前离线，将在网络恢复后继续。", "wifi.slash", .orange)
        }
        guard backendConnectivity.state != .unreachable else {
            return ("无法连接康纳服务器，将自动重试。", "exclamationmark.icloud", .orange)
        }
        switch identityStore.deviceSyncStatus {
        case .disabled:
            return ("已关闭，不会上传或下载设备数据。", "pause.circle", .secondary)
        case .waitingForLogin:
            return ("登录康纳账号后可以开启同步。", "person.crop.circle.badge.questionmark", .secondary)
        case .offline:
            return ("连接暂不可用，将自动重试。", "wifi.slash", .orange)
        case .connecting:
            return ("正在连接同步服务…", "network", .secondary)
        case .syncing:
            return ("正在后台同步…", "arrow.triangle.2.circlepath", .accentColor)
        case .upToDate(let date):
            return ("已同步 · \(date.formatted(date: .abbreviated, time: .shortened))", "checkmark.circle.fill", .green)
        case .failed(let message):
            return ("同步失败：\(message)", "exclamationmark.triangle", .red)
        }
    }

    private var formError: String? {
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请输入用户名。" }
        if password.isEmpty { return "请输入密码。" }
        if mode == .register {
            if !email.contains("@") { return "请输入有效邮箱。" }
            if password != confirmation { return "两次输入的密码不一致。" }
        }
        return nil
    }

    private var canUseAccountService: Bool {
        connectivity.isConnected && backendConnectivity.state != .unreachable
    }

    private var visibleError: String? {
        if didAttemptSubmit, let formError { return formError }
        return identityStore.errorMessage
    }

    private func submit() async {
        didAttemptSubmit = true
        guard formError == nil else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        if mode == .login {
            await identityStore.login(username: username, password: password)
        } else {
            await identityStore.register(username: username, email: email, password: password)
        }
        if identityStore.currentUser != nil { password = ""; confirmation = "" }
    }

    private func retryStoredSession() async {
        isSubmitting = true
        defer { isSubmitting = false }
        await identityStore.restoreSession()
    }
}

struct IdentityAvatarView: View {
    var user: ConnorRemoteUserIdentity
    var size: CGFloat

    var body: some View {
        Group {
            if let value = user.avatarURL, let url = URL(string: value) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { fallback }
                }
            } else { fallback }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .overlay(Circle().stroke(.quaternary))
        .accessibilityLabel("\(user.displayName)的头像")
    }

    private var fallback: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.16))
            Text(String(user.displayName.prefix(1)).uppercased())
                .font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(Color.accentColor)
        }
    }
}
