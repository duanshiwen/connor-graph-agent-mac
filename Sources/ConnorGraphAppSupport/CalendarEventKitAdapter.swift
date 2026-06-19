import Foundation
import EventKit
import CoreGraphics
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

public struct CalendarEventKitSnapshot: Sendable, Equatable {
    public var accounts: [CalendarAccount]
    public var collections: [CalendarCollection]
    public var events: [CalendarEvent]

    public init(accounts: [CalendarAccount], collections: [CalendarCollection], events: [CalendarEvent]) {
        self.accounts = accounts
        self.collections = collections
        self.events = events
    }
}

public enum CalendarEventKitAdapterError: LocalizedError, Sendable, Equatable {
    case accessDenied

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "未获得日历访问权限。请在系统设置中允许康纳同学访问日历。"
        }
    }
}

public struct CalendarEventKitAdapter: Sendable {
    public init() {}

    public static let systemAccountID = CalendarAccountID(rawValue: "calendar-account-macos-eventkit")

    public static func fetchSystemSnapshot(daysBack: Int = 7, daysForward: Int = 90) async throws -> CalendarEventKitSnapshot {
        let store = EKEventStore()
        let granted = try await requestCalendarAccess(store: store)
        guard granted else { throw CalendarEventKitAdapterError.accessDenied }

        let calendars = store.calendars(for: .event)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let now = Date()
        let account = CalendarAccount(
            id: systemAccountID,
            provider: .localFixture,
            displayName: "本机日历",
            health: CalendarAccountHealth(status: .ready, checkedAt: now, summary: "已同步 macOS Calendar / EventKit"),
            createdAt: now,
            updatedAt: now
        )
        let collections = calendars.map { collection(calendar: $0) }
        let intervalStart = Calendar.current.date(byAdding: .day, value: -max(0, daysBack), to: now) ?? now
        let intervalEnd = Calendar.current.date(byAdding: .day, value: max(1, daysForward), to: now) ?? now.addingTimeInterval(90 * 24 * 60 * 60)
        let predicate = store.predicateForEvents(withStart: intervalStart, end: intervalEnd, calendars: calendars)
        let events = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { map(snapshot: snapshot(event: $0)) }
        return CalendarEventKitSnapshot(accounts: [account], collections: collections, events: events)
    }

    public static func requestCalendarAccess(store: EKEventStore) async throws -> Bool {
        if #available(macOS 14.0, *) {
            return try await store.requestFullAccessToEvents()
        } else {
            return try await withCheckedThrowingContinuation { continuation in
                store.requestAccess(to: .event) { granted, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }

    public static func collection(calendar: EKCalendar) -> CalendarCollection {
        CalendarCollection(
            id: CalendarID(rawValue: calendar.calendarIdentifier),
            accountID: systemAccountID,
            displayName: calendar.title,
            colorHex: hexColor(calendar.cgColor),
            isReadOnly: !calendar.allowsContentModifications,
            source: "eventkit"
        )
    }

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

    private static func hexColor(_ color: CGColor?) -> String? {
        guard let color else { return nil }
        guard let converted = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
              let components = converted.components else { return nil }
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        switch components.count {
        case 2:
            red = components[0]
            green = components[0]
            blue = components[0]
        case 3, 4:
            red = components[0]
            green = components[1]
            blue = components[2]
        default:
            return nil
        }
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}
