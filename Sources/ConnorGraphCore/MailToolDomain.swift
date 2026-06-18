import Foundation

public struct MailMessageHeaders: Codable, Sendable, Equatable, Hashable {
    public var messageIDHeader: String?
    public var inReplyTo: String?
    public var references: [String]
    public var rawHeaderHash: String?

    public init(messageIDHeader: String? = nil, inReplyTo: String? = nil, references: [String] = [], rawHeaderHash: String? = nil) {
        self.messageIDHeader = messageIDHeader
        self.inReplyTo = inReplyTo
        self.references = references
        self.rawHeaderHash = rawHeaderHash
    }
}

public struct MailAttachmentDescriptor: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: MailAttachmentID
    public var messageID: MailMessageID
    public var filename: String
    public var mimeType: String
    public var byteCount: Int
    public var contentID: String?
    public var isInline: Bool
    public var contentHash: String?

    public init(
        id: MailAttachmentID,
        messageID: MailMessageID,
        filename: String,
        mimeType: String,
        byteCount: Int,
        contentID: String? = nil,
        isInline: Bool = false,
        contentHash: String? = nil
    ) {
        self.id = id
        self.messageID = messageID
        self.filename = filename
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.contentID = contentID
        self.isInline = isInline
        self.contentHash = contentHash
    }
}

public struct MailMessageSummary: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: MailMessageID
    public var accountID: MailAccountID
    public var mailboxID: MailMailboxID
    public var threadID: MailThreadID?
    public var subject: String
    public var from: MailAddress
    public var to: [MailAddress]
    public var cc: [MailAddress]
    public var date: Date
    public var snippet: String
    public var flags: MailMessageFlags
    public var hasAttachments: Bool

    public init(
        id: MailMessageID,
        accountID: MailAccountID,
        mailboxID: MailMailboxID,
        threadID: MailThreadID? = nil,
        subject: String,
        from: MailAddress,
        to: [MailAddress],
        cc: [MailAddress] = [],
        date: Date = Date(),
        snippet: String,
        flags: MailMessageFlags = MailMessageFlags(),
        hasAttachments: Bool = false
    ) {
        self.id = id
        self.accountID = accountID
        self.mailboxID = mailboxID
        self.threadID = threadID
        self.subject = subject
        self.from = from
        self.to = to
        self.cc = cc
        self.date = date
        self.snippet = snippet
        self.flags = flags
        self.hasAttachments = hasAttachments
    }
}

public struct MailBodyPart: Codable, Sendable, Equatable, Hashable {
    public var mimeType: String
    public var text: String
    public var byteCount: Int
    public var wasTruncated: Bool

    public init(mimeType: String, text: String, byteCount: Int, wasTruncated: Bool = false) {
        self.mimeType = mimeType
        self.text = text
        self.byteCount = byteCount
        self.wasTruncated = wasTruncated
    }
}

public struct MailMessageBody: Codable, Sendable, Equatable, Hashable {
    public var plainText: MailBodyPart?
    public var htmlText: MailBodyPart?
    public var redactedPreview: String
    public var omittedReason: String?
    public var bodyHash: String?

    public init(plainText: MailBodyPart? = nil, htmlText: MailBodyPart? = nil, redactedPreview: String, omittedReason: String? = nil, bodyHash: String? = nil) {
        self.plainText = plainText
        self.htmlText = htmlText
        self.redactedPreview = redactedPreview
        self.omittedReason = omittedReason
        self.bodyHash = bodyHash
    }
}

public struct MailMessageDetail: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: MailMessageID
    public var summary: MailMessageSummary
    public var headers: MailMessageHeaders
    public var body: MailMessageBody?
    public var attachments: [MailAttachmentDescriptor]

    public init(summary: MailMessageSummary, headers: MailMessageHeaders = MailMessageHeaders(), body: MailMessageBody? = nil, attachments: [MailAttachmentDescriptor] = []) {
        self.id = summary.id
        self.summary = summary
        self.headers = headers
        self.body = body
        self.attachments = attachments
    }
}

public enum MailDraftStatus: String, Codable, Sendable, Equatable, Hashable {
    case draft
    case pendingApproval
    case sent
    case discarded
    case failed
}

public struct MailDraft: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: MailDraftID
    public var accountID: MailAccountID
    public var identityID: MailIdentityID
    public var to: [MailAddress]
    public var cc: [MailAddress]
    public var bcc: [MailAddress]
    public var subject: String
    public var body: String
    public var attachmentIDs: [MailAttachmentID]
    public var inReplyToMessageID: MailMessageID?
    public var status: MailDraftStatus
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: MailDraftID,
        accountID: MailAccountID,
        identityID: MailIdentityID,
        to: [MailAddress],
        cc: [MailAddress] = [],
        bcc: [MailAddress] = [],
        subject: String,
        body: String,
        attachmentIDs: [MailAttachmentID] = [],
        inReplyToMessageID: MailMessageID? = nil,
        status: MailDraftStatus = .draft,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.accountID = accountID
        self.identityID = identityID
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
        self.attachmentIDs = attachmentIDs
        self.inReplyToMessageID = inReplyToMessageID
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct MailSendRequest: Codable, Sendable, Equatable, Hashable {
    public var draftID: MailDraftID
    public var approvalRequired: Bool
    public var approvalPayloadJSON: String

    public init(draftID: MailDraftID, approvalRequired: Bool = true, approvalPayloadJSON: String) {
        self.draftID = draftID
        self.approvalRequired = approvalRequired
        self.approvalPayloadJSON = approvalPayloadJSON
    }
}

public struct MailSendReceipt: Codable, Sendable, Equatable, Hashable {
    public var draftID: MailDraftID
    public var providerMessageID: String
    public var sentAt: Date
    public var envelopeHash: String

    public init(draftID: MailDraftID, providerMessageID: String, sentAt: Date = Date(), envelopeHash: String) {
        self.draftID = draftID
        self.providerMessageID = providerMessageID
        self.sentAt = sentAt
        self.envelopeHash = envelopeHash
    }
}

public enum MailToolRiskClass: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case read
    case bodyRead
    case mutation
    case destructive
    case send
    case contactMutation
    case attachmentImport
}

public struct MailToolApprovalPayload: Codable, Sendable, Equatable, Hashable {
    public var title: String
    public var riskClass: MailToolRiskClass
    public var summary: String
    public var redactedPreview: String
    public var payloadJSON: String

    public init(title: String, riskClass: MailToolRiskClass, summary: String, redactedPreview: String, payloadJSON: String) {
        self.title = title
        self.riskClass = riskClass
        self.summary = summary
        self.redactedPreview = redactedPreview
        self.payloadJSON = payloadJSON
    }
}

public struct MailEvidenceCandidate: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var accountID: MailAccountID
    public var mailboxID: MailMailboxID?
    public var messageID: MailMessageID?
    public var evidenceKind: String
    public var redactedSummary: String
    public var sourceHash: String?
    public var noMemory: Bool
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        accountID: MailAccountID,
        mailboxID: MailMailboxID? = nil,
        messageID: MailMessageID? = nil,
        evidenceKind: String,
        redactedSummary: String,
        sourceHash: String? = nil,
        noMemory: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.accountID = accountID
        self.mailboxID = mailboxID
        self.messageID = messageID
        self.evidenceKind = evidenceKind
        self.redactedSummary = redactedSummary
        self.sourceHash = sourceHash
        self.noMemory = noMemory
        self.createdAt = createdAt
    }
}
