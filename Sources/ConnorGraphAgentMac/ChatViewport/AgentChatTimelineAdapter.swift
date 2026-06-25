import Foundation
import ConnorGraphAppSupport

enum CommercialChatItemKind: String, Equatable {
    case message
    case process
    case timestamp
    case system
    case unreadSeparator
    case dateSeparator
}

struct CommercialChatUnreadBoundary: Equatable {
    var beforeItemID: String
    var unreadCount: Int

    var markerID: String { "unread-boundary-before-\(beforeItemID)" }
}

struct CommercialChatUnreadMarker: Equatable {
    var unreadCount: Int
}

struct CommercialChatDateSeparator: Equatable {
    var date: Date
    var title: String
    var dayIdentifier: String

    var separatorID: String { "date-section-\(dayIdentifier)" }
}

struct CommercialChatItem: Identifiable, Equatable {
    var id: String
    var kind: CommercialChatItemKind
    var timelineItem: AgentChatTurnTimelineItem?
    var unreadMarker: CommercialChatUnreadMarker?
    var dateSeparator: CommercialChatDateSeparator?

    static func timeline(_ item: AgentChatTurnTimelineItem) -> CommercialChatItem {
        let kind: CommercialChatItemKind
        if item.message != nil {
            kind = .message
        } else if item.process != nil {
            kind = .process
        } else if item.timestamp != nil {
            kind = .timestamp
        } else {
            kind = .system
        }
        return CommercialChatItem(id: item.id, kind: kind, timelineItem: item, unreadMarker: nil, dateSeparator: nil)
    }

    static func unreadMarker(_ boundary: CommercialChatUnreadBoundary) -> CommercialChatItem {
        CommercialChatItem(
            id: boundary.markerID,
            kind: .unreadSeparator,
            timelineItem: nil,
            unreadMarker: CommercialChatUnreadMarker(unreadCount: max(0, boundary.unreadCount)),
            dateSeparator: nil
        )
    }

    static func dateSeparator(_ separator: CommercialChatDateSeparator) -> CommercialChatItem {
        CommercialChatItem(
            id: separator.separatorID,
            kind: .dateSeparator,
            timelineItem: nil,
            unreadMarker: nil,
            dateSeparator: separator
        )
    }
}

struct AgentChatTimelineAdapter {
    func items(
        from timelineItems: [AgentChatTurnTimelineItem],
        unreadBoundary: CommercialChatUnreadBoundary? = nil,
        insertsDateSeparators: Bool = false,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [CommercialChatItem] {
        var items = insertsDateSeparators
            ? itemsWithDateSeparators(from: timelineItems, now: now, calendar: calendar)
            : timelineItems.map(CommercialChatItem.timeline)
        guard let unreadBoundary,
              unreadBoundary.unreadCount > 0,
              let insertionIndex = items.firstIndex(where: { $0.id == unreadBoundary.beforeItemID })
        else { return items }

        items.insert(.unreadMarker(unreadBoundary), at: insertionIndex)
        return items
    }

    private func itemsWithDateSeparators(
        from timelineItems: [AgentChatTurnTimelineItem],
        now: Date,
        calendar: Calendar
    ) -> [CommercialChatItem] {
        var items: [CommercialChatItem] = []
        var currentDayIdentifier: String?

        for timelineItem in timelineItems {
            if let date = effectiveDate(for: timelineItem) {
                let dayIdentifier = Self.dayIdentifier(for: date, calendar: calendar)
                if dayIdentifier != currentDayIdentifier {
                    let separator = CommercialChatDateSeparator(
                        date: calendar.startOfDay(for: date),
                        title: Self.dateSeparatorTitle(for: date, now: now, calendar: calendar),
                        dayIdentifier: dayIdentifier
                    )
                    items.append(.dateSeparator(separator))
                    currentDayIdentifier = dayIdentifier
                }
            }
            items.append(.timeline(timelineItem))
        }

        return items
    }

    private func effectiveDate(for item: AgentChatTurnTimelineItem) -> Date? {
        item.timestamp?.date ?? item.message?.message.createdAt
    }

    private static func dayIdentifier(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func dateSeparatorTitle(for date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "今天" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            formatter.dateFormat = "M月d日"
        } else {
            formatter.dateFormat = "yyyy年M月d日"
        }
        return formatter.string(from: date)
    }
}
