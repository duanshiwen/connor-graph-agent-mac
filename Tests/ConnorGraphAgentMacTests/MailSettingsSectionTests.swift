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
