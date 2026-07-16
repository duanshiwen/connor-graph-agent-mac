import Foundation
import ConnorGraphCore

public struct NativeCalendarBrowserPresentation: Sendable, Equatable {
    public var daySections: [NativeCalendarDaySectionPresentation]
    public var eventCount: Int
    public var emptyMessage: String?

    public static let empty = NativeCalendarBrowserPresentation(daySections: [], eventCount: 0, emptyMessage: "暂无日程")

    public init(daySections: [NativeCalendarDaySectionPresentation], eventCount: Int, emptyMessage: String? = nil) {
        self.daySections = daySections
        self.eventCount = eventCount
        self.emptyMessage = emptyMessage
    }

    public static func build(events: [CalendarEvent], collections: [CalendarCollection] = [], calendar: Calendar = .current, timeZone: TimeZone = .current) -> NativeCalendarBrowserPresentation {
        guard !events.isEmpty else { return .empty }
        var calendar = calendar
        calendar.timeZone = timeZone
        let calendarNamesByID = Dictionary(uniqueKeysWithValues: collections.map { ($0.id, $0.displayName) })
        let grouped = Dictionary(grouping: events.sorted { $0.start.date < $1.start.date }) { event in
            calendar.startOfDay(for: event.start.date)
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日 EEEE"

        let sections = grouped.keys.sorted().map { day in
            NativeCalendarDaySectionPresentation(
                id: ISO8601DateFormatter().string(from: day),
                title: formatter.string(from: day),
                events: (grouped[day] ?? []).map {
                    NativeCalendarEventRowPresentation(
                        event: $0,
                        calendarName: calendarNamesByID[$0.calendarID],
                        timeZone: timeZone
                    )
                }
            )
        }
        return NativeCalendarBrowserPresentation(daySections: sections, eventCount: events.count)
    }
}

public struct NativeCalendarDaySectionPresentation: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var events: [NativeCalendarEventRowPresentation]

    public init(id: String, title: String, events: [NativeCalendarEventRowPresentation]) {
        self.id = id
        self.title = title
        self.events = events
    }
}

public struct NativeCalendarEventRowPresentation: Sendable, Equatable, Identifiable {
    public var id: CalendarEventID
    public var title: String
    public var timeText: String
    public var calendarName: String?
    public var location: String?

    public init(id: CalendarEventID, title: String, timeText: String, calendarName: String? = nil, location: String? = nil) {
        self.id = id
        self.title = title
        self.timeText = timeText
        self.calendarName = calendarName
        self.location = location
    }

    public init(event: CalendarEvent, calendarName: String? = nil, timeZone: TimeZone = .current) {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        self.init(
            id: event.id,
            title: event.title,
            timeText: event.isAllDay ? "全天" : "\(formatter.string(from: event.start.date))–\(formatter.string(from: event.end.date))",
            calendarName: calendarName,
            location: event.location
        )
    }
}
