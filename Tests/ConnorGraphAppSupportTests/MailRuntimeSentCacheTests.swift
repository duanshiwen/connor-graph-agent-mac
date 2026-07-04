import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Mail Runtime Sent Cache Tests")
struct MailRuntimeSentCacheTests {
    @Test func successfulSendWritesSentMessageToLocalCacheAndSearchIndex() async throws {
        let accountID = MailAccountID(rawValue: "account-sent")
        let identityID = MailIdentityID(rawValue: "identity-sent")
        let binding = AppMailCredentialStore.binding(accountID: accountID, email: "connor@example.com", authMode: .appPassword)
        let identity = MailIdentity(id: identityID, displayName: "Connor", address: MailAddress(email: "connor@example.com"))
        let account = MailAccount(
            id: accountID,
            provider: .genericIMAPSMTP,
            displayName: "Connor Mail",
            identities: [identity],
            outgoing: MailServerEndpoint(host: "smtp.example.com", port: 587, security: .startTLS, protocolKind: .smtp),
            credentialBinding: binding,
            health: MailAccountHealth(status: .ready, summary: "ready")
        )
        let credentialStore = MailRuntimeSentCacheCredentialStore()
        try credentialStore.saveSecret("secret", service: binding.keychainService, account: binding.accountName)
        let cache = InMemoryMailSourceCache()
        let runtime = MailRuntime(
            repository: InMemoryMailSourceRepository(accounts: [account]),
            cache: cache,
            credentialStore: AppMailCredentialStore(credentialStore: credentialStore),
            smtpClient: FakeMailSMTPClient(response: MailSMTPSendResponse(providerMessageID: "provider-sent-id"))
        )

        let draft = try await runtime.createDraft(accountID: accountID, identityID: identityID, to: [MailAddress(email: "alice@example.com")], subject: "Searchable sent subject", body: "Sent body text")
        _ = try await runtime.sendApprovalPayload(draftID: draft.id)
        _ = try await runtime.sendDraft(draftID: draft.id, approved: true)

        let sentResults = try await runtime.searchMessages(MailRuntimeSearchRequest(query: "Searchable sent", accountID: accountID))
        #expect(sentResults.count == 1)
        #expect(sentResults.first?.subject == "Searchable sent subject")
        #expect(sentResults.first?.mailboxID.rawValue.contains("sent") == true)
        let mailboxes = try await cache.listMailboxes(accountID: accountID)
        #expect(mailboxes.contains { $0.role == .sent })
    }

    @Test func successfulSendPersistsSentAttachmentDescriptorsWithoutContent() async throws {
        let accountID = MailAccountID(rawValue: "account-sent-attachments")
        let identityID = MailIdentityID(rawValue: "identity-sent-attachments")
        let binding = AppMailCredentialStore.binding(accountID: accountID, email: "connor@example.com", authMode: .appPassword)
        let identity = MailIdentity(id: identityID, displayName: "Connor", address: MailAddress(email: "connor@example.com"))
        let account = MailAccount(
            id: accountID,
            provider: .genericIMAPSMTP,
            displayName: "Connor Mail",
            identities: [identity],
            outgoing: MailServerEndpoint(host: "smtp.example.com", port: 587, security: .startTLS, protocolKind: .smtp),
            credentialBinding: binding,
            health: MailAccountHealth(status: .ready, summary: "ready")
        )
        let credentialStore = MailRuntimeSentCacheCredentialStore()
        try credentialStore.saveSecret("secret", service: binding.keychainService, account: binding.accountName)
        let cache = InMemoryMailSourceCache()
        let runtime = MailRuntime(
            repository: InMemoryMailSourceRepository(accounts: [account]),
            cache: cache,
            credentialStore: AppMailCredentialStore(credentialStore: credentialStore),
            smtpClient: FakeMailSMTPClient(response: MailSMTPSendResponse(providerMessageID: "provider-sent-attachment-id"))
        )

        let draft = try await runtime.createDraft(accountID: accountID, identityID: identityID, to: [MailAddress(email: "alice@example.com")], subject: "Attachment sent", body: "Sent body text", attachmentIDs: [MailAttachmentID(rawValue: "attachment-1")])
        _ = try await runtime.sendApprovalPayload(draftID: draft.id)
        _ = try await runtime.sendDraft(draftID: draft.id, approved: true)

        let sent = try #require(try await cache.message(id: MailMessageID(rawValue: "provider-sent-attachment-id")))
        #expect(sent.attachments.count == 1)
        let attachment = try #require(sent.attachments.first)
        #expect(attachment.id == MailAttachmentID(rawValue: "attachment-1"))
        #expect(attachment.filename == "attachment-1")
        #expect(attachment.byteCount == 0)
        #expect(sent.body?.plainText?.text.contains("Sent body text") == true)
    }
}


private final class MailRuntimeSentCacheCredentialStore: CredentialStore, @unchecked Sendable {
    private var values: [String: String] = [:]
    private let lock = NSLock()
    func saveSecret(_ secret: String, service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        values["\(service)::\(account)"] = secret
    }
    func readSecret(service: String, account: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return values["\(service)::\(account)"]
    }
    func deleteSecret(service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        values.removeValue(forKey: "\(service)::\(account)")
    }
}
