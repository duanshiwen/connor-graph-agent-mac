import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Mail Preferences Store Tests")
struct MailPreferencesStoreTests {
    @Test func defaultPreferencesAreEmptyWhenFileDoesNotExist() async throws {
        let store = FileBackedMailPreferencesStore(preferencesURL: temporaryPreferencesURL())

        let preferences = try await store.load()

        #expect(preferences.defaultSendAccountID == nil)
        #expect(preferences.defaultSendIdentityID == nil)
    }

    @Test func savesAndLoadsDefaultSendAccountAndIdentity() async throws {
        let url = temporaryPreferencesURL()
        let store = FileBackedMailPreferencesStore(preferencesURL: url)
        let expected = MailPreferences(
            defaultSendAccountID: MailAccountID(rawValue: "shiwen@example.com"),
            defaultSendIdentityID: MailIdentityID(rawValue: "identity-shiwen@example.com")
        )

        try await store.save(expected)
        let loaded = try await FileBackedMailPreferencesStore(preferencesURL: url).load()

        #expect(loaded == expected)
    }

    @Test func reconcilerSetsSingleAccountAsDefaultWhenMissing() async throws {
        let account = sendableAccount("shiwen@example.com")
        let preferences = MailPreferences()

        let reconciled = MailDefaultSendAccountReconciler.reconcile(preferences: preferences, accounts: [account])

        #expect(reconciled.defaultSendAccountID == account.id)
        #expect(reconciled.defaultSendIdentityID == account.identities.first?.id)
    }

    @Test func reconcilerPreservesExistingValidDefaultWhenAddingSecondAccount() async throws {
        let first = sendableAccount("shiwen@example.com")
        let second = sendableAccount("work@example.com")
        let preferences = MailPreferences(defaultSendAccountID: first.id, defaultSendIdentityID: first.identities.first?.id)

        let reconciled = MailDefaultSendAccountReconciler.reconcile(preferences: preferences, accounts: [first, second])

        #expect(reconciled.defaultSendAccountID == first.id)
        #expect(reconciled.defaultSendIdentityID == first.identities.first?.id)
    }

    @Test func reconcilerClearsInvalidDefaultWhenMultipleAccountsNeedExplicitChoice() async throws {
        let first = sendableAccount("shiwen@example.com")
        let second = sendableAccount("work@example.com")
        let preferences = MailPreferences(defaultSendAccountID: MailAccountID(rawValue: "missing@example.com"), defaultSendIdentityID: MailIdentityID(rawValue: "identity-missing@example.com"))

        let reconciled = MailDefaultSendAccountReconciler.reconcile(preferences: preferences, accounts: [first, second])

        #expect(reconciled.defaultSendAccountID == nil)
        #expect(reconciled.defaultSendIdentityID == nil)
    }

    @Test func reconcilerRepairsInvalidDefaultToOnlyAccount() async throws {
        let account = sendableAccount("shiwen@example.com")
        let preferences = MailPreferences(defaultSendAccountID: MailAccountID(rawValue: "missing@example.com"), defaultSendIdentityID: nil)

        let reconciled = MailDefaultSendAccountReconciler.reconcile(preferences: preferences, accounts: [account])

        #expect(reconciled.defaultSendAccountID == account.id)
        #expect(reconciled.defaultSendIdentityID == account.identities.first?.id)
    }

    private func temporaryPreferencesURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-mail-preferences-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("mail-preferences.json")
    }

    private func sendableAccount(_ email: String) -> MailAccount {
        MailAccount(
            id: MailAccountID(rawValue: email),
            provider: .genericIMAPSMTP,
            displayName: email,
            identities: [MailIdentity(id: MailIdentityID(rawValue: "identity-\(email)"), displayName: email, address: MailAddress(email: email), canSend: true)],
            incoming: MailServerEndpoint(host: "imap.example.com", port: 993, security: .tls, protocolKind: .imap),
            outgoing: MailServerEndpoint(host: "smtp.example.com", port: 465, security: .tls, protocolKind: .smtp),
            health: MailAccountHealth(status: .ready, summary: "Ready")
        )
    }
}
