import Foundation
import ConnorGraphCore
import ConnorGraphAppSupport

extension Date {
    func connorLocalFormatted(date: DateFormatter.Style = .medium, time: DateFormatter.Style = .short) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = date
        formatter.timeStyle = time
        return formatter.string(from: self)
    }

    func connorLocalStandardDateTime() -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: self)
    }
}

struct GlobalSearchSessionResult: Identifiable, Equatable {
    var id: String
    var title: String
    var snippet: String
    var updatedAt: Date
    var messageCount: Int

    var updatedAtLabel: String {
        updatedAt.connorLocalFormatted(date: .medium, time: .short)
    }
}

struct GlobalSearchIMConversationResult: Identifiable, Equatable {
    var id: String
    var kind: ImConversationKind
    var title: String
    var participantName: String
    var snippet: String
    var lastMessageAt: Int64

    var kindLabel: String { kind == .group ? "群聊" : "单聊" }

    var lastMessageAtLabel: String {
        guard lastMessageAt > 0 else { return "" }
        return Date(timeIntervalSince1970: TimeInterval(lastMessageAt) / 1_000)
            .connorLocalFormatted(date: .medium, time: .short)
    }
}

struct GlobalSearchPreviewState: Equatable {
    var query: String = ""
    var loadingSections: Set<GlobalSearchSectionKind> = []
    var imConversationResults: [GlobalSearchIMConversationResult] = []
    var chatSessionResults: [GlobalSearchSessionResult] = []
    var calendarResults: [NativeSearchResult] = []
    var rssResults: [NativeSearchResult] = []
    var mailResults: [NativeSearchResult] = []
    var browserHistoryResults: [NativeSearchResult] = []
    var knowledgeBaseResults: [CloudMarketplaceKnowledgeBase] = []
    var searchTokens: [String] = []
    var sectionStatusMessages: [GlobalSearchSectionKind: String] = [:]
    var errorMessage: String?

    init(
        query: String = "",
        isLoading: Bool = false,
        loadingSections: Set<GlobalSearchSectionKind>? = nil,
        imConversationResults: [GlobalSearchIMConversationResult] = [],
        chatSessionResults: [GlobalSearchSessionResult] = [],
        calendarResults: [NativeSearchResult] = [],
        rssResults: [NativeSearchResult] = [],
        mailResults: [NativeSearchResult] = [],
        browserHistoryResults: [NativeSearchResult] = [],
        knowledgeBaseResults: [CloudMarketplaceKnowledgeBase] = [],
        searchTokens: [String] = [],
        sectionStatusMessages: [GlobalSearchSectionKind: String] = [:],
        errorMessage: String? = nil
    ) {
        self.query = query
        self.loadingSections = loadingSections ?? (isLoading ? Set(GlobalSearchSectionKind.allCases) : [])
        self.imConversationResults = imConversationResults
        self.chatSessionResults = chatSessionResults
        self.calendarResults = calendarResults
        self.rssResults = rssResults
        self.mailResults = mailResults
        self.browserHistoryResults = browserHistoryResults
        self.knowledgeBaseResults = knowledgeBaseResults
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
        !imConversationResults.isEmpty || !chatSessionResults.isEmpty || !knowledgeBaseResults.isEmpty || !calendarResults.isEmpty || !rssResults.isEmpty || !mailResults.isEmpty || !browserHistoryResults.isEmpty
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
    case imConversations
    case chatSessions
    case calendar
    case rss
    case mail
    case browserHistory
    case knowledgeMarketplace

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
        case .imConversations: "真人会话"
        case .chatSessions: "对话历史"
        case .calendar: "日历"
        case .rss: "RSS"
        case .mail: "邮件"
        case .browserHistory: "浏览历史"
        case .knowledgeMarketplace: "知识库"
        }
    }

    var systemImage: String {
        switch self {
        case .imConversations: "person.2"
        case .chatSessions: "bubble.left.and.bubble.right"
        case .calendar: "calendar"
        case .rss: "dot.radiowaves.left.and.right"
        case .mail: "envelope"
        case .browserHistory: "clock.arrow.circlepath"
        case .knowledgeMarketplace: "books.vertical"
        }
    }

    var emptyTitle: String {
        switch self {
        case .imConversations: "没有匹配的单聊或群聊"
        case .chatSessions: "没有匹配的对话"
        case .calendar: "没有匹配的日程"
        case .rss: "没有匹配的 RSS"
        case .mail: "没有匹配的邮件"
        case .browserHistory: "没有匹配的浏览历史"
        case .knowledgeMarketplace: "没有匹配的知识库"
        }
    }
}

enum GlobalSearchSelectableItem: Equatable {
    case recentSearch(String)
    case action(GlobalSearchActionKind)
    case imConversation(String)
    case chatSession(String)
    case nativeResult(String)
    case knowledgeBase(String)
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
