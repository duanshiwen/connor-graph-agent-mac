import Foundation
import ConnorGraphCore

enum WebFetchTimeoutPolicy {
    static let defaultMilliseconds = 30_000
    static let minimumMilliseconds = 1_000
    static let maximumMilliseconds = 60_000

    static func normalized(_ requestedMilliseconds: Int?) -> Int {
        min(max(requestedMilliseconds ?? defaultMilliseconds, minimumMilliseconds), maximumMilliseconds)
    }
}

private enum WebFetchDeadline {
    static func run<Value: Sendable>(
        toolName: String,
        timeoutMilliseconds: Int,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let (stream, continuation) = AsyncStream<Result<Value, any Error>>.makeStream(
            bufferingPolicy: .bufferingOldest(1)
        )
        let operationTask = Task {
            do {
                continuation.yield(.success(try await operation()))
            } catch {
                continuation.yield(.failure(error))
            }
            continuation.finish()
        }
        let timeoutTimer = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "com.connor.web-fetch-timeout.(UUID().uuidString)")
        )
        timeoutTimer.schedule(deadline: .now() + .milliseconds(timeoutMilliseconds))
        timeoutTimer.setEventHandler {
            continuation.yield(.failure(AgentToolError.invalidArguments(
                "\(toolName) timed out after \(timeoutMilliseconds)ms"
            )))
            continuation.finish()
        }
        timeoutTimer.resume()
        defer {
            operationTask.cancel()
            timeoutTimer.setEventHandler {}
            timeoutTimer.cancel()
            continuation.finish()
        }

        guard let result = await stream.first(where: { _ in true }) else {
            throw CancellationError()
        }
        return try result.get()
    }
}

public struct BrowserAssistedSearchRequest: Sendable, Equatable {
    public var query: String
    public var engine: String
    public var urlString: String
    public var title: String
    public var revealImmediately: Bool

    public init(query: String, engine: String, urlString: String, title: String, revealImmediately: Bool = false) {
        self.query = query
        self.engine = engine
        self.urlString = urlString
        self.title = title
        self.revealImmediately = revealImmediately
    }
}

public struct BrowserAssistedSearchResult: Sendable, Equatable {
    public var taskID: String
    public var sessionID: String
    public var tabID: String
    public var urlString: String
    public var status: String

    public init(taskID: String, sessionID: String, tabID: String, urlString: String, status: String) {
        self.taskID = taskID
        self.sessionID = sessionID
        self.tabID = tabID
        self.urlString = urlString
        self.status = status
    }
}

public typealias BrowserAssistedSearchHandler = @Sendable (BrowserAssistedSearchRequest) async -> BrowserAssistedSearchResult?

enum WebPageDecodingSupport {
    struct DecodedWebPageText: Sendable, Equatable {
        var text: String
        var encodingName: String
        var mojibakeRepaired: Bool
    }

    static func decodeWebPageText(data: Data, responseEncodingName: String?) -> DecodedWebPageText {
        let declaredEncodingNames = [responseEncodingName, declaredMetaCharset(in: data)]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var candidates: [(String, String.Encoding)] = []
        for name in declaredEncodingNames {
            if let encoding = stringEncoding(forCharsetName: name) {
                candidates.append((normalizedCharsetName(name), encoding))
            }
        }
        candidates.append(contentsOf: [
            ("utf-8", .utf8),
            ("gb18030", gb18030Encoding),
            ("gbk", gb18030Encoding),
            ("big5", big5Encoding),
            ("windows-1252", windows1252Encoding),
            ("iso-8859-1", .isoLatin1)
        ])

        var seen: Set<String> = []
        for (name, encoding) in candidates where seen.insert("\(name)-\(encoding.rawValue)").inserted {
            guard let text = String(data: data, encoding: encoding) else { continue }
            let repaired = repairMojibakeIfNeeded(text)
            return DecodedWebPageText(
                text: repaired.text,
                encodingName: repaired.wasRepaired ? "\(name)→\(repaired.encodingName)" : name,
                mojibakeRepaired: repaired.wasRepaired
            )
        }

        return DecodedWebPageText(text: String(decoding: data, as: UTF8.self), encodingName: "utf-8-lossy", mojibakeRepaired: false)
    }

