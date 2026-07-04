import Foundation

public struct ContactID: RawRepresentable, Codable, Sendable, Equatable, Hashable, Identifiable {
    public var rawValue: String
    public var id: String { rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
}

public typealias MailContactID = ContactID

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
    public var id: ContactID
    public var givenName: String
    public var familyName: String
    public var organizationName: String?
    public var emails: [ContactEmailAddress]
    public var source: String

    public init(id: ContactID, givenName: String, familyName: String = "", organizationName: String? = nil, emails: [ContactEmailAddress], source: String = "connor-cache") {
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
    public var confidence: Double
    public var createdAt: Date

    public init(id: String = UUID().uuidString, candidate: ContactRecord, source: ContactCandidateSource, confidence: Double, createdAt: Date = Date()) {
        self.id = id
        self.candidate = candidate
        self.source = source
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

// MARK: - Mail Contact (from mail header extraction)
public enum ContactSource: String, Codable, Sendable, Hashable {
    case mailHeader = "mail-header"
    case mailBody = "mail-body"
    case userDraft = "user-draft"
    case systemContacts = "system-contacts"
}

public struct MailContact: Codable, Sendable, Identifiable {
    public let id: ContactID
    public var email: String
    public var displayName: String?
    public var frequency: Int
    public var lastContactedAt: Date?
    public var firstSeenAt: Date
    public var lastSeenAt: Date
    public var sources: Set<ContactSource>

    public init(
        id: ContactID,
        email: String,
        displayName: String? = nil,
        frequency: Int = 1,
        lastContactedAt: Date? = nil,
        firstSeenAt: Date = Date(),
        lastSeenAt: Date = Date(),
        sources: Set<ContactSource> = [.mailHeader]
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.frequency = frequency
        self.lastContactedAt = lastContactedAt
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.sources = sources
    }
}
