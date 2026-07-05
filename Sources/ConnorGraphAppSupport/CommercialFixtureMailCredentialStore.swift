import Foundation
import ConnorGraphCore

public final class CommercialFixtureMailCredentialStore: CredentialStore, @unchecked Sendable {
    private let secret: String
    private let binding: MailCredentialBinding

    public init(secret: String, binding: MailCredentialBinding) {
        self.secret = secret
        self.binding = binding
    }

    public func saveSecret(_ secret: String, service: String, account: String) throws {}

    public func readSecret(service: String, account: String) throws -> String? {
        service == binding.credentialNamespace && account == binding.accountName ? secret : nil
    }

    public func deleteSecret(service: String, account: String) throws {}
}