    private static func declaredMetaCharset(in data: Data) -> String? {
        let prefix = data.prefix(4096)
        let probe = String(data: prefix, encoding: .ascii)
            ?? String(data: prefix, encoding: .isoLatin1)
            ?? ""
        let patterns = [
            #"(?i)<meta\s+[^>]*charset\s*=\s*["']?\s*([^\s"'>/;]+)"#,
            #"(?i)<meta\s+[^>]*http-equiv\s*=\s*["']?content-type["']?[^>]*content\s*=\s*["'][^"']*charset\s*=\s*([^\s"'>/;]+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(probe.startIndex..<probe.endIndex, in: probe)
            guard let match = regex.firstMatch(in: probe, range: range), match.numberOfRanges > 1,
                  let charsetRange = Range(match.range(at: 1), in: probe) else { continue }
            return String(probe[charsetRange])
        }
        return nil
    }

    private static func stringEncoding(forCharsetName name: String) -> String.Encoding? {
        switch normalizedCharsetName(name) {
        case "utf-8", "utf8": return .utf8
        case "iso-8859-1", "latin1", "latin-1": return .isoLatin1
        case "windows-1252", "cp1252": return windows1252Encoding
        case "gbk", "gb2312", "gb18030", "hz-gb-2312": return gb18030Encoding
        case "big5", "big-5": return big5Encoding
        default:
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
        }
    }

    private static func normalizedCharsetName(_ name: String) -> String {
        name.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n\"'"))
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
    }

    static var gb18030TestEncoding: String.Encoding { gb18030Encoding }

    private static var gb18030Encoding: String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    }

    private static var big5Encoding: String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
    }

    private static var windows1252Encoding: String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosLatin1.rawValue)))
    }

    private static func repairMojibakeIfNeeded(_ text: String) -> (text: String, wasRepaired: Bool, encodingName: String) {
        guard looksLikeMojibake(text), let latin1Data = text.data(using: .isoLatin1) else {
            return (text, false, "")
        }
        let repairCandidates: [(String, String.Encoding)] = [
            ("gb18030", gb18030Encoding),
            ("utf-8", .utf8),
            ("big5", big5Encoding)
        ]
        let originalScore = mojibakeScore(text)
        var best: (text: String, score: Int, encodingName: String)?
        for (name, encoding) in repairCandidates {
            guard let repaired = String(data: latin1Data, encoding: encoding) else { continue }
            let score = mojibakeScore(repaired)
            if best == nil || score < best!.score {
                best = (repaired, score, name)
            }
        }
        guard let best, best.score + 2 < originalScore else { return (text, false, "") }
        return (best.text, true, best.encodingName)
    }

    private static func looksLikeMojibake(_ text: String) -> Bool {
        mojibakeScore(text) >= 3
    }

    private static func mojibakeScore(_ text: String) -> Int {
        let markers = CharacterSet(charactersIn: "¿ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ×ØÙÚÛÜÝÞß¼½¾µ")
        return text.unicodeScalars.reduce(into: 0) { score, scalar in
            if markers.contains(scalar) { score += 1 }
            if scalar.value == 0xFFFD { score += 4 }
        }
    }

}

private enum WebToolJSON {
    static func encode(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    static func decode(_ string: String?) -> Any? {
        guard let string, let data = string.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}

public struct NativeWebSearchTool: AgentTool {
    public let name = "web_search"
    public let description = "Search the web using Connor's native web search client, with browser assistance for engines that require interactive rendering. Use this for current information, external grounding, Wikipedia/Wikidata lookup, and discovery before fetching a page."
    public let permission: AgentPermissionCapability = .externalNetwork
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "query": .string(description: "Search query keywords."),
        "engine": .stringEnumeration(values: ["duckduckgo", "bing", "google", "yahoo", "baidu"], description: "Search engine. Defaults to duckduckgo."),
        "maxResults": .integer(description: "Maximum number of results, 1-10. Defaults to 5.")
    ], required: ["query"])

    private let browserAssistedSearchHandler: BrowserAssistedSearchHandler?
    private let nativeSearchClient: NativeWebSearchClient

    public init(
        browserAssistedSearchHandler: BrowserAssistedSearchHandler? = nil,
        nativeSearchClient: NativeWebSearchClient = NativeWebSearchClient()
    ) {
        self.browserAssistedSearchHandler = browserAssistedSearchHandler
        self.nativeSearchClient = nativeSearchClient
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let query = arguments.string("query"), !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentToolError.invalidArguments("web_search requires query")
        }
        let engine = (arguments.string("engine") ?? "duckduckgo").lowercased()
        let maxResults = min(max(arguments.int("maxResults") ?? arguments.int("max_results") ?? 5, 1), 10)

