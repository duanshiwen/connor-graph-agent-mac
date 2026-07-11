import Foundation
import ConnorGraphCore

public enum ICalendarEventSerializerError: Error, Sendable, Equatable {
    case invalidTimeRange
    case invalidTimeZone(String)
}

public struct ICalendarEventSerializer: Sendable {
    public init() {}

    public func serialize(draft: CalendarEventDraft, uid: String, timestamp: Date = Date()) throws -> String {
        guard draft.end.date > draft.start.date else { throw ICalendarEventSerializerError.invalidTimeRange }
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Connor//Calendar Agent//EN", "CALSCALE:GREGORIAN", "BEGIN:VEVENT", "UID:\(escape(uid))", "DTSTAMP:\(utc(timestamp))", "CREATED:\(utc(timestamp))", "LAST-MODIFIED:\(utc(timestamp))"]
        if draft.isAllDay {
            lines.append("DTSTART;VALUE=DATE:\(try dateOnly(draft.start))")
            lines.append("DTEND;VALUE=DATE:\(try dateOnly(draft.end))")
        } else {
            lines.append(try dateTimeLine("DTSTART", value: draft.start))
            lines.append(try dateTimeLine("DTEND", value: draft.end))
        }
        lines.append("SUMMARY:\(escape(draft.title))")
        if let location = draft.location { lines.append("LOCATION:\(escape(location))") }
        if let notes = draft.notes { lines.append("DESCRIPTION:\(escape(notes))") }
        if let url = draft.url { lines.append("URL:\(url.absoluteString)") }
        lines.append("END:VEVENT")
        lines.append("END:VCALENDAR")
        return lines.flatMap(fold).joined(separator: "\r\n") + "\r\n"
    }

    private func dateTimeLine(_ name: String, value: CalendarEventDateTime) throws -> String {
        guard let identifier = value.timeZoneIdentifier else { return "\(name):\(utc(value.date))" }
        guard let zone = TimeZone(identifier: identifier) else { throw ICalendarEventSerializerError.invalidTimeZone(identifier) }
        return "\(name);TZID=\(identifier):\(local(value.date, timeZone: zone, dateOnly: false))"
    }

    private func dateOnly(_ value: CalendarEventDateTime) throws -> String {
        let zone: TimeZone
        if let identifier = value.timeZoneIdentifier {
            guard let resolved = TimeZone(identifier: identifier) else { throw ICalendarEventSerializerError.invalidTimeZone(identifier) }
            zone = resolved
        } else { zone = TimeZone(secondsFromGMT: 0)! }
        return local(value.date, timeZone: zone, dateOnly: true)
    }

    private func utc(_ date: Date) -> String { local(date, timeZone: TimeZone(secondsFromGMT: 0)!, dateOnly: false) + "Z" }

    private func local(_ date: Date, timeZone: TimeZone, dateOnly: Bool) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = dateOnly ? "yyyyMMdd" : "yyyyMMdd'T'HHmmss"
        return formatter.string(from: date)
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\r\n", with: "\\n").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\n").replacingOccurrences(of: ";", with: "\\;").replacingOccurrences(of: ",", with: "\\,")
    }

    private func fold(_ line: String) -> [String] {
        guard line.utf8.count > 75 else { return [line] }
        var result: [String] = []
        var current = ""
        var limit = 75
        for character in line {
            let bytes = String(character).utf8.count
            if current.utf8.count + bytes > limit {
                result.append(current)
                current = " " + String(character)
                limit = 75
            } else { current.append(character) }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
