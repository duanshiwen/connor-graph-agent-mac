import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport

@Suite("Calendar Source Agent Runtime Bridge Tests")
struct CalendarSourceAgentRuntimeBridgeTests {
    @Test func runtimeBridgeListsAndSearchesPersistedRemoteEvents() async throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("calendar-agent-runtime-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("store.json")
        let store = FileBackedCalendarSourceRuntimeStore(storeURL: storeURL)
        let accountID = CalendarAccountID(rawValue: "calendar-account-ics")
        let calendarID = CalendarID(rawValue: "calendar-ics")
        try await store.saveSnapshot(CalendarSourceRuntimeSnapshot(
            accounts: [CalendarAccount(id: accountID, provider: .genericCalDAVCardDAV, sourceKind: .icsSubscription, displayName: "ICS")],
            collections: [CalendarCollection(id: calendarID, accountID: accountID, displayName: "ICS", isReadOnly: true, source: "ics-subscription")],
            events: [CalendarEvent(id: CalendarEventID(rawValue: "event-remote"), calendarID: calendarID, title: "Remote Strategy Review", start: CalendarEventDateTime(date: Date(timeIntervalSince1970: 1_782_320_400)), end: CalendarEventDateTime(date: Date(timeIntervalSince1970: 1_782_324_000)), notes: "Calendar Source Platform")]
        ))
        let runtime = CalendarSourceAgentRuntimeBridge(store: store)

        let listed = try await runtime.listEvents(calendarID: nil, runID: "run", sessionID: "session")
        let searched = try await runtime.searchEvents(query: "strategy", startDate: nil, endDate: nil, timePreset: nil, timeFilterMode: nil, timeSort: nil, limit: 10, runID: "run", sessionID: "session")

        #expect(listed.map(\.id) == [CalendarEventID(rawValue: "event-remote")])
        #expect(searched.first?.title == "Remote Strategy Review")
    }
}
