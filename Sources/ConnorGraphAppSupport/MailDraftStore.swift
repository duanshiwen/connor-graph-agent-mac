import Foundation
import ConnorGraphCore

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
