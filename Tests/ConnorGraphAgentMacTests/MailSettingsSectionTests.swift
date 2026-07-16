import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@Suite("Mail Settings Section Tests")
struct MailSettingsSectionTests {
    @Test func settingsSectionsExposeMailSystemSettings() {
        #expect(ConnorSettingsSection.allCases.contains(.mail))
        #expect(ConnorSettingsSection.mail.title == "邮件系统")
        #expect(ConnorSettingsSection.mail.subtitle == "账户、同步、安全")
        #expect(ConnorSettingsSection.mail.systemImage == "envelope.badge")
    }

    @Test func settingsSectionsExposeRSSSystemSettings() {
        #expect(ConnorSettingsSection.allCases.contains(.rss))
        #expect(ConnorSettingsSection.rss.title == "RSS 阅读")
        #expect(ConnorSettingsSection.rss.subtitle == "订阅源、抓取、安全")
        #expect(ConnorSettingsSection.rss.systemImage == "dot.radiowaves.left.and.right")
    }

    @Test func settingsSectionsUseDistinctIconsAndDescribeConnorAccountCapabilities() {
        let icons = ConnorSettingsSection.allCases.map(\.systemImage)

        #expect(Set(icons).count == icons.count)
        #expect(ConnorSettingsSection.preferences.systemImage == "slider.horizontal.3")
        #expect(ConnorSettingsSection.identity.subtitle == "登录、同步、知识市场")
    }

    @Test func mailSettingsSummaryShowsLocalEncryptedCredentialVaultCopy() {
        let summary = MailSettingsSummaryPresentation(presentation: .empty)

        #expect(summary.credentialStorageText == "Connor 本地加密凭据库")
        #expect(summary.credentialStorageText.contains("本地加密"))
        #expect(!summary.credentialStorageText.contains("macOS"))
    }

    @Test func mailSettingsSummaryShowsEmptyStateWithoutAccounts() {
        let summary = MailSettingsSummaryPresentation(presentation: .empty)

        #expect(summary.accountCountText == "0 个")
        #expect(summary.mailboxCountText == "0 个")
        #expect(summary.messageCountText == "0 封")
        #expect(summary.unreadCountText == "0 未读")
        #expect(summary.emptyStateTitle == "暂无邮件账户")
        #expect(summary.emptyStateMessage == "添加 IMAP/SMTP 账户后，康纳同学会同步最近邮件并创建定时刷新任务。")
        #expect(summary.defaultSendAccountText(preferences: MailPreferences()) == "尚未设置")
    }

    @Test func mailSettingsSummaryShowsConfiguredDefaultSendAccount() {
        let account = MailAccount(
            id: MailAccountID(rawValue: "shiwen@example.com"),
            provider: .genericIMAPSMTP,
            displayName: "诗闻邮箱",
            identities: [MailIdentity(id: MailIdentityID(rawValue: "identity-shiwen@example.com"), displayName: "诗闻", address: MailAddress(name: "诗闻", email: "shiwen@example.com"))]
        )
        let presentation = NativeMailBrowserPresentation(accounts: [account], mailboxes: [], messages: [])
        let summary = MailSettingsSummaryPresentation(presentation: presentation)
        let preferences = MailPreferences(defaultSendAccountID: account.id, defaultSendIdentityID: account.identities.first?.id)

        #expect(summary.defaultSendAccountText(preferences: preferences) == "诗闻邮箱 <shiwen@example.com>")
        #expect(summary.defaultSendIdentityText(preferences: preferences) == "诗闻 <shiwen@example.com>")
    }

    @Test func mailBodyDisplayFallsBackToSnippetWhenCachedBodyFieldsAreEmpty() {
        let accountID = MailAccountID(rawValue: "shiwen@example.com")
        let mailboxID = MailMailboxID(rawValue: "inbox")
        let summary = MailMessageSummary(
            id: MailMessageID(rawValue: "shiwen@example.com-INBOX-42"),
            accountID: accountID,
            mailboxID: mailboxID,
            subject: "空正文缓存",
            from: MailAddress(email: "sender@example.com"),
            to: [MailAddress(email: "shiwen@example.com")],
            date: Date(timeIntervalSince1970: 1_783_148_400),
            snippet: "这是一段列表摘要"
        )
        let detail = MailMessageDetail(
            summary: summary,
            body: MailMessageBody(
                plainText: MailBodyPart(mimeType: "text/plain", text: "", byteCount: 0),
                htmlText: MailBodyPart(mimeType: "text/html", text: "", byteCount: 0),
                redactedPreview: ""
            )
        )

        let display = MailBodyDisplayPresentation(detail: detail)

        #expect(display.kind == .fallback)
        #expect(display.text == "这是一段列表摘要")
        #expect(display.html == nil)
    }

