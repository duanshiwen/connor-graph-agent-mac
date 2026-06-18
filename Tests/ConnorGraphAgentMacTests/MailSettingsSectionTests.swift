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
}
