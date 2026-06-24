import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

private final class TestMailCredentialStore: CredentialStore, @unchecked Sendable {
    var secrets: [String: String] = [:]
    func saveSecret(_ secret: String, service: String, account: String) throws { secrets["\(service):\(account)"] = secret }
    func readSecret(service: String, account: String) throws -> String? { secrets["\(service):\(account)"] }
    func deleteSecret(service: String, account: String) throws { secrets.removeValue(forKey: "\(service):\(account)") }
}

@Suite("Mail Runtime Send Pipeline Tests")
struct MailRuntimeSendPipelineTests {
    @Test func approvedSendComposesMessageReadsCredentialCallsSMTPAndMarksDraftSent() async throws {
        let accountID = MailAccountID(rawValue: "account-send")
        let identityID = MailIdentityID(rawValue: "identity-send")
        let binding = AppMailCredentialStore.binding(accountID: accountID, email: "connor@example.com", authMode: .appPassword)
        let account = MailAccount(
            id: accountID,
            provider: .genericIMAPSMTP,
            displayName: "Send Account",
            identities: [MailIdentity(id: identityID, displayName: "Connor", address: MailAddress(name: "Connor", email: "connor@example.com"))],
            outgoing: MailServerEndpoint(host: "smtp.example.com", port: 587, security: .startTLS, protocolKind: .smtp),
            credentialBinding: binding,
            health: MailAccountHealth(status: .ready, summary: "ready")
        )
        let rawCredentialStore = TestMailCredentialStore()
        try rawCredentialStore.saveSecret("app-password", service: binding.keychainService, account: binding.accountName)
        let smtpClient = FakeMailSMTPClient(response: MailSMTPSendResponse(providerMessageID: "provider-123"))
        let draftRepository = InMemoryMailDraftRepository()
        let runtime = MailRuntime(
            repository: InMemoryMailSourceRepository(accounts: [account]),
            cache: InMemoryMailSourceCache(),
            draftStore: draftRepository,
            credentialStore: AppMailCredentialStore(credentialStore: rawCredentialStore),
            smtpClient: smtpClient
        )
        let draft = try await runtime.createDraft(accountID: accountID, identityID: identityID, to: [MailAddress(email: "alice@example.com")], subject: "Real send", body: "Hello")

        let receipt = try await runtime.sendDraft(draftID: draft.id, approved: true, runID: "run", sessionID: "session")

        #expect(receipt.providerMessageID == "provider-123")
        #expect(receipt.envelopeHash == draft.envelopeHash())
        let stored = try #require(try await draftRepository.draft(id: draft.id))
        #expect(stored.status == .sent)
        #expect(stored.sentReceiptID == "provider-123")
        #expect(await smtpClient.requests.count == 1)
        let request = try #require(await smtpClient.requests.first)
        #expect(request.username == "account-send:connor@example.com")
        #expect(request.password == "app-password")
        #expect(request.rawMessage.contains("Subject: Real send"))
    }

