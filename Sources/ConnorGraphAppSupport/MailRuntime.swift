import Foundation
import ConnorGraphCore

public enum MailRuntimeError: Error, Sendable, Equatable, CustomStringConvertible {
    case accountNotFound(String)
    case mailboxNotFound(String)
    case messageNotFound(String)
    case draftNotFound(String)
    case approvalRequired(String)
    case unsupportedNetworkOperation(String)

    public var description: String {
        switch self {
        case .accountNotFound(let id): "Mail account not found: \(id)"
        case .mailboxNotFound(let id): "Mail mailbox not found: \(id)"
        case .messageNotFound(let id): "Mail message not found: \(id)"
        case .draftNotFound(let id): "Mail draft not found: \(id)"
        case .approvalRequired(let id): "Approval required: \(id)"
        case .unsupportedNetworkOperation(let op): "Network operation not implemented in commercial skeleton: \(op)"
        }
    }
}

public protocol MailSourceRepository: Sendable {
    func listAccounts() async throws -> [MailAccount]
    func saveAccount(_ account: MailAccount) async throws
    func account(id: MailAccountID) async throws -> MailAccount?
}

public protocol MailSourceCache: Sendable {
    func listMailboxes(accountID: MailAccountID) async throws -> [MailMailbox]
    func saveMailbox(_ mailbox: MailMailbox) async throws
    func saveMessage(_ message: MailMessageDetail) async throws
    func searchMessages(query: String, accountID: MailAccountID?) async throws -> [MailMessageSummary]
    func message(id: MailMessageID) async throws -> MailMessageDetail?
    func updateFlags(messageIDs: [MailMessageID], transform: @Sendable (MailMessageFlags) -> MailMessageFlags) async throws
}

public protocol MailAuditLogProtocol: Sendable {
    func record(_ record: MailAuditRecord) async throws
    func listRecords() async throws -> [MailAuditRecord]
}

public actor InMemoryMailSourceRepository: MailSourceRepository {
    private var accounts: [MailAccountID: MailAccount]

    public init(accounts: [MailAccount] = []) {
        self.accounts = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
    }

    public func listAccounts() async throws -> [MailAccount] {
        accounts.values.sorted { $0.displayName < $1.displayName }
    }

    public func saveAccount(_ account: MailAccount) async throws {
        accounts[account.id] = account
    }

    public func account(id: MailAccountID) async throws -> MailAccount? {
        accounts[id]
    }
}

public actor InMemoryMailSourceCache: MailSourceCache {
    private var mailboxes: [MailMailboxID: MailMailbox]
    private var messages: [MailMessageID: MailMessageDetail]

    public init(mailboxes: [MailMailbox] = [], messages: [MailMessageDetail] = []) {
        self.mailboxes = Dictionary(uniqueKeysWithValues: mailboxes.map { ($0.id, $0) })
        self.messages = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
    }

    public func listMailboxes(accountID: MailAccountID) async throws -> [MailMailbox] {
        mailboxes.values.filter { $0.accountID == accountID }.sorted { $0.path < $1.path }
    }

    public func saveMailbox(_ mailbox: MailMailbox) async throws {
        mailboxes[mailbox.id] = mailbox
    }

    public func saveMessage(_ message: MailMessageDetail) async throws {
        messages[message.id] = message
    }

    public func searchMessages(query: String, accountID: MailAccountID?) async throws -> [MailMessageSummary] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return messages.values.map(\.summary).filter { summary in
            if let accountID, summary.accountID != accountID { return false }
            if normalized.isEmpty { return true }
            return summary.subject.lowercased().contains(normalized)
                || summary.snippet.lowercased().contains(normalized)
                || summary.from.email.lowercased().contains(normalized)
        }.sorted { $0.date > $1.date }
    }

    public func message(id: MailMessageID) async throws -> MailMessageDetail? {
        messages[id]
    }

    public func updateFlags(messageIDs: [MailMessageID], transform: @Sendable (MailMessageFlags) -> MailMessageFlags) async throws {
        for id in messageIDs {
            guard var detail = messages[id] else { continue }
            detail.summary.flags = transform(detail.summary.flags)
            messages[id] = detail
        }
    }
}

