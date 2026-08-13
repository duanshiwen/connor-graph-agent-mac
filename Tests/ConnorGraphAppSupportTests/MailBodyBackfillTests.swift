import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Mail Body Backfill Tests")
struct MailBodyBackfillTests {
    private func makeAccount(id: String) -> MailAccount {
        let accountID = MailAccountID(rawValue: id)
        let identity = MailIdentity(id: MailIdentityID(rawValue: "identity-\(id)"), displayName: "诗闻", address: MailAddress(email: id))
        return MailAccount(
            id: accountID,
            provider: .genericIMAPSMTP,
            displayName: "诗闻邮箱",
            identities: [identity],
            incoming: MailServerEndpoint(host: "imap.example.com", port: 993, security: .tls, protocolKind: .imap)
        )
    }

    private func headerOnlyDetail(id: MailMessageID, accountID: MailAccountID, mailboxID: MailMailboxID, subject: String) -> MailMessageDetail {
        MailMessageDetail(
            summary: MailMessageSummary(
                id: id,
                accountID: accountID,
                mailboxID: mailboxID,
                subject: subject,
                from: MailAddress(email: "sender@example.com"),
                to: [MailAddress(email: "me@example.com")],
                snippet: "（无正文摘要）"
            ),
            body: nil
        )
    }

    @Test func missingBodyQueryReturnsOnlyHeaderOnlyMessages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let store = try FileBackedMailSourceStore(openingStoragePaths: paths)

        let accountID = MailAccountID(rawValue: "shiwen@example.com")
        try await store.saveAccount(makeAccount(id: accountID.rawValue))
        let inbox = MailMailbox(id: MailMailboxID(rawValue: "inbox"), accountID: accountID, name: "收件箱", path: "INBOX", role: .inbox)
        try await store.saveMailbox(inbox)

        let withBodyID = MailMessageID(rawValue: "\(accountID.rawValue)-INBOX-1")
        let headerOnlyID = MailMessageID(rawValue: "\(accountID.rawValue)-INBOX-2")
        let withBody = MailMessageDetail(
            summary: MailMessageSummary(
                id: withBodyID,
                accountID: accountID,
                mailboxID: inbox.id,
                subject: "有正文",
                from: MailAddress(email: "a@example.com"),
                to: [MailAddress(email: "me@example.com")],
                snippet: "hello"
            ),
            body: MailMessageBody(plainText: MailBodyPart(mimeType: "text/plain", text: "hello", byteCount: 5), redactedPreview: "hello")
        )
        try await store.saveMessage(withBody)
        try await store.saveMessage(headerOnlyDetail(id: headerOnlyID, accountID: accountID, mailboxID: inbox.id, subject: "无正文"))

        let missing = try await store.messagesMissingBody(limit: 100)
        #expect(missing.map(\.id.rawValue) == [headerOnlyID.rawValue])
    }

    @Test func backfillDownloadsAndPersistsTextBodiesForHeaderOnlyMessages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let store = try FileBackedMailSourceStore(openingStoragePaths: paths)

        let accountID = MailAccountID(rawValue: "shiwen@example.com")
        try await store.saveAccount(makeAccount(id: accountID.rawValue))
        let inbox = MailMailbox(id: MailMailboxID(rawValue: "inbox"), accountID: accountID, name: "收件箱", path: "INBOX", role: .inbox)
        let sent = MailMailbox(id: MailMailboxID(rawValue: "sent"), accountID: accountID, name: "已发送", path: "Sent Messages", role: .sent)
        try await store.saveMailbox(inbox)
        try await store.saveMailbox(sent)

        let inboxMessageID = MailMessageID(rawValue: "\(accountID.rawValue)-INBOX-1")
        let sentMessageID = MailMessageID(rawValue: "\(accountID.rawValue)-Sent-2")
        try await store.saveMessage(headerOnlyDetail(id: inboxMessageID, accountID: accountID, mailboxID: inbox.id, subject: "收件无正文"))
        try await store.saveMessage(headerOnlyDetail(id: sentMessageID, accountID: accountID, mailboxID: sent.id, subject: "已发送无正文"))

        let service = MailBodyBackfillService(
            maxBodiesPerRun: 100,
            maxConcurrentFetches: 2,
            batchBodyFetcher: { _, _, _ in [] }
        ) { _, _, detail in
            var copy = detail
            copy.body = MailMessageBody(
                plainText: MailBodyPart(mimeType: "text/plain", text: "回填正文", byteCount: 4),
                redactedPreview: "回填正文"
            )
            return copy
        }
        let saved = try await service.backfillMissingBodies(store: store)
        #expect(saved == 2)
        #expect(try await store.messagesMissingBody(limit: 100).isEmpty)

        let sentDetail = try #require(await store.message(id: sentMessageID))
        #expect(MailBodyOnDemandFetchPlanner.hasDisplayableBody(sentDetail))
        #expect(sentDetail.body?.plainText?.text == "回填正文")
    }

    @Test func backfillProcessesAllMissingMessagesAcrossMultiplePages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let store = try FileBackedMailSourceStore(openingStoragePaths: paths)

        let accountID = MailAccountID(rawValue: "shiwen@example.com")
        try await store.saveAccount(makeAccount(id: accountID.rawValue))
        let inbox = MailMailbox(id: MailMailboxID(rawValue: "inbox"), accountID: accountID, name: "收件箱", path: "INBOX", role: .inbox)
        try await store.saveMailbox(inbox)

        let messageCount = 7
        for index in 1...messageCount {
            let id = MailMessageID(rawValue: "\(accountID.rawValue)-INBOX-\(index)")
            try await store.saveMessage(headerOnlyDetail(id: id, accountID: accountID, mailboxID: inbox.id, subject: "旧邮件 \(index)"))
        }
        #expect(try await store.messagesMissingBody(limit: 100).count == messageCount)

        let service = MailBodyBackfillService(
            maxBodiesPerRun: 2,
            maxConcurrentFetches: 1,
            batchBodyFetcher: { _, _, _ in [] }
        ) { _, _, detail in
            var copy = detail
            copy.body = MailMessageBody(
                plainText: MailBodyPart(mimeType: "text/plain", text: "回填正文", byteCount: 4),
                redactedPreview: "回填正文"
            )
            return copy
        }
        let saved = try await service.backfillMissingBodies(store: store)
        #expect(saved == messageCount)
        #expect(try await store.messagesMissingBody(limit: 100).isEmpty)
    }
}