        if Self.requiresBrowser(engine: engine), let browserAssistedSearchHandler {
            let urlString = Self.searchURLString(query: query, engine: engine)
            let request = BrowserAssistedSearchRequest(
                query: query,
                engine: engine,
                urlString: urlString,
                title: "Search: \(query)",
                revealImmediately: false
            )
            if let browserResult = await browserAssistedSearchHandler(request) {
                let text = """
                Search opened in Connor's built-in browser background runner.
                Engine: \(engine)
                Query: \(query)
                URL: \(browserResult.urlString)
                Task ID: \(browserResult.taskID)
                Browser session ID: \(browserResult.sessionID)
                Browser tab ID: \(browserResult.tabID)
                Status: \(browserResult.status)

                If the search page completes normally, it remains in the background. If the page requires CAPTCHA, human verification, unusual-traffic handling, or a browser security challenge, Connor will switch to the corresponding built-in browser tab and ask the user to intervene.
                """
                return AgentToolResult(
                    toolCallID: context.toolCallID,
                    toolName: name,
                    contentText: text,
                    contentJSON: WebToolJSON.encode([
                        "query": query,
                        "engine": engine,
                        "maxResults": maxResults,
                        "browserAssisted": true,
                        "taskID": browserResult.taskID,
                        "sessionID": browserResult.sessionID,
                        "tabID": browserResult.tabID,
                        "url": browserResult.urlString,
                        "status": browserResult.status
                    ]),
                    citations: [browserResult.urlString]
                )
            }
        }

        let nativeResult = try await nativeSearchClient.search(query: query, engine: engine, maxResults: maxResults)
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: nativeResult.markdown,
            contentJSON: WebToolJSON.encode([
                "query": nativeResult.query,
                "engine": nativeResult.engine,
                "maxResults": maxResults,
                "results": nativeResult.results.map { ["title": $0.title, "url": $0.url, "snippet": $0.snippet] },
                "text": nativeResult.markdown
            ]),
            citations: nativeResult.results.map(\.url)
        )
    }

    private static func requiresBrowser(engine: String) -> Bool {
        switch engine.lowercased() {
        case "google", "bing", "baidu":
            return true
        default:
            return false
        }
    }

    private static func searchURLString(query: String, engine: String) -> String {
        var components = URLComponents()
        switch engine.lowercased() {
        case "google":
            components.scheme = "https"
            components.host = "www.google.com"
            components.path = "/search"
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        case "bing":
            components.scheme = "https"
            components.host = "www.bing.com"
            components.path = "/search"
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        case "baidu":
            components.scheme = "https"
            components.host = "www.baidu.com"
            components.path = "/s"
            components.queryItems = [URLQueryItem(name: "wd", value: query)]
        default:
            components.scheme = "https"
            components.host = "duckduckgo.com"
            components.path = "/"
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        }
        return components.url?.absoluteString ?? "https://duckduckgo.com/?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)"
    }

    private static func extractURLs(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s)]+"#) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var seen = Set<String>()
        return regex.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            let url = String(text[swiftRange]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;"))
            guard seen.insert(url).inserted else { return nil }
            return url
        }
    }
}

