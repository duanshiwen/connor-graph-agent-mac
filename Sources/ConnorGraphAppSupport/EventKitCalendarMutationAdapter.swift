import Foundation
import EventKit
import ConnorGraphCore

public struct EventKitMutationEventSnapshot: Sendable, Equatable {
    public var identifier: String; public var calendarIdentifier: String; public var title: String; public var startDate: Date; public var endDate: Date; public var isAllDay: Bool; public var location: String?; public var url: URL?; public var notes: String?; public var lastModifiedDate: Date?; public var isRecurring: Bool; public var hasAttendees: Bool
    public var recurrenceRule: String?
    public var occurrenceDate: Date?
    public init(identifier: String, calendarIdentifier: String, title: String, startDate: Date, endDate: Date, isAllDay: Bool, location: String? = nil, url: URL? = nil, notes: String? = nil, lastModifiedDate: Date? = nil, isRecurring: Bool = false, hasAttendees: Bool = false, recurrenceRule: String? = nil, occurrenceDate: Date? = nil) { self.identifier = identifier; self.calendarIdentifier = calendarIdentifier; self.title = title; self.startDate = startDate; self.endDate = endDate; self.isAllDay = isAllDay; self.location = location; self.url = url; self.notes = notes; self.lastModifiedDate = lastModifiedDate; self.isRecurring = isRecurring; self.hasAttendees = hasAttendees; self.recurrenceRule = recurrenceRule; self.occurrenceDate = occurrenceDate }
}

/// 与 EKSpan 对应的写入范围；entireSeries 会落到主事件（master）上。
public enum EventKitMutationSpan: String, Sendable, Equatable {
    case thisEvent
    case futureEvents
}

/// 保存事件时对周期规则的处理方式。
public enum EventKitRecurrenceMutation: Sendable, Equatable {
    case keep
    case set(String)
    case clear
}

