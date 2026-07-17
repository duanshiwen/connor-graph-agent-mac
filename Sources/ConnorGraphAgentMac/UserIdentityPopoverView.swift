import SwiftUI
import ConnorGraphAppSupport

struct UserIdentityPopoverView: View {
    @ObservedObject var identityStore: AppUserIdentityStore
    @ObservedObject var connectivity: AppNetworkConnectivity = .shared
    @ObservedObject var backendConnectivity: AppBackendConnectivity = .shared
    var openIdentitySettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch identityStore.authenticationState {
            case let .signedIn(user):
                HStack(spacing: 12) {
                    IdentityAvatarView(user: user, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName).font(.headline)
                        Text("@\(user.username)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                Button(action: openIdentitySettings) {
                    Label("康纳账号", systemImage: "person.text.rectangle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Divider()
                Button(role: .destructive) { Task { await identityStore.logout() } } label: {
                    Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(!canUseAccountService)
                if !connectivity.isConnected {
                    serviceStatus("当前没有网络连接", systemImage: "wifi.slash")
                } else if backendConnectivity.state == .unreachable {
                    serviceStatus("当前无法连接到康纳服务器", systemImage: "exclamationmark.icloud")
                }
            case .restoring:
                ProgressView("正在恢复登录状态…")
            case .signedOut, .expired:
                Label("尚未登录康纳账号", systemImage: "person.crop.circle.badge.questionmark")
                    .font(.headline)
                Text("登录后可查看你的身份、订阅和创建的知识库。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(action: openIdentitySettings) {
                    Text("登录或注册").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                if !connectivity.isConnected {
                    serviceStatus("当前没有网络连接", systemImage: "wifi.slash")
                } else if backendConnectivity.state == .unreachable {
                    serviceStatus("当前无法连接到康纳服务器", systemImage: "exclamationmark.icloud")
                }
            }
        }
        .padding(16)
        .frame(width: 270)
    }

    private var canUseAccountService: Bool {
        connectivity.isConnected && backendConnectivity.state != .unreachable
    }

    private func serviceStatus(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
