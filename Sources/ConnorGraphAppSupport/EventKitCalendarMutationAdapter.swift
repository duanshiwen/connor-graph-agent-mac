import Foundation
import EventKit
import ConnorGraphCore

public struct EventKitMutationEventSnapshot: Sendable, Equatable {
    public var identifier: String; public var calendarIdentifier: String; public var title: String; public var startDate: Date; public var endDate: Date; public var isAllDay: Bool; public var location: String?; public var url: URL?; public var notes: String?; public var lastModifiedDate: Date?; public var isRecurring: Bool; public var hasAttendees: Bool
    public init(identifier: String, calendarIdentifier: String, title: String, startDate: Date, endDate: Date, isAllDay: Bool, location: String? = nil, url: URL? = nil, notes: String? = nil, lastModifiedDate: Date? = nil, isRecurring: Bool = false, hasAttendees: Bool = false) { self.identifier = identifier; self.calendarIdentifier = calendarIdentifier; self.title = title; self.startDate = startDate; self.endDate = endDate; self.isAllDay = isAllDay; self.location = location; self.url = url; self.notes = notes; self.lastModifiedDate = lastModifiedDate; self.isRecurring = isRecurring; self.hasAttendees = hasAttendees }
}

public protocol EventKitMutationClient: Sendable {
    func requestAccess() async throws
    func calendarAllowsModifications(identifier: String) async -> Bool?
    func event(identifier: String) async -> EventKitMutationEventSnapshot?
    func save(_ event: EventKitMutationEventSnapshot) async throws -> EventKitMutationEventSnapshot
    func remove(identifier: String) async throws
}

public actor SystemEventKitMutationClient: EventKitMutationClient {
    private let store = EKEventStore()
    public init() {}
    public func requestAccess() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess { return }
        if status == .denied || status == .restricted { throw CalendarMutationError.permissionDenied }
        guard try await store.requestFullAccessToEvents() else { throw CalendarMutationError.permissionDenied }
    }
    public func calendarAllowsModifications(identifier: String) async -> Bool? { store.calendar(withIdentifier: identifier)?.allowsContentModifications }
    public func event(identifier: String) async -> EventKitMutationEventSnapshot? { store.event(withIdentifier: identifier).map(snapshot) }
    public func save(_ value: EventKitMutationEventSnapshot) async throws -> EventKitMutationEventSnapshot {
        let event = value.identifier.isEmpty ? EKEvent(eventStore: store) : (store.event(withIdentifier: value.identifier) ?? EKEvent(eventStore: store))
        guard let calendar = store.calendar(withIdentifier: value.calendarIdentifier) else { throw CalendarMutationError.readOnlyCollection(nil) }
        event.calendar = calendar; event.title = value.title; event.startDate = value.startDate; event.endDate = value.endDate; event.isAllDay = value.isAllDay; event.location = value.location; event.url = value.url; event.notes = value.notes
        try store.save(event, span: .thisEvent, commit: true)
        guard let id = event.eventIdentifier, let confirmed = store.event(withIdentifier: id) else { throw CalendarMutationError.verificationFailed }
        return snapshot(confirmed)
    }
    public func remove(identifier: String) async throws { guard let event = store.event(withIdentifier: identifier) else { return }; try store.remove(event, span: .thisEvent, commit: true) }
    private func snapshot(_ event: EKEvent) -> EventKitMutationEventSnapshot { .init(identifier: event.eventIdentifier ?? "", calendarIdentifier: event.calendar.calendarIdentifier, title: event.title ?? "Untitled", startDate: event.startDate, endDate: event.endDate, isAllDay: event.isAllDay, location: event.location, url: event.url, notes: event.notes, lastModifiedDate: event.lastModifiedDate, isRecurring: event.hasRecurrenceRules, hasAttendees: !(event.attendees?.isEmpty ?? true)) }
}

