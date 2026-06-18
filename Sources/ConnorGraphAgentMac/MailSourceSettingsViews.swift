import SwiftUI
import ConnorGraphCore
import ConnorGraphAppSupport

struct MailSourceSettingsView: View {
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
                VStack(alignment: .leading, spacing: 0) {
                    MailBrowserTopBar(onAdd: { viewModel.isPresentingAddMailAccountSheet = true })
                    Divider().opacity(0.6)
                    MailMessageDetailPane(account: selectedAccount, mailbox: selectedMailbox, message: selectedMessage)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppShellColors.detailBackground)
        .sheet(isPresented: $viewModel.isPresentingAddMailAccountSheet) {
            AddMailAccountSheet()
        }
    }
}

private struct MailBrowserTopBar: View {
    var onAdd: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: AppShellLayout.spaceM) {
            VStack(alignment: .leading, spacing: AppShellLayout.spaceXS) {
                Text("邮件系统")
                    .font(.system(size: 24, weight: .semibold))
                Text("账户、文件夹和邮件详情由 Connor 本地治理；读取不会自动改变已读状态。")
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: AppShellLayout.spaceM)
            Button(action: onAdd) {
                Label("添加邮件帐户", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.horizontal, AppShellLayout.spaceXL)
        .padding(.vertical, AppShellLayout.spaceL)
    }
}

private struct MailMessageDetailPane: View {
    var account: MailAccount?
    var mailbox: MailMailbox?
    var message: MailMessageSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppShellLayout.spaceL) {
                MailMessageHero(account: account, mailbox: mailbox, message: message)
                MailInfoSection(title: "邮件摘要", systemImage: "doc.text.magnifyingglass") {
                    Text(message.snippet)
                        .font(AgentChatTypography.meta)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
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
                MailInfoSection(title: "治理提示", systemImage: "checkmark.shield") {
                    MailGovernanceHintStrip()
                }
            }
            .padding(AppShellLayout.spaceXL)
            .frame(maxWidth: AppShellLayout.contentMaxWidth, alignment: .leading)
        }
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
                    MailStatusPill(status: message.date.formatted(date: .abbreviated, time: .shortened), color: .secondary, systemImage: "clock")
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

private struct MailGovernanceHintStrip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppShellLayout.spaceS) {
            MailChecklistRow(title: "读取不自动标记已读", isReady: true, detail: "列表和详情预览不会隐式修改邮件 read state。")
            MailChecklistRow(title: "发信始终需要审批", isReady: true, detail: "草稿发送必须进入 Connor approval gate。")
            MailChecklistRow(title: "附件导入受治理", isReady: true, detail: "附件进入 Session Capsule / Attachment Store 后再供 Agent 使用。")
        }
    }
}

struct AddMailAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPreset: MailAccountProviderPreset = .apple
    @State private var displayName: String = ""
    @State private var email: String = ""
    @State private var credential: String = ""
    @State private var incomingHost: String = MailAccountProviderPreset.apple.incomingHost
    @State private var incomingPort: Int = MailAccountProviderPreset.apple.incomingPort
    @State private var outgoingHost: String = MailAccountProviderPreset.apple.outgoingHost
    @State private var outgoingPort: Int = MailAccountProviderPreset.apple.outgoingPort

    private var isManualPreset: Bool {
        selectedPreset == .other
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppShellLayout.spaceL) {
            HStack(alignment: .top, spacing: AppShellLayout.spaceM) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                    Image(systemName: "envelope.badge")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text("添加邮件帐户")
                        .font(.title3.weight(.semibold))
                    Text("选择服务商后，Connor 会预填常见 IMAP/SMTP 配置。真实凭据接入会继续走本地凭据边界和审批治理。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Form {
                Picker("服务商", selection: $selectedPreset) {
                    ForEach(MailAccountProviderPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .onChange(of: selectedPreset) { _, preset in applyPreset(preset) }

                TextField("显示名称", text: $displayName)
                TextField("邮箱地址", text: $email)
                SecureField(selectedPreset == .microsoft ? "OAuth / 授权凭据（稍后接入）" : "授权码 / App Password", text: $credential)

                Section("服务器预设") {
                    TextField("收件服务器", text: $incomingHost)
                        .disabled(!isManualPreset)
                    TextField("收件端口", value: $incomingPort, format: .number)
                        .disabled(!isManualPreset)
                    TextField("发件服务器", text: $outgoingHost)
                        .disabled(!isManualPreset)
                    TextField("发件端口", value: $outgoingPort, format: .number)
                        .disabled(!isManualPreset)
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 300)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label(selectedPreset.subtitle, systemImage: "lock.shield")
                        .font(AgentChatTypography.metaEmphasis)
                    Text(selectedPreset.guidance)
                        .font(AgentChatTypography.meta)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("本轮界面先保存为连接草稿；真实登录、测试连接和凭据持久化会在后续 Mail Runtime 接入中完成。")
                        .font(AgentChatTypography.micro)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存草稿") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 620)
        .onAppear { applyPreset(selectedPreset) }
    }

    private func applyPreset(_ preset: MailAccountProviderPreset) {
        incomingHost = preset.incomingHost
        incomingPort = preset.incomingPort
        outgoingHost = preset.outgoingHost
        outgoingPort = preset.outgoingPort
        if displayName.isEmpty {
            displayName = preset.title
        }
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

private struct MailChecklistRow: View {
    var title: String
    var isReady: Bool
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: AppShellLayout.spaceS) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isReady ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppListTypography.rowTitleSelected)
                Text(detail)
                    .font(AppListTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
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
