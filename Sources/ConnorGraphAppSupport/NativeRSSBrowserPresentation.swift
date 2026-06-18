import Foundation
import ConnorGraphCore

public enum NativeRSSBrowserEmptyState: String, Codable, Sendable, Equatable, Hashable {
    case noSources
    case noItems
    case searchNoResults
    case noSelection
}

public enum RSSSourcePreset: String, CaseIterable, Codable, Sendable, Equatable, Hashable, Identifiable {
    case appleDeveloper
    case swiftBlog
    case hackerNews
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .appleDeveloper: "Apple Developer News"
        case .swiftBlog: "Swift Blog"
        case .hackerNews: "Hacker News"
        case .custom: "自定义订阅源"
        }
    }

    public var subtitle: String {
        switch self {
        case .appleDeveloper: "Apple 官方开发者新闻 RSS"
        case .swiftBlog: "Swift.org 官方博客 feed"
        case .hackerNews: "Hacker News front page RSS"
        case .custom: "输入 RSS / Atom / JSON Feed URL"
        }
    }

    public var feedURLString: String {
        switch self {
        case .appleDeveloper: "https://developer.apple.com/news/rss/news.rss"
        case .swiftBlog: "https://www.swift.org/blog/feed.xml"
        case .hackerNews: "https://news.ycombinator.com/rss"
        case .custom: ""
        }
    }

    public var guidance: String {
        switch self {
        case .appleDeveloper:
            "适合跟踪 Apple 平台、SDK、工具链与 App Store 相关更新。"
        case .swiftBlog:
            "适合跟踪 Swift 语言、SwiftPM、并发、工具链和服务器端 Swift 更新。"
        case .hackerNews:
            "适合高频技术资讯流；建议设置较长抓取间隔，避免噪声过大。"
        case .custom:
            "支持 RSS 2.0、Atom 和 JSON Feed。Connor 会先解析元数据，再纳入本地 source registry。"
        }
    }
}

public struct NativeRSSBrowserPresentation: Sendable, Equatable {
    public var sources: [RSSSource]
    public var items: [RSSItemSummary]

    public init(sources: [RSSSource], items: [RSSItemSummary]) {
        self.sources = sources
        self.items = items
    }

    public func source(id: RSSSourceID?) -> RSSSource? {
        guard let id else { return nil }
        return sources.first { $0.id == id }
    }

    public func item(id: RSSItemID?) -> RSSItemSummary? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }

    public func items(sourceID: RSSSourceID?, query: String, includeHidden: Bool = false) -> [RSSItemSummary] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            if let sourceID, item.sourceID != sourceID { return false }
            if !includeHidden && item.state.isHidden { return false }
            guard !normalized.isEmpty else { return true }
            return item.title.lowercased().contains(normalized)
                || item.snippet.lowercased().contains(normalized)
                || (item.author?.lowercased().contains(normalized) ?? false)
                || (source(id: item.sourceID)?.displayName.lowercased().contains(normalized) ?? false)
        }
        .sorted { $0.publishedAt > $1.publishedAt }
    }

    public func unreadCount(sourceID: RSSSourceID?) -> Int {
        items(sourceID: sourceID, query: "").filter { !$0.state.isRead }.count
    }

    public func defaultSourceID() -> RSSSourceID? { sources.first?.id }

    public func defaultItemID(sourceID: RSSSourceID?) -> RSSItemID? {
        items(sourceID: sourceID, query: "").first?.id
    }

    public func emptyState(forQuery query: String) -> NativeRSSBrowserEmptyState {
        if sources.isEmpty { return .noSources }
        if items.isEmpty { return .noItems }
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .searchNoResults }
        return .noSelection
    }
}

public extension NativeRSSBrowserPresentation {
    static let empty = NativeRSSBrowserPresentation(sources: [], items: [])
}
