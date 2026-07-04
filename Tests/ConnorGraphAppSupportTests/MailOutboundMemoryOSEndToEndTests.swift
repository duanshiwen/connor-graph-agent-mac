import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore
import ConnorGraphAppSupport

private final class MailOutboundMemoryOSCredentialStore: CredentialStore, @unchecked Sendable {
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

@Suite("Mail Outbound Memory OS End-to-End Tests")
struct MailOutboundMemoryOSEndToEndTests {
    @Test func approvedSendPersistsOutboundEvidenceIntoMemoryOSL0L1() async throws {
        let memoryStore = try SQLiteMemoryOSStore(path: temporaryMailOutboundMemoryOSDatabaseURL().path)
        try memoryStore.migrate()
        let memoryFacade = AppMemoryOSFacade(store: memoryStore)
        let accountID = MailAccountID(rawValue: "account-outbound-memory")
        let identityID = MailIdentityID(rawValue: "identity-outbound-memory")
        let binding = AppMailCredentialStore.binding(accountID: accountID, email: "connor@example.com", authMode: .appPassword)
        let identity = MailIdentity(id: identityID, displayName: "Connor", address: MailAddress(email: "connor@example.com"))
        let account = MailAccount(
            id: accountID,
            provider: .genericIMAPSMTP,
            displayName: "Outbound Memory Account",
            identities: [identity],
            outgoing: MailServerEndpoint(host: "smtp.example.com", port: 587, security: .startTLS, protocolKind: .smtp),
            credentialBinding: binding,
            health: MailAccountHealth(status: .ready, summary: "ready")
        )
        let credentialStore = MailOutboundMemoryOSCredentialStore()
        try credentialStore.saveSecret("outbound-app-password", service: binding.credentialNamespace, account: binding.accountName)
        let runtime = MailRuntime(
            repository: InMemoryMailSourceRepository(accounts: [account]),
            cache: InMemoryMailSourceCache(),
            draftStore: InMemoryMailDraftRepository(),
            credentialStore: AppMailCredentialStore(credentialStore: credentialStore),
            smtpClient: FakeMailSMTPClient(response: MailSMTPSendResponse(providerMessageID: "provider-outbound-memory")),
            memoryOSFacade: memoryFacade
        )
        let draft = try await runtime.createDraft(
            accountID: accountID,
            identityID: identityID,
            to: [MailAddress(email: "alice@example.com")],
            cc: [MailAddress(email: "carol@example.com")],
            subject: "Outbound Memory Evidence",
            body: "This sent mail should become outbound Memory OS evidence.",
            intentSummary: "Verify outbound evidence"
        )
        let approval = try await runtime.sendApprovalPayload(draftID: draft.id)

        let receipt = try await runtime.sendDraft(draftID: draft.id, approved: true, runID: "run-outbound-memory", sessionID: "session-outbound-memory")

        #expect(receipt.providerMessageID == "provider-outbound-memory")
        #expect(receipt.envelopeHash == approval.envelopeHash)
        #expect(try memoryStore.query(sql: "SELECT COUNT(*) FROM memory_l0_provenance_objects;").first?.first == "1")
        #expect(try memoryStore.query(sql: "SELECT COUNT(*) FROM memory_l1_capture_events;").first?.first == "1")
        let l0 = try #require(try memoryStore.query(sql: "SELECT source_id, title, content, metadata_json FROM memory_l0_provenance_objects LIMIT 1;").first)
        #expect(l0[0].contains("mail:sent:provider-outbound-memory"))
        #expect(l0[1] == "Outbound Memory Evidence")
        #expect(l0[2].contains("Direction: outbound"))
        #expect(l0[2].contains("To: alice@example.com"))
        #expect(l0[2].contains("Cc: carol@example.com"))
        #expect(l0[2].contains("This sent mail should become outbound Memory OS evidence."))
        #expect(l0[3].contains("\"direction\":\"outbound\""))
        #expect(l0[3].contains("\"mail_draft_id\":\"\(draft.id.rawValue)\""))
        #expect(l0[3].contains("\"provider_message_id\":\"provider-outbound-memory\""))
        #expect(l0[3].contains("\"envelope_hash\":\"\(receipt.envelopeHash)\""))
        #expect(!l0[2].contains("outbound-app-password"))
        #expect(!l0[3].contains("outbound-app-password"))
    }
}

private func temporaryMailOutboundMemoryOSDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("mail-outbound-memory-os-\(UUID().uuidString).sqlite")
}
