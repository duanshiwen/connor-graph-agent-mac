import Foundation
import ConnorGraphCore

public struct AppMailCredentialStore: Sendable {
    public static let keychainService = "ConnorGraphAgent.MailCredentials"

    public var credentialStore: CredentialStore

    public init(credentialStore: CredentialStore = LocalEncryptedCredentialStore()) {
        self.credentialStore = credentialStore
    }

    public func saveCredential(_ secret: String, binding: MailCredentialBinding) throws {
        try credentialStore.saveSecret(secret, service: binding.keychainService, account: binding.accountName)
    }

    public func readCredential(binding: MailCredentialBinding) throws -> String? {
        try credentialStore.readSecret(service: binding.keychainService, account: binding.accountName)
    }

    public func deleteCredential(binding: MailCredentialBinding) throws {
        try credentialStore.deleteSecret(service: binding.keychainService, account: binding.accountName)
    }

    public static func binding(accountID: MailAccountID, email: String, authMode: MailAuthMode) -> MailCredentialBinding {
        MailCredentialBinding(
            keychainService: keychainService,
            accountName: "\(accountID.rawValue):\(email.lowercased())",
            authMode: authMode
        )
    }
}
