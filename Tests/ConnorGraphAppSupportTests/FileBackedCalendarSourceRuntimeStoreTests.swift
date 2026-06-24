import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("File-backed Calendar Source Runtime Store Tests")
struct FileBackedCalendarSourceRuntimeStoreTests {
    @Test func runtimeStorePersistsSnapshotAcrossInstancesWithoutSecrets() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("calendar-runtime-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("store.json")
        let accountID = CalendarAccountID(rawValue: "calendar-account-ics")
        let calendarID = CalendarID(rawValue: "calendar-ics")
        let eventID = CalendarEventID(rawValue: "event-ics-1")
        let account = CalendarAccount(
            id: accountID,
            provider: .genericCalDAVCardDAV,
            sourceKind: .icsSubscription,
            displayName: "ICS",
            configuration: CalendarSourceConfiguration(sourceKind: .icsSubscription, authMode: .none, subscriptionURL: URL(string: "https://example.com/feed.ics"))
        )
        let snapshot = CalendarSourceRuntimeSnapshot(
            accounts: [account],
            collections: [CalendarCollection(id: calendarID, accountID: accountID, displayName: "ICS", isReadOnly: true, source: "ics-subscription")],
            events: [CalendarEvent(id: eventID, calendarID: calendarID, title: "Demo", start: CalendarEventDateTime(date: Date(timeIntervalSince1970: 1)), end: CalendarEventDateTime(date: Date(timeIntervalSince1970: 2)))],
            syncStates: [CalendarAccountSyncState(accountID: accountID, sourceKind: .icsSubscription, failureCount: 0)],
            diagnostics: [CalendarSourceSyncDiagnostic(severity: .info, code: "ok", message: "Synced")]
        )

        let store = FileBackedCalendarSourceRuntimeStore(storeURL: url)
        try await store.saveSnapshot(snapshot)

        let raw = try String(contentsOf: url, encoding: .utf8)
        #expect(!raw.contains("secret-password"))

        let reloaded = FileBackedCalendarSourceRuntimeStore(storeURL: url)
        let loaded = try await reloaded.loadSnapshot()

        #expect(loaded.accounts.first?.id == account.id)
        #expect(loaded.accounts.first?.sourceKind == .icsSubscription)
        #expect(loaded.collections.first?.id == calendarID)
        #expect(loaded.events.first?.id == eventID)
        #expect(loaded.syncStates.first?.accountID == accountID)
        #expect(loaded.diagnostics.first?.code == "ok")
    }

    @Test func runtimeStoreDeletesAccountScopedData() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("calendar-runtime-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("store.json")
        let removedAccountID = CalendarAccountID(rawValue: "calendar-account-remove")
        let keptAccountID = CalendarAccountID(rawValue: "calendar-account-keep")
        let removedCalendarID = CalendarID(rawValue: "calendar-remove")
        let keptCalendarID = CalendarID(rawValue: "calendar-keep")
        let store = FileBackedCalendarSourceRuntimeStore(storeURL: url)
        try await store.saveSnapshot(CalendarSourceRuntimeSnapshot(
            accounts: [
                CalendarAccount(id: removedAccountID, provider: .genericCalDAVCardDAV, sourceKind: .icsSubscription, displayName: "Remove"),
                CalendarAccount(id: keptAccountID, provider: .genericCalDAVCardDAV, sourceKind: .icsSubscription, displayName: "Keep")
            ],
            collections: [
                CalendarCollection(id: removedCalendarID, accountID: removedAccountID, displayName: "Remove", isReadOnly: true),
                CalendarCollection(id: keptCalendarID, accountID: keptAccountID, displayName: "Keep", isReadOnly: true)
            ],
            events: [
                CalendarEvent(id: CalendarEventID(rawValue: "event-remove"), calendarID: removedCalendarID, title: "Remove", start: CalendarEventDateTime(date: Date()), end: CalendarEventDateTime(date: Date())),
                CalendarEvent(id: CalendarEventID(rawValue: "event-keep"), calendarID: keptCalendarID, title: "Keep", start: CalendarEventDateTime(date: Date()), end: CalendarEventDateTime(date: Date()))
            ],
            syncStates: [
                CalendarAccountSyncState(accountID: removedAccountID, sourceKind: .icsSubscription),
                CalendarAccountSyncState(accountID: keptAccountID, sourceKind: .icsSubscription)
            ],
            diagnostics: [
                CalendarSourceSyncDiagnostic(accountID: removedAccountID, severity: .error, code: "removed", message: "Removed"),
                CalendarSourceSyncDiagnostic(accountID: keptAccountID, severity: .info, code: "kept", message: "Kept")
            ]
        ))

        try await store.deleteAccountScopedData(accountID: removedAccountID)
        let loaded = try await store.loadSnapshot()

        #expect(loaded.accounts.map(\.id) == [keptAccountID])
        #expect(loaded.collections.map(\.id) == [keptCalendarID])
        #expect(loaded.events.map(\.calendarID) == [keptCalendarID])
        #expect(loaded.syncStates.map(\.accountID) == [keptAccountID])
        #expect(loaded.diagnostics.map(\.code) == ["kept"])
    }
}