public actor InMemoryMailAuditLog: MailAuditLogProtocol {
    private var records: [MailAuditRecord] = []

    public init() {}

    public func record(_ record: MailAuditRecord) async throws {
        records.append(record)
    }

    public func listRecords() async throws -> [MailAuditRecord] {
        records
    }
}

public struct MailRuntimeSearchRequest: Sendable, Equatable {
    public var query: String
    public var accountID: MailAccountID?
    public var limit: Int

    public init(query: String, accountID: MailAccountID? = nil, limit: Int = 20) {
        self.query = query
        self.accountID = accountID
        self.limit = limit
    }
}

public struct MailRuntimeSendApproval: Codable, Sendable, Equatable {
    public var draftID: MailDraftID
    public var title: String
    public var from: String
    public var to: [String]
    public var cc: [String]
    public var bcc: [String]
    public var subject: String
    public var bodyPreview: String
    public var attachmentCount: Int
    public var riskSummary: String

    public init(draft: MailDraft, from: String) {
        self.draftID = draft.id
        self.title = "Send email approval"
        self.from = from
        self.to = draft.to.map(\.email)
        self.cc = draft.cc.map(\.email)
        self.bcc = draft.bcc.map(\.email)
        self.subject = draft.subject
        self.bodyPreview = String(draft.body.prefix(500))
        self.attachmentCount = draft.attachmentIDs.count
        self.riskSummary = "Email sending is always approval-gated."
    }
}

public actor MailDraftStore {
    private var drafts: [MailDraftID: MailDraft] = [:]

    public init() {}

    public func save(_ draft: MailDraft) {
        drafts[draft.id] = draft
    }

    public func draft(id: MailDraftID) -> MailDraft? {
        drafts[id]
    }

    public func discard(id: MailDraftID) throws -> MailDraft {
        guard var draft = drafts[id] else { throw MailRuntimeError.draftNotFound(id.rawValue) }
        draft.status = .discarded
        drafts[id] = draft
        return draft
    }
}

public struct MailRuntime: Sendable {
    public var repository: any MailSourceRepository
    public var cache: any MailSourceCache
    public var auditLog: any MailAuditLogProtocol
    public var draftStore: MailDraftStore

    public init(
        repository: any MailSourceRepository,
        cache: any MailSourceCache,
        auditLog: any MailAuditLogProtocol = InMemoryMailAuditLog(),
        draftStore: MailDraftStore = MailDraftStore()
    ) {
        self.repository = repository
        self.cache = cache
        self.auditLog = auditLog
        self.draftStore = draftStore
    }

    public static func fixture() -> MailRuntime {
        let accountID = MailAccountID(rawValue: "fixture-account")
        let identity = MailIdentity(id: MailIdentityID(rawValue: "fixture-identity"), displayName: "Connor Fixture", address: MailAddress(name: "Connor Fixture", email: "connor@example.com"))
        let account = MailAccount(id: accountID, provider: .localFixture, displayName: "Fixture Mail", identities: [identity], health: MailAccountHealth(status: .ready, summary: "Fixture ready"))
        let inbox = MailMailbox(id: MailMailboxID(rawValue: "fixture-inbox"), accountID: accountID, name: "Inbox", path: "INBOX", role: .inbox, status: MailMailboxStatus(messageCount: 1, unreadCount: 1, syncCursor: MailSyncCursor(value: "1"), lastSyncedAt: Date()))
        let summary = MailMessageSummary(
            id: MailMessageID(rawValue: "fixture-message-1"),
            accountID: accountID,
            mailboxID: inbox.id,
            threadID: MailThreadID(rawValue: "fixture-thread-1"),
            subject: "Connor Native Mail System",
            from: MailAddress(name: "Alice", email: "alice@example.com"),
            to: [identity.address],
            snippet: "Commercial native mail system fixture",
            flags: MailMessageFlags(isRead: false),
            hasAttachments: true
        )
        let body = MailMessageBody(plainText: MailBodyPart(mimeType: "text/plain", text: "Commercial native mail system fixture body", byteCount: 43), redactedPreview: "Commercial native mail system fixture body", bodyHash: "fixture-body-hash")
        let attachment = MailAttachmentDescriptor(id: MailAttachmentID(rawValue: "fixture-attachment-1"), messageID: summary.id, filename: "brief.pdf", mimeType: "application/pdf", byteCount: 1024)
        let detail = MailMessageDetail(summary: summary, headers: MailMessageHeaders(messageIDHeader: "<fixture@example.com>", rawHeaderHash: "fixture-header-hash"), body: body, attachments: [attachment])
        return MailRuntime(repository: InMemoryMailSourceRepository(accounts: [account]), cache: InMemoryMailSourceCache(mailboxes: [inbox], messages: [detail]))
    }

