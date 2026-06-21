import Foundation
import CryptoKit
import ConnorGraphCore

public enum RSSRuntimeError: Error, LocalizedError, Equatable {
    case sourceNotFound(String)
    case itemNotFound(String)
    case invalidURL(String)
    case unsupportedFeed(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .sourceNotFound(let id): "RSS source not found: \(id)"
        case .itemNotFound(let id): "RSS item not found: \(id)"
        case .invalidURL(let url): "Invalid RSS URL: \(url)"
        case .unsupportedFeed(let detail): "Unsupported feed: \(detail)"
        case .parseFailed(let detail): "Failed to parse feed: \(detail)"
        }
    }
}

public protocol RSSSourceRepository: Sendable {
    func listSources() async throws -> [RSSSource]
    func source(id: RSSSourceID) async throws -> RSSSource?
    func saveSource(_ source: RSSSource) async throws
    func deleteSource(id: RSSSourceID) async throws
}

public protocol RSSSourceCache: Sendable {
    func listItems(sourceID: RSSSourceID?, includeHidden: Bool) async throws -> [RSSItemSummary]
    func searchItems(query: String, sourceID: RSSSourceID?, includeHidden: Bool) async throws -> [RSSItemSummary]
    func item(id: RSSItemID) async throws -> RSSItemDetail?
    func upsertItems(_ items: [RSSItemDetail]) async throws -> (inserted: Int, duplicates: Int)
    func updateState(itemIDs: [RSSItemID], transform: @Sendable (RSSItemState) -> RSSItemState) async throws
    func deleteItems(sourceID: RSSSourceID) async throws
}

public protocol RSSAuditLogProtocol: Sendable {
    func record(_ record: RSSAuditRecord) async throws
}

public actor InMemoryRSSSourceRepository: RSSSourceRepository {
    private var sources: [RSSSourceID: RSSSource]

    public init(sources: [RSSSource] = []) {
        self.sources = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
    }

    public func listSources() async throws -> [RSSSource] {
        sources.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public func source(id: RSSSourceID) async throws -> RSSSource? { sources[id] }

    public func saveSource(_ source: RSSSource) async throws { sources[source.id] = source }

    public func deleteSource(id: RSSSourceID) async throws { sources.removeValue(forKey: id) }
}

public actor InMemoryRSSSourceCache: RSSSourceCache {
    private var items: [RSSItemID: RSSItemDetail]

    public init(items: [RSSItemDetail] = []) {
        self.items = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    public func listItems(sourceID: RSSSourceID? = nil, includeHidden: Bool = false) async throws -> [RSSItemSummary] {
        filtered(sourceID: sourceID, includeHidden: includeHidden)
    }

    public func searchItems(query: String, sourceID: RSSSourceID? = nil, includeHidden: Bool = false) async throws -> [RSSItemSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return filtered(sourceID: sourceID, includeHidden: includeHidden) }
        return filtered(sourceID: sourceID, includeHidden: includeHidden).filter { item in
            item.title.localizedCaseInsensitiveContains(trimmed)
            || item.snippet.localizedCaseInsensitiveContains(trimmed)
            || (item.author?.localizedCaseInsensitiveContains(trimmed) == true)
        }
    }

    public func item(id: RSSItemID) async throws -> RSSItemDetail? { items[id] }

    public func upsertItems(_ newItems: [RSSItemDetail]) async throws -> (inserted: Int, duplicates: Int) {
        var inserted = 0
        var duplicates = 0
        for item in newItems {
            if items[item.id] == nil {
                items[item.id] = item
                inserted += 1
            } else {
                duplicates += 1
            }
        }
        return (inserted, duplicates)
    }

    public func updateState(itemIDs: [RSSItemID], transform: @Sendable (RSSItemState) -> RSSItemState) async throws {
        for id in itemIDs {
            guard var detail = items[id] else { continue }
            detail.summary.state = transform(detail.summary.state)
            items[id] = detail
        }
    }

    public func deleteItems(sourceID: RSSSourceID) async throws {
        items = items.filter { _, detail in detail.summary.sourceID != sourceID }
    }

    private func filtered(sourceID: RSSSourceID?, includeHidden: Bool) -> [RSSItemSummary] {
        items.values.map(\.summary)
            .filter { sourceID == nil || $0.sourceID == sourceID }
            .filter { includeHidden || !$0.state.isHidden }
            .sorted { $0.publishedAt > $1.publishedAt }
    }
}

public actor InMemoryRSSAuditLog: RSSAuditLogProtocol {
    public private(set) var records: [RSSAuditRecord] = []
    public init() {}
    public func record(_ record: RSSAuditRecord) async throws { records.append(record) }
}

public protocol RSSFetchAdapter: Sendable {
    func fetch(url: URL, timeoutSeconds: Int) async throws -> Data
}

public struct URLSessionRSSFetchAdapter: RSSFetchAdapter {
    public init() {}
    public func fetch(url: URL, timeoutSeconds: Int) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: TimeInterval(timeoutSeconds))
        request.setValue("ConnorGraphAgentMac/1.0 RSS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RSSRuntimeError.unsupportedFeed("HTTP \(http.statusCode)")
        }
        return data
    }
}

