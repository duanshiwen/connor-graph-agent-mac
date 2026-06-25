import Foundation
import ConnorGraphCore
import ConnorGraphAppSupport

struct GlobalSearchPreviewState: Equatable {
    var query: String = ""
    var isLoading: Bool = false
    var mailResults: [NativeSearchResult] = []
    var calendarResults: [NativeSearchResult] = []
    var rssResults: [NativeSearchResult] = []
    var browserHistoryResults: [BrowserHistoryRecord] = []
    var errorMessage: String?

    static let empty = GlobalSearchPreviewState()

    var hasAnySourceResults: Bool {
        !mailResults.isEmpty || !calendarResults.isEmpty || !rssResults.isEmpty || !browserHistoryResults.isEmpty
    }
}

enum GlobalSearchSectionKind: String, CaseIterable, Identifiable {
    case mail
    case calendar
    case rss
    case browserHistory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mail: "邮件"
        case .calendar: "日历"
        case .rss: "RSS"
        case .browserHistory: "浏览历史"
        }
    }

    var systemImage: String {
        switch self {
        case .mail: "envelope"
        case .calendar: "calendar"
        case .rss: "dot.radiowaves.left.and.right"
        case .browserHistory: "clock.arrow.circlepath"
        }
    }

    var emptyTitle: String {
        switch self {
        case .mail: "没有匹配的邮件"
        case .calendar: "没有匹配的日程"
        case .rss: "没有匹配的 RSS"
        case .browserHistory: "没有匹配的浏览历史"
        }
    }
}

enum GlobalSearchActionKind: String, CaseIterable, Identifiable {
    case newChat
    case webSearch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newChat: "新对话"
        case .webSearch: "网页搜索"
        }
    }

    var systemImage: String {
        switch self {
        case .newChat: "bubble.left.and.bubble.right"
        case .webSearch: "globe"
        }
    }

    func subtitle(for query: String) -> String {
        switch self {
        case .newChat:
            "把“\(query)”发送给 LLM"
        case .webSearch:
            "用内置浏览器搜索“\(query)”"
        }
    }
}
