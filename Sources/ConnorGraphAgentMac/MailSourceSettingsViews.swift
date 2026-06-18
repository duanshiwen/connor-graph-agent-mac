import SwiftUI
import ConnorGraphCore
import ConnorGraphAppSupport

struct MailSourceSettingsView: View {
    private let accounts: [MailAccount]
    private let mailboxes: [MailMailbox]
    private let messages: [MailMessageSummary]
    private let auditRecords: [MailAuditRecord]
    private let readiness: NativeMailReadiness

    init(
        accounts: [MailAccount] = NativeMailUIPreviewData.accounts,
        mailboxes: [MailMailbox] = NativeMailUIPreviewData.mailboxes,
        messages: [MailMessageSummary] = NativeMailUIPreviewData.messages,
        auditRecords: [MailAuditRecord] = NativeMailUIPreviewData.auditRecords,
        readiness: NativeMailReadiness = NativeMailUIPreviewData.readiness
    ) {
        self.accounts = accounts
        self.mailboxes = mailboxes
        self.messages = messages
        self.auditRecords = auditRecords
        self.readiness = readiness
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppShellLayout.spaceXL) {
                MailHeroHeader(readiness: readiness)
                MailReadinessGrid(readiness: readiness)
                LazyVGrid(columns: [.init(.flexible(), spacing: AppShellLayout.spaceL), .init(.flexible(), spacing: AppShellLayout.spaceL)], spacing: AppShellLayout.spaceL) {
                    MailAccountsCard(accounts: accounts)
                    MailGovernanceCard(readiness: readiness)
                }
                MailMailboxOverviewCard(mailboxes: mailboxes)
                MailMessagePreviewCard(messages: messages)
                MailAuditTimelineCard(records: auditRecords)
            }
            .padding(AppShellLayout.spaceXL)
            .frame(maxWidth: AppShellLayout.contentMaxWidth + 180, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppShellColors.detailBackground.ignoresSafeArea())
        .navigationTitle("Mail")
    }
}

private struct MailHeroHeader: View {
    var readiness: NativeMailReadiness

    var body: some View {
        HStack(alignment: .top, spacing: AppShellLayout.spaceL) {
            ZStack {
                Circle()
                    .fill(ConnorCraftPalette.accentSoftFill)
                    .frame(width: 56, height: 56)
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(.system(size: 25, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(ConnorCraftPalette.accent)
            }

            VStack(alignment: .leading, spacing: AppShellLayout.spaceS) {
                HStack(spacing: AppShellLayout.spaceS) {
                    Text("Connor Native Mail System")
                        .font(.system(size: 24, weight: .semibold))
                    MailStatusPill(status: readiness.isReady ? "Ready" : "Needs setup", color: readiness.isReady ? .green : .orange, systemImage: readiness.isReady ? "checkmark.shield" : "exclamationmark.triangle")
                }
                Text("AI 通过受治理的原生工具读取、搜索、起草、审批发送邮件；账号、凭据、同步、联系人写入、附件导入与 Graph evidence admission 都保留在 Connor 主权边界内。")
                    .font(AgentChatTypography.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
                HStack(spacing: AppShellLayout.spaceS) {
                    MailStatusPill(status: "Read tools default allowed", color: .blue, systemImage: "book")
                    MailStatusPill(status: "Send always approval-gated", color: .red, systemImage: "paperplane")
                    MailStatusPill(status: "No implicit read-state mutation", color: .purple, systemImage: "eye.slash")
                }
            }
            Spacer(minLength: AppShellLayout.spaceM)
        }
        .padding(AppShellLayout.spaceXL)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppShellLayout.radiusL, style: .continuous)
                .stroke(ConnorCraftPalette.accentBorder, lineWidth: 1)
        )
    }
}

private struct MailReadinessGrid: View {
    var readiness: NativeMailReadiness

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: AppShellLayout.spaceM), count: 4), spacing: AppShellLayout.spaceM) {
            AppMetricCard(title: "Accounts", value: "\(readiness.healthyAccountCount)/\(readiness.accountCount)", color: readiness.healthyAccountCount > 0 ? .green : .orange)
            AppMetricCard(title: "Credential", value: readiness.credentialBoundaryReady ? "Bounded" : "Missing", color: readiness.credentialBoundaryReady ? .green : .orange)
            AppMetricCard(title: "Sync Cursor", value: readiness.syncCursorReady ? "Ready" : "Pending", color: readiness.syncCursorReady ? .green : .orange)
            AppMetricCard(title: "Evidence", value: readiness.evidencePolicyReady ? "Review" : "Blocked", color: readiness.evidencePolicyReady ? .blue : .orange)
        }
    }
}