    @Test func mailBodyDisplayUsesHTMLOnlyWhenTrimmedContentExists() {
        let accountID = MailAccountID(rawValue: "shiwen@example.com")
        let mailboxID = MailMailboxID(rawValue: "inbox")
        let summary = MailMessageSummary(
            id: MailMessageID(rawValue: "shiwen@example.com-INBOX-43"),
            accountID: accountID,
            mailboxID: mailboxID,
            subject: "HTML 正文",
            from: MailAddress(email: "sender@example.com"),
            to: [MailAddress(email: "shiwen@example.com")],
            date: Date(timeIntervalSince1970: 1_783_148_400),
            snippet: "摘要"
        )
        let blankHTML = MailMessageDetail(
            summary: summary,
            body: MailMessageBody(
                plainText: nil,
                htmlText: MailBodyPart(mimeType: "text/html", text: "  \n\t", byteCount: 4),
                redactedPreview: "摘要"
            )
        )
        let richHTML = MailMessageDetail(
            summary: summary,
            body: MailMessageBody(
                plainText: nil,
                htmlText: MailBodyPart(mimeType: "text/html", text: "<p>Hello</p>", byteCount: 12),
                redactedPreview: "Hello"
            )
        )

        #expect(MailBodyDisplayPresentation(detail: blankHTML).kind == .fallback)
        #expect(MailBodyDisplayPresentation(detail: blankHTML).html == nil)
        #expect(MailBodyDisplayPresentation(detail: richHTML).kind == .html)
        #expect(MailBodyDisplayPresentation(detail: richHTML).html == "<p>Hello</p>")
    }

    @Test func mailBodyDisplayPrefersHTMLWhenPlainTextAlsoExists() {
        let accountID = MailAccountID(rawValue: "shiwen@example.com")
        let mailboxID = MailMailboxID(rawValue: "inbox")
        let summary = MailMessageSummary(
            id: MailMessageID(rawValue: "shiwen@example.com-INBOX-44"),
            accountID: accountID,
            mailboxID: mailboxID,
            subject: "营销邮件",
            from: MailAddress(email: "sender@example.com"),
            to: [MailAddress(email: "shiwen@example.com")],
            snippet: "查看收据"
        )
        let detail = MailMessageDetail(
            summary: summary,
            body: MailMessageBody(
                plainText: MailBodyPart(mimeType: "text/plain", text: "Apple Receipt\nTotal: 10", byteCount: 23),
                htmlText: MailBodyPart(mimeType: "text/html", text: "<html><body><a style='background:#1d9bf0;color:white'>View receipt</a></body></html>", byteCount: 80),
                redactedPreview: "Apple Receipt"
            )
        )

        let display = MailBodyDisplayPresentation(detail: detail)

        #expect(display.kind == .html)
        #expect(display.text.contains("View receipt"))
        #expect(display.html?.contains("View receipt") == true)
    }

    @Test func mailBodyDisplayRecoversCachedQuotedPrintableHTMLBeforeRendering() {
        let detail = quotedPrintableHTMLMessageDetail()

        let display = MailBodyDisplayPresentation(detail: detail)

        #expect(display.kind == .html)
        #expect(display.html?.contains("段诗闻") == true)
        #expect(display.html?.contains("=E6=AE") == false)
        #expect(display.text.contains("段诗闻"))
    }

    @Test func mailBodyDisplayCanBePreparedAsynchronouslyWithoutChangingRecoveredHTML() async {
        let detail = quotedPrintableHTMLMessageDetail()

        let display = await MailBodyDisplayPresentation.preparing(detail: detail)

        #expect(display.kind == .html)
        #expect(display.html?.contains("段诗闻") == true)
        #expect(display.html?.contains("=E6=AE") == false)
        #expect(display.text.contains("段诗闻"))
    }

