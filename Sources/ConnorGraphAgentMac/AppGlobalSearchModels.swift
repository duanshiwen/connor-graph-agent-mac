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

/// 综合搜索“会话”栏里的会话类型：AI 对话 / 笔记 / 单聊 / 群聊。
enum GlobalSearchSessionKind: String, Sendable, Equatable {
    case agentChat
    case note
    case peer
    case group

    var kindLabel: String {
        switch self {
        case .agentChat: return "AI"
        case .note: return "笔记"
        case .peer: return "单聊"
        case .group: return "群聊"
        }
    }

    var systemImage: String {
        switch self {
        case .agentChat: return "bubble.left.and.bubble.right"
        case .note: return "note.text"
        case .peer: return "person.crop.circle.fill"
        case .group: return "person.3.fill"
        }
    }
}

/// 统一的“会话”搜索结果：AI 对话、笔记、单聊、群聊都归到这一类，并带类型标注。
struct GlobalSearchConversationResult: Identifiable, Equatable {
    var id: String
    var kind: GlobalSearchSessionKind
    var title: String
    var snippet: String
    var metaText: String
    var updatedAt: Date

    var updatedAtLabel: String {
        updatedAt.connorLocalFormatted(date: .medium, time: .short)
    }
}

struct GlobalSearchPreviewState: Equatable {
    var query: String = ""
    var loadingSections: Set<GlobalSearchSectionKind> = []
    var sessionResults: [GlobalSearchConversationResult] = []
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
        sessionResults: [GlobalSearchConversationResult] = [],
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
        self.sessionResults = sessionResults
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
        !sessionResults.isEmpty || !knowledgeBaseResults.isEmpty || !calendarResults.isEmpty || !rssResults.isEmpty || !mailResults.isEmpty || !browserHistoryResults.isEmpty
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
    case sessions
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
        case .sessions: "会话"
        case .calendar: "日历"
        case .rss: "RSS"
        case .mail: "邮件"
        case .browserHistory: "浏览历史"
        case .knowledgeMarketplace: "知识库"
        }
    }

    var systemImage: String {
        switch self {
        case .sessions: "tray.full"
        case .calendar: "calendar"
        case .rss: "dot.radiowaves.left.and.right"
        case .mail: "envelope"
        case .browserHistory: "clock.arrow.circlepath"
        case .knowledgeMarketplace: "books.vertical"
        }
    }

    var emptyTitle: String {
        switch self {
        case .sessions: "没有匹配的会话"
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
    case session(GlobalSearchConversationResult)
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