public struct NativeImageSearchTool: AgentTool {
    public let name = "image_search"
    public let description = "Search Openverse, Wikimedia Commons, general web image search (Bing Images), and Unsplash (when UNSPLASH_ACCESS_KEY is configured) for existing images of places, products, people, landmarks, and other real-world subjects. Submit exactly one concise English search phrase per call, translating the user's visual intent while preserving proper names. Choose the single best query; never pack alternative queries into englishQuery; never issue multiple image_search calls in parallel. Returns candidates, per-provider availability reasons, explicit retry guidance, and a text-only fallback when image services cannot be reached. Images remain optional and must not block an otherwise complete answer."
    public let permission: AgentPermissionCapability = .externalNetwork
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "englishQuery": .string(description: "Exactly one concise English image-search phrase. Translate non-English requests, preserve proper names, and add an established English entity name when useful. Do not provide a list or alternatives separated by commas, semicolons, slashes, newlines, or OR."),
        "maxResults": .integer(description: "Maximum number of candidates, 1-10. Defaults to 5."),
        "licenseFilter": .stringEnumeration(values: ["all", "commercial", "modification"], description: "Optional reuse filter. Defaults to all.")
    ], required: ["englishQuery"])

    private let client: NativeImageSearchClient

    public init(client: NativeImageSearchClient = NativeImageSearchClient()) {
        self.client = client
    }

    public func normalizeLegacyArguments(_ arguments: AgentToolArguments) -> AgentToolArguments {
        arguments.normalizingAliases([
            "englishQuery": ["query", "q", "keywords", "searchQuery"],
            "maxResults": ["max_results", "limit"],
            "licenseFilter": ["license_filter"]
        ])
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let englishQuery = arguments.string("englishQuery"), !englishQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentToolError.invalidArguments("image_search requires englishQuery with concise English search terms")
        }
        let maxResults = min(max(arguments.int("maxResults") ?? 5, 1), 10)
        let rawFilter = arguments.string("licenseFilter") ?? NativeImageSearchLicenseFilter.all.rawValue
        guard let licenseFilter = NativeImageSearchLicenseFilter(rawValue: rawFilter.lowercased()) else {
            throw AgentToolError.invalidArguments("image_search licenseFilter must be all, commercial, or modification")
        }

        let result = try await client.search(englishQuery: englishQuery, maxResults: maxResults, licenseFilter: licenseFilter)
        let resultText = modelGuidance(for: result)
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: result.markdown.isEmpty ? resultText : result.markdown,
            contentJSON: WebToolJSON.encode([
                "query": result.query,
                "queryLanguage": "en",
                "provider": result.provider,
                "providers": result.diagnostics.map { diagnostic in
                    [
                        "provider": diagnostic.provider,
                        "status": diagnostic.status.rawValue,
                        "reason": diagnostic.reason,
                        "retryAdvice": diagnostic.retryAdvice.rawValue
                    ]
                },
                "retryAdvice": result.retryAdvice.rawValue,
                "fallbackAction": fallbackAction(for: result),
                "licenseFilter": result.licenseFilter.rawValue,
                "results": result.results.map { item in
                    [
                        "title": item.title,
                        "imageURL": item.imageURL,
                        "thumbnailURL": item.thumbnailURL,
                        "sourcePageURL": item.sourcePageURL,
                        "creator": item.creator,
                        "creatorURL": item.creatorURL,
                        "license": item.license,
                        "licenseURL": item.licenseURL,
                        "attribution": item.attribution,
                        "width": item.width.map { $0 as Any } ?? NSNull(),
                        "height": item.height.map { $0 as Any } ?? NSNull()
                    ] as [String: Any]
                },
                "text": result.markdown.isEmpty ? resultText : result.markdown
            ]),
            citations: result.results.map(\.sourcePageURL),
            error: result.results.isEmpty ? resultText : nil
        )
    }

    private func modelGuidance(for result: NativeImageSearchResult) -> String {
        let reasons = result.diagnostics.map { "\($0.provider): \($0.reason)" }.joined(separator: " ")
        switch result.retryAdvice {
        case .notNeeded:
            return result.markdown
        case .retryWithEnglishQuery:
            return "Image search did not run because englishQuery was not written as English search terms. Translate and retry once immediately with a concise English query."
        case .retryOnceWithBroaderEnglishQuery:
            return "No suitable image candidates were found. You may retry once immediately with broader English terms; otherwise continue without an image."
        case .retryLater:
            return "Image search services are currently unreachable or temporarily unavailable. \(reasons) Do not retry image_search again in this run. Continue the user's task without image search or an inserted image; a later run may retry."
        case .doNotRetry:
            return "Image search cannot be used in this run. \(reasons) Do not retry this tool unless its configuration, permission, or provider compatibility changes. Continue without an image when visual evidence is not essential."
        }
    }

    private func fallbackAction(for result: NativeImageSearchResult) -> String {
        result.results.isEmpty ? "continue_without_image" : "use_candidates_if_relevant"
    }
}

public struct BrowserAssistedWebFetchRequest: Equatable, Sendable {
    public var urlString: String
    public var extractMode: String
    public var waitUntil: String
    public var timeoutMilliseconds: Int
    public var revealImmediately: Bool

    public init(urlString: String, extractMode: String, waitUntil: String, timeoutMilliseconds: Int, revealImmediately: Bool = false) {
        self.urlString = urlString
        self.extractMode = extractMode
        self.waitUntil = waitUntil
        self.timeoutMilliseconds = timeoutMilliseconds
        self.revealImmediately = revealImmediately
    }
}