    public func listAccounts(runID: String? = nil, sessionID: String? = nil) async throws -> [MailAccount] {
        let accounts = try await repository.listAccounts()
        try await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, kind: .accountHealthChecked, riskClass: .read, redactedSummary: "Listed \(accounts.count) mail accounts"))
        return accounts
    }

    public func accountHealth(accountID: MailAccountID, runID: String? = nil, sessionID: String? = nil) async throws -> MailAccountHealth {
        guard let account = try await repository.account(id: accountID) else { throw MailRuntimeError.accountNotFound(accountID.rawValue) }
        try await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, accountID: accountID, kind: .accountHealthChecked, riskClass: .read, redactedSummary: account.health.summary))
        return account.health
    }

    public func listMailboxes(accountID: MailAccountID, runID: String? = nil, sessionID: String? = nil) async throws -> [MailMailbox] {
        let boxes = try await cache.listMailboxes(accountID: accountID)
        try await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, accountID: accountID, kind: .messageSearched, riskClass: .read, redactedSummary: "Listed \(boxes.count) mailboxes"))
        return boxes
    }

    public func searchMessages(_ request: MailRuntimeSearchRequest, runID: String? = nil, sessionID: String? = nil) async throws -> [MailMessageSummary] {
        let messages = try await cache.searchMessages(query: request.query, accountID: request.accountID)
        try await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, accountID: request.accountID, kind: .messageSearched, riskClass: .read, redactedSummary: "Searched mail messages; returned \(min(messages.count, request.limit)) summaries"))
        return Array(messages.prefix(request.limit))
    }

    public func getMessage(id: MailMessageID, includeBody: Bool = false, runID: String? = nil, sessionID: String? = nil) async throws -> MailMessageDetail {
        guard var message = try await cache.message(id: id) else { throw MailRuntimeError.messageNotFound(id.rawValue) }
        if !includeBody { message.body = nil }
        try await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, accountID: message.summary.accountID, messageID: id, kind: includeBody ? .messageBodyRead : .messageRead, riskClass: includeBody ? .bodyRead : .read, redactedSummary: includeBody ? "Read mail body without mutating read state" : "Read mail summary/detail without body and without mutating read state", payloadHash: message.headers.rawHeaderHash))
        return message
    }

    public func setReadState(messageIDs: [MailMessageID], isRead: Bool, runID: String? = nil, sessionID: String? = nil) async throws {
        try await cache.updateFlags(messageIDs: messageIDs) { flags in
            var copy = flags
            copy.isRead = isRead
            return copy
        }
        try await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, kind: .stateMutated, riskClass: .mutation, redactedSummary: "Set read state for \(messageIDs.count) messages to \(isRead)"))
    }

    public func createDraft(accountID: MailAccountID, identityID: MailIdentityID, to: [MailAddress], subject: String, body: String, runID: String? = nil, sessionID: String? = nil) async throws -> MailDraft {
        let draft = MailDraft(id: MailDraftID(rawValue: UUID().uuidString), accountID: accountID, identityID: identityID, to: to, subject: subject, body: body)
        await draftStore.save(draft)
        try await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, accountID: accountID, draftID: draft.id, kind: .draftCreated, riskClass: .mutation, redactedSummary: "Created mail draft to \(to.map(\.email).joined(separator: ", "))"))
        return draft
    }

    public func sendApprovalPayload(draftID: MailDraftID) async throws -> MailRuntimeSendApproval {
        guard let draft = await draftStore.draft(id: draftID) else { throw MailRuntimeError.draftNotFound(draftID.rawValue) }
        let account = try await repository.account(id: draft.accountID)
        let from = account?.identities.first { $0.id == draft.identityID }?.address.email ?? "unknown"
        return MailRuntimeSendApproval(draft: draft, from: from)
    }

    public func sendDraft(draftID: MailDraftID, approved: Bool, runID: String? = nil, sessionID: String? = nil) async throws -> MailSendReceipt {
        guard let draft = await draftStore.draft(id: draftID) else { throw MailRuntimeError.draftNotFound(draftID.rawValue) }
        guard approved else {
            try await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, accountID: draft.accountID, draftID: draftID, kind: .sendApprovalRequested, riskClass: .send, redactedSummary: "Send approval required"))
            throw MailRuntimeError.approvalRequired(draftID.rawValue)
        }
        let receipt = MailSendReceipt(draftID: draftID, providerMessageID: "fixture-sent-\(draftID.rawValue)", envelopeHash: String(abs(draft.subject.hashValue)))
        try await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, accountID: draft.accountID, draftID: draftID, kind: .messageSent, riskClass: .send, redactedSummary: "Sent approved draft to \(draft.to.map(\.email).joined(separator: ", "))", payloadHash: receipt.envelopeHash))
        return receipt
    }

    public func evidenceCandidate(for messageID: MailMessageID) async throws -> MailEvidenceCandidate {
        let detail = try await getMessage(id: messageID, includeBody: false)
        let candidate = MailEvidenceCandidate(accountID: detail.summary.accountID, mailboxID: detail.summary.mailboxID, messageID: messageID, evidenceKind: "mail-message", redactedSummary: detail.summary.subject, sourceHash: detail.headers.rawHeaderHash)
        try await auditLog.record(MailAuditRecord(accountID: detail.summary.accountID, messageID: messageID, kind: .evidenceCandidateCreated, riskClass: .read, redactedSummary: candidate.redactedSummary, payloadHash: candidate.sourceHash))
        return candidate
    }
}

