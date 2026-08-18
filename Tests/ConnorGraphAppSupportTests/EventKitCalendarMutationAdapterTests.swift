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

    @Test func deletePreservesCompositeEventIdentifierExactly() async throws {
        let compositeID = "467EBD97-A2D1:8BCA05B8/opaque"
        let snapshot = EventKitMutationEventSnapshot(identifier: compositeID, calendarIdentifier: "c", title: "Delete", startDate: Date(timeIntervalSince1970: 10), endDate: Date(timeIntervalSince1970: 20), isAllDay: false, lastModifiedDate: Date(timeIntervalSince1970: 30))
        let client = FakeEventKitMutationClient(calendars: ["c": true], events: [compositeID: snapshot])
        let event = CalendarEvent(id: .init(rawValue: compositeID), calendarID: .init(rawValue: "c"), title: "Delete", start: .init(date: snapshot.startDate), end: .init(date: snapshot.endDate), sourceMetadata: .init(sourceKind: .macOSEventKit, remoteIdentifier: compositeID, etag: "30.0"))
        let result = try await EventKitCalendarMutationAdapter(client: client).mutate(.init(operation: .delete, eventID: event.id, expectedVersion: .init(value: "30.0")), account: .init(id: CalendarEventKitAdapter.systemAccountID, provider: .localFixture, displayName: "Local"), collection: .init(id: .init(rawValue: "c"), accountID: CalendarEventKitAdapter.systemAccountID, displayName: "Work"), currentEvent: event)
        #expect(result.receipt.eventID?.rawValue == compositeID)
        #expect(await client.event(identifier: compositeID) == nil)
    }

    @Test func updateRejectsStaleVersion() async throws {
        let snapshot = EventKitMutationEventSnapshot(identifier: "e", calendarIdentifier: "c", title: "Old", startDate: Date(timeIntervalSince1970: 10), endDate: Date(timeIntervalSince1970: 20), isAllDay: false, lastModifiedDate: Date(timeIntervalSince1970: 30))
        let client = FakeEventKitMutationClient(calendars: ["c": true], events: ["e": snapshot])
        let adapter = EventKitCalendarMutationAdapter(client: client)
        let event = CalendarEvent(id: .init(rawValue: "e"), calendarID: .init(rawValue: "c"), title: "Old", start: .init(date: snapshot.startDate), end: .init(date: snapshot.endDate), sourceMetadata: .init(sourceKind: .macOSEventKit, remoteIdentifier: "e", etag: "stale"))
        await #expect(throws: CalendarMutationError.self) { try await adapter.mutate(.init(operation: .update, eventID: event.id, expectedVersion: .init(value: "stale"), patch: .init(title: .set("New"))), account: .init(id: CalendarEventKitAdapter.systemAccountID, provider: .localFixture, displayName: "Local"), collection: .init(id: .init(rawValue: "c"), accountID: CalendarEventKitAdapter.systemAccountID, displayName: "Work"), currentEvent: event) }
    }

    @Test func createRecurringEventWritesRecurrenceRule() async throws {
        let client = FakeEventKitMutationClient(calendars: ["c": true])
        let adapter = EventKitCalendarMutationAdapter(client: client)
        let draft = CalendarEventDraft(
            calendarID: .init(rawValue: "c"),
            title: "Standup",
            start: .init(date: Date(timeIntervalSince1970: 10)),
            end: .init(date: Date(timeIntervalSince1970: 20)),
            recurrence: .init(frequency: .weekly, interval: 2, count: 10)
        )
        let result = try await adapter.mutate(.init(operation: .create, draft: draft), account: .init(id: CalendarEventKitAdapter.systemAccountID, provider: .localFixture, displayName: "Local"), collection: .init(id: .init(rawValue: "c"), accountID: CalendarEventKitAdapter.systemAccountID, displayName: "Work"), currentEvent: nil)
        #expect(await client.lastSavedRecurrence == .set("FREQ=WEEKLY;INTERVAL=2;COUNT=10"))
        #expect(result.confirmedEvent?.recurrenceSummary?.ruleDescription == "FREQ=WEEKLY;INTERVAL=2;COUNT=10")
        #expect(result.confirmedEvent?.sourceMetadata?.isRecurring == true)
    }

    @Test func updateRecurringSeriesAllowsTitleAndRuleChanges() async throws {
        let snapshot = EventKitMutationEventSnapshot(identifier: "e", calendarIdentifier: "c", title: "Standup", startDate: Date(timeIntervalSince1970: 10), endDate: Date(timeIntervalSince1970: 20), isAllDay: false, lastModifiedDate: Date(timeIntervalSince1970: 30), isRecurring: true, recurrenceRule: "FREQ=WEEKLY")
        let client = FakeEventKitMutationClient(calendars: ["c": true], events: ["e": snapshot])
        let event = CalendarEvent(id: .init(rawValue: "e"), calendarID: .init(rawValue: "c"), title: "Standup", start: .init(date: snapshot.startDate), end: .init(date: snapshot.endDate), recurrenceSummary: .init(ruleDescription: "FREQ=WEEKLY"), sourceMetadata: .init(sourceKind: .macOSEventKit, remoteIdentifier: "e", etag: "30.0", isRecurring: true))
        let result = try await EventKitCalendarMutationAdapter(client: client).mutate(
            .init(operation: .update, eventID: event.id, expectedVersion: .init(value: "30.0"), patch: .init(title: .set("Retro"), recurrence: .set(.init(frequency: .daily, count: 5)))),
            account: .init(id: CalendarEventKitAdapter.systemAccountID, provider: .localFixture, displayName: "Local"),
            collection: .init(id: .init(rawValue: "c"), accountID: CalendarEventKitAdapter.systemAccountID, displayName: "Work"),
            currentEvent: event
        )
        #expect(result.confirmedEvent?.title == "Retro")
        #expect(await client.lastSavedRecurrence == .set("FREQ=DAILY;COUNT=5"))
        #expect(await client.lastSavedSpan == .thisEvent)
        #expect(await client.lastSavedOccurrenceDate == nil)
    }

    @Test func updateSingleOccurrenceTargetsOccurrenceDateWithThisEventSpan() async throws {
        let snapshot = EventKitMutationEventSnapshot(identifier: "e", calendarIdentifier: "c", title: "Standup", startDate: Date(timeIntervalSince1970: 10), endDate: Date(timeIntervalSince1970: 20), isAllDay: false, lastModifiedDate: Date(timeIntervalSince1970: 30), isRecurring: true, recurrenceRule: "FREQ=DAILY")
        let client = FakeEventKitMutationClient(calendars: ["c": true], events: ["e": snapshot])
        let event = CalendarEvent(id: .init(rawValue: "e"), calendarID: .init(rawValue: "c"), title: "Standup", start: .init(date: snapshot.startDate), end: .init(date: snapshot.endDate), recurrenceSummary: .init(ruleDescription: "FREQ=DAILY"), sourceMetadata: .init(sourceKind: .macOSEventKit, remoteIdentifier: "e", etag: "30.0", isRecurring: true))
        let occurrence = Date(timeIntervalSince1970: 86_410)
        _ = try await EventKitCalendarMutationAdapter(client: client).mutate(
            .init(operation: .update, eventID: event.id, expectedVersion: .init(value: "30.0"), patch: .init(title: .set("Moved")), scope: .thisEvent, occurrenceDate: occurrence),
            account: .init(id: CalendarEventKitAdapter.systemAccountID, provider: .localFixture, displayName: "Local"),
            collection: .init(id: .init(rawValue: "c"), accountID: CalendarEventKitAdapter.systemAccountID, displayName: "Work"),
            currentEvent: event
        )
        #expect(await client.lastSavedSpan == .thisEvent)
        #expect(await client.lastSavedOccurrenceDate == occurrence)
        #expect(await client.lastSavedRecurrence == .keep)
    }

    @Test func updateFutureOccurrencesUsesFutureEventsSpan() async throws {
        let snapshot = EventKitMutationEventSnapshot(identifier: "e", calendarIdentifier: "c", title: "Standup", startDate: Date(timeIntervalSince1970: 10), endDate: Date(timeIntervalSince1970: 20), isAllDay: false, lastModifiedDate: Date(timeIntervalSince1970: 30), isRecurring: true, recurrenceRule: "FREQ=DAILY")
        let client = FakeEventKitMutationClient(calendars: ["c": true], events: ["e": snapshot])
        let event = CalendarEvent(id: .init(rawValue: "e"), calendarID: .init(rawValue: "c"), title: "Standup", start: .init(date: snapshot.startDate), end: .init(date: snapshot.endDate), recurrenceSummary: .init(ruleDescription: "FREQ=DAILY"), sourceMetadata: .init(sourceKind: .macOSEventKit, remoteIdentifier: "e", etag: "30.0", isRecurring: true))
        _ = try await EventKitCalendarMutationAdapter(client: client).mutate(
            .init(operation: .update, eventID: event.id, expectedVersion: .init(value: "30.0"), patch: .init(title: .set("Later")), scope: .futureEvents, occurrenceDate: Date(timeIntervalSince1970: 86_410)),
            account: .init(id: CalendarEventKitAdapter.systemAccountID, provider: .localFixture, displayName: "Local"),
            collection: .init(id: .init(rawValue: "c"), accountID: CalendarEventKitAdapter.systemAccountID, displayName: "Work"),
            currentEvent: event
        )
        #expect(await client.lastSavedSpan == .futureEvents)
    }

    @Test func updateCanClearRecurrence() async throws {
        let snapshot = EventKitMutationEventSnapshot(identifier: "e", calendarIdentifier: "c", title: "Standup", startDate: Date(timeIntervalSince1970: 10), endDate: Date(timeIntervalSince1970: 20), isAllDay: false, lastModifiedDate: Date(timeIntervalSince1970: 30), isRecurring: true, recurrenceRule: "FREQ=WEEKLY")
        let client = FakeEventKitMutationClient(calendars: ["c": true], events: ["e": snapshot])
        let event = CalendarEvent(id: .init(rawValue: "e"), calendarID: .init(rawValue: "c"), title: "Standup", start: .init(date: snapshot.startDate), end: .init(date: snapshot.endDate), recurrenceSummary: .init(ruleDescription: "FREQ=WEEKLY"), sourceMetadata: .init(sourceKind: .macOSEventKit, remoteIdentifier: "e", etag: "30.0", isRecurring: true))
        _ = try await EventKitCalendarMutationAdapter(client: client).mutate(
            .init(operation: .update, eventID: event.id, expectedVersion: .init(value: "30.0"), patch: .init(title: .set("One-off"), recurrence: .clear)),
            account: .init(id: CalendarEventKitAdapter.systemAccountID, provider: .localFixture, displayName: "Local"),
            collection: .init(id: .init(rawValue: "c"), accountID: CalendarEventKitAdapter.systemAccountID, displayName: "Work"),
            currentEvent: event
        )
        #expect(await client.lastSavedRecurrence == .clear)
    }

    @Test func deleteOccurrenceAndSeriesUseExpectedSpans() async throws {
        func event() -> CalendarEvent {
            let snapshot = EventKitMutationEventSnapshot(identifier: "e", calendarIdentifier: "c", title: "Standup", startDate: Date(timeIntervalSince1970: 10), endDate: Date(timeIntervalSince1970: 20), isAllDay: false, lastModifiedDate: Date(timeIntervalSince1970: 30), isRecurring: true, recurrenceRule: "FREQ=DAILY")
            return CalendarEvent(id: .init(rawValue: "e"), calendarID: .init(rawValue: "c"), title: "Standup", start: .init(date: snapshot.startDate), end: .init(date: snapshot.endDate), recurrenceSummary: .init(ruleDescription: "FREQ=DAILY"), sourceMetadata: .init(sourceKind: .macOSEventKit, remoteIdentifier: "e", etag: "30.0", isRecurring: true))
        }
        let account = CalendarAccount(id: CalendarEventKitAdapter.systemAccountID, provider: .localFixture, displayName: "Local")
        let collection = CalendarCollection(id: .init(rawValue: "c"), accountID: CalendarEventKitAdapter.systemAccountID, displayName: "Work")
        func seed() -> FakeEventKitMutationClient {
            FakeEventKitMutationClient(calendars: ["c": true], events: ["e": EventKitMutationEventSnapshot(identifier: "e", calendarIdentifier: "c", title: "Standup", startDate: Date(timeIntervalSince1970: 10), endDate: Date(timeIntervalSince1970: 20), isAllDay: false, lastModifiedDate: Date(timeIntervalSince1970: 30), isRecurring: true, recurrenceRule: "FREQ=DAILY")])
        }

        let occurrenceClient = seed()
        _ = try await EventKitCalendarMutationAdapter(client: occurrenceClient).mutate(.init(operation: .delete, eventID: .init(rawValue: "e"), expectedVersion: .init(value: "30.0"), scope: .thisEvent, occurrenceDate: Date(timeIntervalSince1970: 86_410)), account: account, collection: collection, currentEvent: event())
        #expect(await occurrenceClient.lastRemovedSpan == .thisEvent)
        #expect(await occurrenceClient.lastRemovedOccurrenceDate == Date(timeIntervalSince1970: 86_410))

        let futureClient = seed()
        _ = try await EventKitCalendarMutationAdapter(client: futureClient).mutate(.init(operation: .delete, eventID: .init(rawValue: "e"), expectedVersion: .init(value: "30.0"), scope: .futureEvents, occurrenceDate: Date(timeIntervalSince1970: 172_810)), account: account, collection: collection, currentEvent: event())
        #expect(await futureClient.lastRemovedSpan == .futureEvents)

        let seriesClient = seed()
        _ = try await EventKitCalendarMutationAdapter(client: seriesClient).mutate(.init(operation: .delete, eventID: .init(rawValue: "e"), expectedVersion: .init(value: "30.0")), account: account, collection: collection, currentEvent: event())
        #expect(await seriesClient.lastRemovedSpan == .thisEvent)
        #expect(await seriesClient.lastRemovedOccurrenceDate == nil)
    }
}

