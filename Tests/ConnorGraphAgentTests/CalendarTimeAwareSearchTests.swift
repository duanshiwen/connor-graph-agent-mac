import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAgent

@Suite("Calendar Time-aware Search Tests")
struct CalendarTimeAwareSearchTests {
    @Test func calendarSearchUsesIntervalOverlapAndPreservesTimeFields() async throws {
        let calendarID = CalendarID(rawValue: "work")
        let event = CalendarEvent(
            id: CalendarEventID(rawValue: "event-1"),
            calendarID: calendarID,
            title: "Strategy workshop",
            start: CalendarEventDateTime(date: ISO8601DateFormatter().date(from: "2026-06-20T23:00:00Z")!, timeZoneIdentifier: "Asia/Shanghai"),
            end: CalendarEventDateTime(date: ISO8601DateFormatter().date(from: "2026-06-21T02:00:00Z")!, timeZoneIdentifier: "Asia/Shanghai"),
            location: "Hangzhou",
            notes: "Agent OS planning"
        )
        let runtime = InMemoryAgentCalendarRuntime(events: [event])
        let results = try await runtime.searchEvents(
            query: "strategy",
            startDate: ISO8601DateFormatter().date(from: "2026-06-21T00:00:00Z")!,
            endDate: ISO8601DateFormatter().date(from: "2026-06-21T01:00:00Z")!,
            timePreset: nil,
            timeFilterMode: nil,
            timeSort: "timeAscThenRelevance",
            runID: "run",
            sessionID: "session"
        )

        #expect(results.map(\.id) == [CalendarEventID(rawValue: "event-1")])
        #expect(results.first?.start.timeZoneIdentifier == "Asia/Shanghai")
        #expect(results.first?.end.date == ISO8601DateFormatter().date(from: "2026-06-21T02:00:00Z")!)
    }

    @Test func calendarReadToolSchemaDoesNotExposeInternalSearchOperation() {
        let tool = CalendarReadTool(runtime: InMemoryAgentCalendarRuntime())
        guard case .closedObject(let properties, _) = tool.inputSchema else {
            Issue.record("calendar_read schema should be a closed object")
            return
        }
        #expect(!tool.description.contains("search_events"))
        #expect(!tool.description.localizedCaseInsensitiveContains("time-aware"))
        #expect(!properties.keys.contains("query"))
        #expect(!properties.keys.contains("startDate"))
        #expect(!properties.keys.contains("endDate"))
        #expect(!properties.keys.contains("timePreset"))
        #expect(!properties.keys.contains("timeFilterMode"))
        #expect(!properties.keys.contains("timeSort"))
        #expect(!properties.keys.contains("limit"))
    }
}