public protocol MailProtocolAdapter: Sendable {
    var protocolKind: MailProtocolKind { get }
    func testConnection(endpoint: MailServerEndpoint) async throws -> MailAccountHealth
}

public struct MailIMAPAdapter: MailProtocolAdapter {
    public var protocolKind: MailProtocolKind { .imap }
    public init() {}
    public func testConnection(endpoint: MailServerEndpoint) async throws -> MailAccountHealth {
        MailAccountHealth(status: endpoint.protocolKind == .imap ? .ready : .blocked, summary: "IMAP adapter skeleton validated endpoint \(endpoint.host):\(endpoint.port)", blockingReasons: endpoint.protocolKind == .imap ? [] : ["Endpoint protocol is not IMAP"])
    }
}

public struct MailSMTPAdapter: MailProtocolAdapter {
    public var protocolKind: MailProtocolKind { .smtp }
    public init() {}
    public func testConnection(endpoint: MailServerEndpoint) async throws -> MailAccountHealth {
        MailAccountHealth(status: endpoint.protocolKind == .smtp ? .ready : .blocked, summary: "SMTP adapter skeleton validated endpoint \(endpoint.host):\(endpoint.port)", blockingReasons: endpoint.protocolKind == .smtp ? [] : ["Endpoint protocol is not SMTP"])
    }
}

public struct MailJMAPAdapter: MailProtocolAdapter {
    public var protocolKind: MailProtocolKind { .jmap }
    public init() {}
    public func testConnection(endpoint: MailServerEndpoint) async throws -> MailAccountHealth { MailAccountHealth(status: .degraded, summary: "JMAP reserved adapter skeleton for \(endpoint.host)") }
}

public struct MailGmailAPIAdapter: MailProtocolAdapter {
    public var protocolKind: MailProtocolKind { .gmailAPI }
    public init() {}
    public func testConnection(endpoint: MailServerEndpoint) async throws -> MailAccountHealth { MailAccountHealth(status: .degraded, summary: "Gmail API reserved adapter skeleton for \(endpoint.host)") }
}

public struct MailMicrosoftGraphAdapter: MailProtocolAdapter {
    public var protocolKind: MailProtocolKind { .microsoftGraph }
    public init() {}
    public func testConnection(endpoint: MailServerEndpoint) async throws -> MailAccountHealth { MailAccountHealth(status: .degraded, summary: "Microsoft Graph reserved adapter skeleton for \(endpoint.host)") }
}

public struct MailMIMEParser: Sendable, Equatable {
    public init() {}

