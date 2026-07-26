import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@MainActor
struct MailFeatureModelTests {
    @Test func reloadBuildsPresentationRepairsSelectionAndReconcilesPreferences() async throws {
        let f = try fixture(); defer { f.cleanup() }
        let data = mailFixture(id: "message-1")
        try await f.store.saveAccount(data.account); try await f.store.saveMailbox(data.mailbox); try await f.store.saveMessage(data.detail)
        await f.model.reload()
        #expect(f.model.presentation.messages.map(\.id) == [data.detail.id])
        #expect(f.model.selectedAccountID == data.account.id)
        #expect(f.model.selectedMailboxID == data.mailbox.id)
        #expect(f.model.selectedMessageID == data.detail.id)
    }

    @Test func searchResultSupportsPrefixedAndLegacyIDs() async throws {
        let f = try fixture(); defer { f.cleanup() }
        let data = mailFixture(id: "yakii_d@icloud.com-INBOX-100")
        try await f.store.saveAccount(data.account); try await f.store.saveMailbox(data.mailbox); try await f.store.saveMessage(data.detail)
        await f.model.reload()
        f.model.searchQuery = "old"
        f.model.openSearchResult(NativeSearchResult(id: "mail-result", sourceKind: .mail, externalID: "mail-yakii-d-icloud-com-INBOX-100", title: "mail", snippet: "", score: 1, lexicalScore: 1, freshnessScore: 0, fieldScore: 0, temporal: NativeSearchTemporalMetadata(), resultTimeLabel: ""))
        #expect(f.model.selectedMessageID == data.detail.id)
        #expect(f.model.searchQuery.isEmpty)
    }

    @Test func defaultSendAccountPersistsAndMissingAccountReportsExactError() async throws {
        let f = try fixture(); defer { f.cleanup() }
        await f.model.setDefaultSendAccount(MailAccountID(rawValue: "missing"))
        #expect(f.model.errorMessage == "无法设置默认发信账户：账户不存在")
        let data = mailFixture(id: "message-1")
        try await f.store.saveAccount(data.account); try await f.store.saveMailbox(data.mailbox); await f.model.reload()
        await f.model.setDefaultSendAccount(data.account.id)
        #expect(f.model.preferences.defaultSendAccountID == data.account.id)
    }

