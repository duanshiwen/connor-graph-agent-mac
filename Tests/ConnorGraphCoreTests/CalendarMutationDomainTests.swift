import Foundation
import Testing
import ConnorGraphCore

@Suite("Calendar Mutation Domain Tests")
struct CalendarMutationDomainTests {
    @Test func bidirectionalConfigurationRoundTripsAndLegacyDefaultsReadOnly() throws {
        let value = CalendarSourceConfiguration(sourceKind: .genericCalDAV, syncMode: .bidirectional)
        #expect(try JSONDecoder().decode(CalendarSourceConfiguration.self, from: JSONEncoder().encode(value)) == value)
        let legacy = #"{"sourceKind":"genericCalDAV","authMode":"appPassword","syncWindowPastDays":30,"syncWindowFutureDays":365,"enabledCollectionIDs":[],"providerMetadata":{}}"#
        let decoded = try JSONDecoder().decode(CalendarSourceConfiguration.self, from: Data(legacy.utf8))
        #expect(decoded.syncMode == .readOnly)
        #expect(CalendarSourceKind.genericCalDAV.supportsWrite)
        #expect(!CalendarSourceKind.icsSubscription.supportsWrite)
    }

    @Test func eventSourceMetadataRoundTripsAndLegacyEventStillDecodes() throws {
        let metadata = CalendarEventSourceMetadata(sourceKind: .genericCalDAV, remoteIdentifier: "uid-1", resourceURL: URL(string: "https://cal.example/u/a.ics"), etag: "\"v1\"")
        let event = CalendarEvent(id: .init(rawValue: "e1"), calendarID: .init(rawValue: "c1"), title: "Test", start: .init(date: Date(timeIntervalSince1970: 10)), end: .init(date: Date(timeIntervalSince1970: 20)), sourceMetadata: metadata)
        #expect(try JSONDecoder().decode(CalendarEvent.self, from: JSONEncoder().encode(event)) == event)
        let legacy = #"{"id":"e1","calendarID":"c1","title":"Old","start":{"date":10},"end":{"date":20},"isAllDay":false,"attendees":[],"updatedAt":20}"#
        #expect(try JSONDecoder().decode(CalendarEvent.self, from: Data(legacy.utf8)).sourceMetadata == nil)
    }

    @Test func mutationRequestsValidateRequiredPayloadAndTimeRange() throws {
        let calendarID = CalendarID(rawValue: "c1")
        let draft = CalendarEventDraft(calendarID: calendarID, title: "Focus", start: .init(date: Date(timeIntervalSince1970: 10)), end: .init(date: Date(timeIntervalSince1970: 20)))
        let create = CalendarMutationRequest(operation: .create, draft: draft, runID: "r", sessionID: "s")
        #expect(try create.validated() == create)
        let invalid = CalendarMutationRequest(operation: .create, draft: .init(calendarID: calendarID, title: "", start: .init(date: Date(timeIntervalSince1970: 20)), end: .init(date: Date(timeIntervalSince1970: 10))))
        #expect(throws: CalendarMutationError.self) { try invalid.validated() }
        let emptyUpdate = CalendarMutationRequest(operation: .update, eventID: .init(rawValue: "e1"), expectedVersion: .init(value: "v1"), patch: .init())
        #expect(throws: CalendarMutationError.self) { try emptyUpdate.validated() }
        let delete = CalendarMutationRequest(operation: .delete, eventID: .init(rawValue: "e1"), expectedVersion: .init(value: "v1"))
        #expect(try delete.validated() == delete)
    }

    @Test func explicitPatchDistinguishesClearFromNoChange() throws {
        let patch = CalendarEventPatch(title: .set("Renamed"), location: .clear, notes: .set("note"))
        let decoded = try JSONDecoder().decode(CalendarEventPatch.self, from: JSONEncoder().encode(patch))
        #expect(decoded == patch)
        #expect(decoded.location == .clear)
        #expect(decoded.url == .unchanged)
    }
}