private struct MailAccountsCard: View {
    var accounts: [MailAccount]

    var body: some View {
        MailPanelCard(title: "Accounts", systemImage: "person.crop.circle.badge.checkmark") {
            VStack(alignment: .leading, spacing: AppShellLayout.spaceM) {
                ForEach(accounts) { account in
                    HStack(alignment: .top, spacing: AppShellLayout.spaceM) {
                        Image(systemName: icon(for: account.provider))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(color(for: account.health.status))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: AppShellLayout.spaceXS) {
                            Text(account.displayName)
                                .font(AppListTypography.header)
                            Text(account.identities.map { $0.address.email }.joined(separator: ", "))
                                .font(AppListTypography.rowSubtitle)
                                .foregroundStyle(.secondary)
                            Text(account.health.summary)
                                .font(AgentChatTypography.micro)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        MailStatusPill(status: account.health.status.rawValue, color: color(for: account.health.status))
                    }
                    .padding(AppShellLayout.spaceM)
                    .background(AppShellColors.subtleCardBackground, in: RoundedRectangle(cornerRadius: AppShellLayout.radiusM, style: .continuous))
                }
            }
        }
    }

    private func icon(for provider: MailProviderKind) -> String {
        switch provider {
        case .gmail: "g.circle.fill"
        case .microsoft365: "m.circle.fill"
        case .jmap: "j.circle.fill"
        case .genericIMAPSMTP: "tray.full"
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

private struct MailGovernanceCard: View {
    var readiness: NativeMailReadiness

    var body: some View {
        MailPanelCard(title: "Governance", systemImage: "checkmark.shield") {
            VStack(alignment: .leading, spacing: AppShellLayout.spaceS) {
                MailChecklistRow(title: "Tool audit log", isReady: readiness.toolAuditReady, detail: "Every read/body/mutation/send path records a redacted audit event.")
                MailChecklistRow(title: "Send approval", isReady: readiness.sendApprovalReady, detail: "mail_send_draft never auto-sends; approval payload is explicit.")
                MailChecklistRow(title: "Contact approval", isReady: readiness.contactApprovalReady, detail: "Mail-derived contacts become candidates/drafts first.")
                MailChecklistRow(title: "Attachment import", isReady: readiness.attachmentImportReady, detail: "Attachments enter Session Capsule / Attachment Store by tool call.")
            }
        }
    }
}

private struct MailMailboxOverviewCard: View {
    var mailboxes: [MailMailbox]

    var body: some View {
        MailPanelCard(title: "Mailbox Sync", systemImage: "arrow.triangle.2.circlepath") {
            VStack(spacing: 0) {
                ForEach(mailboxes) { mailbox in
                    HStack(spacing: AppShellLayout.spaceM) {
                        Image(systemName: icon(for: mailbox.role))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mailbox.name)
                                .font(AppListTypography.rowTitleSelected)
                            Text(mailbox.path)
                                .font(AgentChatTypography.monoMicro)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        MailCompactMetric(label: "Messages", value: "\(mailbox.status.messageCount)")
                        MailCompactMetric(label: "Unread", value: "\(mailbox.status.unreadCount)", color: mailbox.status.unreadCount > 0 ? .blue : .secondary)
                        MailStatusPill(status: mailbox.status.syncCursor == nil ? "No cursor" : "Cursor", color: mailbox.status.syncCursor == nil ? .orange : .green, systemImage: mailbox.status.syncCursor == nil ? "pause.circle" : "checkmark.circle")
                    }
                    .padding(.vertical, AppShellLayout.spaceM)
                    if mailbox.id != mailboxes.last?.id { Divider().opacity(0.55) }
                }
            }
        }
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

private struct MailMessagePreviewCard: View {
    var messages: [MailMessageSummary]

    var body: some View {
        MailPanelCard(title: "Tool Result Preview", systemImage: "list.bullet.rectangle") {
            VStack(spacing: AppShellLayout.spaceS) {
                ForEach(messages) { message in
                    HStack(alignment: .top, spacing: AppShellLayout.spaceM) {
                        Circle()
                            .fill(message.flags.isRead ? Color.secondary.opacity(0.18) : ConnorCraftPalette.accent)
                            .frame(width: 9, height: 9)
                            .padding(.top, 7)
                        VStack(alignment: .leading, spacing: AppShellLayout.spaceXS) {
                            HStack(spacing: AppShellLayout.spaceS) {
                                Text(message.subject)
                                    .font(message.flags.isRead ? AppListTypography.rowTitle : AppListTypography.rowTitleSelected)
                                    .lineLimit(1)
                                if message.hasAttachments {
                                    Image(systemName: "paperclip")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text("From \(message.from.name ?? message.from.email) · \(message.from.email)")
                                .font(AppListTypography.rowCaption)
                                .foregroundStyle(.secondary)
                            Text(message.snippet)
                                .font(AgentChatTypography.micro)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                        Spacer()
                        MailStatusPill(status: message.flags.isRead ? "Read" : "Unread", color: message.flags.isRead ? .secondary : .blue)
                    }
                    .padding(AppShellLayout.spaceM)
                    .background(AppShellColors.subtleCardBackground, in: RoundedRectangle(cornerRadius: AppShellLayout.radiusM, style: .continuous))
                }
            }
        }
    }
}

private struct MailAuditTimelineCard: View {
    var records: [MailAuditRecord]

    var body: some View {
        MailPanelCard(title: "Audit Timeline", systemImage: "clock.badge.checkmark") {
            VStack(alignment: .leading, spacing: AppShellLayout.spaceM) {
                ForEach(records) { record in
                    HStack(alignment: .top, spacing: AppShellLayout.spaceM) {
                        Image(systemName: icon(for: record.riskClass))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(color(for: record.riskClass))
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.kind.rawValue)
                                .font(AppListTypography.rowTitleSelected)
                            Text(record.redactedSummary)
                                .font(AppListTypography.rowSubtitle)
                                .foregroundStyle(.secondary)
                            if let payloadHash = record.payloadHash {
                                Text("hash: \(payloadHash)")
                                    .font(AgentChatTypography.monoMicro)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        MailStatusPill(status: record.riskClass.rawValue, color: color(for: record.riskClass))
                    }
                }
            }
        }
    }

    private func icon(for risk: MailToolRiskClass) -> String {
        switch risk {
        case .read: "book"
        case .bodyRead: "doc.text.magnifyingglass"
        case .mutation: "slider.horizontal.3"
        case .destructive: "trash"
        case .send: "paperplane"
        case .contactMutation: "person.crop.circle.badge.plus"
        case .attachmentImport: "paperclip"
        }
    }

    private func color(for risk: MailToolRiskClass) -> Color {
        switch risk {
        case .read: .blue
        case .bodyRead: .purple
        case .mutation: .orange
        case .destructive, .send, .contactMutation: .red
        case .attachmentImport: .teal
        }
    }
}

private struct MailPanelCard<Content: View>: View {
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

private struct MailCompactMetric: View {
    var label: String
    var value: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(AgentChatTypography.metaEmphasis)
                .foregroundStyle(color)
            Text(label)
                .font(AgentChatTypography.micro)
                .foregroundStyle(.tertiary)
        }
        .frame(minWidth: 56, alignment: .trailing)
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

enum NativeMailUIPreviewData {
    static let accountID = MailAccountID(rawValue: "fixture-account")
    static let identityID = MailIdentityID(rawValue: "fixture-identity")
    static let mailboxID = MailMailboxID(rawValue: "fixture-inbox")

    static let accounts: [MailAccount] = [
        MailAccount(
            id: accountID,
            provider: .localFixture,
            displayName: "Fixture Mail",
            identities: [MailIdentity(id: identityID, displayName: "Connor Fixture", address: MailAddress(name: "Connor Fixture", email: "connor@example.com"))],
            incoming: MailServerEndpoint(host: "imap.example.com", port: 993, security: .tls, protocolKind: .imap),
            outgoing: MailServerEndpoint(host: "smtp.example.com", port: 587, security: .startTLS, protocolKind: .smtp),
            credentialBinding: MailCredentialBinding(keychainService: "connor.mail.fixture", accountName: "connor@example.com", authMode: .oauth2),
            health: MailAccountHealth(status: .ready, summary: "Credential boundary, sync cursor, and audit hooks ready")
        )
    ]

    static let mailboxes: [MailMailbox] = [
        MailMailbox(id: mailboxID, accountID: accountID, name: "Inbox", path: "INBOX", role: .inbox, status: MailMailboxStatus(messageCount: 128, unreadCount: 7, syncCursor: MailSyncCursor(value: "uid:928"), lastSyncedAt: Date())),
        MailMailbox(id: MailMailboxID(rawValue: "fixture-sent"), accountID: accountID, name: "Sent", path: "Sent", role: .sent, status: MailMailboxStatus(messageCount: 42, unreadCount: 0, syncCursor: MailSyncCursor(value: "uid:311"), lastSyncedAt: Date())),
        MailMailbox(id: MailMailboxID(rawValue: "fixture-archive"), accountID: accountID, name: "Archive", path: "Archive", role: .archive, status: MailMailboxStatus(messageCount: 560, unreadCount: 0, syncCursor: MailSyncCursor(value: "uid:1440"), lastSyncedAt: Date()))
    ]

    static let messages: [MailMessageSummary] = [
        MailMessageSummary(id: MailMessageID(rawValue: "fixture-message-1"), accountID: accountID, mailboxID: mailboxID, threadID: MailThreadID(rawValue: "fixture-thread-1"), subject: "Connor Native Mail System", from: MailAddress(name: "Alice", email: "alice@example.com"), to: [MailAddress(email: "connor@example.com")], snippet: "Commercial native mail system fixture. Reading this message never marks it as read.", flags: MailMessageFlags(isRead: false), hasAttachments: true),
        MailMessageSummary(id: MailMessageID(rawValue: "fixture-message-2"), accountID: accountID, mailboxID: mailboxID, threadID: MailThreadID(rawValue: "fixture-thread-2"), subject: "OAuth migration checklist", from: MailAddress(name: "Security", email: "security@example.com"), to: [MailAddress(email: "connor@example.com")], snippet: "Provider auth policy, token refresh, keychain isolation, and audit readiness.", flags: MailMessageFlags(isRead: true), hasAttachments: false)
    ]

    static let auditRecords: [MailAuditRecord] = [
        MailAuditRecord(accountID: accountID, kind: .messageSearched, riskClass: .read, redactedSummary: "Searched mail messages; returned redacted summaries"),
        MailAuditRecord(accountID: accountID, messageID: MailMessageID(rawValue: "fixture-message-1"), kind: .messageBodyRead, riskClass: .bodyRead, redactedSummary: "Read mail body without mutating read state", payloadHash: "fixture-body-hash"),
        MailAuditRecord(accountID: accountID, kind: .sendApprovalRequested, riskClass: .send, redactedSummary: "Send approval required before mail_send_draft")
    ]

    static let readiness = NativeMailReadiness(accountCount: 1, healthyAccountCount: 1, credentialBoundaryReady: true, syncCursorReady: true, toolAuditReady: true, sendApprovalReady: true, contactApprovalReady: true, attachmentImportReady: true, evidencePolicyReady: true)
}
