import Foundation
import ConnorGraphCore

public struct MailRuntimeSearchRequest: Sendable, Equatable {
    public var query: String
    public var accountID: MailAccountID?
    public var limit: Int
    public var startDate: Date?
    public var endDate: Date?
    public var timePreset: NativeSearchTimePreset?
    public var timeSort: NativeSearchTemporalSort

    public init(query: String, accountID: MailAccountID? = nil, limit: Int = 20, startDate: Date? = nil, endDate: Date? = nil, timePreset: NativeSearchTimePreset? = nil, timeSort: NativeSearchTemporalSort = .relevanceThenTimeDesc) {
        self.query = query
        self.accountID = accountID
        self.limit = NativeSearchLimitPolicy.clampSearchLimit(limit)
        self.startDate = startDate
        self.endDate = endDate
        self.timePreset = timePreset
        self.timeSort = timeSort
    }

    public var temporalFilter: NativeSearchTemporalFilter? {
        if let timePreset {
            var filter = NativeSearchTimePresetResolver.resolve(timePreset)
            filter.timeFieldPreference = [.sentAt, .receivedAt]
            return filter
        }
        return .sourceDefault(start: startDate, end: endDate, sourceKind: .mail)
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
        let messages: [MailMessageSummary]
        if let timeAwareCache = cache as? any TimeAwareMailSourceCache {
            messages = try await timeAwareCache.searchMessages(query: request.query, accountID: request.accountID, temporalFilter: request.temporalFilter, temporalSort: request.timeSort, limit: request.limit)
        } else {
            let all = try await cache.searchMessages(query: request.query, accountID: request.accountID)
            let filtered = request.temporalFilter.map { filter in all.filter { summary in
                filter.contains(NativeSearchTemporalMetadata(primaryTime: summary.date, primaryTimeKind: .sentAt, sentAt: summary.date), sourceKind: .mail)
            } } ?? all
            messages = filtered.sorted { lhs, rhs in request.timeSort == .timeAscThenRelevance || request.timeSort == .relevanceThenTimeAsc ? lhs.date < rhs.date : lhs.date > rhs.date }
        }
        let limit = NativeSearchLimitPolicy.clampSearchLimit(request.limit)
        try await auditLog.record(MailAuditRecord(runID: runID, sessionID: sessionID, accountID: request.accountID, kind: .messageSearched, riskClass: .read, redactedSummary: "Searched mail messages; returned \(min(messages.count, limit)) summaries"))
        return Array(messages.prefix(limit))
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
