import Foundation
import ConnorGraphCore

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

public struct BrowserFetchTool: AgentTool {
    public let name = "browser_fetch"
    public let description = "Fetch a web page URL and return a lightweight text/HTML snapshot for the agent. Use this when you need to read a known URL directly before reasoning or creating graph evidence."
    public let permission: AgentPermissionCapability = .externalNetwork
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "url": .string(description: "The absolute http/https URL to fetch."),
        "max_chars": .integer(description: "Maximum number of characters to return. Defaults to 12000, capped at 50000."),
        "user_agent": .string(description: "Optional User-Agent header. Defaults to ConnorGraphAgent/1.0.")
    ], required: ["url"])

    public init() {}

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let urlString = arguments.string("url"), let url = URL(string: urlString), ["http", "https"].contains(url.scheme?.lowercased()) else {
            throw AgentToolError.invalidArguments("browser_fetch requires an absolute http/https url")
        }
        let maxChars = min(max(arguments.int("max_chars") ?? 12_000, 1_000), 50_000)
        let userAgent = arguments.string("user_agent") ?? "ConnorGraphAgent/1.0 (+https://local-agent)"

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,text/plain;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let mimeType = response.mimeType ?? "unknown"
        let decoded = Self.decodeWebPageText(data: data, responseEncodingName: response.textEncodingName)
        let extracted = Self.extractReadableText(from: decoded.text)
        let truncated = String(extracted.prefix(maxChars))
        let wasTruncated = extracted.count > maxChars

        let json = Self.encodeJSONObject([
            "url": url.absoluteString,
            "statusCode": statusCode,
            "mimeType": mimeType,
            "contentLength": data.count,
            "decodedEncoding": decoded.encodingName,
            "mojibakeRepaired": decoded.mojibakeRepaired,
            "returnedCharacters": truncated.count,
            "truncated": wasTruncated,
            "text": truncated
        ])

        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Fetched \(url.absoluteString) [status=\(statusCode), mime=\(mimeType)]\n\n\(truncated)\(wasTruncated ? "\n\n[truncated]" : "")",
            contentJSON: json,
            citations: [url.absoluteString]
        )
    }

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

    private static func extractReadableText(from html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: #"(?is)<script[^>]*>.*?</script>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?is)<style[^>]*>.*?</style>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?is)<noscript[^>]*>.*?</noscript>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?i)</(p|div|section|article|header|footer|li|h[1-6]|tr)>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: " ", options: .regularExpression)
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'")
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = text.replacingOccurrences(of: #"[ \t\f\r]+"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\n\s*\n\s*\n+"#, with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    fileprivate static func encodeJSONObject(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }
}

public struct SearchEngineMCPConfiguration: Sendable, Equatable {
    public var pythonExecutable: String?
    public var sourceDirectory: String?
    public var timeoutSeconds: TimeInterval

    public init(
        pythonExecutable: String? = nil,
        sourceDirectory: String? = nil,
        timeoutSeconds: TimeInterval = 90,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.pythonExecutable = Self.nonEmpty(pythonExecutable) ?? Self.nonEmpty(environment["CONNOR_SEARCH_ENGINE_MCP_PYTHON"])
        self.sourceDirectory = Self.nonEmpty(sourceDirectory) ?? Self.nonEmpty(environment["CONNOR_SEARCH_ENGINE_MCP_DIR"])
        self.timeoutSeconds = timeoutSeconds
    }

    public var isConfigured: Bool {
        pythonExecutable != nil && sourceDirectory != nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct SearchEngineMCPTool: AgentTool {
    public let name = "web_search"
    public let description = "Search the web through the configured search-engine-mcp source. Use this for current information, external grounding, Wikipedia/Wikidata lookup, and discovery before fetching a page."
    public let permission: AgentPermissionCapability = .externalNetwork
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "query": .string(description: "Search query keywords."),
        "engine": .string(description: "Search engine: duckduckgo, bing, google, yahoo, or baidu. Defaults to duckduckgo."),
        "max_results": .integer(description: "Maximum number of results, 1-10. Defaults to 5.")
    ], required: ["query"])

    private let configuration: SearchEngineMCPConfiguration
    private let browserAssistedSearchHandler: BrowserAssistedSearchHandler?
    private let nativeSearchClient: NativeWebSearchClient

    public init(
        configuration: SearchEngineMCPConfiguration = SearchEngineMCPConfiguration(),
        browserAssistedSearchHandler: BrowserAssistedSearchHandler? = nil,
        nativeSearchClient: NativeWebSearchClient = NativeWebSearchClient()
    ) {
        self.configuration = configuration
        self.browserAssistedSearchHandler = browserAssistedSearchHandler
        self.nativeSearchClient = nativeSearchClient
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let query = arguments.string("query"), !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentToolError.invalidArguments("web_search requires query")
        }
        let engine = (arguments.string("engine") ?? "duckduckgo").lowercased()
        let maxResults = min(max(arguments.int("max_results") ?? 5, 1), 10)

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
                    contentJSON: BrowserFetchTool.encodeJSONObject([
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
            contentJSON: BrowserFetchTool.encodeJSONObject([
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

public struct SearchEngineMCPWebFetchTool: AgentTool {
    public let name = "web_fetch"
    public let description = "Fetch and extract a web page through search-engine-mcp. Prefer this over browser_fetch when you want cleaned Markdown/text, tables, and optional JavaScript rendering."
    public let permission: AgentPermissionCapability = .externalNetwork
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "url": .string(description: "The absolute URL to fetch."),
        "extract_mode": .string(description: "markdown or text. Defaults to markdown."),
        "render_mode": .string(description: "auto, http, or js. Defaults to auto."),
        "wait_until": .string(description: "load, domcontentloaded, networkidle, or commit. Defaults to networkidle."),
        "timeout_ms": .integer(description: "Timeout in milliseconds. Defaults to 720000.")
    ], required: ["url"])

    private let configuration: SearchEngineMCPConfiguration
    private let browserAssistedSearchHandler: BrowserAssistedSearchHandler?
    private let browserAssistedWebFetchHandler: BrowserAssistedWebFetchHandler?
    private let nativeFetchClient: NativeWebFetchClient

    public init(
        configuration: SearchEngineMCPConfiguration = SearchEngineMCPConfiguration(),
        browserAssistedSearchHandler: BrowserAssistedSearchHandler? = nil,
        browserAssistedWebFetchHandler: BrowserAssistedWebFetchHandler? = nil,
        nativeFetchClient: NativeWebFetchClient = NativeWebFetchClient()
    ) {
        self.configuration = configuration
        self.browserAssistedSearchHandler = browserAssistedSearchHandler
        self.browserAssistedWebFetchHandler = browserAssistedWebFetchHandler
        self.nativeFetchClient = nativeFetchClient
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let url = arguments.string("url"), !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentToolError.invalidArguments("web_fetch requires url")
        }
        let renderMode = (arguments.string("render_mode") ?? "auto").lowercased()
        let extractMode = (arguments.string("extract_mode") ?? "markdown").lowercased()
        let waitUntil = (arguments.string("wait_until") ?? "networkidle").lowercased()
        let timeoutMilliseconds = arguments.int("timeout_ms") ?? 720_000
        if renderMode == "js", let browserAssistedWebFetchHandler {
            let request = BrowserAssistedWebFetchRequest(
                urlString: url,
                extractMode: extractMode,
                waitUntil: waitUntil,
                timeoutMilliseconds: timeoutMilliseconds,
                revealImmediately: false
            )
            if let browserResult = await browserAssistedWebFetchHandler(request) {
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
                        contentJSON: BrowserFetchTool.encodeJSONObject(json),
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
                        contentJSON: BrowserFetchTool.encodeJSONObject(json),
                        citations: [browserResult.urlString]
                    )
                case .failed, .timedOut:
                    throw AgentToolError.invalidArguments(browserResult.errorMessage ?? "Connor WKWebView web_fetch(js) failed with status \(browserResult.status.rawValue)")
                }
            }
        }
        let nativeResult = try await nativeFetchClient.fetch(
            urlString: url,
            extractMode: extractMode,
            timeoutMilliseconds: timeoutMilliseconds
        )
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: nativeResult.contentText,
            contentJSON: BrowserFetchTool.encodeJSONObject([
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
}

enum SearchEngineMCPSubprocess {
    static func call(tool: String, arguments: [String: Any], configuration: SearchEngineMCPConfiguration) async throws -> String {
        guard JSONSerialization.isValidJSONObject(arguments),
              let jsonData = try? JSONSerialization.data(withJSONObject: arguments),
              let json = String(data: jsonData, encoding: .utf8) else {
            throw AgentToolError.invalidArguments("Arguments must be JSON serializable")
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let result = try run(tool: tool, argumentsJSON: json, configuration: configuration)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func run(tool: String, argumentsJSON json: String, configuration: SearchEngineMCPConfiguration) throws -> String {
        let script = """
import asyncio, json, sys
from src.server import handle_call_tool

async def main():
    tool = sys.argv[1]
    args = json.loads(sys.argv[2])
    result = await handle_call_tool(tool, args)
    print("\\n".join(getattr(item, "text", str(item)) for item in result))

asyncio.run(main())
"""

        guard let pythonExecutable = configuration.pythonExecutable,
              let sourceDirectory = configuration.sourceDirectory else {
            throw AgentToolError.invalidArguments("search-engine-mcp is not configured. Set CONNOR_SEARCH_ENGINE_MCP_PYTHON and CONNOR_SEARCH_ENGINE_MCP_DIR, or inject SearchEngineMCPConfiguration explicitly.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonExecutable)
        process.arguments = ["-c", script, tool, json]
        process.currentDirectoryURL = URL(fileURLWithPath: sourceDirectory)

        var environment = ProcessInfo.processInfo.environment
        let existingPythonPath = environment["PYTHONPATH"]
        environment["PYTHONPATH"] = [sourceDirectory, existingPythonPath].compactMap { $0 }.joined(separator: ":")
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let deadline = Date().addingTimeInterval(configuration.timeoutSeconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            throw AgentToolError.invalidArguments("search-engine-mcp call timed out after \(Int(configuration.timeoutSeconds))s")
        }

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw AgentToolError.invalidArguments("search-engine-mcp failed: \(errorOutput.isEmpty ? output : errorOutput)")
        }
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !errorOutput.isEmpty {
            return errorOutput
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
