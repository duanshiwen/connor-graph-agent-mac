import Foundation
import ConnorGraphCore

public struct NativeWebHTTPResponse: Sendable, Equatable {
    public var data: Data
    public var statusCode: Int
    public var mimeType: String?
    public var finalURL: URL?
    public var textEncodingName: String?

    public init(data: Data, statusCode: Int, mimeType: String?, finalURL: URL?, textEncodingName: String?) {
        self.data = data
        self.statusCode = statusCode
        self.mimeType = mimeType
        self.finalURL = finalURL
        self.textEncodingName = textEncodingName
    }
}

public protocol NativeWebHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> NativeWebHTTPResponse
}

public struct URLSessionNativeWebHTTPClient: NativeWebHTTPClient {
    public init() {}

    public func data(for request: URLRequest) async throws -> NativeWebHTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        return NativeWebHTTPResponse(
            data: data,
            statusCode: http?.statusCode ?? 0,
            mimeType: response.mimeType,
            finalURL: response.url,
            textEncodingName: response.textEncodingName
        )
    }
}

public struct NativeWebFetchResult: Sendable, Equatable {
    public var urlString: String
    public var finalURLString: String
    public var title: String
    public var contentText: String
    public var statusCode: Int
    public var mimeType: String
    public var engine: String
    public var truncated: Bool
    public var originalCharacterCount: Int
}

public struct NativeWebFetchClient: Sendable {
    private let httpClient: any NativeWebHTTPClient
    private let maxCharacters: Int

    public init(httpClient: any NativeWebHTTPClient = URLSessionNativeWebHTTPClient(), maxCharacters: Int = 50_000) {
        self.httpClient = httpClient
        self.maxCharacters = max(1_000, maxCharacters)
    }

    public func fetch(urlString: String, extractMode: String, timeoutMilliseconds: Int) async throws -> NativeWebFetchResult {
        guard let url = URL(string: urlString), ["http", "https"].contains(url.scheme?.lowercased()) else {
            throw AgentToolError.invalidArguments("web_fetch requires an absolute http/https url")
        }

        var request = URLRequest(url: url, timeoutInterval: TimeInterval(max(timeoutMilliseconds, 1_000)) / 1000.0)
        request.httpMethod = "GET"
        request.setValue("ConnorGraphAgent/1.0 (+https://local-agent)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,text/plain;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")

        let response = try await httpClient.data(for: request)
        guard (200..<400).contains(response.statusCode) else {
            throw AgentToolError.invalidArguments("web_fetch failed with HTTP status \(response.statusCode)")
        }

        let decoded = BrowserFetchTool.decodeWebPageText(data: response.data, responseEncodingName: response.textEncodingName)
        let title = NativeWebTextExtractor.title(from: decoded.text)
        let markdown = NativeWebTextExtractor.markdown(from: decoded.text, baseURL: response.finalURL ?? url)
        let plainText = NativeWebTextExtractor.plainText(fromMarkdown: markdown)
        let selected = extractMode.lowercased() == "text" ? plainText : markdown
        let truncatedText = String(selected.prefix(maxCharacters))

        return NativeWebFetchResult(
            urlString: url.absoluteString,
            finalURLString: (response.finalURL ?? url).absoluteString,
            title: title,
            contentText: truncatedText,
            statusCode: response.statusCode,
            mimeType: response.mimeType ?? "unknown",
            engine: "native-urlsession",
            truncated: selected.count > maxCharacters,
            originalCharacterCount: selected.count
        )
    }
}

public struct NativeWebSearchResultItem: Sendable, Equatable {
    public var title: String
    public var url: String
    public var snippet: String

    public init(title: String, url: String, snippet: String) {
        self.title = title
        self.url = url
        self.snippet = snippet
    }
}

public struct NativeWebSearchResult: Sendable, Equatable {
    public var query: String
    public var engine: String
    public var results: [NativeWebSearchResultItem]
    public var markdown: String
}

public struct NativeWebSearchClient: Sendable {
    private let httpClient: any NativeWebHTTPClient

    public init(httpClient: any NativeWebHTTPClient = URLSessionNativeWebHTTPClient()) {
        self.httpClient = httpClient
    }

