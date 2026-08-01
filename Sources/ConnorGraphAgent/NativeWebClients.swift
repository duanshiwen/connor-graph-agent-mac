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

        let decoded = WebPageDecodingSupport.decodeWebPageText(data: response.data, responseEncodingName: response.textEncodingName)
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

        let decoded = WebPageDecodingSupport.decodeWebPageText(data: response.data, responseEncodingName: response.textEncodingName)
        let results = Array(NativeWebSearchParser.duckDuckGoResults(from: decoded.text).prefix(max(1, min(maxResults, 10))))
        let markdown = results.enumerated().map { index, item in
            var lines = ["\(index + 1). \(item.title)", "   URL: \(item.url)"]
            if !item.snippet.isEmpty { lines.append("   Snippet: \(item.snippet)") }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")

        return NativeWebSearchResult(query: query, engine: normalizedEngine, results: results, markdown: markdown)
    }
}

public enum NativeImageSearchLicenseFilter: String, Sendable, Equatable {
    case all
    case commercial
    case modification
}

public enum NativeImageSearchProviderStatus: String, Sendable, Equatable {
    case succeeded
    case noResults = "no_results"
    case failed
    case invalidQuery = "invalid_query"
}

public enum NativeImageSearchRetryAdvice: String, Sendable, Equatable {
    case notNeeded = "not_needed"
    case retryWithEnglishQuery = "retry_with_english_query"
    case retryOnceWithBroaderEnglishQuery = "retry_once_with_broader_english_query"
    case retryLater = "retry_later"
    case doNotRetry = "do_not_retry"
}

public struct NativeImageSearchProviderDiagnostic: Sendable, Equatable {
    public var provider: String
    public var status: NativeImageSearchProviderStatus
    public var reason: String
    public var retryAdvice: NativeImageSearchRetryAdvice
}

public struct NativeImageSearchResultItem: Sendable, Equatable {
    public var title: String
    public var imageURL: String
    public var thumbnailURL: String
    public var sourcePageURL: String
    public var creator: String
    public var creatorURL: String
    public var license: String
    public var licenseURL: String
    public var attribution: String
    public var width: Int?
    public var height: Int?
}

public struct NativeImageSearchResult: Sendable, Equatable {
    public var query: String
    public var provider: String
    public var licenseFilter: NativeImageSearchLicenseFilter
    public var results: [NativeImageSearchResultItem]
    public var markdown: String
    public var diagnostics: [NativeImageSearchProviderDiagnostic]
    public var retryAdvice: NativeImageSearchRetryAdvice
}

public struct NativeImageSearchClient: Sendable {
    private struct ProviderAttempt: Sendable {
        var results: [NativeImageSearchResultItem]
        var diagnostic: NativeImageSearchProviderDiagnostic
    }

    private let httpClient: any NativeWebHTTPClient

    public init(httpClient: any NativeWebHTTPClient = URLSessionNativeWebHTTPClient()) {
        self.httpClient = httpClient
    }

