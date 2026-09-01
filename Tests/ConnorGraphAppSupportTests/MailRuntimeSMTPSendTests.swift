import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Mail Runtime SMTP Send Tests")
struct MailRuntimeSMTPSendTests {
    @Test func approvedSendUsesCredentialComposerSMTPAndPersistsReceipt() async throws {
        let accountID = MailAccountID(rawValue: "account-1")
        let identityID = MailIdentityID(rawValue: "identity-1")
        let binding = AppMailCredentialStore.binding(accountID: accountID, email: "connor@example.com", authMode: .appPassword)
        let identity = MailIdentity(id: identityID, displayName: "Connor", address: MailAddress(name: "Connor", email: "connor@example.com"))
        let account = MailAccount(
            id: accountID,
            provider: .genericIMAPSMTP,
            displayName: "Connor Mail",
            identities: [identity],
            outgoing: MailServerEndpoint(host: "smtp.example.com", port: 587, security: .startTLS, protocolKind: .smtp),
            credentialBinding: binding,
            health: MailAccountHealth(status: .ready, summary: "ready")
        )
        let credentialMemory = MailRuntimeSMTPMemoryCredentialStore()
        try credentialMemory.saveSecret("app-password", service: binding.credentialNamespace, account: binding.accountName)
        let smtp = FakeMailSMTPClient(response: MailSMTPSendResponse(providerMessageID: "smtp-server-id"))
        let draftRepository = InMemoryMailDraftRepository()
        let notifications = MailCacheChangeNotificationRecorder()
        let observer = NotificationCenter.default.addObserver(forName: .connorMailCacheDidChange, object: nil, queue: nil) { notification in
            notifications.record(notification)
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let runtime = MailRuntime(
            repository: InMemoryMailSourceRepository(accounts: [account]),
            cache: InMemoryMailSourceCache(),
            draftStore: draftRepository,
            credentialStore: AppMailCredentialStore(credentialStore: credentialMemory),
            smtpClient: smtp,
            messageComposer: MailMessageComposer()
        )

        let draft = try await runtime.createDraft(accountID: accountID, identityID: identityID, to: [MailAddress(email: "alice@example.com")], subject: "Approved", body: "Body")
        _ = try await runtime.sendApprovalPayload(draftID: draft.id)
        let receipt = try await runtime.sendDraft(draftID: draft.id, approved: true)

        #expect(receipt.providerMessageID == "smtp-server-id")
        let request = try #require(await smtp.requests.first)
        #expect(request.username == "connor@example.com")
        #expect(request.password == "app-password")
        #expect(request.from.email == "connor@example.com")
        #expect(request.recipients.map(\.email) == ["alice@example.com"])
        #expect(request.rawMessage.contains("Subject: Approved"))
        #expect(try await draftRepository.draft(id: draft.id)?.status == .sent)
        let attempts = try await draftRepository.sendAttempts(draftID: draft.id)
        #expect(attempts.contains { $0.status == .sent && $0.providerMessageID == "smtp-server-id" })
        // 过滤出本用例账号的通知，避免并行执行时捕获到其他用例（如 execute 模式）的通知。
        let notification = try #require(notifications.notifications.first { ($0.userInfo?[MailCacheChangeNotificationUserInfoKey.accountID] as? String) == accountID.rawValue })
        #expect(notification.userInfo?[MailCacheChangeNotificationUserInfoKey.accountID] as? String == accountID.rawValue)
        #expect(notification.userInfo?[MailCacheChangeNotificationUserInfoKey.messageID] as? String == "smtp-server-id")
        #expect(notification.userInfo?[MailCacheChangeNotificationUserInfoKey.reason] as? String == MailCacheChangeReason.sentMessageSaved.rawValue)
    }

    /// 回归测试：执行模式（trustedWrite/allowAll）没有审批卡片，approved=true 直接发送
    /// 且 draft 未写入 approvedEnvelopeHash 时，应视为自动批准并成功发送。
    @Test func approvedSendWithoutApprovalCardAutoApprovesInExecuteMode() async throws {
        let accountID = MailAccountID(rawValue: "account-execute")
        let identityID = MailIdentityID(rawValue: "identity-execute")
        let binding = AppMailCredentialStore.binding(accountID: accountID, email: "connor@example.com", authMode: .appPassword)
        let identity = MailIdentity(id: identityID, displayName: "Connor", address: MailAddress(name: "Connor", email: "connor@example.com"))
        let account = MailAccount(
            id: accountID,
            provider: .genericIMAPSMTP,
            displayName: "Connor Mail",
            identities: [identity],
            outgoing: MailServerEndpoint(host: "smtp.example.com", port: 587, security: .startTLS, protocolKind: .smtp),
            credentialBinding: binding,
            health: MailAccountHealth(status: .ready, summary: "ready")
        )
        let credentialMemory = MailRuntimeSMTPMemoryCredentialStore()
        try credentialMemory.saveSecret("app-password", service: binding.credentialNamespace, account: binding.accountName)
        let smtp = FakeMailSMTPClient(response: MailSMTPSendResponse(providerMessageID: "execute-smtp-id"))
        let draftRepository = InMemoryMailDraftRepository()
        let runtime = MailRuntime(
            repository: InMemoryMailSourceRepository(accounts: [account]),
            cache: InMemoryMailSourceCache(),
            draftStore: draftRepository,
            credentialStore: AppMailCredentialStore(credentialStore: credentialMemory),
            smtpClient: smtp,
            messageComposer: MailMessageComposer()
        )

        let draft = try await runtime.createDraft(accountID: accountID, identityID: identityID, to: [MailAddress(email: "alice@example.com")], subject: "Execute mode", body: "Body")
        // 不调用 sendApprovalPayload：模拟执行模式无审批卡片。
        let receipt = try await runtime.sendDraft(draftID: draft.id, approved: true)

        #expect(receipt.providerMessageID == "execute-smtp-id")
        #expect(try await draftRepository.draft(id: draft.id)?.status == .sent)
        #expect(try await smtp.requests.first?.rawMessage.contains("Subject: Execute mode") == true)
    }

    @Test func approvedSendFailsWhenCredentialMissingAndDoesNotCallSMTP() async throws {
        let accountID = MailAccountID(rawValue: "account-1")
        let identityID = MailIdentityID(rawValue: "identity-1")
        let binding = AppMailCredentialStore.binding(accountID: accountID, email: "connor@example.com", authMode: .appPassword)
        let account = MailAccount(
            id: accountID,
            provider: .genericIMAPSMTP,
            displayName: "Connor Mail",
            identities: [MailIdentity(id: identityID, displayName: "Connor", address: MailAddress(email: "connor@example.com"))],
            outgoing: MailServerEndpoint(host: "smtp.example.com", port: 587, security: .startTLS, protocolKind: .smtp),
            credentialBinding: binding,
            health: MailAccountHealth(status: .ready, summary: "ready")
        )
        let smtp = FakeMailSMTPClient()
        let runtime = MailRuntime(
            repository: InMemoryMailSourceRepository(accounts: [account]),
            cache: InMemoryMailSourceCache(),
            credentialStore: AppMailCredentialStore(credentialStore: MailRuntimeSMTPMemoryCredentialStore()),
            smtpClient: smtp
        )
        let draft = try await runtime.createDraft(accountID: accountID, identityID: identityID, to: [MailAddress(email: "alice@example.com")], subject: "Missing credential", body: "Body")
        _ = try await runtime.sendApprovalPayload(draftID: draft.id)

        await #expect(throws: MailRuntimeError.self) {
            _ = try await runtime.sendDraft(draftID: draft.id, approved: true)
        }
        #expect(await smtp.requests.isEmpty)
    }
}


private final class MailCacheChangeNotificationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var notifications: [Notification] = []

    func record(_ notification: Notification) {
        lock.lock(); defer { lock.unlock() }
        notifications.append(notification)
    }
}

private final class MailRuntimeSMTPMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private var secrets: [String: String] = [:]
    private let lock = NSLock()

    func saveSecret(_ secret: String, service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        secrets["\(service)::\(account)"] = secret
    }

    func readSecret(service: String, account: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return secrets["\(service)::\(account)"]
    }

    func deleteSecret(service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        secrets.removeValue(forKey: "\(service)::\(account)")
    }
}
