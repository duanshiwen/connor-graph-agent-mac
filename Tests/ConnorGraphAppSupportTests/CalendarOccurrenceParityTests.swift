import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Calendar recurrence parity")
struct CalendarOccurrenceParityTests {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func calendar(_ body: String) -> String { "BEGIN:VCALENDAR\nVERSION:2.0\n" + body + "\nEND:VCALENDAR" }
    private func event(_ body: String) -> String { "BEGIN:VEVENT\nUID:series\nSUMMARY:周会\n" + body + "\nEND:VEVENT" }

    @Test func exclusionsDetachedAndCancelledExceptionsRemainDistinct() throws {
        let body = event("DTSTART:20261001T090000Z\nDTEND:20261001T100000Z\nRRULE:FREQ=DAILY;COUNT=5\nEXDATE:20261002T090000Z\nRDATE:20261008T090000Z") + "\n" + event("RECURRENCE-ID:20261003T090000Z\nDTSTART:20261003T140000Z\nDTEND:20261003T150000Z") + "\n" + event("RECURRENCE-ID:20261004T090000Z\nDTSTART:20261004T090000Z\nDTEND:20261004T100000Z\nSTATUS:CANCELLED")
        let rows = try ICalendarParser().occurrences(from: calendar(body), windowStart: date("2026-10-01T00:00:00Z"), windowEnd: date("2026-10-10T00:00:00Z"))
        #expect(rows.map(\.start.date) == ["2026-10-01T09:00:00Z", "2026-10-03T14:00:00Z", "2026-10-05T09:00:00Z", "2026-10-08T09:00:00Z"].map(date))
        #expect(Set(rows.compactMap(\.recurrenceIdentifier)).count == 4)
    }
    @Test func daylightSavingAndQuotedParticipants() throws {
        let body = event("DTSTART;TZID=America/New_York:20261031T090000\nDTEND;TZID=America/New_York:20261031T100000\nRRULE:FREQ=DAILY;COUNT=3\nATTENDEE;CN=\"Alice; Zhang\";PARTSTAT=ACCEPTED:mailto:alice@example.com")
        let rows = try ICalendarParser().occurrences(from: calendar(body), windowStart: date("2026-10-31T00:00:00Z"), windowEnd: date("2026-11-04T00:00:00Z"))
        #expect(rows.map(\.start.date) == ["2026-10-31T13:00:00Z", "2026-11-01T14:00:00Z", "2026-11-02T14:00:00Z"].map(date))
        #expect(rows.first?.attendees.first?.name == "Alice; Zhang")
    }
    @Test func seriesMergePreservesExclusionsAndCustomTimezone() throws {
        let zone = "BEGIN:VTIMEZONE\nTZID:Custom/Office\nBEGIN:STANDARD\nDTSTART:19700101T000000\nTZOFFSETFROM:+0530\nTZOFFSETTO:+0530\nEND:STANDARD\nEND:VTIMEZONE\n"
        let body = calendar(zone + event("DTSTART;TZID=Custom/Office:20261001T090000\nDTEND;TZID=Custom/Office:20261001T100000\nRRULE:FREQ=DAILY;COUNT=3\nEXDATE;TZID=Custom/Office:20261002T090000"))
        let replacement = calendar(event("DTSTART:20261001T033000Z\nDTEND:20261001T043000Z\nRRULE:FREQ=DAILY;COUNT=3").replacingOccurrences(of: "SUMMARY:周会", with: "SUMMARY:改名"))
        let merged = try ICalendarOccurrenceEvaluator.mergeSeries(original: body, replacement: replacement)
        #expect(merged.contains("EXDATE"))
        #expect(merged.contains("VTIMEZONE"))
        let rows = try ICalendarParser().occurrences(from: merged, windowStart: date("2026-10-01T00:00:00Z"), windowEnd: date("2026-10-05T00:00:00Z"))
        #expect(rows.count == 2)
        #expect(rows.first?.start.date == date("2026-10-01T03:30:00Z"))
    }
    @Test func eventKitSnapshotsKeepEveryOccurrenceAndPeople() {
        let person = CalendarAttendee(id: .init(rawValue: "alice"), email: "alice@example.com", responseStatus: .accepted)
        let a = CalendarSystemEventSnapshot(identifier: "shared-id", calendarIdentifier: "work", title: "系列", startDate: Date(timeIntervalSince1970: 100), endDate: Date(timeIntervalSince1970: 200), isAllDay: false, isRecurring: true, hasAttendees: true, attendees: [person], organizerEmail: "owner@example.com")
        var b = a; b.startDate = a.startDate.addingTimeInterval(86400)
        #expect(CalendarEventKitAdapter.map(snapshot: a).id != CalendarEventKitAdapter.map(snapshot: b).id)
        #expect(CalendarEventKitAdapter.map(snapshot: a).attendees == [person])
        #expect(CalendarEventKitAdapter.map(snapshot: a).sourceMetadata?.organizerEmail == "owner@example.com")
    }
    @Test func confirmedSeriesReplacesEveryCachedOccurrenceWithoutTouchingOtherSeries() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("calendar-series-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileBackedCalendarSourceRuntimeStore(storeURL: directory.appendingPathComponent("store.json"))
        let calendarID = CalendarID(rawValue: "work"), accountID = CalendarAccountID(rawValue: "account")
        func row(_ id: String, remote: String) -> CalendarEvent {
            .init(id: .init(rawValue: id), calendarID: calendarID, title: id, start: .init(date: Date(timeIntervalSince1970: 100)), end: .init(date: Date(timeIntervalSince1970: 200)), sourceMetadata: .init(sourceKind: .genericCalDAV, remoteIdentifier: remote))
        }
        try await store.saveSnapshot(.init(events: [row("first", remote: "series"), row("second", remote: "series"), row("other", remote: "other")]))
        let replacement = row("updated", remote: "series")
        let audit = CalendarMutationAuditRecord(runID: nil, sessionID: nil, accountID: accountID, calendarID: calendarID, eventID: replacement.id, sourceKind: .genericCalDAV, operation: .update, status: .confirmed)
        try await store.applyMutationResult(.init(receipt: .init(mutationKind: .updateEvent, eventID: replacement.id, approved: true, summary: "updated"), confirmedSeriesEvents: [replacement], seriesRemoteIdentifier: "series"), audit: audit)
        let updated = try await store.loadSnapshot()
        #expect(Set(updated.events.map(\.id.rawValue)) == Set(["updated", "other"]))
        try await store.applyMutationResult(.init(receipt: .init(mutationKind: .deleteEvent, eventID: replacement.id, approved: true, summary: "deleted"), confirmedSeriesEvents: [], seriesRemoteIdentifier: "series"), audit: audit)
        let deleted = try await store.loadSnapshot()
        #expect(deleted.events.map(\.id.rawValue) == ["other"])
    }
}
