import Foundation
import Contacts
import ConnorGraphCore

public struct ContactsSystemContactSnapshot: Sendable, Equatable {
    public var identifier: String
    public var givenName: String
    public var familyName: String
    public var organizationName: String?
    public var emails: [String]

    public init(identifier: String, givenName: String, familyName: String, organizationName: String? = nil, emails: [String] = []) {
        self.identifier = identifier
        self.givenName = givenName
        self.familyName = familyName
        self.organizationName = organizationName
        self.emails = emails
    }
}

public struct ContactsSystemAdapter: Sendable {
    public init() {}

    public static func map(snapshot: ContactsSystemContactSnapshot) -> ContactRecord {
        ContactRecord(
            id: MailContactID(rawValue: snapshot.identifier),
            givenName: snapshot.givenName,
            familyName: snapshot.familyName,
            organizationName: snapshot.organizationName,
            emails: snapshot.emails.map { ContactEmailAddress(email: $0) },
            source: "system-contacts"
        )
    }

    public static func snapshot(contact: CNContact) -> ContactsSystemContactSnapshot {
        ContactsSystemContactSnapshot(
            identifier: contact.identifier,
            givenName: contact.givenName,
            familyName: contact.familyName,
            organizationName: contact.organizationName.isEmpty ? nil : contact.organizationName,
            emails: contact.emailAddresses.map { String($0.value) }
        )
    }
}
