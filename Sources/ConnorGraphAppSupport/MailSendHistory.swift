import Foundation
import ConnorGraphCore

public struct MailSendHistory: Codable, Sendable, Equatable {
    public var draft: MailDraft
    public var attempts: [MailSendAttempt]
    public var auditRecords: [MailAuditRecord]

    public init(draft: MailDraft, attempts: [MailSendAttempt], auditRecords: [MailAuditRecord]) {
        self.draft = draft
        self.attempts = attempts
        self.auditRecords = auditRecords
    }

    public var latestAttempt: MailSendAttempt? { attempts.last }
    public var latestSentAttempt: MailSendAttempt? { attempts.last { $0.status == .sent } }
    public var providerMessageID: String? { draft.sentReceiptID ?? latestSentAttempt?.providerMessageID }
    public var envelopeHash: String? { latestSentAttempt?.envelopeHash ?? attempts.last?.envelopeHash }
    public var isTerminal: Bool { draft.status == .sent || draft.status == .failed || draft.status == .discarded }
}
