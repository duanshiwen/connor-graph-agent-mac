import Foundation

public struct MailContactID: RawRepresentable, Codable, Sendable, Equatable, Hashable, Identifiable {
    public var rawValue: String
    public var id: String { rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct ContactEmailAddress: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { email.lowercased() }
    public var label: String?
    public var email: String

    public init(label: String? = nil, email: String) {
        self.label = label
        self.email = email
    }
}

public struct ContactRecord: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: MailContactID
    public var givenName: String
    public var familyName: String
    public var organizationName: String?
    public var emails: [ContactEmailAddress]
    public var source: String

    public init(id: MailContactID, givenName: String, familyName: String = "", organizationName: String? = nil, emails: [ContactEmailAddress], source: String = "connor-cache") {
        self.id = id
        self.givenName = givenName
        self.familyName = familyName
        self.organizationName = organizationName
        self.emails = emails
        self.source = source
    }
}

public enum ContactCandidateSource: String, Codable, Sendable, Equatable, Hashable {
    case mailHeader
    case mailBody
    case userDraft
}

public struct ContactCandidate: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var candidate: ContactRecord
    public var source: ContactCandidateSource
    public var relatedMessageID: MailMessageID?
    public var confidence: Double
    public var createdAt: Date

    public init(id: String = UUID().uuidString, candidate: ContactRecord, source: ContactCandidateSource, relatedMessageID: MailMessageID? = nil, confidence: Double, createdAt: Date = Date()) {
        self.id = id
        self.candidate = candidate
        self.source = source
        self.relatedMessageID = relatedMessageID
        self.confidence = confidence
        self.createdAt = createdAt
    }
}

public enum ContactMutationDraftStatus: String, Codable, Sendable, Equatable, Hashable {
    case draft
    case pendingApproval
    case committed
    case discarded
}

public struct ContactMutationDraft: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var record: ContactRecord
    public var status: ContactMutationDraftStatus
    public var approvalRequired: Bool
    public var createdAt: Date

    public init(id: String = UUID().uuidString, record: ContactRecord, status: ContactMutationDraftStatus = .draft, approvalRequired: Bool = true, createdAt: Date = Date()) {
        self.id = id
        self.record = record
        self.status = status
        self.approvalRequired = approvalRequired
        self.createdAt = createdAt
    }
}
