import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("Default Search Engine Tests")
struct DefaultSearchEngineTests {
    @Test func defaultEngineIsBing() {
        #expect(DefaultSearchEngine.default == .bing)
    }

    @Test func supportedEnginesExposeUserFacingNames() {
        #expect(DefaultSearchEngine.allCases.map(\.displayName) == ["Bing", "Google", "DuckDuckGo", "Yahoo", "360", "搜狗"])
    }

    @Test func buildsBingSearchURL() throws {
        let url = try #require(DefaultSearchEngine.bing.searchURL(for: "connor search"))

        #expect(url.scheme == "https")
        #expect(url.host == "cn.bing.com")
        #expect(url.path == "/search")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value == "connor search")
    }

    @Test func buildsSupportedSearchURLsWithEngineSpecificQueryParameter() throws {
        let cases: [(DefaultSearchEngine, String, String, String)] = [
            (.google, "www.google.com", "/search", "q"),
            (.duckDuckGo, "duckduckgo.com", "/", "q"),
            (.yahoo, "search.yahoo.com", "/search", "p"),
            (.so360, "www.so.com", "/s", "q"),
            (.sogou, "www.sogou.com", "/web", "query")
        ]

        for (engine, host, path, queryName) in cases {
            let url = try #require(engine.searchURL(for: "swift testing"))
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

            #expect(url.scheme == "https")
            #expect(url.host == host)
            #expect(url.path == path)
            #expect(components.queryItems?.first(where: { $0.name == queryName })?.value == "swift testing")
        }
    }

    @Test func alternativeEnginesPersistAndEncodeChineseQueries() throws {
        for engine in [DefaultSearchEngine.so360, .sogou] {
            let data = try JSONEncoder().encode(engine)
            #expect(try JSONDecoder().decode(DefaultSearchEngine.self, from: data) == engine)
            let url = try #require(engine.searchURL(for: "中文 & C++"))
            #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "中文 & C++")
            #expect(BrowserNavigationURLResolver.normalizedURLString(from: "中文 & C++", defaultSearchEngine: engine) == url.absoluteString)
        }
    }

    @Test func blankQueriesDoNotBuildSearchURLs() {
        #expect(DefaultSearchEngine.bing.searchURL(for: "   ") == nil)
    }

    @Test func decodesRemovedEngineRawValuesByFallingBackToDefault() throws {
        let data = try #require("\"baidu\"".data(using: .utf8))
        let engine = try JSONDecoder().decode(DefaultSearchEngine.self, from: data)

        #expect(engine == .default)
        #expect(engine == .bing)
    }
}

@Suite("Browser Navigation URL Resolver Tests")
struct BrowserNavigationURLResolverTests {
    @Test func preservesBlankAndAbsoluteURLs() {
        #expect(BrowserNavigationURLResolver.normalizedURLString(from: "about:blank", defaultSearchEngine: .bing) == "about:blank")
        #expect(BrowserNavigationURLResolver.normalizedURLString(from: "https://example.com/path", defaultSearchEngine: .bing) == "https://example.com/path")
        #expect(BrowserNavigationURLResolver.normalizedURLString(from: "http://example.com/path", defaultSearchEngine: .bing) == "http://example.com/path")
    }

    @Test func treatsDomainLikeInputAsHTTPSURL() {
        #expect(BrowserNavigationURLResolver.normalizedURLString(from: "example.com", defaultSearchEngine: .bing) == "https://example.com")
    }

    @Test func routesKeywordInputThroughSelectedSearchEngine() {
        #expect(BrowserNavigationURLResolver.normalizedURLString(from: "connor search", defaultSearchEngine: .bing)?.hasPrefix("https://cn.bing.com/search?") == true)
        #expect(BrowserNavigationURLResolver.normalizedURLString(from: "connor search", defaultSearchEngine: .google)?.hasPrefix("https://www.google.com/search?") == true)
    }

    @Test func emptyInputReturnsNil() {
        #expect(BrowserNavigationURLResolver.normalizedURLString(from: "   ", defaultSearchEngine: .bing) == nil)
    }

    @Test func localAppsAndFilesAreNotSentToSearch() {
        for input in ["localhost:3000/test", "127.0.0.1:8000/test", "[::1]:8080/test"] {
            #expect(BrowserNavigationURLResolver.normalizedURLString(from: input, defaultSearchEngine: .bing) == "https://\(input)")
        }
        #expect(BrowserNavigationURLResolver.normalizedURLString(from: "file:///tmp/page.html", defaultSearchEngine: .bing) == "file:///tmp/page.html")
    }

    @Test func unsupportedSchemesCannotBeTreatedAsHostnames() {
        for input in ["javascript:example.com", "data:text/html,example.com", "ftp://example.com", "about:config", "blob:https://example.com/id"] {
            #expect(BrowserNavigationURLResolver.normalizedURLString(from: input, defaultSearchEngine: .bing) == nil)
        }
    }

    @Test func closedTabsArePrivateSafeBoundedAndSessionScoped() {
        var tabs = BrowserRecentlyClosedTabs()
        for index in 0..<30 { tabs.remember("https://example.com/\(index)", sessionID: "a") }
        tabs.remember("https://example.com/private", sessionID: "a", isPrivate: true)
        tabs.remember("about:blank", sessionID: "a")
        #expect(tabs.takeLast(in: "b") == nil)
        #expect(tabs.takeLast(in: "a") == "https://example.com/29")
        var count = 1
        while tabs.takeLast(in: "a") != nil { count += 1 }
        #expect(count == 20)
        #expect(!tabs.hasPages(in: "a"))
    }

    @Test func suggestionsPreferOpenTabsDeduplicateAndMatchTitlesOrURLs() {
        let candidates = [
            BrowserAddressSuggestion(source: "标签", title: "康纳文档", url: "https://example.com/docs"),
            BrowserAddressSuggestion(source: "收藏", title: "康纳文档收藏", url: "https://example.com/docs"),
            BrowserAddressSuggestion(source: "历史", title: "其他", url: "https://connor.run")
        ]
        #expect(BrowserAddressSuggestion.matching("康纳", candidates: candidates).count == 1)
        #expect(BrowserAddressSuggestion.matching("EXAMPLE", candidates: candidates).first?.source == "标签")
        #expect(BrowserAddressSuggestion.matching("connor.run", candidates: candidates).first?.source == "历史")
        #expect(BrowserAddressSuggestion.matching(" ", candidates: candidates).isEmpty)
        #expect(BrowserAddressSuggestion.matching("example", candidates: candidates, limit: 0).isEmpty)
    }
    @Test func comparisonBoundsSourcesAndPreservesAttribution() throws {
        let sources = (1...8).map { index in BrowserComparisonSource(tabID:String(index),url:"https://example.com/\(index)",title:"Page \(index)",text:String(repeating:"康",count:14000),totalCharacters:14000,truncated:false) }
        let prompt = try BrowserComparisonPrompt.make(question:"比较",pages:sources)
        let data = try #require(prompt.split(separator:"\n").last?.data(using:.utf8))
        let json = try #require(JSONSerialization.jsonObject(with:data) as? [[String:Any]])
        #expect(json.count == 8)
        let page = try #require(json[0]["page"] as? [String:Any])
        #expect((page["text"] as? String)?.count == 8000)
        #expect(page["truncated"] as? Bool == true)
        #expect(page["url"] as? String == "https://example.com/1")
        #expect(throws: (any Error).self) { try BrowserComparisonPrompt.make(question:"比较",pages:[]) }
    }

}
