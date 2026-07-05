import Foundation
import ConnorGraphCore

public struct AppCalendarCredentialStore: Sendable {
    public static let credentialNamespace = "ConnorGraphAgent.CalendarCredentials"

    public var credentialStore: CredentialStore

    public init(credentialStore: CredentialStore = LocalEncryptedCredentialStore()) {
        self.credentialStore = credentialStore
    }

    public func saveCredential(_ secret: String, binding: CalendarCredentialBinding) throws {
        try credentialStore.saveSecret(secret, service: binding.credentialNamespace, account: binding.accountName)
    }

    public func readCredential(binding: CalendarCredentialBinding) throws -> String? {
        try credentialStore.readSecret(service: binding.credentialNamespace, account: binding.accountName)
    }

    public func deleteCredential(binding: CalendarCredentialBinding) throws {
        try credentialStore.deleteSecret(service: binding.credentialNamespace, account: binding.accountName)
    }

    public static func binding(accountID: CalendarAccountID, username: String, authMode: CalendarSourceAuthMode) -> CalendarCredentialBinding {
        CalendarCredentialBinding(
            credentialNamespace: credentialNamespace,
            accountName: "\(accountID.rawValue):\(username.lowercased())",
            authMode: authMode
        )
    }
}
