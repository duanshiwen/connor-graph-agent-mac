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

    @Test func searchEventsTimePresetTodayReturnsOnlyTodayEvents() async throws {
        let runtime = try await makeRuntimeWithDaySpanningEvents()

        let today = try await runtime.searchEvents(query: "", startDate: nil, endDate: nil, timePreset: "today", timeFilterMode: nil, timeSort: nil, limit: 50, runID: "run", sessionID: "session")

        #expect(today.map(\.title) == ["Today Meeting"])
    }

    @Test func searchEventsTimePresetYesterdayReturnsOnlyYesterdayEvents() async throws {
        let runtime = try await makeRuntimeWithDaySpanningEvents()

        let yesterday = try await runtime.searchEvents(query: "", startDate: nil, endDate: nil, timePreset: "yesterday", timeFilterMode: nil, timeSort: nil, limit: 50, runID: "run", sessionID: "session")

        #expect(yesterday.map(\.title) == ["Yesterday Meeting"])
    }

    @Test func searchEventsExplicitRangeStillFiltersOverlappingEvents() async throws {
        let runtime = try await makeRuntimeWithDaySpanningEvents()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let rangeStart = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        let rangeEnd = calendar.date(byAdding: .day, value: 1, to: startOfToday)!

        let inRange = try await runtime.searchEvents(query: "", startDate: rangeStart, endDate: rangeEnd, timePreset: nil, timeFilterMode: nil, timeSort: nil, limit: 50, runID: "run", sessionID: "session")

        #expect(Set(inRange.map(\.title)) == ["Today Meeting", "Yesterday Meeting"])
    }

    @Test func searchEventsTimePresetComposesWithKeywordFilter() async throws {
        let runtime = try await makeRuntimeWithDaySpanningEvents()

        let results = try await runtime.searchEvents(query: "week", startDate: nil, endDate: nil, timePreset: "today", timeFilterMode: nil, timeSort: nil, limit: 50, runID: "run", sessionID: "session")

        #expect(results.isEmpty)
    }

    // MARK: - Helpers

    private func makeRuntimeWithDaySpanningEvents() async throws -> CalendarSourceAgentRuntimeBridge {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        func at(_ dayOffset: Int, _ hour: Int) -> Date {
            calendar.date(byAdding: .hour, value: dayOffset * 24 + hour, to: startOfToday)!
        }
        let events = [
            makeEvent(id: "event-today", title: "Today Meeting", start: at(0, 10), end: at(0, 11)),
            makeEvent(id: "event-yesterday", title: "Yesterday Meeting", start: at(-1, 10), end: at(-1, 11)),
            makeEvent(id: "event-next-week", title: "Next Week Meeting", start: at(7, 10), end: at(7, 11)),
        ]
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("calendar-agent-runtime-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("store.json")
        let store = FileBackedCalendarSourceRuntimeStore(storeURL: storeURL)
        let accountID = CalendarAccountID(rawValue: "calendar-account-ics")
        let calendarID = CalendarID(rawValue: "calendar-ics")
        try await store.saveSnapshot(CalendarSourceRuntimeSnapshot(
            accounts: [CalendarAccount(id: accountID, provider: .genericCalDAVCardDAV, sourceKind: .icsSubscription, displayName: "ICS")],
            collections: [CalendarCollection(id: calendarID, accountID: accountID, displayName: "ICS", isReadOnly: true, source: "ics-subscription")],
            events: events
        ))
        return CalendarSourceAgentRuntimeBridge(store: store)
    }

    private func makeEvent(id: String, title: String, start: Date, end: Date) -> CalendarEvent {
        CalendarEvent(
            id: CalendarEventID(rawValue: id),
            calendarID: CalendarID(rawValue: "calendar-ics"),
            title: title,
            start: CalendarEventDateTime(date: start),
            end: CalendarEventDateTime(date: end)
        )
    }
}
