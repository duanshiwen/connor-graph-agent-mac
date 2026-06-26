import Foundation
import ConnorGraphCore
import ConnorGraphAppSupport

struct GlobalSearchSessionResult: Identifiable, Equatable {
    var id: String
    var title: String
    var snippet: String
    var updatedAt: Date
    var messageCount: Int

    var updatedAtLabel: String {
        updatedAt.formatted(date: .abbreviated, time: .shortened)
    }
}

struct GlobalSearchPreviewState: Equatable {
    var query: String = ""
    var loadingSections: Set<GlobalSearchSectionKind> = []
    var chatSessionResults: [GlobalSearchSessionResult] = []
    var mailResults: [NativeSearchResult] = []
    var calendarResults: [NativeSearchResult] = []
    var rssResults: [NativeSearchResult] = []
    var browserHistoryResults: [NativeSearchResult] = []
    var searchTokens: [String] = []
    var errorMessage: String?

    init(
        query: String = "",
        isLoading: Bool = false,
        loadingSections: Set<GlobalSearchSectionKind>? = nil,
        chatSessionResults: [GlobalSearchSessionResult] = [],
        mailResults: [NativeSearchResult] = [],
        calendarResults: [NativeSearchResult] = [],
        rssResults: [NativeSearchResult] = [],
        browserHistoryResults: [NativeSearchResult] = [],
        searchTokens: [String] = [],
        errorMessage: String? = nil
    ) {
        self.query = query
        self.loadingSections = loadingSections ?? (isLoading ? Set(GlobalSearchSectionKind.allCases) : [])
        self.chatSessionResults = chatSessionResults
        self.mailResults = mailResults
        self.calendarResults = calendarResults
        self.rssResults = rssResults
        self.browserHistoryResults = browserHistoryResults
        self.searchTokens = searchTokens
        self.errorMessage = errorMessage
    }

    static let empty = GlobalSearchPreviewState()

    var isLoading: Bool { !loadingSections.isEmpty }

    func isSectionLoading(_ kind: GlobalSearchSectionKind) -> Bool {
        loadingSections.contains(kind)
    }

    var hasAnySourceResults: Bool {
        !chatSessionResults.isEmpty || !mailResults.isEmpty || !calendarResults.isEmpty || !rssResults.isEmpty || !browserHistoryResults.isEmpty
    }
}

enum GlobalSearchSectionKind: String, CaseIterable, Identifiable {
    case chatSessions
    case mail
    case calendar
    case rss
    case browserHistory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chatSessions: "对话历史"
        case .mail: "邮件"
        case .calendar: "日历"
        case .rss: "RSS"
        case .browserHistory: "浏览历史"
        }
    }

    var systemImage: String {
        switch self {
        case .chatSessions: "bubble.left.and.bubble.right"
        case .mail: "envelope"
        case .calendar: "calendar"
        case .rss: "dot.radiowaves.left.and.right"
        case .browserHistory: "clock.arrow.circlepath"
        }
    }

    var emptyTitle: String {
        switch self {
        case .chatSessions: "没有匹配的对话"
        case .mail: "没有匹配的邮件"
        case .calendar: "没有匹配的日程"
        case .rss: "没有匹配的 RSS"
        case .browserHistory: "没有匹配的浏览历史"
        }
    }
}

enum GlobalSearchSelectableItem: Equatable {
    case action(GlobalSearchActionKind)
    case chatSession(String)
    case nativeResult(String)
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
