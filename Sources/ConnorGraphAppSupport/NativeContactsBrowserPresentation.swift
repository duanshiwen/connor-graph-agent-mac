import Foundation
import ConnorGraphCore

public struct NativeContactsBrowserPresentation: Sendable, Equatable {
    public var query: String
    public var rows: [NativeContactRowPresentation]
    public var emptyMessage: String?

    public static let empty = NativeContactsBrowserPresentation(query: "", rows: [], emptyMessage: "暂无联系人")

    public init(query: String, rows: [NativeContactRowPresentation], emptyMessage: String? = nil) {
        self.query = query
        self.rows = rows
        self.emptyMessage = emptyMessage
    }

    public static func build(records: [ContactRecord], query: String = "") -> NativeContactsBrowserPresentation {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = normalized.isEmpty ? records : records.filter { record in
            record.givenName.lowercased().contains(normalized)
            || record.familyName.lowercased().contains(normalized)
            || (record.organizationName?.lowercased().contains(normalized) ?? false)
            || record.emails.contains { $0.email.lowercased().contains(normalized) }
        }
        let rows = filtered
            .sorted { $0.displayName < $1.displayName }
            .map(NativeContactRowPresentation.init(record:))
        return NativeContactsBrowserPresentation(query: query, rows: rows, emptyMessage: rows.isEmpty ? "没有匹配的联系人" : nil)
    }

    /// 从联系人列表构建
    public static func build(contacts: [MailContact], query: String = "") -> NativeContactsBrowserPresentation {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = normalized.isEmpty ? contacts : contacts.filter { contact in
            contact.email.lowercased().contains(normalized)
            || (contact.displayName?.lowercased().contains(normalized) ?? false)
        }
        let rows = filtered
            .sorted { $0.frequency > $1.frequency }
            .map(NativeContactRowPresentation.init(contact:))
        return NativeContactsBrowserPresentation(query: query, rows: rows, emptyMessage: rows.isEmpty ? "没有匹配的联系人" : nil)
    }

    public static func build(profiles: [PersonProfile], query: String = "") -> NativeContactsBrowserPresentation {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let activeProfiles = profiles.filter(\.isActiveForDefaultContext)
        let filtered = normalized.isEmpty ? activeProfiles : activeProfiles.filter { profile in
            profile.matchesContactQuery(normalized)
        }
        let rows = filtered
            .sorted { left, right in
                left.displayName.localizedStandardCompare(right.displayName) == .orderedAscending
            }
            .map(NativeContactRowPresentation.init(profile:))
        let emptyMessage: String?
        if rows.isEmpty {
            emptyMessage = normalized.isEmpty ? "暂无联系人" : "没有匹配的联系人"
        } else {
            emptyMessage = nil
        }
        return NativeContactsBrowserPresentation(query: query, rows: rows, emptyMessage: emptyMessage)
    }
}

public struct NativeContactRowPresentation: Sendable, Equatable, Identifiable {
    public var id: ContactID
    public var displayName: String
    public var primaryEmail: String?
    public var organizationName: String?
    public var subtitle: String
    public var status: PersonProfileStatus?
    public var accessibilityLabel: String

    public init(id: ContactID, displayName: String, primaryEmail: String? = nil, organizationName: String? = nil, subtitle: String? = nil, status: PersonProfileStatus? = nil) {
        self.id = id
        self.displayName = displayName
        self.primaryEmail = primaryEmail
        self.organizationName = organizationName
        self.subtitle = subtitle ?? primaryEmail ?? organizationName ?? "暂无联系方式"
        self.status = status
        self.accessibilityLabel = "查看人物档案，\(displayName)，\(self.subtitle)"
    }

    public init(record: ContactRecord) {
        self.init(
            id: record.id,
            displayName: record.displayName,
            primaryEmail: record.emails.first?.email,
            organizationName: record.organizationName
        )
    }

    public init(contact: MailContact) {
        self.init(
            id: contact.id,
            displayName: contact.displayName ?? contact.email,
            primaryEmail: contact.email,
            organizationName: nil
        )
    }

    public init(profile: PersonProfile) {
        self.init(
            id: profile.id,
            displayName: profile.displayName,
            primaryEmail: profile.emails.first?.email,
            organizationName: profile.organizationName,
            subtitle: profile.contactSubtitle,
            status: profile.status
        )
    }
}

private extension PersonProfile {
    func matchesContactQuery(_ normalized: String) -> Bool {
        guard !normalized.isEmpty else { return true }
        let values = [
            displayName,
            givenName,
            familyName,
            gender ?? "",
            organizationName ?? "",
            jobTitle ?? "",
            notes ?? "",
            aliases.joined(separator: " "),
            emails.map(\.email).joined(separator: " "),
            phones.map(\.number).joined(separator: " "),
            addresses.map(\.value).joined(separator: " ")
        ]
        return values.contains { $0.lowercased().contains(normalized) }
    }
}

public extension ContactRecord {
    var displayName: String {
        let combined = [givenName, familyName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return combined.isEmpty ? (emails.first?.email ?? id.rawValue) : combined
    }
}