    @Test func sendHistoryAggregatesReceiptAttemptsAndAuditRecords() async throws {
        let accountID = MailAccountID(rawValue: "account-history")
        let identityID = MailIdentityID(rawValue: "identity-history")
        let binding = AppMailCredentialStore.binding(accountID: accountID, email: "connor@example.com", authMode: .appPassword)
        let account = MailAccount(
            id: accountID,
            provider: .genericIMAPSMTP,
            displayName: "History Account",
            identities: [MailIdentity(id: identityID, displayName: "Connor", address: MailAddress(email: "connor@example.com"))],
            outgoing: MailServerEndpoint(host: "smtp.example.com", port: 587, security: .startTLS, protocolKind: .smtp),
            credentialBinding: binding,
            health: MailAccountHealth(status: .ready, summary: "ready")
        )
        let rawCredentialStore = TestMailCredentialStore()
        try rawCredentialStore.saveSecret("app-password", service: binding.keychainService, account: binding.accountName)
        let auditLog = InMemoryMailAuditLog()
        let draftRepository = InMemoryMailDraftRepository()
        let runtime = MailRuntime(
            repository: InMemoryMailSourceRepository(accounts: [account]),
            cache: InMemoryMailSourceCache(),
            auditLog: auditLog,
            draftStore: draftRepository,
            credentialStore: AppMailCredentialStore(credentialStore: rawCredentialStore),
            smtpClient: FakeMailSMTPClient(response: MailSMTPSendResponse(providerMessageID: "provider-history"))
        )
        let draft = try await runtime.createDraft(accountID: accountID, identityID: identityID, to: [MailAddress(email: "alice@example.com")], subject: "History", body: "Body")

        _ = try await runtime.sendDraft(draftID: draft.id, approved: true, runID: "run-history", sessionID: "session-history")
        let history = try await runtime.sendHistory(draftID: draft.id)

        #expect(history.draft.status == .sent)
        #expect(history.providerMessageID == "provider-history")
        #expect(history.envelopeHash == draft.envelopeHash())
        #expect(history.attempts.map(\.status) == [.sending, .sent])
        #expect(history.auditRecords.contains { $0.kind == .draftCreated })
        #expect(history.auditRecords.contains { $0.kind == .messageSent && $0.payloadHash == draft.envelopeHash() })
        #expect(history.isTerminal)
    }

    @Test func unapprovedSendDoesNotCallSMTPAndKeepsApprovalGate() async throws {
        let runtime = MailRuntime.fixture()
        let draft = try await runtime.createDraft(accountID: MailAccountID(rawValue: "fixture-account"), identityID: MailIdentityID(rawValue: "fixture-identity"), to: [MailAddress(email: "alice@example.com")], subject: "Needs approval", body: "Body")

        await #expect(throws: MailRuntimeError.self) {
            _ = try await runtime.sendDraft(draftID: draft.id, approved: false)
        }
    }

    @Test func sendFailureMarksDraftFailedAndRecordsAttempt() async throws {
        let accountID = MailAccountID(rawValue: "account-fail")
        let identityID = MailIdentityID(rawValue: "identity-fail")
        let binding = AppMailCredentialStore.binding(accountID: accountID, email: "connor@example.com", authMode: .appPassword)
        let account = MailAccount(
            id: accountID,
            provider: .genericIMAPSMTP,
            displayName: "Send Account",
            identities: [MailIdentity(id: identityID, displayName: "Connor", address: MailAddress(email: "connor@example.com"))],
            outgoing: MailServerEndpoint(host: "smtp.example.com", port: 587, security: .startTLS, protocolKind: .smtp),
            credentialBinding: binding,
            health: MailAccountHealth(status: .ready, summary: "ready")
        )
        let rawCredentialStore = TestMailCredentialStore()
        try rawCredentialStore.saveSecret("app-password", service: binding.keychainService, account: binding.accountName)
        let draftRepository = InMemoryMailDraftRepository()
        let runtime = MailRuntime(
            repository: InMemoryMailSourceRepository(accounts: [account]),
            cache: InMemoryMailSourceCache(),
            draftStore: draftRepository,
            credentialStore: AppMailCredentialStore(credentialStore: rawCredentialStore),
            smtpClient: FakeMailSMTPClient(error: MailSMTPClientError.smtpRejected("550 rejected"))
        )
        let draft = try await runtime.createDraft(accountID: accountID, identityID: identityID, to: [MailAddress(email: "alice@example.com")], subject: "Fail", body: "Body")

        await #expect(throws: Error.self) {
            _ = try await runtime.sendDraft(draftID: draft.id, approved: true)
        }

        let stored = try #require(try await draftRepository.draft(id: draft.id))
        #expect(stored.status == .failed)
        #expect(stored.lastSendError?.contains("550 rejected") == true)
        #expect(try await draftRepository.sendAttempts(draftID: draft.id).contains { $0.status == .failed })
    }
}