public enum BrowserAssistedWebFetchStatus: String, Sendable {
    case fetched
    case needsUserIntervention
    case failed
    case timedOut
}

public struct BrowserAssistedWebFetchResult: Equatable, Sendable {
    public var status: BrowserAssistedWebFetchStatus
    public var urlString: String
    public var finalURLString: String
    public var title: String
    public var contentText: String
    public var taskID: String
    public var sessionID: String
    public var tabID: String
    public var errorMessage: String?
    public var interventionReason: String?
    public var truncated: Bool
    public var originalCharacterCount: Int

    public init(
        status: BrowserAssistedWebFetchStatus,
        urlString: String,
        finalURLString: String,
        title: String,
        contentText: String,
        taskID: String,
        sessionID: String,
        tabID: String,
        errorMessage: String?,
        interventionReason: String?,
        truncated: Bool,
        originalCharacterCount: Int
    ) {
        self.status = status
        self.urlString = urlString
        self.finalURLString = finalURLString
        self.title = title
        self.contentText = contentText
        self.taskID = taskID
        self.sessionID = sessionID
        self.tabID = tabID
        self.errorMessage = errorMessage
        self.interventionReason = interventionReason
        self.truncated = truncated
        self.originalCharacterCount = originalCharacterCount
    }
}

public typealias BrowserAssistedWebFetchHandler = @Sendable (BrowserAssistedWebFetchRequest) async -> BrowserAssistedWebFetchResult?

