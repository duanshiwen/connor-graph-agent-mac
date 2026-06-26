import Foundation
import Testing
@testable import ConnorGraphAppSupport

@Suite("Default Search Engine Tests")
struct DefaultSearchEngineTests {
    @Test func defaultEngineIsBing() {
        #expect(DefaultSearchEngine.default == .bing)
    }

    @Test func supportedEnginesExposeUserFacingNames() {
        #expect(DefaultSearchEngine.allCases.map(\.displayName) == ["Bing", "Google", "DuckDuckGo", "百度", "Yahoo"])
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
            (.baidu, "www.baidu.com", "/s", "wd"),
            (.yahoo, "search.yahoo.com", "/search", "p")
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

    @Test func blankQueriesDoNotBuildSearchURLs() {
        #expect(DefaultSearchEngine.bing.searchURL(for: "   ") == nil)
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
}
