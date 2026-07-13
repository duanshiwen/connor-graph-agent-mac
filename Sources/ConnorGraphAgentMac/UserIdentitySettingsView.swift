import SwiftUI
import ConnorGraphAppSupport

struct UserIdentitySettingsView: View {
    @ObservedObject var identityStore: AppUserIdentityStore
    @State private var mode: AuthenticationMode = .login
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isSubmitting = false
    @State private var didAttemptSubmit = false

    enum AuthenticationMode: String, CaseIterable, Identifiable {
        case login = "登录"
        case register = "创建账号"
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            switch identityStore.authenticationState {
            case .signedIn(let user): signedInContent(user)
            case .restoring: restoringView
            case .signedOut, .expired: authenticationView
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .task(id: identityStore.currentUser?.id) {
            if identityStore.currentUser != nil { await identityStore.refreshLibraries() }
        }
        .onChange(of: mode) { _, _ in didAttemptSubmit = false }
    }

    private var authenticationView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 72, height: 72)
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 38, weight: .medium)).foregroundStyle(Color.accentColor)
                }
                Text("康纳账号").font(.system(size: 24, weight: .semibold))
                Text("登录后管理你创建和订阅的知识库")
                    .font(.callout).foregroundStyle(.secondary)
            }

            VStack(spacing: 18) {
                Picker("账号操作", selection: $mode) {
                    ForEach(AuthenticationMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                VStack(spacing: 12) {
                    accountField("用户名", text: $username, systemImage: "person")
                    if mode == .register {
                        accountField("邮箱", text: $email, systemImage: "envelope")
                    }
                    accountSecureField("密码", text: $password, systemImage: "lock")
                    if mode == .register {
                        accountSecureField("确认密码", text: $confirmation, systemImage: "lock.rotation")
                    }
                }

                if case .expired = identityStore.authenticationState {
                    statusMessage("登录已失效，请重新登录。", systemImage: "exclamationmark.circle", color: .orange)
                } else if let error = visibleError {
                    statusMessage(error, systemImage: "exclamationmark.circle", color: .red)
                }

                Button { Task { await submit() } } label: {
                    HStack(spacing: 8) {
                        if isSubmitting { ProgressView().controlSize(.small) }
                        Text(mode == .login ? "登录" : "创建账号").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity).frame(height: 22)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSubmitting)
            }
            .padding(24)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.quaternary))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)

            Label("康纳账号与本地会话、偏好和 Memory OS 相互独立", systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: 460)
        .padding(.top, 28)
        .padding(.horizontal, 32)
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
                        Text(user.displayName).font(.title3.weight(.semibold))
                        Text("@\(user.username)").foregroundStyle(.secondary)
                        Text(user.email).font(SettingsListTypography.rowSubtitle).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("退出登录", role: .destructive) { Task { await identityStore.logout() } }
                        .buttonStyle(.bordered)
                }
                Divider()
                SettingsValueRow(title: "角色", value: user.role)
                Divider()
                SettingsValueRow(title: "注册时间", value: user.createdAt.formatted(date: .long, time: .omitted))
            }

            libraryGroup(title: "我创建的知识库", emptyMessage: "你还没有创建知识库。", libraries: identityStore.ownedKnowledgeBases)
            libraryGroup(title: "我订阅的知识库", emptyMessage: "你还没有订阅知识库。", libraries: identityStore.subscribedKnowledgeBases.map(\.knowledgeBase))

            if identityStore.isLoadingLibraries { ProgressView("正在刷新知识库…") }
            if let error = identityStore.errorMessage { Text(error).font(SettingsListTypography.rowCaption).foregroundStyle(.red) }
            HStack { Spacer(); Button("刷新") { Task { await identityStore.refreshLibraries() } }.disabled(identityStore.isLoadingLibraries) }
        }
    }

    private func accountField(_ title: String, text: Binding<String>, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 18)
            TextField(title, text: text).textFieldStyle(.plain)
        }
        .padding(.horizontal, 13).frame(height: 42)
        .background(.background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(.quaternary))
    }

    private func accountSecureField(_ title: String, text: Binding<String>, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 18)
            SecureField(title, text: text).textFieldStyle(.plain)
        }
        .padding(.horizontal, 13).frame(height: 42)
        .background(.background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(.quaternary))
    }

    private func statusMessage(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption).foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func libraryGroup(title: String, emptyMessage: String, libraries: [ConnorKnowledgeBaseSummary]) -> some View {
        SettingsGroup(title: title) {
            if libraries.isEmpty {
                Text(emptyMessage).font(SettingsListTypography.rowCaption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(libraries.enumerated()), id: \.element.id) { index, library in
                    KnowledgeLibraryIdentityRow(library: library)
                    if index < libraries.count - 1 { Divider() }
                }
            }
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

private struct KnowledgeLibraryIdentityRow: View {
    var library: ConnorKnowledgeBaseSummary
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "books.vertical").font(.title3).foregroundStyle(.orange).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(library.name).font(SettingsListTypography.rowTitleSelected)
                Text([library.category, library.visibility, "\(library.subscriberCount) 位订阅者"].compactMap { $0 }.joined(separator: " · "))
                    .font(SettingsListTypography.rowCaption).foregroundStyle(.secondary)
                if let description = library.description, !description.isEmpty {
                    Text(description).font(SettingsListTypography.rowSubtitle).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
        }
        .frame(minHeight: SettingsListLayout.prominentRowMinHeight)
    }
}