    @Test func listProjectionLoadsAllMessagesThroughDatabasePages() async throws {
        let f = try fixture(); defer { f.cleanup() }
        let data = mailFixture(id: "message-template")
        let messages = (0..<130).map { index in
            MailMessageDetail(summary: MailMessageSummary(
                id: MailMessageID(rawValue: String(format: "message-%03d", index)),
                accountID: data.account.id,
                mailboxID: data.mailbox.id,
                subject: "Subject \(index)",
                from: MailAddress(email: "sender@example.com"),
                to: data.account.identities.map(\.address),
                date: Date(timeIntervalSince1970: TimeInterval(10_000 - index / 3)),
                snippet: "Snippet"
            ), body: MailMessageBody(
                plainText: MailBodyPart(
                    mimeType: "text/plain",
                    text: index.isMultiple(of: 2) ? "BodyNeedle \(index)" : "Ordinary body \(index)",
                    byteCount: 32
                ),
                redactedPreview: "Body preview"
            ))
        }
        try await f.store.saveAccount(data.account)
        try await f.store.saveMailbox(data.mailbox)
        try await f.store.saveMessagesBatch(messages)

        await f.model.reload()
        #expect(f.model.visibleListMessages.count == 50)

        f.model.loadMoreListMessagesIfNeeded(currentMessageID: messages[10].id)
        await f.model.waitForPendingOperations()
        #expect(f.model.visibleListMessages.count == 50)

        let firstPageEnd = try #require(f.model.visibleListMessages.last?.id)
        f.model.loadMoreListMessagesIfNeeded(currentMessageID: firstPageEnd)
        f.model.loadMoreListMessagesIfNeeded(currentMessageID: firstPageEnd)
        await f.model.waitForPendingOperations()
        #expect(f.model.visibleListMessages.count == 100)

        f.model.loadMoreListMessagesIfNeeded(currentMessageID: try #require(f.model.visibleListMessages.last?.id))
        await f.model.waitForPendingOperations()
        #expect(f.model.visibleListMessages.count == 130)
        #expect(Set(f.model.visibleListMessages.map(\.id)).count == 130)
        #expect(f.model.visibleListMessages.map(\.id) == messages.map(\.id))

        f.model.searchQuery = "BodyNeedle"
        await f.model.waitForPendingOperations()
        #expect(f.model.visibleListMessages.count == 50)
        f.model.loadMoreListMessagesIfNeeded(currentMessageID: try #require(f.model.visibleListMessages.last?.id))
        await f.model.waitForPendingOperations()
        #expect(f.model.visibleListMessages.count == 65)
        #expect(Set(f.model.visibleListMessages.map(\.id)).count == 65)
    }

    @Test func shutdownPreventsFurtherReloadApplication() async throws {
        let f = try fixture(); defer { f.cleanup() }
        f.model.shutdown(); await f.model.reload()
        #expect(f.model.presentation == .empty)
    }

    @Test func addingAccountRefreshesImmediatelyAndSyncsBeforeTaskReconciliation() async throws {
        let f = try fixture(); defer { f.cleanup() }
        var reconciliationCount = 0
        f.model.sourceSetChanged = {
            reconciliationCount += 1
            throw MailFeatureModelTestError.reconciliationFailed
        }
        f.model.presentAddAccountSheet()

        try await f.model.addAccountAndPrepareSync(
            displayName: "Test Mail",
            email: "test@example.com",
            provider: .genericIMAPSMTP,
            incomingHost: "imap.example.com",
            incomingPort: 143,
            incomingSecurity: .startTLS,
            outgoingHost: "smtp.example.com",
            outgoingPort: 587,
            outgoingSecurity: .startTLS,
            username: "test@example.com",
            password: "app-password",
            authMode: .password
        )

        #expect(f.model.presentation.accounts.map(\.id.rawValue) == ["test@example.com"])
        #expect(f.model.presentation.mailboxes.map(\.path) == ["INBOX"])
        #expect(f.model.isPresentingAddAccountSheet == false)
        #expect(f.model.isSyncing)

        await f.model.waitForPendingOperations()

        #expect(reconciliationCount == 1)
        #expect(f.model.isSyncing == false)
        #expect(f.model.presentation.accounts.first?.health.status == .blocked)
        #expect(f.model.syncMessage?.contains("全量同步完成") == true)
        #expect(f.model.syncMessage?.contains("定时刷新任务创建失败") == true)
    }

    @Test func addingAccountFailsExplicitlyWhenMailStoreIsUnavailable() async throws {
        let credentials = MailFeatureMemoryCredentialStore()
        let model = MailFeatureModel(
            store: nil,
            preferencesStore: nil,
            credentialStore: AppMailCredentialStore(credentialStore: credentials)
        )

        await #expect(throws: MailFeatureModel.ModelError.storeUnavailable) {
            try await model.addAccountAndPrepareSync(
                displayName: "Test Mail",
                email: "test@example.com",
                provider: .genericIMAPSMTP,
                incomingHost: "imap.example.com",
                incomingPort: 993,
                incomingSecurity: .tls,
                outgoingHost: "smtp.example.com",
                outgoingPort: 587,
                outgoingSecurity: .startTLS,
                username: "test@example.com",
                password: "app-password",
                authMode: .password
            )
        }
        #expect(credentials.savedSecretCount == 0)
    }

    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mail-feature-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = FileBackedMailSourceStore(storeURL: root.appendingPathComponent("mail.json"))
        let preferences = FileBackedMailPreferencesStore(preferencesURL: root.appendingPathComponent("preferences.json"))
        let credentials = MailFeatureMemoryCredentialStore()
        return Fixture(
            root: root,
            store: store,
            model: MailFeatureModel(
                store: store,
                preferencesStore: preferences,
                credentialStore: AppMailCredentialStore(credentialStore: credentials)
            )
        )
    }

    private func mailFixture(id: String) -> (account: MailAccount, mailbox: MailMailbox, detail: MailMessageDetail) {
        let accountID = MailAccountID(rawValue: "mail@example.com")
        let identity = MailIdentity(id: MailIdentityID(rawValue: "identity"), displayName: "Mail", address: MailAddress(name: "Mail", email: "mail@example.com"))
        let account = MailAccount(id: accountID, provider: .localFixture, displayName: "Mail", identities: [identity])
        let mailbox = MailMailbox(id: MailMailboxID(rawValue: "inbox"), accountID: accountID, name: "Inbox", path: "INBOX", role: .inbox)
        let summary = MailMessageSummary(id: MailMessageID(rawValue: id), accountID: accountID, mailboxID: mailbox.id, subject: "Subject", from: MailAddress(email: "sender@example.com"), to: [identity.address], snippet: "Snippet")
        return (account, mailbox, MailMessageDetail(summary: summary))
    }

    private struct Fixture { let root: URL; let store: FileBackedMailSourceStore; let model: MailFeatureModel; func cleanup() { try? FileManager.default.removeItem(at: root) } }
}

private enum MailFeatureModelTestError: Error {
    case reconciliationFailed
}

private final class MailFeatureMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var secrets: [String: String] = [:]

    var savedSecretCount: Int {
        lock.withLock { secrets.count }
    }

    func saveSecret(_ secret: String, service: String, account: String) throws {
        lock.withLock { secrets["\(service):\(account)"] = secret }
    }

    func readSecret(service: String, account: String) throws -> String? {
        lock.withLock { secrets["\(service):\(account)"] }
    }

    func deleteSecret(service: String, account: String) throws {
        _ = lock.withLock { secrets.removeValue(forKey: "\(service):\(account)") }
    }
}
