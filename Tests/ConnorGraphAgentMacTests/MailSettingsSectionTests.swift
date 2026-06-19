import Testing
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
}
