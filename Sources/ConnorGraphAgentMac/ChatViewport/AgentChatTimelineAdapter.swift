import Foundation
import ConnorGraphAppSupport

enum CommercialChatItemKind: String, Equatable {
    case message
    case process
    case timestamp
    case system
    case unreadSeparator
}

struct CommercialChatItem: Identifiable, Equatable {
    var id: String
    var kind: CommercialChatItemKind
    var timelineItem: AgentChatTurnTimelineItem?

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
        return CommercialChatItem(id: item.id, kind: kind, timelineItem: item)
    }
}

struct AgentChatTimelineAdapter {
    func items(from timelineItems: [AgentChatTurnTimelineItem]) -> [CommercialChatItem] {
        timelineItems.map(CommercialChatItem.timeline)
    }
}
