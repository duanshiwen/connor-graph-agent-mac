import Foundation

public enum MailAuditEventKind: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case accountCreated
    case accountHealthChecked
    case syncStarted
    case syncFinished
    case messageSearched
    case messageRead
    case messageBodyRead
    case stateMutated
    case draftCreated
    case draftUpdated
    case sendApprovalRequested
    case messageSent
    case attachmentImported
    case contactRead
    case contactCandidateExtracted
    case contactMutationApprovalRequested
    case evidenceCandidateCreated
    case policyBlocked
}

public struct MailAuditRecord: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var runID: String?
    public var sessionID: String?
    public var accountID: MailAccountID?
    public var messageID: MailMessageID?
    public var draftID: MailDraftID?
    public var kind: MailAuditEventKind
    public var riskClass: MailToolRiskClass
    public var redactedSummary: String
    public var payloadHash: String?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        runID: String? = nil,
        sessionID: String? = nil,
        accountID: MailAccountID? = nil,
        messageID: MailMessageID? = nil,
        draftID: MailDraftID? = nil,
        kind: MailAuditEventKind,
        riskClass: MailToolRiskClass,
        redactedSummary: String,
        payloadHash: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.runID = runID
        self.sessionID = sessionID
        self.accountID = accountID
        self.messageID = messageID
        self.draftID = draftID
        self.kind = kind
        self.riskClass = riskClass
        self.redactedSummary = redactedSummary
        self.payloadHash = payloadHash
        self.createdAt = createdAt
    }
}