public protocol RSSFeedParsingAdapter: Sendable {
    func parse(data: Data, source: RSSSource) throws -> RSSParsedFeed
}

public final class RSSFeedParser: NSObject, RSSFeedParsingAdapter, XMLParserDelegate, @unchecked Sendable {
    private struct XMLItem {
        var fields: [String: String] = [:]
        var contentEncoded: String = ""
    }

    private var format: RSSFeedFormat = .unknown
    private var channelFields: [String: String] = [:]
    private var items: [XMLItem] = []
    private var currentItem: XMLItem?
    private var elementStack: [String] = []
    private var currentText = ""

    public override init() { super.init() }

    public func parse(data: Data, source: RSSSource) throws -> RSSParsedFeed {
        if let json = try? parseJSONFeed(data: data, source: source) { return json }
        return try parseXMLFeed(data: data, source: source)
    }

    private func parseJSONFeed(data: Data, source: RSSSource) throws -> RSSParsedFeed {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["version"] != nil else {
            throw RSSRuntimeError.unsupportedFeed("not json feed")
        }
        let title = (object["title"] as? String)?.trimmedNonEmpty ?? source.displayName
        let homeURL = URL(string: object["home_page_url"] as? String ?? "")
        let feedURL = URL(string: object["feed_url"] as? String ?? "") ?? source.feedURL
        let iconURL = URL(string: object["favicon"] as? String ?? "") ?? URL(string: object["icon"] as? String ?? "")
        let metadata = RSSFeedMetadata(title: title, siteURL: homeURL, feedURL: feedURL, description: object["description"] as? String, iconURL: iconURL, format: .jsonFeed)
        let rawItems = object["items"] as? [[String: Any]] ?? []
        let details = rawItems.prefix(source.fetchPolicy.maxItemsPerFetch).map { raw -> RSSItemDetail in
            let externalID = raw["id"] as? String
            let url = URL(string: raw["url"] as? String ?? raw["external_url"] as? String ?? "")
            let date = RSSDateParser.parse(raw["date_published"] as? String) ?? RSSDateParser.parse(raw["date_modified"] as? String) ?? Date()
            let contentHTML = raw["content_html"] as? String
            let contentText = raw["content_text"] as? String
            let summaryText = raw["summary"] as? String ?? contentText ?? contentHTML ?? ""
            let plain = RSSHTMLSanitizer.plainText(from: summaryText)
            let content = RSSItemContent(safeMarkdown: RSSHTMLSanitizer.safeMarkdown(from: contentHTML ?? contentText ?? ""), plainText: RSSHTMLSanitizer.plainText(from: contentHTML ?? contentText ?? ""), rawHTMLHash: contentHTML.map(RSSHash.sha256), byteCount: (contentHTML ?? contentText ?? "").utf8.count)
            let summary = RSSItemSummary(id: RSSIdentity.itemID(sourceID: source.id, externalID: externalID, link: url, title: raw["title"] as? String, publishedAt: date, content: plain), sourceID: source.id, externalID: externalID, title: (raw["title"] as? String)?.trimmedNonEmpty ?? "Untitled", link: url, author: (raw["author"] as? [String: Any])?["name"] as? String, publishedAt: date, snippet: String(plain.prefix(280)), media: RSSItemMedia(thumbnailURL: URL(string: raw["image"] as? String ?? "")), state: RSSItemState(), contentHash: RSSHash.sha256(plain))
            return RSSItemDetail(summary: summary, content: content)
        }
        return RSSParsedFeed(metadata: metadata, items: details)
    }