public protocol EventKitMutationClient: Sendable {
    func requestAccess() async throws
    func calendarAllowsModifications(identifier: String) async -> Bool?
    func event(identifier: String) async -> EventKitMutationEventSnapshot?
    func save(_ event: EventKitMutationEventSnapshot, span: EventKitMutationSpan, recurrence: EventKitRecurrenceMutation) async throws -> EventKitMutationEventSnapshot
    func remove(identifier: String, occurrenceDate: Date?, span: EventKitMutationSpan) async throws
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
    public func save(_ value: EventKitMutationEventSnapshot, span: EventKitMutationSpan, recurrence: EventKitRecurrenceMutation) async throws -> EventKitMutationEventSnapshot {
        let event: EKEvent
        if value.identifier.isEmpty {
            event = EKEvent(eventStore: store)
        } else if let occurrenceDate = value.occurrenceDate, let occurrence = occurrenceEvent(identifier: value.identifier, occurrenceDate: occurrenceDate) {
            event = occurrence
        } else {
            event = store.event(withIdentifier: value.identifier) ?? EKEvent(eventStore: store)
        }
        guard let calendar = store.calendar(withIdentifier: value.calendarIdentifier) else { throw CalendarMutationError.readOnlyCollection(nil) }
        event.calendar = calendar; event.title = value.title; event.startDate = value.startDate; event.endDate = value.endDate; event.isAllDay = value.isAllDay; event.location = value.location; event.url = value.url; event.notes = value.notes
        switch recurrence {
        case .keep:
            break
        case .set(let rrule):
            guard let rule = Self.recurrenceRule(from: rrule) else { throw CalendarMutationError.invalidInput("Unsupported recurrence rule: \(rrule)") }
            event.recurrenceRules = [rule]
        case .clear:
            event.recurrenceRules = []
        }
        try store.save(event, span: span == .thisEvent ? .thisEvent : .futureEvents, commit: true)
        guard let id = event.eventIdentifier, let confirmed = store.event(withIdentifier: id) else { throw CalendarMutationError.verificationFailed }
        return snapshot(confirmed)
    }
    public func remove(identifier: String, occurrenceDate: Date?, span: EventKitMutationSpan) async throws {
        guard let event = store.event(withIdentifier: identifier) else { return }
        let target = occurrenceDate.flatMap { occurrenceEvent(identifier: identifier, occurrenceDate: $0) } ?? event
        try store.remove(target, span: span == .thisEvent ? .thisEvent : .futureEvents, commit: true)
    }
    private func occurrenceEvent(identifier: String, occurrenceDate: Date) -> EKEvent? {
        guard let master = store.event(withIdentifier: identifier) else { return nil }
        let start = occurrenceDate.addingTimeInterval(-60)
        let end = occurrenceDate.addingTimeInterval(60)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [master.calendar])
        return store.events(matching: predicate).first {
            $0.eventIdentifier == identifier && $0.occurrenceDate == occurrenceDate
        }
    }
    private func snapshot(_ event: EKEvent) -> EventKitMutationEventSnapshot { .init(identifier: event.eventIdentifier ?? "", calendarIdentifier: event.calendar.calendarIdentifier, title: event.title ?? "Untitled", startDate: event.startDate, endDate: event.endDate, isAllDay: event.isAllDay, location: event.location, url: event.url, notes: event.notes, lastModifiedDate: event.lastModifiedDate, isRecurring: event.hasRecurrenceRules, hasAttendees: !(event.attendees?.isEmpty ?? true), recurrenceRule: event.recurrenceRules?.first.map(Self.rruleString(from:))) }

    static func rruleString(from rule: EKRecurrenceRule) -> String {
        let frequency: String
        switch rule.frequency {
        case .daily: frequency = "DAILY"
        case .weekly: frequency = "WEEKLY"
        case .monthly: frequency = "MONTHLY"
        case .yearly: frequency = "YEARLY"
        @unknown default: frequency = "DAILY"
        }
        var parts = ["FREQ=\(frequency)"]
        if rule.interval > 1 { parts.append("INTERVAL=\(rule.interval)") }
        if let end = rule.recurrenceEnd {
            if let date = end.endDate {
                parts.append("UNTIL=\(utc(date))")
            } else if end.occurrenceCount > 0 {
                parts.append("COUNT=\(end.occurrenceCount)")
            }
        }
        return parts.joined(separator: ";")
    }

    static func recurrenceRule(from rrule: String) -> EKRecurrenceRule? {
        var frequency: EKRecurrenceFrequency?
        var interval = 1
        var end: EKRecurrenceEnd?
        for part in rrule.components(separatedBy: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            switch pair[0].uppercased() {
            case "FREQ":
                switch pair[1].uppercased() {
                case "DAILY": frequency = .daily
                case "WEEKLY": frequency = .weekly
                case "MONTHLY": frequency = .monthly
                case "YEARLY": frequency = .yearly
                default: return nil
                }
            case "INTERVAL":
                interval = Int(pair[1]) ?? 1
            case "COUNT":
                if let count = Int(pair[1]), count > 0 { end = .init(occurrenceCount: count) }
            case "UNTIL":
                if let date = utcDate(pair[1]) { end = .init(end: date) }
            default:
                break
            }
        }
        guard let frequency else { return nil }
        return EKRecurrenceRule(recurrenceWith: frequency, interval: max(1, interval), end: end)
    }

    private static func utc(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func utcDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.date(from: value.replacingOccurrences(of: "'", with: "").uppercased())
    }
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
            let recurrence = d.recurrence.flatMap(\.rruleString)
            return result(try await client.save(.init(identifier: "", calendarIdentifier: d.calendarID.rawValue, title: d.title, startDate: d.start.date, endDate: d.end.date, isAllDay: d.isAllDay, location: d.location, url: d.url, notes: d.notes, recurrenceRule: recurrence), span: .thisEvent, recurrence: recurrence.map(EventKitRecurrenceMutation.set) ?? .keep), kind: .createEvent)
        case .update:
            guard let currentEvent, let remoteID = currentEvent.sourceMetadata?.remoteIdentifier ?? request.eventID?.rawValue, let remote = await client.event(identifier: remoteID), let patch = request.patch else { throw CalendarMutationError.eventNotFound }
            try protect(remote)
            let actual = version(remote)
            guard actual == request.expectedVersion?.value else { throw CalendarMutationError.conflict(expected: request.expectedVersion?.value, actual: actual) }
            var updated = remote
            apply(patch.title, to: &updated.title); apply(patch.start, to: &updated.startDate, transform: { $0.date }); apply(patch.end, to: &updated.endDate, transform: { $0.date }); apply(patch.isAllDay, to: &updated.isAllDay); applyOptional(patch.location, to: &updated.location); applyOptional(patch.url, to: &updated.url); applyOptional(patch.notes, to: &updated.notes)
            guard updated.endDate > updated.startDate else { throw CalendarMutationError.invalidInput("end must be after start") }
            let recurrenceChange: EventKitRecurrenceMutation
            switch patch.recurrence {
            case .unchanged:
                recurrenceChange = .keep
            case .clear:
                updated.recurrenceRule = nil
                recurrenceChange = .clear
            case .set(let recurrence):
                guard let rrule = recurrence.rruleString else { throw CalendarMutationError.invalidInput("invalid recurrence rule") }
                updated.recurrenceRule = rrule
                recurrenceChange = .set(rrule)
            }
            let (span, occurrenceDate) = eventKitSpan(for: request.scope, occurrenceDate: request.occurrenceDate)
            updated.occurrenceDate = occurrenceDate
            return result(try await client.save(updated, span: span, recurrence: recurrenceChange), kind: .updateEvent)
        case .delete:
            guard let currentEvent, let remoteID = currentEvent.sourceMetadata?.remoteIdentifier ?? request.eventID?.rawValue, let remote = await client.event(identifier: remoteID) else { throw CalendarMutationError.eventNotFound }
            try protect(remote); let actual = version(remote); guard actual == request.expectedVersion?.value else { throw CalendarMutationError.conflict(expected: request.expectedVersion?.value, actual: actual) }
            let (span, occurrenceDate) = eventKitSpan(for: request.scope, occurrenceDate: request.occurrenceDate)
            try await client.remove(identifier: remoteID, occurrenceDate: occurrenceDate, span: span)
            return CalendarMutationResult(receipt: .init(mutationKind: .deleteEvent, eventID: currentEvent.id, approved: true, summary: "Deleted calendar event \(currentEvent.id.rawValue)"))
        }
    }
    private func protect(_ event: EventKitMutationEventSnapshot) throws { if event.hasAttendees { throw CalendarMutationError.schedulingUnsupported } }
    private func eventKitSpan(for scope: CalendarMutationScope, occurrenceDate: Date?) -> (EventKitMutationSpan, Date?) {
        switch scope {
        case .thisEvent:
            return (.thisEvent, occurrenceDate)
        case .futureEvents:
            return (.futureEvents, occurrenceDate)
        case .entireSeries:
            return (.thisEvent, nil)
        }
    }
    private func version(_ event: EventKitMutationEventSnapshot) -> String { String(event.lastModifiedDate?.timeIntervalSince1970 ?? 0) }
    private func result(_ value: EventKitMutationEventSnapshot, kind: CalendarMutationKind) -> CalendarMutationResult { let v = version(value); let event = CalendarEvent(id: .init(rawValue: value.identifier), calendarID: .init(rawValue: value.calendarIdentifier), title: value.title, start: .init(date: value.startDate), end: .init(date: value.endDate), isAllDay: value.isAllDay, location: value.location, url: value.url, notes: value.notes, recurrenceSummary: value.recurrenceRule.map(CalendarRecurrenceSummary.init(ruleDescription:)), sourceMetadata: .init(sourceKind: .macOSEventKit, remoteIdentifier: value.identifier, etag: v, isRecurring: value.isRecurring || value.recurrenceRule != nil, hasAttendees: value.hasAttendees), updatedAt: value.lastModifiedDate ?? Date()); return .init(receipt: .init(mutationKind: kind, eventID: event.id, approved: true, summary: kind == .createEvent ? "Created calendar event \(event.id.rawValue)" : "Updated calendar event \(event.id.rawValue)"), confirmedEvent: event, remoteVersion: .init(value: v)) }
    private func apply<T>(_ p: CalendarPatchValue<T>, to v: inout T) { if case .set(let x) = p { v = x } }
    private func apply<A,B>(_ p: CalendarPatchValue<A>, to v: inout B, transform: (A) -> B) { if case .set(let x) = p { v = transform(x) } }
    private func applyOptional<T>(_ p: CalendarPatchValue<T>, to v: inout T?) { switch p { case .unchanged: break; case .clear: v = nil; case .set(let x): v = x } }
}
