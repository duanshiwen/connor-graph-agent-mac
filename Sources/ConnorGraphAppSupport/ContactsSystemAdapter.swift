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

public enum ContactsSystemAdapterError: LocalizedError, Sendable, Equatable {
    case accessDenied

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "未获得通讯录访问权限。请在系统设置中允许康纳同学访问联系人。"
        }
    }
}

public struct ContactsSystemAdapter: Sendable {
    public init() {}

    public static func fetchSystemContacts() async throws -> [ContactRecord] {
        let store = CNContactStore()
        let granted = try await requestContactsAccess(store: store)
        guard granted else { throw ContactsSystemAdapterError.accessDenied }

        return try await Task.detached(priority: .userInitiated) {
            let keys: [CNKeyDescriptor] = [
                CNContactIdentifierKey as CNKeyDescriptor,
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactEmailAddressesKey as CNKeyDescriptor
            ]
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.sortOrder = .userDefault
            var records: [ContactRecord] = []
            try store.enumerateContacts(with: request) { contact, _ in
                let record = map(snapshot: snapshot(contact: contact))
                let hasName = !record.givenName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !record.familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !(record.organizationName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                if hasName || !record.emails.isEmpty {
                    records.append(record)
                }
            }
            return records
        }.value
    }

    public static func requestContactsAccess(store: CNContactStore) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            store.requestAccess(for: .contacts) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

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
