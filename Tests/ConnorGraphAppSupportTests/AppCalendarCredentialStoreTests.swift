import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("App Calendar Credential Store Tests")
struct AppCalendarCredentialStoreTests {
    @Test func calendarCredentialStoreDefaultsToLocalEncryptedCredentialStore() {
        let store = AppCalendarCredentialStore()

        #expect(store.credentialStore is LocalEncryptedCredentialStore)
    }

    @Test func calendarCredentialStoreSavesReadsAndDeletesSecrets() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ConnorCalendarCredentialTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let backingStore = LocalEncryptedCredentialStore(rootDirectory: root)
        let store = AppCalendarCredentialStore(credentialStore: backingStore)
        let binding = AppCalendarCredentialStore.binding(
            accountID: CalendarAccountID(rawValue: "calendar-account-caldav"),
            username: "Shiwen@Example.COM",
            authMode: .appPassword
        )

        try store.saveCredential("calendar-app-password", binding: binding)

        #expect(binding.credentialNamespace == AppCalendarCredentialStore.credentialNamespace)
        #expect(binding.accountName == "calendar-account-caldav:shiwen@example.com")
        #expect(try store.readCredential(binding: binding) == "calendar-app-password")

        try store.deleteCredential(binding: binding)

        #expect(try store.readCredential(binding: binding) == nil)
    }
}
