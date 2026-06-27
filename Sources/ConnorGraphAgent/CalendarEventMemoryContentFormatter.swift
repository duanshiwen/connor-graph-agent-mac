import Foundation
import ConnorGraphCore

public enum CalendarEventMemoryContentFormatter {
    public static func format(event: CalendarEvent) -> String {
        format(
            title: event.title,
            start: event.start.date,
            end: event.end.date,
            location: event.location,
            notes: event.notes,
            attendees: event.attendees.map { attendee in attendee.email ?? attendee.name ?? attendee.id.rawValue }
        )
    }

    public static func format(
        title: String,
        start: Date? = nil,
        end: Date? = nil,
        location: String? = nil,
        notes: String? = nil,
        attendees: [String] = []
    ) -> String {
        let formatter = ISO8601DateFormatter()
        return """
        Title: \(title)
        Start: \(start.map { formatter.string(from: $0) } ?? "")
        End: \(end.map { formatter.string(from: $0) } ?? "")
        Location: \(location ?? "")
        Notes: \(notes ?? "")
        Attendees: \(attendees.joined(separator: ", "))
        """
    }
}
