import Foundation
import ConnorGraphCore

public struct ContactRuntime: Sendable {
    public private(set) var contacts: [ContactRecord]

    public init(contacts: [ContactRecord] = []) {
        self.contacts = contacts
    }

    public func search(query: String) -> [ContactRecord] {
        let normalized = query.lowercased()
        return contacts.filter { contact in
            contact.givenName.lowercased().contains(normalized)
                || contact.familyName.lowercased().contains(normalized)
                || contact.emails.contains { $0.email.lowercased().contains(normalized) }
        }
    }

}
