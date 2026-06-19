import Foundation
import EventKit
import ConnorGraphCore

public struct CalendarSystemEventSnapshot: Sendable, Equatable {
    public var identifier: String
    public var calendarIdentifier: String
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var location: String?
    public var notes: String?

    public init(identifier: String, calendarIdentifier: String, title: String, startDate: Date, endDate: Date, isAllDay: Bool, location: String? = nil, notes: String? = nil) {
        self.identifier = identifier
        self.calendarIdentifier = calendarIdentifier
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
    }
}

public struct CalendarEventKitAdapter: Sendable {
    public init() {}

    public static func map(snapshot: CalendarSystemEventSnapshot) -> CalendarEvent {
        CalendarEvent(
            id: CalendarEventID(rawValue: snapshot.identifier),
            calendarID: CalendarID(rawValue: snapshot.calendarIdentifier),
            title: snapshot.title,
            start: CalendarEventDateTime(date: snapshot.startDate),
            end: CalendarEventDateTime(date: snapshot.endDate),
            isAllDay: snapshot.isAllDay,
            location: snapshot.location,
            notes: snapshot.notes
        )
    }

    public static func snapshot(event: EKEvent) -> CalendarSystemEventSnapshot {
        CalendarSystemEventSnapshot(
            identifier: event.eventIdentifier ?? UUID().uuidString,
            calendarIdentifier: event.calendar.calendarIdentifier,
            title: event.title ?? "Untitled",
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location,
            notes: event.notes
        )
    }
}