public struct NativeWebFetchTool: AgentTool {
    public let name = "web_fetch"
    public let description = "Fetch and extract one page with url or up to 10 independent pages concurrently with urls. Prefer urls whenever multiple page URLs are already known. Connor tries the native HTTP extractor first and automatically falls back to its WKWebView browser session when auto rendering encounters HTTP errors, blocked or unusable content, or JavaScript-dependent pages. Use renderMode js when a retained login session or browser rendering is known to be required. Never use browser assistance to bypass authorization or access content the user is not permitted to access."
    public let permission: AgentPermissionCapability = .externalNetwork
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "url": .string(description: "One absolute http/https URL. Use either url or urls, never both."),
        "urls": .array(items: .string(description: "An absolute http/https URL."), description: "One to 10 independent URLs fetched concurrently with a maximum concurrency of 4. Prefer this over multiple web_fetch calls when the URLs are known together."),
        "extractMode": .stringEnumeration(values: ["markdown", "text"], description: "Extraction format. Defaults to markdown."),
        "renderMode": .stringEnumeration(values: ["auto", "http", "js"], description: "Rendering strategy. Defaults to auto."),
        "waitUntil": .stringEnumeration(values: ["load", "domcontentloaded", "networkidle", "commit"], description: "Page readiness condition. Defaults to networkidle."),
        "timeoutMs": .integer(description: "Per-page timeout in milliseconds. Defaults to 30000, capped at 60000.")
    ], required: [])

    private static let maximumBatchSize = 10
    private static let maximumBatchConcurrency = 4

    private let browserAssistedWebFetchHandler: BrowserAssistedWebFetchHandler?
    private let nativeFetchClient: NativeWebFetchClient

    public init(
        browserAssistedWebFetchHandler: BrowserAssistedWebFetchHandler? = nil,
        nativeFetchClient: NativeWebFetchClient = NativeWebFetchClient()
    ) {
        self.browserAssistedWebFetchHandler = browserAssistedWebFetchHandler
        self.nativeFetchClient = nativeFetchClient
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let singleURL = arguments.string("url")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let batchURLs = arguments.array("urls")?.compactMap(\.stringValue).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard singleURL == nil || batchURLs == nil else {
            throw AgentToolError.invalidArguments("web_fetch accepts either url or urls, not both")
        }
        let urls = singleURL.map { [$0] } ?? batchURLs ?? []
        guard !urls.isEmpty, urls.allSatisfy({ !$0.isEmpty }) else {
            throw AgentToolError.invalidArguments("web_fetch requires a non-empty url or urls array")
        }
        guard urls.count <= Self.maximumBatchSize else {
            throw AgentToolError.invalidArguments("web_fetch urls accepts at most \(Self.maximumBatchSize) URLs")
        }
        guard urls.allSatisfy(Self.isAbsoluteWebURL) else {
            throw AgentToolError.invalidArguments("web_fetch requires absolute http/https URLs")
        }
        let renderMode = (arguments.string("renderMode") ?? arguments.string("render_mode") ?? "auto").lowercased()
        let extractMode = (arguments.string("extractMode") ?? arguments.string("extract_mode") ?? "markdown").lowercased()
        let waitUntil = (arguments.string("waitUntil") ?? arguments.string("wait_until") ?? "networkidle").lowercased()
        let timeoutMilliseconds = WebFetchTimeoutPolicy.normalized(arguments.int("timeoutMs") ?? arguments.int("timeout_ms"))
        if batchURLs != nil {
            return await executeBatch(
                urls: urls,
                renderMode: renderMode,
                extractMode: extractMode,
                waitUntil: waitUntil,
                timeoutMilliseconds: timeoutMilliseconds,
                context: context
            )
        }
        return try await fetchOne(
            url: urls[0],
            renderMode: renderMode,
            extractMode: extractMode,
            waitUntil: waitUntil,
            timeoutMilliseconds: timeoutMilliseconds,
            context: context
        )
    }

    private func fetchOne(
        url: String,
        renderMode: String,
        extractMode: String,
        waitUntil: String,
        timeoutMilliseconds: Int,
        context: AgentToolExecutionContext
    ) async throws -> AgentToolResult {
        return try await WebFetchDeadline.run(toolName: name, timeoutMilliseconds: timeoutMilliseconds) {
            try await executeWithinDeadline(
                url: url,
                renderMode: renderMode,
                extractMode: extractMode,
                waitUntil: waitUntil,
                timeoutMilliseconds: timeoutMilliseconds,
                context: context
            )
        }
    }

    private func executeBatch(
        urls: [String],
        renderMode: String,
        extractMode: String,
        waitUntil: String,
        timeoutMilliseconds: Int,
        context: AgentToolExecutionContext
    ) async -> AgentToolResult {
        let outcomes = await AgentToolBatchScheduler(maximumConcurrency: Self.maximumBatchConcurrency).run(urls) { url in
            do {
                return WebFetchBatchOutcome(
                    url: url,
                    result: try await fetchOne(
                        url: url,
                        renderMode: renderMode,
                        extractMode: extractMode,
                        waitUntil: waitUntil,
                        timeoutMilliseconds: timeoutMilliseconds,
                        context: context
                    ),
                    error: nil
                )
            } catch {
                return WebFetchBatchOutcome(url: url, result: nil, error: String(describing: error))
            }
        }
        let citations = outcomes.flatMap { $0.result?.citations ?? [] }.reduce(into: [String]()) { collected, citation in
            if !collected.contains(citation) { collected.append(citation) }
        }
        let entries: [[String: Any]] = outcomes.map { outcome in
            if let result = outcome.result {
                return [
                    "requestedURL": outcome.url,
                    "success": true,
                    "content": result.contentText,
                    "metadata": WebToolJSON.decode(result.contentJSON) ?? NSNull()
                ]
            }
            return [
                "requestedURL": outcome.url,
                "success": false,
                "error": outcome.error ?? "Unknown web fetch error"
            ]
        }
        let contentText = outcomes.enumerated().map { index, outcome in
            let body = outcome.result?.contentText ?? "Error: \(outcome.error ?? "Unknown web fetch error")"
            return "[\(index + 1)] \(outcome.url)\n\(body)"
        }.joined(separator: "\n\n")
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: contentText,
            contentJSON: WebToolJSON.encode([
                "requestedCount": outcomes.count,
                "succeededCount": outcomes.count(where: { $0.result != nil }),
                "failedCount": outcomes.count(where: { $0.result == nil }),
                "maximumConcurrency": Self.maximumBatchConcurrency,
                "results": entries
            ]),
            citations: citations
        )
    }

    private func executeWithinDeadline(
        url: String,
        renderMode: String,
        extractMode: String,
        waitUntil: String,
        timeoutMilliseconds: Int,
        context: AgentToolExecutionContext
    ) async throws -> AgentToolResult {
        if renderMode == "js", let result = try await executeBrowserAssistedFetch(
            url: url,
            extractMode: extractMode,
            waitUntil: waitUntil,
            timeoutMilliseconds: timeoutMilliseconds,
            renderMode: renderMode,
            context: context
        ) {
            return result
        }
        let nativeResult: NativeWebFetchResult
        do {
            nativeResult = try await nativeFetchClient.fetch(
                urlString: url,
                extractMode: extractMode,
                timeoutMilliseconds: timeoutMilliseconds,
                onRetryProgress: { [context] message in
                    context.publishToolProgress(toolName: name, message: message)
                }
            )
        } catch {
            if renderMode == "auto", let result = try await executeBrowserAssistedFetch(
                url: url,
                extractMode: extractMode,
                waitUntil: waitUntil,
                timeoutMilliseconds: timeoutMilliseconds,
                renderMode: renderMode,
                context: context
            ) {
                return result
            }
            throw error
        }
        if renderMode == "auto",
           nativeResult.contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let result = try await executeBrowserAssistedFetch(
               url: url,
               extractMode: extractMode,
               waitUntil: waitUntil,
               timeoutMilliseconds: timeoutMilliseconds,
               renderMode: renderMode,
               context: context
           ) {
            return result
        }
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: nativeResult.contentText,
            contentJSON: WebToolJSON.encode([
                "url": nativeResult.urlString,
                "finalURL": nativeResult.finalURLString,
                "title": nativeResult.title,
                "renderMode": renderMode,
                "extractMode": extractMode,
                "engine": nativeResult.engine,
                "statusCode": nativeResult.statusCode,
                "mimeType": nativeResult.mimeType,
                "truncated": nativeResult.truncated,
                "originalCharacterCount": nativeResult.originalCharacterCount,
                "text": nativeResult.contentText
            ]),
            citations: [nativeResult.finalURLString.isEmpty ? nativeResult.urlString : nativeResult.finalURLString]
        )
    }

    private func executeBrowserAssistedFetch(
        url: String,
        extractMode: String,
        waitUntil: String,
        timeoutMilliseconds: Int,
        renderMode: String,
        context: AgentToolExecutionContext
    ) async throws -> AgentToolResult? {
        guard let browserAssistedWebFetchHandler else { return nil }
        let request = BrowserAssistedWebFetchRequest(
            urlString: url,
            extractMode: extractMode,
            waitUntil: waitUntil,
            timeoutMilliseconds: timeoutMilliseconds,
            revealImmediately: false
        )
        guard let browserResult = await browserAssistedWebFetchHandler(request) else { return nil }
        let json: [String: Any] = [
            "url": browserResult.urlString,
            "finalURL": browserResult.finalURLString,
            "title": browserResult.title,
            "renderMode": renderMode,
            "engine": "wkwebview",
            "browserAssisted": true,
            "taskID": browserResult.taskID,
            "sessionID": browserResult.sessionID,
            "tabID": browserResult.tabID,
            "status": browserResult.status.rawValue,
            "errorMessage": browserResult.errorMessage as Any,
            "interventionReason": browserResult.interventionReason as Any,
            "truncated": browserResult.truncated,
            "originalCharacterCount": browserResult.originalCharacterCount
        ]
        switch browserResult.status {
        case .fetched:
            return AgentToolResult(
                toolCallID: context.toolCallID,
                toolName: name,
                contentText: browserResult.contentText,
                contentJSON: WebToolJSON.encode(json),
                citations: [browserResult.finalURLString.isEmpty ? browserResult.urlString : browserResult.finalURLString]
            )
        case .needsUserIntervention:
            let reason = browserResult.interventionReason ?? "Browser page requires user intervention."
            let text = """
            Connor opened this page in the built-in browser, but it requires user intervention.
            URL: \(browserResult.urlString)
            Final URL: \(browserResult.finalURLString)
            Reason: \(reason)
            Task ID: \(browserResult.taskID)
            Browser session ID: \(browserResult.sessionID)
            Browser tab ID: \(browserResult.tabID)
            """
            return AgentToolResult(
                toolCallID: context.toolCallID,
                toolName: name,
                contentText: text,
                contentJSON: WebToolJSON.encode(json),
                citations: [browserResult.urlString]
            )
        case .failed, .timedOut:
            throw AgentToolError.invalidArguments(browserResult.errorMessage ?? "Connor WKWebView web_fetch(js) failed with status \(browserResult.status.rawValue)")
        }
    }

    private static func isAbsoluteWebURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }
}

private struct WebFetchBatchOutcome: Sendable {
    var url: String
    var result: AgentToolResult?
    var error: String?
}
