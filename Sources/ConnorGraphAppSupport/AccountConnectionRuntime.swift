import Foundation
import ConnorGraphCore

public struct AccountConnectionRuntime: Sendable {
    public init() {}

    public func makeAccount(
        provider: ConnectedAccountProviderKind,
        displayName: String,
        primaryIdentifier: String,
        credentialBinding: ConnectedAccountCredentialBinding? = nil,
        now: Date = Date()
    ) -> ConnectedAccount {
        let slug = Self.slug(for: primaryIdentifier)
        return ConnectedAccount(
            id: ConnectedAccountID(rawValue: "connected-\(slug)"),
            provider: provider,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? primaryIdentifier : displayName,
            primaryIdentifier: primaryIdentifier,
            credentialBinding: credentialBinding,
            capabilities: provider.defaultCapabilities.map { ConnectedAccountCapability(kind: $0, status: .enabled) },
            createdAt: now,
            updatedAt: now
        )
    }

    public static func slug(for identifier: String) -> String {
        let allowed = CharacterSet.alphanumerics
        return identifier.lowercased().unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(Character(scalar)) : "-"
        }.joined().split(separator: "-").joined(separator: "-")
    }
}
