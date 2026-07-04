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
        let addresses = ([message.summary.from] + message.summary.to + message.summary.cc)
            .filter { !$0.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var seen = Set<String>()
        return addresses.compactMap { address in
            let email = address.email.lowercased()
            guard seen.insert(email).inserted else { return nil }
            let display = (address.name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? email
            let parts = display.split(separator: " ", maxSplits: 1).map(String.init)
            let record = ContactRecord(
                id: ContactID(rawValue: "mail-\(email)"),
                givenName: parts.first ?? display,
                familyName: parts.dropFirst().first ?? "",
                emails: [ContactEmailAddress(label: "mail", email: email)],
                source: "mail-header"
            )
            return ContactCandidate(candidate: record, source: .mailHeader, confidence: 0.86)
        }
    }

}