    private func parseXMLFeed(data: Data, source: RSSSource) throws -> RSSParsedFeed {
        reset()
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw RSSRuntimeError.parseFailed(parser.parserError?.localizedDescription ?? "unknown XML parser error")
        }
        let title = channelFields["title"]?.trimmedNonEmpty ?? source.displayName
        let siteURL = URL(string: channelFields["link"] ?? "")
        let metadata = RSSFeedMetadata(title: title, siteURL: siteURL, feedURL: source.feedURL, description: channelFields["description"] ?? channelFields["subtitle"], iconURL: URL(string: channelFields["image.url"] ?? channelFields["icon"] ?? channelFields["logo"] ?? ""), format: format)
        let details = items.prefix(source.fetchPolicy.maxItemsPerFetch).map { item -> RSSItemDetail in
            let externalID = item.fields["guid"] ?? item.fields["id"]
            let link = URL(string: item.fields["link.href"] ?? item.fields["link"] ?? "")
            let date = RSSDateParser.parse(item.fields["pubDate"]) ?? RSSDateParser.parse(item.fields["published"]) ?? RSSDateParser.parse(item.fields["updated"]) ?? Date()
            let body = item.contentEncoded.trimmedNonEmpty ?? item.fields["content"] ?? item.fields["description"] ?? item.fields["summary"] ?? ""
            let plain = RSSHTMLSanitizer.plainText(from: body)
            let title = item.fields["title"]?.trimmedNonEmpty ?? "Untitled"
            let summary = RSSItemSummary(id: RSSIdentity.itemID(sourceID: source.id, externalID: externalID, link: link, title: title, publishedAt: date, content: plain), sourceID: source.id, externalID: externalID, title: title, link: link, author: item.fields["author"] ?? item.fields["creator"], publishedAt: date, snippet: String((RSSHTMLSanitizer.plainText(from: item.fields["description"] ?? item.fields["summary"] ?? body)).prefix(280)), media: RSSItemMedia(thumbnailURL: URL(string: item.fields["media.thumbnail"] ?? item.fields["enclosure.url"] ?? "")), state: RSSItemState(), contentHash: RSSHash.sha256(plain))
            let content = RSSItemContent(safeMarkdown: RSSHTMLSanitizer.safeMarkdown(from: body), plainText: plain, rawHTMLHash: RSSHash.sha256(body), byteCount: body.utf8.count)
            return RSSItemDetail(summary: summary, content: content)
        }
        return RSSParsedFeed(metadata: metadata, items: details)
    }

    private func reset() {
        format = .unknown
        channelFields = [:]
        items = []
        currentItem = nil
        elementStack = []
        currentText = ""
    }

    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let name = qName ?? elementName
        if elementStack.isEmpty {
            if name.lowercased() == "rss" { format = .rss }
            if name.lowercased() == "feed" { format = .atom }
        }
        elementStack.append(name)
        currentText = ""
        if name.lowercased() == "item" || name.lowercased() == "entry" { currentItem = XMLItem() }
        if name.lowercased() == "link", let href = attributeDict["href"], currentItem != nil { currentItem?.fields["link.href"] = href }
        if name.lowercased() == "enclosure", let url = attributeDict["url"], currentItem != nil { currentItem?.fields["enclosure.url"] = url }
        if name.lowercased().contains("thumbnail"), let url = attributeDict["url"], currentItem != nil { currentItem?.fields["media.thumbnail"] = url }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) { currentText += string }
    public func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { currentText += String(data: CDATABlock, encoding: .utf8) ?? "" }

    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = qName ?? elementName
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if var item = currentItem {
            if !text.isEmpty {
                if name.lowercased() == "encoded" || name.lowercased() == "content:encoded" { item.contentEncoded += text }
                else { item.fields[name] = text }
                currentItem = item
            }
            if name.lowercased() == "item" || name.lowercased() == "entry" {
                items.append(item)
                currentItem = nil
            }
        } else if !text.isEmpty {
            if elementStack.contains(where: { $0.lowercased() == "channel" }) || format == .atom {
                channelFields[name] = text
            }
        }
        _ = elementStack.popLast()
        currentText = ""
    }
}

