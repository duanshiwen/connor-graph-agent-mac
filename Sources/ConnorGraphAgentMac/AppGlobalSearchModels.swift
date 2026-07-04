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
    var calendarResults: [NativeSearchResult] = []
    var rssResults: [NativeSearchResult] = []
    var mailResults: [NativeSearchResult] = []
    var browserHistoryResults: [NativeSearchResult] = []
    var searchTokens: [String] = []
    var sectionStatusMessages: [GlobalSearchSectionKind: String] = [:]
    var errorMessage: String?

    init(
        query: String = "",
        isLoading: Bool = false,
        loadingSections: Set<GlobalSearchSectionKind>? = nil,
        chatSessionResults: [GlobalSearchSessionResult] = [],
        calendarResults: [NativeSearchResult] = [],
        rssResults: [NativeSearchResult] = [],
        mailResults: [NativeSearchResult] = [],
        browserHistoryResults: [NativeSearchResult] = [],
        searchTokens: [String] = [],
        sectionStatusMessages: [GlobalSearchSectionKind: String] = [:],
        errorMessage: String? = nil
    ) {
        self.query = query
        self.loadingSections = loadingSections ?? (isLoading ? Set(GlobalSearchSectionKind.allCases) : [])
        self.chatSessionResults = chatSessionResults
        self.calendarResults = calendarResults
        self.rssResults = rssResults
        self.mailResults = mailResults
        self.browserHistoryResults = browserHistoryResults
        self.searchTokens = searchTokens
        self.sectionStatusMessages = sectionStatusMessages
        self.errorMessage = errorMessage
    }

    static let empty = GlobalSearchPreviewState()

    var isLoading: Bool { !loadingSections.isEmpty }

    func isSectionLoading(_ kind: GlobalSearchSectionKind) -> Bool {
        loadingSections.contains(kind)
    }

    func sectionStatusMessage(_ kind: GlobalSearchSectionKind) -> String? {
        sectionStatusMessages[kind]
    }

    var hasAnySourceResults: Bool {
        !chatSessionResults.isEmpty || !calendarResults.isEmpty || !rssResults.isEmpty || !mailResults.isEmpty || !browserHistoryResults.isEmpty
    }
}

struct GlobalSearchNativeSectionResult: Sendable {
    var kind: GlobalSearchSectionKind
    var results: [NativeSearchResult]
    var errorMessage: String?
    var timing: GlobalSearchSectionTiming?

    init(
        kind: GlobalSearchSectionKind,
        results: [NativeSearchResult],
        errorMessage: String? = nil,
        timing: GlobalSearchSectionTiming? = nil
    ) {
        self.kind = kind
        self.results = results
        self.errorMessage = errorMessage
        self.timing = timing
    }
}

enum GlobalSearchSectionKind: String, CaseIterable, Identifiable, Sendable {
    case chatSessions
    case calendar
    case rss
    case mail
    case browserHistory

    init(nativeSourceKind: NativeSearchSourceKind) {
        switch nativeSourceKind {
        case .calendar: self = .calendar
        case .rss: self = .rss
        case .mail: self = .mail
        case .browserHistory: self = .browserHistory
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chatSessions: "对话历史"
        case .calendar: "日历"
        case .rss: "RSS"
        case .mail: "邮件"
        case .browserHistory: "浏览历史"
        }
    }

    var systemImage: String {
        switch self {
        case .chatSessions: "bubble.left.and.bubble.right"
        case .calendar: "calendar"
        case .rss: "dot.radiowaves.left.and.right"
        case .mail: "envelope"
        case .browserHistory: "clock.arrow.circlepath"
        }
    }

    var emptyTitle: String {
        switch self {
        case .chatSessions: "没有匹配的对话"
        case .calendar: "没有匹配的日程"
        case .rss: "没有匹配的 RSS"
        case .mail: "没有匹配的邮件"
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
            "把“\(query)”发送给 AI"
        case .webSearch:
            "用内置浏览器搜索“\(query)”"
        }
    }
}
