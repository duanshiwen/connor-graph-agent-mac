import Foundation
import ConnorGraphAppSupport

enum CommercialChatItemKind: String, Equatable {
    case message
    case process
    case timestamp
    case system
    case unreadSeparator
}

struct CommercialChatUnreadBoundary: Equatable {
    var beforeItemID: String
    var unreadCount: Int

    var markerID: String { "unread-boundary-before-\(beforeItemID)" }
}

struct CommercialChatUnreadMarker: Equatable {
    var unreadCount: Int
}

struct CommercialChatItem: Identifiable, Equatable {
    var id: String
    var kind: CommercialChatItemKind
    var timelineItem: AgentChatTurnTimelineItem?
    var unreadMarker: CommercialChatUnreadMarker?

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
        return CommercialChatItem(id: item.id, kind: kind, timelineItem: item, unreadMarker: nil)
    }

    static func unreadMarker(_ boundary: CommercialChatUnreadBoundary) -> CommercialChatItem {
        CommercialChatItem(
            id: boundary.markerID,
            kind: .unreadSeparator,
            timelineItem: nil,
            unreadMarker: CommercialChatUnreadMarker(unreadCount: max(0, boundary.unreadCount))
        )
    }
}

struct AgentChatTimelineAdapter {
    func items(
        from timelineItems: [AgentChatTurnTimelineItem],
        unreadBoundary: CommercialChatUnreadBoundary? = nil
    ) -> [CommercialChatItem] {
        var items = timelineItems.map(CommercialChatItem.timeline)
        guard let unreadBoundary,
              unreadBoundary.unreadCount > 0,
              let insertionIndex = items.firstIndex(where: { $0.id == unreadBoundary.beforeItemID })
        else { return items }

        items.insert(.unreadMarker(unreadBoundary), at: insertionIndex)
        return items
    }
}