    public func search(query: String, engine: String, maxResults: Int) async throws -> NativeWebSearchResult {
        let normalizedEngine = engine.lowercased()
        guard normalizedEngine == "duckduckgo" else {
            throw AgentToolError.invalidArguments("Native HTTP search currently supports duckduckgo. Engine \(engine) requires browser-assisted search.")
        }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentToolError.invalidArguments("web_search requires query")
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "duckduckgo.com"
        components.path = "/html/"
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else {
            throw AgentToolError.invalidArguments("Unable to construct DuckDuckGo search URL")
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue("ConnorGraphAgent/1.0 (+https://local-agent)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,text/plain;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")

        let response = try await httpClient.data(for: request)
        guard (200..<400).contains(response.statusCode) else {
            throw AgentToolError.invalidArguments("web_search failed with HTTP status \(response.statusCode)")
        }

        let decoded = BrowserFetchTool.decodeWebPageText(data: response.data, responseEncodingName: response.textEncodingName)
        let results = Array(NativeWebSearchParser.duckDuckGoResults(from: decoded.text).prefix(max(1, min(maxResults, 10))))
        let markdown = results.enumerated().map { index, item in
            var lines = ["\(index + 1). \(item.title)", "   URL: \(item.url)"]
            if !item.snippet.isEmpty { lines.append("   Snippet: \(item.snippet)") }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")

        return NativeWebSearchResult(query: query, engine: normalizedEngine, results: results, markdown: markdown)
    }
}

enum NativeWebTextExtractor {
    static func title(from html: String) -> String {
        guard let raw = firstMatch(in: html, pattern: #"(?is)<title[^>]*>(.*?)</title>"#) else { return "" }
        return collapseWhitespace(decodeHTMLEntities(stripTags(raw)))
    }

    static func markdown(from html: String, baseURL: URL) -> String {
        var text = html
        text = removeElement("script", from: text)
        text = removeElement("style", from: text)
        text = removeElement("nav", from: text)
        text = removeElement("footer", from: text)
        text = removeElement("header", from: text)
        text = replaceLinks(in: text, baseURL: baseURL)
        text = replaceBlock(pattern: #"(?is)<h1[^>]*>(.*?)</h1>"#, prefix: "# ", in: text)
        text = replaceBlock(pattern: #"(?is)<h2[^>]*>(.*?)</h2>"#, prefix: "## ", in: text)
        text = replaceBlock(pattern: #"(?is)<h3[^>]*>(.*?)</h3>"#, prefix: "### ", in: text)
        text = replaceBlock(pattern: #"(?is)<li[^>]*>(.*?)</li>"#, prefix: "- ", in: text)
        text = replaceParagraphs(in: text)
        text = text.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
        text = stripTags(text)
        text = decodeHTMLEntities(text)
        return normalizeMarkdown(text)
    }

    static func plainText(fromMarkdown markdown: String) -> String {
        var text = markdown
        text = text.replacingOccurrences(of: #"(?m)^#{1,6}\s*"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?m)^-\s+"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\(([^)]+)\)"#, with: "$1", options: .regularExpression)
        return normalizeMarkdown(text)
    }

    private static func removeElement(_ name: String, from html: String) -> String {
        html.replacingOccurrences(of: #"(?is)<\#(name)\b[^>]*>.*?</\#(name)>"#, with: " ", options: .regularExpression)
    }

    private static func replaceBlock(pattern: String, prefix: String, in html: String) -> String {
        replaceMatches(in: html, pattern: pattern) { match in
            "\n\n\(prefix)\(collapseWhitespace(stripTags(match)))\n\n"
        }
    }

    private static func replaceParagraphs(in html: String) -> String {
        replaceMatches(in: html, pattern: #"(?is)<p[^>]*>(.*?)</p>"#) { match in
            "\n\n\(collapseWhitespace(stripTags(match)))\n\n"
        }
    }

    private static func replaceLinks(in html: String, baseURL: URL) -> String {
        replaceMatches(in: html, pattern: #"(?is)<a\b[^>]*href=[\"']([^\"']+)[\"'][^>]*>(.*?)</a>"#) { fullMatch in
            let href = firstMatch(in: fullMatch, pattern: #"(?is)href=[\"']([^\"']+)[\"']"#) ?? ""
            let label = collapseWhitespace(stripTags(firstMatch(in: fullMatch, pattern: #"(?is)<a\b[^>]*>(.*?)</a>"#) ?? ""))
            let resolved = URL(string: decodeHTMLEntities(href), relativeTo: baseURL)?.absoluteURL.absoluteString ?? decodeHTMLEntities(href)
            return label.isEmpty ? resolved : "[\(label)](\(resolved))"
        }
    }

    static func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
    }

    static func decodeHTMLEntities(_ text: String) -> String {
        var decoded = text
        let entities: [String: String] = [
            "&nbsp;": " ", "&#160;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#34;": "\"", "&#39;": "'", "&apos;": "'"
        ]
        for (entity, value) in entities { decoded = decoded.replacingOccurrences(of: entity, with: value) }
        decoded = replaceMatches(in: decoded, pattern: #"&#(\d+);"#) { match in
            guard let value = firstMatch(in: match, pattern: #"&#(\d+);"#).flatMap(Int.init), let scalar = UnicodeScalar(value) else { return match }
            return String(Character(scalar))
        }
        return decoded
    }

    static func normalizeMarkdown(_ text: String) -> String {
        var lines = text.components(separatedBy: .newlines).map { collapseWhitespace($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        lines = lines.reduce(into: [String]()) { result, line in
            if line.isEmpty, result.last?.isEmpty == true { return }
            result.append(line)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func collapseWhitespace(_ text: String) -> String {
        decodeHTMLEntities(text).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[swiftRange])
    }

    static func replaceMatches(in text: String, pattern: String, transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).reversed()
        var output = text
        for match in matches {
            guard let range = Range(match.range, in: output) else { continue }
            output.replaceSubrange(range, with: transform(String(output[range])))
        }
        return output
    }
}

enum NativeWebSearchParser {
    static func duckDuckGoResults(from html: String) -> [NativeWebSearchResultItem] {
        guard let regex = try? NSRegularExpression(pattern: #"(?is)<a\b[^>]*class=[\"'][^\"']*result__a[^\"']*[\"'][^>]*>.*?</a>"#) else { return [] }
        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        return matches.compactMap { match in
            guard let anchorRange = Range(match.range, in: html) else { return nil }
            let anchor = String(html[anchorRange])
            guard let href = NativeWebTextExtractor.firstMatch(in: anchor, pattern: #"(?is)href=[\"']([^\"']+)[\"']"#) else { return nil }
            let title = NativeWebTextExtractor.collapseWhitespace(NativeWebTextExtractor.stripTags(anchor))
            let url = decodeDuckDuckGoURL(href)
            let tailStart = anchorRange.upperBound
            let tailEnd = html.index(tailStart, offsetBy: min(1_500, html.distance(from: tailStart, to: html.endIndex)))
            let tail = String(html[tailStart..<tailEnd])
            let snippetRaw = NativeWebTextExtractor.firstMatch(in: tail, pattern: #"(?is)<(?:a|div)\b[^>]*class=[\"'][^\"']*result__snippet[^\"']*[\"'][^>]*>(.*?)</(?:a|div)>"#) ?? ""
            let snippet = NativeWebTextExtractor.collapseWhitespace(NativeWebTextExtractor.stripTags(snippetRaw))
            guard !title.isEmpty, !url.isEmpty else { return nil }
            return NativeWebSearchResultItem(title: title, url: url, snippet: snippet)
        }
    }

    private static func decodeDuckDuckGoURL(_ href: String) -> String {
        let decodedHref = NativeWebTextExtractor.decodeHTMLEntities(href)
        let absolute: URL?
        if decodedHref.hasPrefix("//") {
            absolute = URL(string: "https:\(decodedHref)")
        } else {
            absolute = URL(string: decodedHref)
        }
        if let absolute,
           absolute.host?.contains("duckduckgo.com") == true,
           let components = URLComponents(url: absolute, resolvingAgainstBaseURL: false),
           let uddg = components.queryItems?.first(where: { $0.name == "uddg" })?.value,
           let decoded = uddg.removingPercentEncoding {
            return decoded
        }
        return absolute?.absoluteString ?? decodedHref
    }
}
