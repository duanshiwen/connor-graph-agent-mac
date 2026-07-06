import Foundation

public enum PersonProfileStatus: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case active
    case pending
    case merged
    case deleted
}

public struct PersonPhoneNumber: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var label: String?
    public var number: String

    public init(id: String = UUID().uuidString, label: String? = nil, number: String) {
        self.id = id
        self.label = label
        self.number = number
    }
}

public struct PersonPostalAddress: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var label: String?
    public var value: String

    public init(id: String = UUID().uuidString, label: String? = nil, value: String) {
        self.id = id
        self.label = label
        self.value = value
    }
}

public struct PersonProfile: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: ContactID
    public var displayName: String
    public var aliases: [String]
    public var givenName: String
    public var familyName: String
    public var gender: String?
    public var emails: [ContactEmailAddress]
    public var phones: [PersonPhoneNumber]
    public var addresses: [PersonPostalAddress]
    public var organizationName: String?
    public var jobTitle: String?
    public var notes: String?
    public var status: PersonProfileStatus
    public var mergedIntoID: ContactID?
    public var memoryEntityID: String?
    public var memoryStableKey: String?
    public var source: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: ContactID = ContactID(rawValue: "person-\(UUID().uuidString)"),
        displayName: String,
        aliases: [String] = [],
        givenName: String = "",
        familyName: String = "",
        gender: String? = nil,
        emails: [ContactEmailAddress] = [],
        phones: [PersonPhoneNumber] = [],
        addresses: [PersonPostalAddress] = [],
        organizationName: String? = nil,
        jobTitle: String? = nil,
        notes: String? = nil,
        status: PersonProfileStatus = .active,
        mergedIntoID: ContactID? = nil,
        memoryEntityID: String? = nil,
        memoryStableKey: String? = nil,
        source: String = "person-registry",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.aliases = aliases
        self.givenName = givenName
        self.familyName = familyName
        self.gender = gender
        self.emails = emails
        self.phones = phones
        self.addresses = addresses
        self.organizationName = organizationName
        self.jobTitle = jobTitle
        self.notes = notes
        self.status = status
        self.mergedIntoID = mergedIntoID
        self.memoryEntityID = memoryEntityID
        self.memoryStableKey = memoryStableKey
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public extension PersonProfile {
    init(contactRecord: ContactRecord, now: Date = Date()) {
        let displayName = [contactRecord.givenName, contactRecord.familyName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        self.init(
            id: contactRecord.id,
            displayName: displayName.isEmpty ? contactRecord.emails.first?.email ?? contactRecord.id.rawValue : displayName,
            givenName: contactRecord.givenName,
            familyName: contactRecord.familyName,
            emails: contactRecord.emails,
            organizationName: contactRecord.organizationName,
            source: contactRecord.source,
            createdAt: now,
            updatedAt: now
        )
    }

    var contactRecord: ContactRecord {
        ContactRecord(
            id: id,
            givenName: givenName.isEmpty ? displayName : givenName,
            familyName: familyName,
            organizationName: organizationName,
            emails: emails,
            source: source
        )
    }

    var isActiveForDefaultContext: Bool {
        status == .active || status == .pending
    }

    var contactSubtitle: String {
        if let email = emails.first?.email.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            return email
        }

        let job = jobTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let organization = organizationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !job.isEmpty && !organization.isEmpty { return "\(job) · \(organization)" }
        if !job.isEmpty { return job }
        if !organization.isEmpty { return organization }

        if let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            return notes
        }

        return "暂无联系方式"
    }
}

public struct PersonProfileDraft: Codable, Sendable, Equatable, Hashable {
    public var id: ContactID?
    public var displayName: String
    public var aliases: [String]
    public var givenName: String
    public var familyName: String
    public var gender: String?
    public var emails: [ContactEmailAddress]
    public var phones: [PersonPhoneNumber]
    public var addresses: [PersonPostalAddress]
    public var organizationName: String?
    public var jobTitle: String?
    public var notes: String?
    public var status: PersonProfileStatus

    public init(
        id: ContactID? = nil,
        displayName: String,
        aliases: [String] = [],
        givenName: String = "",
        familyName: String = "",
        gender: String? = nil,
        emails: [ContactEmailAddress] = [],
        phones: [PersonPhoneNumber] = [],
        addresses: [PersonPostalAddress] = [],
        organizationName: String? = nil,
        jobTitle: String? = nil,
        notes: String? = nil,
        status: PersonProfileStatus = .active
    ) {
        self.id = id
        self.displayName = displayName
        self.aliases = aliases
        self.givenName = givenName
        self.familyName = familyName
        self.gender = gender
        self.emails = emails
        self.phones = phones
        self.addresses = addresses
        self.organizationName = organizationName
        self.jobTitle = jobTitle
        self.notes = notes
        self.status = status
    }
}
