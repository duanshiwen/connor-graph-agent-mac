import Foundation

public enum ICalendarParserError: Error, Sendable, Equatable {
    case invalidDate(String)
}

public struct ICalendarEvent: Sendable, Equatable {
    public struct DateTime: Sendable, Equatable {
        public var date: Date
        public var timeZoneIdentifier: String?

        public init(date: Date, timeZoneIdentifier: String? = nil) {
            self.date = date
            self.timeZoneIdentifier = timeZoneIdentifier
        }
    }

    public var uid: String
    public var summary: String
    public var start: DateTime
    public var end: DateTime?
    public var isAllDay: Bool
    public var location: String?
    public var description: String?
    public var url: URL?
    public var recurrenceRule: String?
    public var lastModified: Date?

    public init(uid: String, summary: String, start: DateTime, end: DateTime? = nil, isAllDay: Bool = false, location: String? = nil, description: String? = nil, url: URL? = nil, recurrenceRule: String? = nil, lastModified: Date? = nil) {
        self.uid = uid
        self.summary = summary
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.description = description
        self.url = url
        self.recurrenceRule = recurrenceRule
        self.lastModified = lastModified
    }
}

public struct ICalendarParser: Sendable {
    public init() {}

    public func events(from ics: String) throws -> [ICalendarEvent] {
        let lines = unfold(ics)
        var events: [ICalendarEvent] = []
        var current: [ICalendarProperty] = []
        var insideEvent = false

        for line in lines {
            if line.uppercased() == "BEGIN:VEVENT" {
                insideEvent = true
                current = []
                continue
            }
            if line.uppercased() == "END:VEVENT" {
                if let event = try buildEvent(from: current) { events.append(event) }
                insideEvent = false
                current = []
                continue
            }
            if insideEvent, let property = ICalendarProperty(line: line) {
                current.append(property)
            }
        }
        return events
    }

    private func unfold(_ ics: String) -> [String] {
        var unfolded: [String] = []
        for rawLine in ics.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                guard !unfolded.isEmpty else { continue }
                unfolded[unfolded.count - 1] += String(line.dropFirst())
            } else {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { unfolded.append(trimmed) }
            }
        }
        return unfolded
    }

    private func buildEvent(from properties: [ICalendarProperty]) throws -> ICalendarEvent? {
        guard let uid = value("UID", in: properties) else { return nil }
        let summary = value("SUMMARY", in: properties) ?? "Untitled"
        guard let startProperty = property("DTSTART", in: properties) else { return nil }
        let start = try parseDateTime(startProperty)
        let end = try property("DTEND", in: properties).map(parseDateTime)
        return ICalendarEvent(
            uid: uid,
            summary: summary,
            start: start.value,
            end: end?.value,
            isAllDay: start.isAllDay,
            location: value("LOCATION", in: properties),
            description: value("DESCRIPTION", in: properties),
            url: value("URL", in: properties).flatMap(URL.init(string:)),
            recurrenceRule: value("RRULE", in: properties),
            lastModified: try property("LAST-MODIFIED", in: properties).map { try parseDateTime($0).value.date }
        )
    }

    private func property(_ name: String, in properties: [ICalendarProperty]) -> ICalendarProperty? {
        properties.first { $0.name.uppercased() == name }
    }

    private func value(_ name: String, in properties: [ICalendarProperty]) -> String? {
        property(name, in: properties)?.value
    }

    private func parseDateTime(_ property: ICalendarProperty) throws -> (value: ICalendarEvent.DateTime, isAllDay: Bool) {
        let raw = property.value
        let isAllDay = property.parameters["VALUE"]?.uppercased() == "DATE" || (raw.count == 8 && !raw.contains("T"))
        if isAllDay {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd"
            guard let date = formatter.date(from: raw) else { throw ICalendarParserError.invalidDate(raw) }
            return (ICalendarEvent.DateTime(date: date, timeZoneIdentifier: property.parameters["TZID"]), true)
        }

        let timeZoneIdentifier = property.parameters["TZID"]
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = raw.hasSuffix("Z") ? TimeZone(secondsFromGMT: 0) : timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = raw.hasSuffix("Z") ? "yyyyMMdd'T'HHmmss'Z'" : "yyyyMMdd'T'HHmmss"
        guard let date = formatter.date(from: raw) else { throw ICalendarParserError.invalidDate(raw) }
        return (ICalendarEvent.DateTime(date: date, timeZoneIdentifier: timeZoneIdentifier), false)
    }
}

private struct ICalendarProperty: Sendable, Equatable {
    var name: String
    var parameters: [String: String]
    var value: String

    init?(line: String) {
        guard let separator = line.firstIndex(of: ":") else { return nil }
        let head = String(line[..<separator])
        value = String(line[line.index(after: separator)...])
        let parts = head.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard let first = parts.first else { return nil }
        name = first.uppercased()
        var parsedParameters: [String: String] = [:]
        for parameter in parts.dropFirst() {
            guard let equal = parameter.firstIndex(of: "=") else { continue }
            let key = String(parameter[..<equal]).uppercased()
            let value = String(parameter[parameter.index(after: equal)...])
            parsedParameters[key] = value
        }
        parameters = parsedParameters
    }
}
