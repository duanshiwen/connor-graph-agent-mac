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

    @Test func mailBrowserPresentationReturnsMessagesNewestFirst() {
        let accountID = MailAccountID(rawValue: "shiwen@example.com")
        let mailboxID = MailMailboxID(rawValue: "inbox")
        let older = MailMessageSummary(id: MailMessageID(rawValue: "old"), accountID: accountID, mailboxID: mailboxID, subject: "Old", from: MailAddress(email: "a@example.com"), to: [], date: Date(timeIntervalSince1970: 100), snippet: "old")
        let newer = MailMessageSummary(id: MailMessageID(rawValue: "new"), accountID: accountID, mailboxID: mailboxID, subject: "New", from: MailAddress(email: "a@example.com"), to: [], date: Date(timeIntervalSince1970: 200), snippet: "new")
        let presentation = NativeMailBrowserPresentation(accounts: [], mailboxes: [], messages: [older, newer])

        #expect(presentation.messages(accountID: nil, mailboxID: nil, query: "").map(\.id) == [newer.id, older.id])
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
