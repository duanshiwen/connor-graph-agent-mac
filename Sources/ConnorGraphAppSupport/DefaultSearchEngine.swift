import Foundation

public enum DefaultSearchEngine: String, Codable, Sendable, Equatable, CaseIterable, Identifiable {
    case bing
    case google
    case duckDuckGo
    case baidu
    case yahoo

    public static let `default`: DefaultSearchEngine = .bing

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bing: "Bing"
        case .google: "Google"
        case .duckDuckGo: "DuckDuckGo"
        case .baidu: "百度"
        case .yahoo: "Yahoo"
        }
    }

    public func searchURL(for query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = [URLQueryItem(name: queryParameterName, value: trimmed)]
        return components.url
    }

    public func searchURLString(for query: String) -> String? {
        searchURL(for: query)?.absoluteString
    }

    private var host: String {
        switch self {
        case .bing: "cn.bing.com"
        case .google: "www.google.com"
        case .duckDuckGo: "duckduckgo.com"
        case .baidu: "www.baidu.com"
        case .yahoo: "search.yahoo.com"
        }
    }

    private var path: String {
        switch self {
        case .bing, .google, .yahoo: "/search"
        case .duckDuckGo: "/"
        case .baidu: "/s"
        }
    }

    private var queryParameterName: String {
        switch self {
        case .bing, .google, .duckDuckGo: "q"
        case .baidu: "wd"
        case .yahoo: "p"
        }
    }
}

public enum BrowserNavigationURLResolver {
    public static func normalizedURLString(from value: String, defaultSearchEngine: DefaultSearchEngine) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == "about:blank" { return trimmed }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return trimmed }
        if trimmed.contains(".") && !trimmed.contains(" ") { return "https://\(trimmed)" }
        return defaultSearchEngine.searchURLString(for: trimmed)
    }
}
