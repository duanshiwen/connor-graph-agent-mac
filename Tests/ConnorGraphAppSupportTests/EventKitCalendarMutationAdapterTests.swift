import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("EventKit Calendar Mutation Adapter Tests")
struct EventKitCalendarMutationAdapterTests {
    @Test func createsAndVerifiesEvent() async throws {
        let client = FakeEventKitMutationClient(calendars: ["c": true])
        let adapter = EventKitCalendarMutationAdapter(client: client)
        let account = CalendarAccount(id: CalendarEventKitAdapter.systemAccountID, provider: .localFixture, sourceKind: .macOSEventKit, displayName: "Local", configuration: .init(sourceKind: .macOSEventKit, syncMode: .bidirectional))
        let collection = CalendarCollection(id: .init(rawValue: "c"), accountID: account.id, displayName: "Work")
        let result = try await adapter.mutate(.init(operation: .create, draft: .init(calendarID: collection.id, title: "Focus", start: .init(date: Date(timeIntervalSince1970: 10)), end: .init(date: Date(timeIntervalSince1970: 20)))), account: account, collection: collection, currentEvent: nil)
        #expect(result.confirmedEvent?.title == "Focus")
        #expect(result.remoteVersion != nil)
    }

    @Test func updateRejectsStaleVersion() async throws {
        let snapshot = EventKitMutationEventSnapshot(identifier: "e", calendarIdentifier: "c", title: "Old", startDate: Date(timeIntervalSince1970: 10), endDate: Date(timeIntervalSince1970: 20), isAllDay: false, lastModifiedDate: Date(timeIntervalSince1970: 30))
        let client = FakeEventKitMutationClient(calendars: ["c": true], events: ["e": snapshot])
        let adapter = EventKitCalendarMutationAdapter(client: client)
        let event = CalendarEvent(id: .init(rawValue: "e"), calendarID: .init(rawValue: "c"), title: "Old", start: .init(date: snapshot.startDate), end: .init(date: snapshot.endDate), sourceMetadata: .init(sourceKind: .macOSEventKit, remoteIdentifier: "e", etag: "stale"))
        await #expect(throws: CalendarMutationError.self) { try await adapter.mutate(.init(operation: .update, eventID: event.id, expectedVersion: .init(value: "stale"), patch: .init(title: .set("New"))), account: .init(id: CalendarEventKitAdapter.systemAccountID, provider: .localFixture, displayName: "Local"), collection: .init(id: .init(rawValue: "c"), accountID: CalendarEventKitAdapter.systemAccountID, displayName: "Work"), currentEvent: event) }
    }
}

private actor FakeEventKitMutationClient: EventKitMutationClient {
    var calendars: [String: Bool]
    var events: [String: EventKitMutationEventSnapshot]
    init(calendars: [String: Bool], events: [String: EventKitMutationEventSnapshot] = [:]) { self.calendars = calendars; self.events = events }
    func requestAccess() async throws {}
    func calendarAllowsModifications(identifier: String) async -> Bool? { calendars[identifier] }
    func event(identifier: String) async -> EventKitMutationEventSnapshot? { events[identifier] }
    func save(_ event: EventKitMutationEventSnapshot) async throws -> EventKitMutationEventSnapshot { var value = event; if value.identifier.isEmpty { value.identifier = "created" }; value.lastModifiedDate = Date(timeIntervalSince1970: 40); events[value.identifier] = value; return value }
    func remove(identifier: String) async throws { events.removeValue(forKey: identifier) }
}