public enum RSSDateParser {
    public static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        let rfc822 = DateFormatter()
        rfc822.locale = Locale(identifier: "en_US_POSIX")
        rfc822.timeZone = TimeZone(secondsFromGMT: 0)
        rfc822.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return iso.date(from: value) ?? rfc822.date(from: value)
    }
}

public enum RSSHTMLSanitizer {
    public static func plainText(from html: String) -> String {
        safeMarkdown(from: html)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func safeMarkdown(from html: String) -> String {
        html.replacingOccurrences(of: #"(?is)<script[^>]*>.*?</script>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)<style[^>]*>.*?</style>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\s+on\w+\s*=\s*(['"]).*?\1"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum RSSHash {
    public static func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public enum RSSIdentity {
    public static func sourceID(feedURL: URL) -> RSSSourceID {
        RSSSourceID(rawValue: "rss-source-" + RSSHash.sha256(feedURL.absoluteString).prefix(12))
    }

    public static func itemID(sourceID: RSSSourceID, externalID: String?, link: URL?, title: String?, publishedAt: Date, content: String) -> RSSItemID {
        let raw = externalID?.trimmedNonEmpty ?? link?.absoluteString ?? "\(sourceID.rawValue)|\(title ?? "")|\(Int(publishedAt.timeIntervalSince1970))|\(content.prefix(128))"
        return RSSItemID(rawValue: "rss-item-" + RSSHash.sha256(sourceID.rawValue + "|" + raw).prefix(16))
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

public struct RSSOPMLService: Sendable {
    public init() {}

    public func export(document: OPMLDocument) -> String {
        let outlines = document.outlines.map { outline in
            let html = outline.htmlURL.map { " htmlUrl=\"\(escape($0.absoluteString))\"" } ?? ""
            let category = outline.categoryPath.isEmpty ? "" : " category=\"\(escape(outline.categoryPath.joined(separator: "/")))\""
            return "    <outline text=\"\(escape(outline.title))\" title=\"\(escape(outline.title))\" type=\"rss\" xmlUrl=\"\(escape(outline.xmlURL.absoluteString))\"\(html)\(category)/>"
        }.joined(separator: "\n")
        return """
        <?xml version=\"1.0\" encoding=\"UTF-8\"?>
        <opml version=\"2.0\">
          <head><title>\(escape(document.title))</title></head>
          <body>
        \(outlines)
          </body>
        </opml>
        """
    }

    public func parse(_ xml: String) throws -> OPMLDocument {
        let regex = try NSRegularExpression(pattern: #"<outline\b[^>]*xmlUrl=[\"']([^\"']+)[\"'][^>]*>??"#, options: [.caseInsensitive])
        let ns = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        let outlines = regex.matches(in: xml, range: ns).compactMap { match -> OPMLSubscriptionOutline? in
            guard let urlRange = Range(match.range(at: 1), in: xml), let url = URL(string: String(xml[urlRange])) else { return nil }
            let elementRange = Range(match.range(at: 0), in: xml).map { String(xml[$0]) } ?? ""
            let title = attribute("title", in: elementRange) ?? attribute("text", in: elementRange) ?? url.host ?? url.absoluteString
            let html = attribute("htmlUrl", in: elementRange).flatMap(URL.init(string:))
            return OPMLSubscriptionOutline(title: title, xmlURL: url, htmlURL: html)
        }
        return OPMLDocument(title: "Imported OPML", outlines: outlines)
    }

    private func attribute(_ name: String, in element: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\\b\(name)=[\\\"']([^\\\"']+)[\\\"']", options: [.caseInsensitive]), let match = regex.firstMatch(in: element, range: NSRange(element.startIndex..<element.endIndex, in: element)), let range = Range(match.range(at: 1), in: element) else { return nil }
        return String(element[range])
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

public struct RSSRuntimeSearchRequest: Sendable, Equatable {
    public var query: String
    public var sourceID: RSSSourceID?
    public var includeHidden: Bool
    public var limit: Int
    public var startDate: Date?
    public var endDate: Date?
    public var timePreset: NativeSearchTimePreset?
    public var timeSort: NativeSearchTemporalSort

    public init(query: String, sourceID: RSSSourceID? = nil, includeHidden: Bool = false, limit: Int = 50, startDate: Date? = nil, endDate: Date? = nil, timePreset: NativeSearchTimePreset? = nil, timeSort: NativeSearchTemporalSort = .relevanceThenTimeDesc) {
        self.query = query
        self.sourceID = sourceID
        self.includeHidden = includeHidden
        self.limit = limit
        self.startDate = startDate
        self.endDate = endDate
        self.timePreset = timePreset
        self.timeSort = timeSort
    }

    public var temporalFilter: NativeSearchTemporalFilter? {
        if let timePreset {
            var filter = NativeSearchTimePresetResolver.resolve(timePreset)
            filter.timeFieldPreference = [.publishedAt, .fetchedAt]
            return filter
        }
        return .sourceDefault(start: startDate, end: endDate, sourceKind: .rss)
    }
}

public struct RSSRuntime: Sendable {
    public var repository: any RSSSourceRepository
    public var cache: any RSSSourceCache
    public var auditLog: any RSSAuditLogProtocol
    public var parser: any RSSFeedParsingAdapter
    public var fetcher: any RSSFetchAdapter
    public var opmlService: RSSOPMLService

    public init(repository: any RSSSourceRepository, cache: any RSSSourceCache, auditLog: any RSSAuditLogProtocol = InMemoryRSSAuditLog(), parser: any RSSFeedParsingAdapter = RSSFeedParser(), fetcher: any RSSFetchAdapter = URLSessionRSSFetchAdapter(), opmlService: RSSOPMLService = RSSOPMLService()) {
        self.repository = repository
        self.cache = cache
        self.auditLog = auditLog
        self.parser = parser
        self.fetcher = fetcher
        self.opmlService = opmlService
    }

    public static func fixture(now: Date = Date()) -> RSSRuntime {
        let sourceID = RSSSourceID(rawValue: "fixture-rss-source")
        let source = RSSSource(id: sourceID, feedURL: URL(string: "https://example.com/feed.xml")!, siteURL: URL(string: "https://example.com"), displayName: "Connor RSS Fixture", format: .rss, unreadCount: 2, health: RSSSourceHealth(status: .ready, summary: "Fixture ready"))
        let items = [
            RSSItemDetail(summary: RSSItemSummary(id: RSSItemID(rawValue: "fixture-rss-item-1"), sourceID: sourceID, externalID: "1", title: "Connor Native RSS System", link: URL(string: "https://example.com/rss-system"), author: "Alice", publishedAt: now.addingTimeInterval(-60), snippet: "Commercial native RSS system fixture", state: RSSItemState(isRead: false), contentHash: RSSHash.sha256("Commercial native RSS system fixture body")), content: RSSItemContent(safeMarkdown: "# Connor Native RSS System\n\nCommercial native RSS system fixture body", plainText: "Connor Native RSS System Commercial native RSS system fixture body", rawHTMLHash: RSSHash.sha256("fixture"), byteCount: 52)),
            RSSItemDetail(summary: RSSItemSummary(id: RSSItemID(rawValue: "fixture-rss-item-2"), sourceID: sourceID, externalID: "2", title: "Graph Memory Evidence for Feeds", link: URL(string: "https://example.com/evidence"), author: "Bob", publishedAt: now.addingTimeInterval(-3600), snippet: "RSS items can become governed evidence candidates", state: RSSItemState(isRead: false, isStarred: true), contentHash: RSSHash.sha256("RSS evidence")), content: RSSItemContent(safeMarkdown: "RSS items can become governed evidence candidates", plainText: "RSS items can become governed evidence candidates", rawHTMLHash: nil, byteCount: 48))
        ]
        return RSSRuntime(repository: InMemoryRSSSourceRepository(sources: [source]), cache: InMemoryRSSSourceCache(items: items))
    }

    public func listSources(runID: String? = nil, sessionID: String? = nil) async throws -> [RSSSource] {
        let sources = try await repository.listSources()
        try await auditLog.record(RSSAuditRecord(runID: runID, sessionID: sessionID, kind: .sourceListed, riskClass: .read, redactedSummary: "Listed \(sources.count) RSS sources"))
        return sources
    }

    public func addSource(feedURL: URL, displayName: String? = nil, runID: String? = nil, sessionID: String? = nil) async throws -> RSSSource {
        let source = RSSSource(id: RSSIdentity.sourceID(feedURL: feedURL), feedURL: feedURL, displayName: displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? displayName! : (feedURL.host ?? feedURL.absoluteString), health: RSSSourceHealth(status: .unknown, summary: "Not synced"))
        try await repository.saveSource(source)
        try await auditLog.record(RSSAuditRecord(runID: runID, sessionID: sessionID, sourceID: source.id, kind: .sourceAdded, riskClass: .sourceManagement, redactedSummary: "Added RSS source \(source.displayName)", payloadHash: RSSHash.sha256(feedURL.absoluteString)))
        return source
    }

    public func updateSource(sourceID: RSSSourceID, feedURL: URL, displayName: String?, runID: String? = nil, sessionID: String? = nil) async throws -> RSSSource {
        guard var source = try await repository.source(id: sourceID) else { throw RSSRuntimeError.sourceNotFound(sourceID.rawValue) }
        let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let feedURLChanged = source.feedURL != feedURL
        source.feedURL = feedURL
        source.displayName = trimmedName.isEmpty ? (feedURL.host ?? feedURL.absoluteString) : trimmedName
        source.updatedAt = Date()
        if feedURLChanged {
            source.format = .unknown
            source.siteURL = nil
            source.iconURL = nil
            source.syncCursor = nil
            source.health = RSSSourceHealth(status: .unknown, summary: "Feed URL changed; sync required")
            try await cache.deleteItems(sourceID: sourceID)
        }
        try await repository.saveSource(source)
        try await auditLog.record(RSSAuditRecord(runID: runID, sessionID: sessionID, sourceID: sourceID, kind: .sourceUpdated, riskClass: .sourceManagement, redactedSummary: "Updated RSS source \(source.displayName)", payloadHash: RSSHash.sha256(feedURL.absoluteString)))
        return source
    }

    public func deleteSource(sourceID: RSSSourceID, runID: String? = nil, sessionID: String? = nil) async throws {
        guard let source = try await repository.source(id: sourceID) else { throw RSSRuntimeError.sourceNotFound(sourceID.rawValue) }
        try await repository.deleteSource(id: sourceID)
        try await cache.deleteItems(sourceID: sourceID)
        try await auditLog.record(RSSAuditRecord(runID: runID, sessionID: sessionID, sourceID: sourceID, kind: .sourceDeleted, riskClass: .sourceManagement, redactedSummary: "Deleted RSS source \(source.displayName)", payloadHash: RSSHash.sha256(source.feedURL.absoluteString)))
    }

    public func testSource(sourceID: RSSSourceID, runID: String? = nil, sessionID: String? = nil) async throws -> RSSParseReport {
        guard let source = try await repository.source(id: sourceID) else { throw RSSRuntimeError.sourceNotFound(sourceID.rawValue) }
        let data = try await fetcher.fetch(url: source.feedURL, timeoutSeconds: source.fetchPolicy.timeoutSeconds)
        let parsed = try parser.parse(data: data, source: source)
        let report = RSSParseReport(format: parsed.metadata.format, itemCount: parsed.items.count)
        try await auditLog.record(RSSAuditRecord(runID: runID, sessionID: sessionID, sourceID: sourceID, kind: .sourceTested, riskClass: .network, redactedSummary: "Tested RSS source; parsed \(report.itemCount) items"))
        return report
    }

    public func syncSource(sourceID: RSSSourceID, runID: String? = nil, sessionID: String? = nil) async throws -> RSSFetchResult {
        guard var source = try await repository.source(id: sourceID) else { throw RSSRuntimeError.sourceNotFound(sourceID.rawValue) }
        let data = try await fetcher.fetch(url: source.feedURL, timeoutSeconds: source.fetchPolicy.timeoutSeconds)
        let parsed = try parser.parse(data: data, source: source)
        let result = try await cache.upsertItems(parsed.items)
        source.displayName = parsed.metadata.title
        source.siteURL = parsed.metadata.siteURL
        source.iconURL = parsed.metadata.iconURL
        source.format = parsed.metadata.format
        source.syncCursor = RSSSyncCursor(value: ISO8601DateFormatter().string(from: Date()), lastItemDate: parsed.items.map(\.summary.publishedAt).max(), lastItemID: parsed.items.first?.id)
        source.health = RSSSourceHealth(status: .ready, summary: "Synced \(parsed.items.count) items")
        source.updatedAt = Date()
        try await repository.saveSource(source)
        let fetchResult = RSSFetchResult(runID: RSSFetchRunID(rawValue: UUID().uuidString), sourceID: sourceID, insertedCount: result.inserted, duplicateCount: result.duplicates, parseReport: RSSParseReport(format: parsed.metadata.format, itemCount: parsed.items.count))
        try await auditLog.record(RSSAuditRecord(runID: runID, sessionID: sessionID, sourceID: sourceID, kind: .sourceSynced, riskClass: .network, redactedSummary: "Synced RSS source; inserted \(result.inserted), duplicates \(result.duplicates)"))
        return fetchResult
    }

    public func searchItems(_ request: RSSRuntimeSearchRequest, runID: String? = nil, sessionID: String? = nil) async throws -> [RSSItemSummary] {
        let items: [RSSItemSummary]
        if let timeAwareCache = cache as? any TimeAwareRSSSourceCache {
            items = try await timeAwareCache.searchItems(query: request.query, sourceID: request.sourceID, includeHidden: request.includeHidden, temporalFilter: request.temporalFilter, temporalSort: request.timeSort, limit: request.limit)
        } else {
            let all = try await cache.searchItems(query: request.query, sourceID: request.sourceID, includeHidden: request.includeHidden)
            let filtered = request.temporalFilter.map { filter in all.filter { item in
                filter.contains(NativeSearchTemporalMetadata(primaryTime: item.publishedAt, primaryTimeKind: .publishedAt, publishedAt: item.publishedAt, fetchedAt: item.fetchedAt), sourceKind: .rss)
            } } ?? all
            items = filtered.sorted { lhs, rhs in request.timeSort == .timeAscThenRelevance || request.timeSort == .relevanceThenTimeAsc ? lhs.publishedAt < rhs.publishedAt : lhs.publishedAt > rhs.publishedAt }
        }
        try await auditLog.record(RSSAuditRecord(runID: runID, sessionID: sessionID, sourceID: request.sourceID, kind: .itemSearched, riskClass: .read, redactedSummary: "Searched RSS items; returned \(min(items.count, request.limit)) summaries"))
        return Array(items.prefix(request.limit))
    }

    public func listItems(sourceID: RSSSourceID? = nil, includeHidden: Bool = false, limit: Int = 50, runID: String? = nil, sessionID: String? = nil) async throws -> [RSSItemSummary] {
        let items = try await cache.listItems(sourceID: sourceID, includeHidden: includeHidden)
        try await auditLog.record(RSSAuditRecord(runID: runID, sessionID: sessionID, sourceID: sourceID, kind: .itemListed, riskClass: .read, redactedSummary: "Listed RSS items; returned \(min(items.count, limit)) summaries"))
        return Array(items.prefix(limit))
    }

    public func getItem(id: RSSItemID, includeContent: Bool = false, runID: String? = nil, sessionID: String? = nil) async throws -> RSSItemDetail {
        guard var detail = try await cache.item(id: id) else { throw RSSRuntimeError.itemNotFound(id.rawValue) }
        if !includeContent { detail.content = nil }
        try await auditLog.record(RSSAuditRecord(runID: runID, sessionID: sessionID, sourceID: detail.summary.sourceID, itemID: id, kind: includeContent ? .itemContentRead : .itemRead, riskClass: includeContent ? .contentRead : .read, redactedSummary: includeContent ? "Read RSS item content" : "Read RSS item summary", payloadHash: detail.summary.contentHash))
        return detail
    }

    public func setReadState(itemIDs: [RSSItemID], isRead: Bool, runID: String? = nil, sessionID: String? = nil) async throws {
        try await cache.updateState(itemIDs: itemIDs) { state in var copy = state; copy.isRead = isRead; return copy }
        try await auditLog.record(RSSAuditRecord(runID: runID, sessionID: sessionID, kind: .itemStateMutated, riskClass: .mutation, redactedSummary: "Set read state for \(itemIDs.count) RSS items to \(isRead)"))
    }

    public func setStarState(itemIDs: [RSSItemID], isStarred: Bool, runID: String? = nil, sessionID: String? = nil) async throws {
        try await cache.updateState(itemIDs: itemIDs) { state in var copy = state; copy.isStarred = isStarred; return copy }
        try await auditLog.record(RSSAuditRecord(runID: runID, sessionID: sessionID, kind: .itemStateMutated, riskClass: .mutation, redactedSummary: "Set star state for \(itemIDs.count) RSS items to \(isStarred)"))
    }

    public func setHiddenState(itemIDs: [RSSItemID], isHidden: Bool, runID: String? = nil, sessionID: String? = nil) async throws {
        try await cache.updateState(itemIDs: itemIDs) { state in var copy = state; copy.isHidden = isHidden; return copy }
        try await auditLog.record(RSSAuditRecord(runID: runID, sessionID: sessionID, kind: .itemStateMutated, riskClass: .mutation, redactedSummary: "Set hidden state for \(itemIDs.count) RSS items to \(isHidden)"))
    }

    public func importOPML(_ xml: String, runID: String? = nil, sessionID: String? = nil) async throws -> OPMLDocument {
        let document = try opmlService.parse(xml)
        for outline in document.outlines {
            _ = try await addSource(feedURL: outline.xmlURL, displayName: outline.title, runID: runID, sessionID: sessionID)
        }
        try await auditLog.record(RSSAuditRecord(runID: runID, sessionID: sessionID, kind: .opmlImported, riskClass: .importExport, redactedSummary: "Imported OPML with \(document.outlines.count) subscriptions"))
        return document
    }

    public func exportOPML(runID: String? = nil, sessionID: String? = nil) async throws -> String {
        let sources = try await repository.listSources()
        let document = OPMLDocument(title: "Connor RSS Subscriptions", outlines: sources.map { OPMLSubscriptionOutline(title: $0.displayName, xmlURL: $0.feedURL, htmlURL: $0.siteURL) })
        let xml = opmlService.export(document: document)
        try await auditLog.record(RSSAuditRecord(runID: runID, sessionID: sessionID, kind: .opmlExported, riskClass: .importExport, redactedSummary: "Exported OPML with \(sources.count) subscriptions", payloadHash: RSSHash.sha256(xml)))
        return xml
    }

    public func evidenceCandidate(for itemID: RSSItemID) async throws -> RSSEvidenceCandidate {
        let detail = try await getItem(id: itemID, includeContent: false)
        let candidate = RSSEvidenceCandidate(sourceID: detail.summary.sourceID, itemID: itemID, redactedSummary: detail.summary.title, sourceHash: detail.summary.contentHash)
        try await auditLog.record(RSSAuditRecord(sourceID: detail.summary.sourceID, itemID: itemID, kind: .evidenceCandidateCreated, riskClass: .read, redactedSummary: candidate.redactedSummary, payloadHash: candidate.sourceHash))
        return candidate
    }
}
