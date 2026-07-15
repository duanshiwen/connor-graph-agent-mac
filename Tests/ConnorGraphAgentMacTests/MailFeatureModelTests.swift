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

    @Test func listProjectionUsesBoundedWindowAndPersistsFiltersInModel() throws {
        let f = try fixture(); defer { f.cleanup() }
        let data = mailFixture(id: "message-template")
        let messages = (0..<250).map { index in
            MailMessageSummary(
                id: MailMessageID(rawValue: "message-\(index)"),
                accountID: data.account.id,
                mailboxID: data.mailbox.id,
                subject: index == 149 ? "Needle" : "Subject \(index)",
                from: MailAddress(email: "sender@example.com"),
                to: data.account.identities.map(\.address),
                date: Date(timeIntervalSince1970: TimeInterval(index)),
                snippet: "Snippet"
            )
        }

        f.model.presentation = NativeMailBrowserPresentation(
            accounts: [data.account],
            mailboxes: [data.mailbox],
            messages: messages
        )
        #expect(f.model.filteredListMessages.count == 250)
        #expect(f.model.visibleListMessages.count == 100)
        #expect(f.model.hiddenFilteredListMessageCount == 150)

        f.model.loadMoreListMessages()
        #expect(f.model.visibleListMessages.count == 200)
        #expect(f.model.hiddenFilteredListMessageCount == 50)

        f.model.searchQuery = "Needle"
        #expect(f.model.filteredListMessages.map(\.subject) == ["Needle"])
        #expect(f.model.visibleListMessages.count == 1)
    }

    @Test func shutdownPreventsFurtherReloadApplication() async throws {
        let f = try fixture(); defer { f.cleanup() }
        f.model.shutdown(); await f.model.reload()
        #expect(f.model.presentation == .empty)
    }

    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mail-feature-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = FileBackedMailSourceStore(storeURL: root.appendingPathComponent("mail.json"))
        let preferences = FileBackedMailPreferencesStore(preferencesURL: root.appendingPathComponent("preferences.json"))
        return Fixture(root: root, store: store, model: MailFeatureModel(store: store, preferencesStore: preferences))
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
