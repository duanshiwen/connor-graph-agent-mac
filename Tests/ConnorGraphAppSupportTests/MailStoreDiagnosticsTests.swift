import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Mail Store Diagnostics Tests")
struct MailStoreDiagnosticsTests {
    @Test func diagnosticsIdentifyCurrentStoreLegacyStoreAndMailboxRoles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let store = FileBackedMailSourceStore(storagePaths: paths)
        let accountID = MailAccountID(rawValue: "shiwen@example.com")
        let account = MailAccount(id: accountID, provider: .genericIMAPSMTP, displayName: "诗闻邮箱", identities: [])
        try await store.saveAccount(account)
        try await store.saveMailbox(MailMailbox(id: MailMailboxID(rawValue: "inbox"), accountID: accountID, name: "收件箱", path: "INBOX", role: .inbox))
        try await store.saveMailbox(MailMailbox(id: MailMailboxID(rawValue: "sent"), accountID: accountID, name: "已发送", path: "Sent Messages", role: .sent))
        let legacyURL = paths.applicationSupportDirectory.appendingPathComponent("mail", isDirectory: true).appendingPathComponent("mail.db")
        try FileManager.default.createDirectory(at: legacyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("legacy".utf8).write(to: legacyURL)

        let diagnostics = try await MailStoreDiagnosticsService(storagePaths: paths).snapshot()

        #expect(diagnostics.currentStorePath.hasSuffix("mail/mail-source.sqlite"))
        #expect(diagnostics.currentStoreExists)
        #expect(diagnostics.legacyStorePath.hasSuffix("mail/mail.db"))
        #expect(diagnostics.legacyStoreExists)
        #expect(diagnostics.legacyStoreNote.contains("legacy"))
        #expect(diagnostics.accountCount == 1)
        #expect(diagnostics.mailboxCount == 2)
        #expect(diagnostics.messageCount == 0)
        #expect(diagnostics.mailboxRoleCounts["inbox"] == 1)
        #expect(diagnostics.mailboxRoleCounts["sent"] == 1)
    }
}
