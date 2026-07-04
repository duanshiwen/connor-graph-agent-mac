import Foundation
import ConnorGraphCore

public struct AppMailCredentialStore: Sendable {
    public static let credentialNamespace = "ConnorGraphAgent.MailCredentials"

    public var credentialStore: CredentialStore

    public init(credentialStore: CredentialStore = LocalEncryptedCredentialStore()) {
        self.credentialStore = credentialStore
    }

    public func saveCredential(_ secret: String, binding: MailCredentialBinding) throws {
        try credentialStore.saveSecret(secret, service: binding.credentialNamespace, account: binding.accountName)
    }

    public func readCredential(binding: MailCredentialBinding) throws -> String? {
        try credentialStore.readSecret(service: binding.credentialNamespace, account: binding.accountName)
    }

    public func deleteCredential(binding: MailCredentialBinding) throws {
        try credentialStore.deleteSecret(service: binding.credentialNamespace, account: binding.accountName)
    }

    public static func binding(accountID: MailAccountID, email: String, authMode: MailAuthMode) -> MailCredentialBinding {
        MailCredentialBinding(
            credentialNamespace: credentialNamespace,
            accountName: "\(accountID.rawValue):\(email.lowercased())",
            authMode: authMode
        )
    }
}