    private func quotedPrintableHTMLMessageDetail() -> MailMessageDetail {
        let accountID = MailAccountID(rawValue: "shiwen@example.com")
        let mailboxID = MailMailboxID(rawValue: "inbox")
        let summary = MailMessageSummary(
            id: MailMessageID(rawValue: "shiwen@example.com-INBOX-45"),
            accountID: accountID,
            mailboxID: mailboxID,
            subject: "LinkedIn digest",
            from: MailAddress(email: "messaging-digest-noreply@linkedin.com"),
            to: [MailAddress(email: "shiwen@example.com")],
            date: Date(timeIntervalSince1970: 1_783_148_400),
            snippet: "=E6=AE=B5=E8=AF=97=E9=97=BB"
        )
        return MailMessageDetail(
            summary: summary,
            body: MailMessageBody(
                plainText: nil,
                htmlText: MailBodyPart(
                    mimeType: "text/html",
                    text: "<html><body><table><tr><td>=E6=AE=B5=E8=AF=97=E9=97=BB</td></tr></table></body></html>",
                    byteCount: 95
                ),
                redactedPreview: "=E6=AE=B5=E8=AF=97=E9=97=BB"
            )
        )
    }

    @Test func mailMessageListPresentationUsesSentDateInContextText() {
        let sentAt = Date(timeIntervalSince1970: 1_783_148_400)
        let account = MailAccount(id: MailAccountID(rawValue: "shiwen@example.com"), provider: .genericIMAPSMTP, displayName: "诗闻邮箱", identities: [])
        let mailbox = MailMailbox(id: MailMailboxID(rawValue: "inbox"), accountID: account.id, name: "收件箱", path: "INBOX", role: .inbox)
        let message = MailMessageSummary(
            id: MailMessageID(rawValue: "shiwen@example.com-INBOX-44"),
            accountID: account.id,
            mailboxID: mailbox.id,
            subject: "发信日期展示",
            from: MailAddress(email: "sender@example.com"),
            to: [MailAddress(email: "shiwen@example.com")],
            date: sentAt,
            snippet: "摘要"
        )

        let row = MailMessageListRowPresentation(message: message, account: account, mailbox: mailbox)

        #expect(row.contextText.contains("诗闻邮箱"))
        #expect(row.contextText.contains("收件箱"))
        #expect(row.contextText.contains(sentAt.connorLocalFormatted(date: .medium, time: .short)))
    }

    @Test func mailMessageListPresentationLabelsReceivedAndSentRows() {
        let account = MailAccount(id: MailAccountID(rawValue: "shiwen@example.com"), provider: .genericIMAPSMTP, displayName: "诗闻邮箱", identities: [])
        let inbox = MailMailbox(id: MailMailboxID(rawValue: "inbox"), accountID: account.id, name: "收件箱", path: "INBOX", role: .inbox)
        let sent = MailMailbox(id: MailMailboxID(rawValue: "sent"), accountID: account.id, name: "已发送", path: "Sent", role: .sent)
        let receivedMessage = MailMessageSummary(id: MailMessageID(rawValue: "received"), accountID: account.id, mailboxID: inbox.id, subject: "收到", from: MailAddress(email: "sender@example.com"), to: [], snippet: "摘要")
        let sentMessage = MailMessageSummary(id: MailMessageID(rawValue: "sent-message"), accountID: account.id, mailboxID: sent.id, subject: "发出", from: MailAddress(email: "shiwen@example.com"), to: [], snippet: "摘要")

        let receivedRow = MailMessageListRowPresentation(message: receivedMessage, account: account, mailbox: inbox)
        let sentRow = MailMessageListRowPresentation(message: sentMessage, account: account, mailbox: sent)

        #expect(receivedRow.directionLabelText == "收到")
        #expect(receivedRow.directionLabelSystemImage == "tray.fill")
        #expect(sentRow.directionLabelText == "已发送")
        #expect(sentRow.directionLabelSystemImage == "paperplane.fill")
    }

    @Test func mailMessageListPresentationFallsBackToMessageIDWhenMailboxIsMissing() {
        let account = MailAccount(id: MailAccountID(rawValue: "shiwen@example.com"), provider: .genericIMAPSMTP, displayName: "诗闻邮箱", identities: [])
        let receivedMessage = MailMessageSummary(id: MailMessageID(rawValue: "shiwen@example.com-INBOX-44"), accountID: account.id, mailboxID: MailMailboxID(rawValue: "missing-inbox"), subject: "收到", from: MailAddress(email: "sender@example.com"), to: [], snippet: "摘要")
        let sentMessage = MailMessageSummary(id: MailMessageID(rawValue: "shiwen@example.com-Sent-44"), accountID: account.id, mailboxID: MailMailboxID(rawValue: "missing-sent"), subject: "发出", from: MailAddress(email: "shiwen@example.com"), to: [], snippet: "摘要")

        let receivedRow = MailMessageListRowPresentation(message: receivedMessage, account: account, mailbox: nil)
        let sentRow = MailMessageListRowPresentation(message: sentMessage, account: account, mailbox: nil)

        #expect(receivedRow.directionLabelText == "收到")
        #expect(receivedRow.directionLabelSystemImage == "tray.fill")
        #expect(sentRow.directionLabelText == "已发送")
        #expect(sentRow.directionLabelSystemImage == "paperplane.fill")
    }

