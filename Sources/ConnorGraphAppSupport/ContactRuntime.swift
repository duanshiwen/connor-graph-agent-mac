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

    public func extractCandidates(from message: MailMessageDetail) -> [ContactCandidate] {
        let addresses = [message.summary.from] + message.summary.to + message.summary.cc
        return addresses.map { address in
            ContactCandidate(candidate: ContactRecord(id: MailContactID(rawValue: address.email.lowercased()), givenName: address.name ?? address.email, emails: [ContactEmailAddress(email: address.email)], source: "mail-header"), source: .mailHeader, relatedMessageID: message.id, confidence: 0.85)
        }
    }
}