private actor FakeEventKitMutationClient: EventKitMutationClient {
    var calendars: [String: Bool]
    var events: [String: EventKitMutationEventSnapshot]
    private(set) var savedSpans: [EventKitMutationSpan] = []
    private(set) var savedRecurrences: [EventKitRecurrenceMutation] = []
    private(set) var savedOccurrenceDates: [Date?] = []
    private(set) var removedSpans: [EventKitMutationSpan] = []
    private(set) var removedOccurrenceDates: [Date?] = []
    init(calendars: [String: Bool], events: [String: EventKitMutationEventSnapshot] = [:]) { self.calendars = calendars; self.events = events }
    func requestAccess() async throws {}
    func calendarAllowsModifications(identifier: String) async -> Bool? { calendars[identifier] }
    func event(identifier: String) async -> EventKitMutationEventSnapshot? { events[identifier] }
    func save(_ event: EventKitMutationEventSnapshot, span: EventKitMutationSpan, recurrence: EventKitRecurrenceMutation) async throws -> EventKitMutationEventSnapshot {
        var value = event
        if value.identifier.isEmpty { value.identifier = "created" }
        value.lastModifiedDate = Date(timeIntervalSince1970: 40)
        savedSpans.append(span)
        savedRecurrences.append(recurrence)
        savedOccurrenceDates.append(value.occurrenceDate)
        events[value.identifier] = value
        return value
    }
    func remove(identifier: String, occurrenceDate: Date?, span: EventKitMutationSpan) async throws {
        removedSpans.append(span)
        removedOccurrenceDates.append(occurrenceDate)
        events.removeValue(forKey: identifier)
    }
    var lastSavedSpan: EventKitMutationSpan? { savedSpans.last }
    var lastSavedRecurrence: EventKitRecurrenceMutation? { savedRecurrences.last }
    var lastSavedOccurrenceDate: Date? { savedOccurrenceDates.last ?? nil }
    var lastRemovedSpan: EventKitMutationSpan? { removedSpans.last }
    var lastRemovedOccurrenceDate: Date? { removedOccurrenceDates.last ?? nil }
}