public struct EventKitCalendarMutationAdapter: CalendarMutationAdapter, Sendable {
    private let client: any EventKitMutationClient
    public init(client: any EventKitMutationClient = SystemEventKitMutationClient()) { self.client = client }
    public func mutate(_ request: CalendarMutationRequest, account: CalendarAccount, collection: CalendarCollection?, currentEvent: CalendarEvent?) async throws -> CalendarMutationResult {
        try await client.requestAccess()
        guard let collection, await client.calendarAllowsModifications(identifier: collection.id.rawValue) == true else { throw CalendarMutationError.readOnlyCollection(nil) }
        switch request.operation {
        case .create:
            guard let d = request.draft else { throw CalendarMutationError.invalidInput("draft required") }
            return result(try await client.save(.init(identifier: "", calendarIdentifier: d.calendarID.rawValue, title: d.title, startDate: d.start.date, endDate: d.end.date, isAllDay: d.isAllDay, location: d.location, url: d.url, notes: d.notes)), kind: .createEvent)
        case .update:
            guard let currentEvent, let remoteID = currentEvent.sourceMetadata?.remoteIdentifier ?? request.eventID?.rawValue, let remote = await client.event(identifier: remoteID), let patch = request.patch else { throw CalendarMutationError.eventNotFound }
            try protect(remote)
            let actual = version(remote)
            guard actual == request.expectedVersion?.value else { throw CalendarMutationError.conflict(expected: request.expectedVersion?.value, actual: actual) }
            var updated = remote
            apply(patch.title, to: &updated.title); apply(patch.start, to: &updated.startDate, transform: { $0.date }); apply(patch.end, to: &updated.endDate, transform: { $0.date }); apply(patch.isAllDay, to: &updated.isAllDay); applyOptional(patch.location, to: &updated.location); applyOptional(patch.url, to: &updated.url); applyOptional(patch.notes, to: &updated.notes)
            guard updated.endDate > updated.startDate else { throw CalendarMutationError.invalidInput("end must be after start") }
            return result(try await client.save(updated), kind: .updateEvent)
        case .delete:
            guard let currentEvent, let remoteID = currentEvent.sourceMetadata?.remoteIdentifier ?? request.eventID?.rawValue, let remote = await client.event(identifier: remoteID) else { throw CalendarMutationError.eventNotFound }
            try protect(remote); let actual = version(remote); guard actual == request.expectedVersion?.value else { throw CalendarMutationError.conflict(expected: request.expectedVersion?.value, actual: actual) }
            try await client.remove(identifier: remoteID)
            return CalendarMutationResult(receipt: .init(mutationKind: .deleteEvent, eventID: currentEvent.id, approved: true, summary: "Deleted calendar event \(currentEvent.id.rawValue)"))
        }
    }
    private func protect(_ event: EventKitMutationEventSnapshot) throws { if event.isRecurring { throw CalendarMutationError.recurrenceUnsupported }; if event.hasAttendees { throw CalendarMutationError.schedulingUnsupported } }
    private func version(_ event: EventKitMutationEventSnapshot) -> String { String(event.lastModifiedDate?.timeIntervalSince1970 ?? 0) }
    private func result(_ value: EventKitMutationEventSnapshot, kind: CalendarMutationKind) -> CalendarMutationResult { let v = version(value); let event = CalendarEvent(id: .init(rawValue: value.identifier), calendarID: .init(rawValue: value.calendarIdentifier), title: value.title, start: .init(date: value.startDate), end: .init(date: value.endDate), isAllDay: value.isAllDay, location: value.location, url: value.url, notes: value.notes, sourceMetadata: .init(sourceKind: .macOSEventKit, remoteIdentifier: value.identifier, etag: v, isRecurring: value.isRecurring, hasAttendees: value.hasAttendees), updatedAt: value.lastModifiedDate ?? Date()); return .init(receipt: .init(mutationKind: kind, eventID: event.id, approved: true, summary: kind == .createEvent ? "Created calendar event \(event.id.rawValue)" : "Updated calendar event \(event.id.rawValue)"), confirmedEvent: event, remoteVersion: .init(value: v)) }
    private func apply<T>(_ p: CalendarPatchValue<T>, to v: inout T) { if case .set(let x) = p { v = x } }
    private func apply<A,B>(_ p: CalendarPatchValue<A>, to v: inout B, transform: (A) -> B) { if case .set(let x) = p { v = transform(x) } }
    private func applyOptional<T>(_ p: CalendarPatchValue<T>, to v: inout T?) { switch p { case .unchanged: break; case .clear: v = nil; case .set(let x): v = x } }
}