    public func parsePlainMessage(raw: String, messageID: MailMessageID, summary: MailMessageSummary, maxBodyCharacters: Int = 16_000) -> MailMessageDetail {
        let parts = raw.components(separatedBy: "\n\n")
        let bodyText = parts.dropFirst().joined(separator: "\n\n")
        let truncated = bodyText.count > maxBodyCharacters
        let clipped = String(bodyText.prefix(maxBodyCharacters))
        let body = MailMessageBody(plainText: MailBodyPart(mimeType: "text/plain", text: clipped, byteCount: bodyText.utf8.count, wasTruncated: truncated), redactedPreview: String(clipped.prefix(500)), omittedReason: truncated ? "body-truncated" : nil, bodyHash: String(abs(bodyText.hashValue)))
        return MailMessageDetail(summary: summary, headers: MailMessageHeaders(messageIDHeader: messageID.rawValue, rawHeaderHash: String(abs(raw.hashValue))), body: body)
    }
}

public struct MailSyncEngine: Sendable, Equatable {
    public init() {}
    public func readiness(account: MailAccount, mailboxCount: Int, cursorCount: Int) -> MailAccountHealth {
        let blockers = [account.credentialBinding == nil ? "Missing credential binding" : nil, mailboxCount == 0 ? "No mailboxes discovered" : nil].compactMap { $0 }
        return MailAccountHealth(status: blockers.isEmpty ? .ready : .blocked, summary: "\(mailboxCount) mailboxes · \(cursorCount) cursors", blockingReasons: blockers)
    }
}

public struct MailAttachmentImportService: Sendable, Equatable {
    public init() {}
    public func importDescriptor(_ descriptor: MailAttachmentDescriptor, sessionID: String) -> String {
        "session://\(sessionID)/mail-attachments/\(descriptor.id.rawValue)/\(descriptor.filename)"
    }
}

public struct ContactRuntime: Sendable {
    public private(set) var contacts: [ContactRecord]

    public init(contacts: [ContactRecord] = []) {
        self.contacts = contacts
    }

    public func search(query: String) -> [ContactRecord] {
        let normalized = query.lowercased()
        return contacts.filter { contact in
            contact.givenName.lowercased().contains(normalized)
                || contact.familyName.lowercased().contains(normalized)
                || contact.emails.contains { $0.email.lowercased().contains(normalized) }
        }
    }

    public func extractCandidates(from message: MailMessageDetail) -> [ContactCandidate] {
        let addresses = [message.summary.from] + message.summary.to + message.summary.cc
        return addresses.map { address in
            ContactCandidate(candidate: ContactRecord(id: MailContactID(rawValue: address.email.lowercased()), givenName: address.name ?? address.email, emails: [ContactEmailAddress(email: address.email)], source: "mail-header"), source: .mailHeader, relatedMessageID: message.id, confidence: 0.85)
        }
    }
}

public struct NativeMailReadiness: Codable, Sendable, Equatable {
    public var accountCount: Int
    public var healthyAccountCount: Int
    public var credentialBoundaryReady: Bool
    public var syncCursorReady: Bool
    public var toolAuditReady: Bool
    public var sendApprovalReady: Bool
    public var contactApprovalReady: Bool
    public var attachmentImportReady: Bool
    public var evidencePolicyReady: Bool

    public var isReady: Bool {
        accountCount > 0 && healthyAccountCount > 0 && credentialBoundaryReady && syncCursorReady && toolAuditReady && sendApprovalReady && contactApprovalReady && attachmentImportReady && evidencePolicyReady
    }

    public init(accountCount: Int, healthyAccountCount: Int, credentialBoundaryReady: Bool, syncCursorReady: Bool, toolAuditReady: Bool, sendApprovalReady: Bool, contactApprovalReady: Bool, attachmentImportReady: Bool, evidencePolicyReady: Bool) {
        self.accountCount = accountCount
        self.healthyAccountCount = healthyAccountCount
        self.credentialBoundaryReady = credentialBoundaryReady
        self.syncCursorReady = syncCursorReady
        self.toolAuditReady = toolAuditReady
        self.sendApprovalReady = sendApprovalReady
        self.contactApprovalReady = contactApprovalReady
        self.attachmentImportReady = attachmentImportReady
        self.evidencePolicyReady = evidencePolicyReady
    }
}
