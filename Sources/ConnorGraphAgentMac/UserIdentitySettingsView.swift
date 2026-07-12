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

    enum AuthenticationMode: String, CaseIterable, Identifiable {
        case login = "登录"
        case register = "注册"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceXL) {
            switch identityStore.authenticationState {
            case .signedIn(let user): signedInContent(user)
            case .restoring: ProgressView("正在恢复登录状态…").frame(maxWidth: .infinity, minHeight: 180)
            case .signedOut, .expired: authenticationForm
            }
        }
        .task(id: identityStore.currentUser?.id) {
            if identityStore.currentUser != nil { await identityStore.refreshLibraries() }
        }
    }

    private var authenticationForm: some View {
        SettingsGroup(title: "Connor 账号") {
            Picker("账号操作", selection: $mode) {
                ForEach(AuthenticationMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if case .expired = identityStore.authenticationState {
                Label("登录已失效，请重新登录。", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)
            }
            TextField("用户名", text: $username)
                .textFieldStyle(.roundedBorder)
            if mode == .register {
                TextField("邮箱", text: $email)
                    .textFieldStyle(.roundedBorder)
            }
            SecureField("密码", text: $password)
                .textFieldStyle(.roundedBorder)
            if mode == .register {
                SecureField("确认密码", text: $confirmation)
                    .textFieldStyle(.roundedBorder)
            }
            if let error = formError ?? identityStore.errorMessage {
                Text(error).font(SettingsListTypography.rowCaption).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button(mode.rawValue) { Task { await submit() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSubmitting || formError != nil)
            }
            Text("远端账号只用于身份、协作和知识库服务；不会上传本地会话、偏好或 Memory OS。")
                .font(SettingsListTypography.rowCaption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func signedInContent(_ user: ConnorRemoteUserIdentity) -> some View {
        SettingsGroup(title: "个人资料") {
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

    private func submit() async {
        guard formError == nil else { return }
        isSubmitting = true; defer { isSubmitting = false }
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
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.quaternary))
        .accessibilityLabel("\(user.displayName)的头像")
    }

    private var fallback: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.16))
            Text(String(user.displayName.prefix(1)).uppercased()).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(Color.accentColor)
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
