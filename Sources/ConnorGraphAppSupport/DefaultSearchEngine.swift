import Foundation

public enum DefaultSearchEngine: String, Codable, Sendable, Equatable, CaseIterable, Identifiable {
    case bing
    case google
    case duckDuckGo
    case yahoo

    public static let `default`: DefaultSearchEngine = .bing

    public var id: String { rawValue }

    /// 旧版本持久化里可能存过已移除的引擎（如 baidu）；解码到未知 rawValue 时安全回退到默认值，避免整个设置解码失败。
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = DefaultSearchEngine(rawValue: rawValue) ?? .default
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var displayName: String {
        switch self {
        case .bing: "Bing"
        case .google: "Google"
        case .duckDuckGo: "DuckDuckGo"
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
        case .yahoo: "search.yahoo.com"
        }
    }

    private var path: String {
        switch self {
        case .bing, .google, .yahoo: "/search"
        case .duckDuckGo: "/"
        }
    }

    private var queryParameterName: String {
        switch self {
        case .bing, .google, .duckDuckGo: "q"
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