    public func search(
        englishQuery: String,
        maxResults: Int,
        licenseFilter: NativeImageSearchLicenseFilter
    ) async throws -> NativeImageSearchResult {
        let normalizedQuery = englishQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            throw AgentToolError.invalidArguments("image_search requires englishQuery")
        }
        guard normalizedQuery.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil else {
            let diagnostic = NativeImageSearchProviderDiagnostic(
                provider: "input",
                status: .invalidQuery,
                reason: "englishQuery does not contain English search terms.",
                retryAdvice: .retryWithEnglishQuery
            )
            return result(
                query: normalizedQuery,
                licenseFilter: licenseFilter,
                attempts: [ProviderAttempt(results: [], diagnostic: diagnostic)],
                limit: 0
            )
        }
        let resultLimit = min(max(maxResults, 1), 10)
        let openverse = await searchOpenverse(
            englishQuery: normalizedQuery,
            maxResults: resultLimit,
            licenseFilter: licenseFilter
        )
        let commons = await searchWikimediaCommons(
            englishQuery: normalizedQuery,
            maxResults: resultLimit
        )
        return result(
            query: normalizedQuery,
            licenseFilter: licenseFilter,
            attempts: [openverse, commons],
            limit: resultLimit
        )
    }

    // Keep callers using the original label source-compatible while the tool schema migrates.
    public func search(
        query: String,
        maxResults: Int,
        licenseFilter: NativeImageSearchLicenseFilter
    ) async throws -> NativeImageSearchResult {
        try await search(englishQuery: query, maxResults: maxResults, licenseFilter: licenseFilter)
    }

    private func searchOpenverse(
        englishQuery: String,
        maxResults: Int,
        licenseFilter: NativeImageSearchLicenseFilter
    ) async -> ProviderAttempt {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.openverse.org"
        components.path = "/v1/images/"
        components.queryItems = [
            URLQueryItem(name: "q", value: englishQuery),
            URLQueryItem(name: "page_size", value: String(maxResults)),
            URLQueryItem(name: "mature", value: "false")
        ]
        if licenseFilter != .all {
            components.queryItems?.append(URLQueryItem(name: "license_type", value: licenseFilter.rawValue))
        }
        guard let url = components.url else {
            return failedAttempt(provider: "openverse", reason: "Could not construct the Openverse request URL.", retryAdvice: .doNotRetry)
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let response: NativeWebHTTPResponse
        do {
            response = try await httpClient.data(for: request)
        } catch {
            return networkFailureAttempt(provider: "openverse", error: error)
        }
        guard (200..<300).contains(response.statusCode) else {
            return httpFailureAttempt(provider: "openverse", statusCode: response.statusCode)
        }
        let decoded: OpenverseImageSearchResponse
        do {
            decoded = try JSONDecoder().decode(OpenverseImageSearchResponse.self, from: response.data)
        } catch {
            return failedAttempt(
                provider: "openverse",
                reason: "Openverse returned an incompatible response. The provider contract may have changed.",
                retryAdvice: .doNotRetry
            )
        }

        return successfulAttempt(provider: "openverse", results: Array(decoded.results.compactMap(\.resultItem).prefix(maxResults)))
    }

    private func searchWikimediaCommons(englishQuery: String, maxResults: Int) async -> ProviderAttempt {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "commons.wikimedia.org"
        components.path = "/w/api.php"
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: "\(englishQuery) filetype:bitmap"),
            URLQueryItem(name: "gsrnamespace", value: "6"),
            URLQueryItem(name: "gsrlimit", value: String(maxResults)),
            URLQueryItem(name: "gsrsort", value: "relevance"),
            URLQueryItem(name: "prop", value: "imageinfo"),
            URLQueryItem(name: "iiprop", value: "url|extmetadata"),
            URLQueryItem(name: "iiurlwidth", value: "1200"),
            URLQueryItem(name: "iiextmetadatalanguage", value: "en"),
            URLQueryItem(name: "iiextmetadatafilter", value: "Artist|LicenseShortName|LicenseUrl|Attribution|ImageDescription"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "origin", value: "*")
        ]
        guard let url = components.url else {
            return failedAttempt(provider: "wikimedia_commons", reason: "Could not construct the Wikimedia Commons request URL.", retryAdvice: .doNotRetry)
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let response: NativeWebHTTPResponse
        do {
            response = try await httpClient.data(for: request)
        } catch {
            return networkFailureAttempt(provider: "wikimedia_commons", error: error)
        }
        guard (200..<300).contains(response.statusCode) else {
            return httpFailureAttempt(provider: "wikimedia_commons", statusCode: response.statusCode)
        }
        let decoded: WikimediaCommonsImageSearchResponse
        do {
            decoded = try JSONDecoder().decode(WikimediaCommonsImageSearchResponse.self, from: response.data)
        } catch {
            return failedAttempt(
                provider: "wikimedia_commons",
                reason: "Wikimedia Commons returned an incompatible response. The provider contract may have changed.",
                retryAdvice: .doNotRetry
            )
        }
        if let apiError = decoded.error {
            return failedAttempt(
                provider: "wikimedia_commons",
                reason: "Wikimedia Commons rejected the request (\(apiError.code)): \(apiError.info)",
                retryAdvice: .doNotRetry
            )
        }
        let results = decoded.query?.pages
            .sorted { ($0.index ?? Int.max) < ($1.index ?? Int.max) }
            .compactMap(\.resultItem) ?? []
        return successfulAttempt(provider: "wikimedia_commons", results: Array(results.prefix(maxResults)))
    }

    private func result(
        query: String,
        licenseFilter: NativeImageSearchLicenseFilter,
        attempts: [ProviderAttempt],
        limit: Int
    ) -> NativeImageSearchResult {
        let merged = roundRobinMerge(attempts.map(\.results), limit: limit)
        let successfulProviders = attempts
            .filter { $0.diagnostic.status == .succeeded }
            .map(\.diagnostic.provider)
        let diagnostics = attempts.map(\.diagnostic)
        let retryAdvice: NativeImageSearchRetryAdvice
        if !merged.isEmpty {
            retryAdvice = .notNeeded
        } else if diagnostics.contains(where: { $0.status == .invalidQuery }) {
            retryAdvice = .retryWithEnglishQuery
        } else if diagnostics.contains(where: { $0.status == .noResults }) {
            retryAdvice = .retryOnceWithBroaderEnglishQuery
        } else if diagnostics.contains(where: { $0.retryAdvice == .retryLater }) {
            retryAdvice = .retryLater
        } else {
            retryAdvice = .doNotRetry
        }
        return NativeImageSearchResult(
            query: query,
            provider: successfulProviders.isEmpty ? "none" : successfulProviders.joined(separator: "+"),
            licenseFilter: licenseFilter,
            results: merged,
            markdown: markdown(for: merged),
            diagnostics: diagnostics,
            retryAdvice: retryAdvice
        )
    }

    private func roundRobinMerge(_ resultSets: [[NativeImageSearchResultItem]], limit: Int) -> [NativeImageSearchResultItem] {
        guard limit > 0 else { return [] }
        var merged: [NativeImageSearchResultItem] = []
        var seenImageURLs = Set<String>()
        var seenSourceURLs = Set<String>()
        let maximumCount = resultSets.map(\.count).max() ?? 0
        for index in 0..<maximumCount {
            for results in resultSets where index < results.count {
                let item = results[index]
                guard seenImageURLs.insert(item.imageURL).inserted,
                      seenSourceURLs.insert(item.sourcePageURL).inserted else { continue }
                merged.append(item)
                if merged.count == limit { return merged }
            }
        }
        return merged
    }

    private func markdown(for results: [NativeImageSearchResultItem]) -> String {
        results.enumerated().map { index, item in
            var lines = [
                "\(index + 1). \(item.title)",
                "   Image URL: \(item.imageURL)",
                "   Source page: \(item.sourcePageURL)"
            ]
            if !item.creator.isEmpty { lines.append("   Creator: \(item.creator)") }
            if !item.license.isEmpty { lines.append("   License: \(item.license)") }
            if !item.attribution.isEmpty { lines.append("   Attribution: \(item.attribution)") }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private func successfulAttempt(provider: String, results: [NativeImageSearchResultItem]) -> ProviderAttempt {
        let status: NativeImageSearchProviderStatus = results.isEmpty ? .noResults : .succeeded
        let reason = results.isEmpty ? "The provider returned no matching images." : "The provider returned \(results.count) candidate(s)."
        let retryAdvice: NativeImageSearchRetryAdvice = results.isEmpty ? .retryOnceWithBroaderEnglishQuery : .notNeeded
        return ProviderAttempt(
            results: results,
            diagnostic: NativeImageSearchProviderDiagnostic(provider: provider, status: status, reason: reason, retryAdvice: retryAdvice)
        )
    }

    private func failedAttempt(provider: String, reason: String, retryAdvice: NativeImageSearchRetryAdvice) -> ProviderAttempt {
        ProviderAttempt(
            results: [],
            diagnostic: NativeImageSearchProviderDiagnostic(provider: provider, status: .failed, reason: reason, retryAdvice: retryAdvice)
        )
    }

    private func httpFailureAttempt(provider: String, statusCode: Int) -> ProviderAttempt {
        switch statusCode {
        case 429:
            failedAttempt(provider: provider, reason: "The provider rate limit was exceeded (HTTP 429).", retryAdvice: .retryLater)
        case 500...599:
            failedAttempt(provider: provider, reason: "The provider is temporarily unavailable (HTTP \(statusCode)).", retryAdvice: .retryLater)
        case 401, 403:
            failedAttempt(provider: provider, reason: "The provider rejected access (HTTP \(statusCode)).", retryAdvice: .doNotRetry)
        default:
            failedAttempt(provider: provider, reason: "The provider rejected the request (HTTP \(statusCode)).", retryAdvice: .doNotRetry)
        }
    }

    private func networkFailureAttempt(provider: String, error: Error) -> ProviderAttempt {
        if let urlError = error as? URLError {
            let retryableCodes: Set<URLError.Code> = [
                .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                .dnsLookupFailed, .notConnectedToInternet, .internationalRoamingOff
            ]
            return failedAttempt(
                provider: provider,
                reason: "Network request failed (\(urlError.code.rawValue): \(urlError.localizedDescription)).",
                retryAdvice: retryableCodes.contains(urlError.code) ? .retryLater : .doNotRetry
            )
        }
        return failedAttempt(
            provider: provider,
            reason: "Network request failed: \(error.localizedDescription)",
            retryAdvice: .doNotRetry
        )
    }

    private static let userAgent = "ConnorGraphAgent/1.0 (https://github.com/duanshiwen/connor-graph-agent-mac)"
}

private struct OpenverseImageSearchResponse: Decodable {
    var results: [OpenverseImageSearchItem]
}

private struct OpenverseImageSearchItem: Decodable {
    var title: String?
    var url: String?
    var thumbnail: String?
    var foreignLandingURL: String?
    var creator: String?
    var creatorURL: String?
    var license: String?
    var licenseVersion: String?
    var licenseURL: String?
    var attribution: String?
    var width: Int?
    var height: Int?

    enum CodingKeys: String, CodingKey {
        case title, url, thumbnail, creator, license, attribution, width, height
        case foreignLandingURL = "foreign_landing_url"
        case creatorURL = "creator_url"
        case licenseVersion = "license_version"
        case licenseURL = "license_url"
    }

    var resultItem: NativeImageSearchResultItem? {
        let imageURL = url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sourcePageURL = foreignLandingURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard isHTTPURL(imageURL), isHTTPURL(sourcePageURL) else { return nil }
        let normalizedLicense = [license, licenseVersion]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return NativeImageSearchResultItem(
            title: normalizedTitle.isEmpty ? "Untitled image" : normalizedTitle,
            imageURL: imageURL,
            thumbnailURL: thumbnail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            sourcePageURL: sourcePageURL,
            creator: creator?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            creatorURL: creatorURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            license: normalizedLicense,
            licenseURL: licenseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            attribution: attribution?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            width: width,
            height: height
        )
    }

    private func isHTTPURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

private struct WikimediaCommonsImageSearchResponse: Decodable {
    var query: Query?
    var error: APIError?

    struct Query: Decodable {
        var pages: [Page]
    }

    struct APIError: Decodable {
        var code: String
        var info: String
    }

    struct Page: Decodable {
        var title: String
        var index: Int?
        var imageinfo: [ImageInfo]?

        var resultItem: NativeImageSearchResultItem? {
            guard let info = imageinfo?.first else { return nil }
            let imageURL = info.thumburl?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? info.url?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""
            let sourcePageURL = info.descriptionurl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard isHTTPURL(imageURL), isHTTPURL(sourcePageURL) else { return nil }
            let creatorHTML = info.extmetadata?["Artist"]?.value ?? ""
            let creator = normalizedHTMLText(creatorHTML)
            let license = normalizedHTMLText(info.extmetadata?["LicenseShortName"]?.value ?? "")
            let attributionValue = normalizedHTMLText(info.extmetadata?["Attribution"]?.value ?? "")
            let normalizedTitle = title.replacingOccurrences(of: "File:", with: "", options: [.anchored])
            let attribution = attributionValue.isEmpty
                ? [normalizedTitle, creator, license].filter { !$0.isEmpty }.joined(separator: " — ")
                : attributionValue
            return NativeImageSearchResultItem(
                title: normalizedTitle,
                imageURL: imageURL,
                thumbnailURL: info.thumburl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                sourcePageURL: sourcePageURL,
                creator: creator,
                creatorURL: firstResolvedHTTPURL(in: creatorHTML),
                license: license,
                licenseURL: info.extmetadata?["LicenseUrl"]?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                attribution: attribution,
                width: info.thumbwidth,
                height: info.thumbheight
            )
        }

        private func normalizedHTMLText(_ value: String) -> String {
            NativeWebTextExtractor.collapseWhitespace(NativeWebTextExtractor.stripTags(value))
        }

        private func firstResolvedHTTPURL(in html: String) -> String {
            guard let href = NativeWebTextExtractor.firstMatch(in: html, pattern: #"(?is)href=[\"']([^\"']+)[\"']"#) else { return "" }
            let absolute = href.hasPrefix("//") ? "https:\(href)" : href
            return isHTTPURL(absolute) ? absolute : ""
        }

        private func isHTTPURL(_ value: String) -> Bool {
            guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
            return scheme == "http" || scheme == "https"
        }
    }

    struct ImageInfo: Decodable {
        var thumburl: String?
        var thumbwidth: Int?
        var thumbheight: Int?
        var url: String?
        var descriptionurl: String?
        var extmetadata: [String: MetadataValue]?
    }

    struct MetadataValue: Decodable {
        var value: String?
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
