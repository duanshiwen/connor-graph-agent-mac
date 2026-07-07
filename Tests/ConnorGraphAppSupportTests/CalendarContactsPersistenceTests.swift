import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Calendar Contacts Persistence Tests")
struct CalendarContactsPersistenceTests {
    @Test func fileBackedCalendarStorageSurvivesRuntimeRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ConnorCalendarStorageTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()

        let accountID = CalendarAccountID(rawValue: "calendar-account-test")
        let calendarID = CalendarID(rawValue: "calendar-test")
        let eventID = CalendarEventID(rawValue: "calendar-event-test")
        let account = CalendarAccount(id: accountID, provider: .genericCalDAVCardDAV, displayName: "Test Calendar")
        let collection = CalendarCollection(id: calendarID, accountID: accountID, displayName: "Personal")
        let event = CalendarEvent(
            id: eventID,
            calendarID: calendarID,
            title: "Persistent Event",
            start: CalendarEventDateTime(date: Date(timeIntervalSince1970: 1_800_000_000)),
            end: CalendarEventDateTime(date: Date(timeIntervalSince1970: 1_800_003_600))
        )

        let store = FileBackedCalendarSourceStore(storagePaths: paths)
        try await store.saveSnapshot(FileBackedCalendarSourceStore.Snapshot(accounts: [account], collections: [collection], events: [event]))

        let restartedStore = FileBackedCalendarSourceStore(storagePaths: paths)
        let restored = try await restartedStore.loadSnapshot()

        #expect(restored.accounts.map(\.id).contains(accountID))
        #expect(restored.collections.map(\.id).contains(calendarID))
        #expect(restored.events.map(\.id).contains(eventID))
        #expect(restored.events.first?.title == "Persistent Event")
    }

}
