import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

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
        var htmlOnly = withBody
        htmlOnly.summary.id = MailMessageID(rawValue: "html-only")
        htmlOnly.body = MailMessageBody(htmlText: MailBodyPart(mimeType: "text/html", text: "<p>HTML body</p>", byteCount: 16), redactedPreview: "")
        try await store.saveMessage(htmlOnly)
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
            copy.attachments = [MailAttachmentDescriptor(id: MailAttachmentID(rawValue: "attachment-1"), messageID: detail.id, filename: "report.pdf", mimeType: "application/pdf", byteCount: 128)]
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
        #expect(sentDetail.attachments.map(\.filename) == ["report.pdf"])
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
    @Test func concurrentFallbackKeepsBodiesWithTheirOriginalMessages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileBackedMailSourceStore(storeURL: root.appendingPathComponent("mail.sqlite"))
        let account = makeAccount(id: "owner@example.test")
        let box = MailMailbox(id: MailMailboxID(rawValue: "inbox"), accountID: account.id, name: "Inbox", path: "INBOX", role: .inbox)
        try await store.saveAccount(account)
        try await store.saveMailbox(box)
        var originals: [MailMessageDetail] = []
        for index in 1...2 {
            var detail = headerOnlyDetail(id: MailMessageID(rawValue: "message-\(index)"), accountID: account.id, mailboxID: box.id, subject: "Test")
            detail.summary.date = Date(timeIntervalSince1970: Double(index))
            originals.append(detail)
        }
        try await store.saveMessagesBatch(originals)
        let service = MailBodyBackfillService(maxConcurrentFetches: 2, batchBodyFetcher: { _, _, _ in [] }) { _, _, detail in
            try await Task.sleep(for: .milliseconds(detail.id.rawValue.hasSuffix("2") ? 60 : 2))
            var result = detail
            result.body = MailMessageBody(plainText: MailBodyPart(mimeType: "text/plain", text: detail.id.rawValue, byteCount: 9), redactedPreview: detail.id.rawValue)
            return result
        }
        #expect(try await service.backfillMissingBodies(store: store) == 2)
        for original in originals {
            let saved = try #require(await store.message(id: original.id))
            #expect(saved.body?.plainText?.text == original.id.rawValue)
        }
    }

    @Test func partialBatchSuccessOnlyRetriesMissingBodies() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileBackedMailSourceStore(storeURL: root.appendingPathComponent("mail.sqlite"))
        let account = makeAccount(id: "owner@example.test")
        let box = MailMailbox(id: MailMailboxID(rawValue: "inbox"), accountID: account.id, name: "Inbox", path: "INBOX", role: .inbox)
        try await store.saveAccount(account)
        try await store.saveMailbox(box)
        for index in 1...3 { try await store.saveMessage(headerOnlyDetail(id: MailMessageID(rawValue: "message-\(index)"), accountID: account.id, mailboxID: box.id, subject: "Test")) }
        let attempts = BackfillAttemptRecorder()
        let service = MailBodyBackfillService(batchBodyFetcher: { _, _, details in
            details.map { detail -> MailMessageDetail? in
                guard detail.id.rawValue != "message-2" else { return nil }
                var result = detail
                result.body = MailMessageBody(plainText: MailBodyPart(mimeType: "text/plain", text: detail.id.rawValue, byteCount: 9), redactedPreview: detail.id.rawValue)
                return result
            }
        }) { _, _, detail in
            await attempts.record(detail.id.rawValue)
            var result = detail
            result.body = MailMessageBody(plainText: MailBodyPart(mimeType: "text/plain", text: detail.id.rawValue, byteCount: 9), redactedPreview: detail.id.rawValue)
            return result
        }
        #expect(try await service.backfillMissingBodies(store: store) == 3)
        #expect(await attempts.ids == ["message-2"])
        #expect(try await store.messagesMissingBody(limit: 100).isEmpty)
    }

    @Test func failuresBackOffDurablyAndRemainRetryable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("mail.sqlite")
        let store = FileBackedMailSourceStore(storeURL: url)
        let account = makeAccount(id: "owner@example.test")
        let box = MailMailbox(id: MailMailboxID(rawValue: "inbox"), accountID: account.id, name: "Inbox", path: "INBOX", role: .inbox)
        try await store.saveAccount(account)
        try await store.saveMailbox(box)
        let id = MailMessageID(rawValue: "failed-message")
        try await store.saveMessage(headerOnlyDetail(id: id, accountID: account.id, mailboxID: box.id, subject: "Test"))
        let service = MailBodyBackfillService(batchBodyFetcher: { _, _, _ in [] }, bodyFetcher: { _, _, _ in nil })
        #expect(try await service.backfillMissingBodies(store: store) == 0)
        #expect(try await store.messagesMissingBody(limit: 100).isEmpty)
        let reopened = FileBackedMailSourceStore(storeURL: url)
        #expect(try await reopened.messagesMissingBody(limit: 100).isEmpty)
        try reopened.recordBackfillAttempts([id], now: Date().addingTimeInterval(-4000))
        #expect(try await reopened.messagesMissingBody(limit: 100).map(\.id) == [id])
    }

}


private actor BackfillAttemptRecorder {
    var ids: [String] = []
    func record(_ id: String) { ids.append(id) }
}