    @Test func mailMessageListPresentationDoesNotMislabelCustomMailboxAsReceived() {
        let account = MailAccount(id: MailAccountID(rawValue: "shiwen@example.com"), provider: .genericIMAPSMTP, displayName: "诗闻邮箱", identities: [])
        let custom = MailMailbox(id: MailMailboxID(rawValue: "custom"), accountID: account.id, name: "旅行", path: "Travel", role: .custom)
        let message = MailMessageSummary(id: MailMessageID(rawValue: "custom-message"), accountID: account.id, mailboxID: custom.id, subject: "旅行", from: MailAddress(email: "sender@example.com"), to: [], snippet: "摘要")

        let row = MailMessageListRowPresentation(message: message, account: account, mailbox: custom)

        #expect(row.directionLabelText == "邮件")
        #expect(row.directionLabelSystemImage == "envelope")
    }

    @Test func mailBrowserPresentationReturnsMessagesNewestFirst() {
        let accountID = MailAccountID(rawValue: "shiwen@example.com")
        let mailboxID = MailMailboxID(rawValue: "inbox")
        let older = MailMessageSummary(id: MailMessageID(rawValue: "old"), accountID: accountID, mailboxID: mailboxID, subject: "Old", from: MailAddress(email: "a@example.com"), to: [], date: Date(timeIntervalSince1970: 100), snippet: "old")
        let newer = MailMessageSummary(id: MailMessageID(rawValue: "new"), accountID: accountID, mailboxID: mailboxID, subject: "New", from: MailAddress(email: "a@example.com"), to: [], date: Date(timeIntervalSince1970: 200), snippet: "new")
        let presentation = NativeMailBrowserPresentation(accounts: [], mailboxes: [], messages: [older, newer])

        #expect(presentation.messages(accountID: nil, mailboxID: nil, query: "").map(\.id) == [newer.id, older.id])
    }

    @Test func mailDirectionFilterPresentationProvidesChipAndEmptyStateCopy() {
        #expect(MailMessageDirectionFilter.all.mailListChipTitle == "全部")
        #expect(MailMessageDirectionFilter.received.mailListChipTitle == "收件")
        #expect(MailMessageDirectionFilter.sent.mailListChipTitle == "已发送")
        #expect(MailMessageDirectionFilter.received.emptyListTitle == "还没有收到邮件")
        #expect(MailMessageDirectionFilter.sent.emptyListTitle == "还没有已发送邮件")
    }

    @Test func mailSettingsSummaryCountsAccountsMailboxesMessagesAndUnread() {
        let accountID = MailAccountID(rawValue: "shiwen@example.com")
        let account = MailAccount(
            id: accountID,
            provider: .genericIMAPSMTP,
            displayName: "诗闻 iCloud",
            identities: [],
            health: MailAccountHealth(status: .ready, summary: "正常")
        )
        let inbox = MailMailbox(
            id: MailMailboxID(rawValue: "inbox"),
            accountID: accountID,
            name: "Inbox",
            path: "INBOX",
            role: .inbox,
            status: MailMailboxStatus(messageCount: 3, unreadCount: 2, lastSyncedAt: Date(timeIntervalSince1970: 1_783_148_400))
        )
        let archive = MailMailbox(
            id: MailMailboxID(rawValue: "archive"),
            accountID: accountID,
            name: "Archive",
            path: "Archive",
            role: .archive,
            status: MailMailboxStatus(messageCount: 4, unreadCount: 1)
        )
        let presentation = NativeMailBrowserPresentation(accounts: [account], mailboxes: [inbox, archive], messages: [])
        let summary = MailSettingsSummaryPresentation(presentation: presentation)

        #expect(summary.accountCountText == "1 个")
        #expect(summary.mailboxCountText == "2 个")
        #expect(summary.messageCountText == "0 封")
        #expect(summary.unreadCountText == "3 未读")
        #expect(summary.emptyStateTitle == nil)
        #expect(summary.lastSyncedText?.isEmpty == false)
    }
}
