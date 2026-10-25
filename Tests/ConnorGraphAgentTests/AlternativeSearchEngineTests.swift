import Foundation
import Testing
@testable import ConnorGraphAgent

@Suite("Alternative Search Engines")
struct AlternativeSearchEngineTests {
    static let soHTML = """
    <div class="res-list"><a class=alink href="https://m.so.com/jump?u=https%3A%2F%2Fexample.com%2F360%3Fa%3D1%26b%3D2&amp;from=m.so.com">
    <h3 class="res-title"><em>360</em> 搜索结果</h3><p class="g-main summary">中文 &amp; 摘要</p></a></div>
    <a href="javascript:alert(1)"><h3>Unsafe</h3></a>
    """
    static let sogouHTML = """
    <div class="vrwrap"><h3 class="vr-title"><!--awbg--><a href="./link?url=result&amp;id=1">搜狗 <em>结果</em></a></h3>
    <a class="txt-summary" href="./link?url=result">真实的中文摘要</a></div>
    """

    @Test func parsesResultLinksAndSkipsNonWebLinks() {
        let so = AlternativeSearchParser.results(from: Self.soHTML, engine: "so360")
        #expect(so.count == 1)
        #expect(so.first?.url == "https://example.com/360?a=1&b=2")
        #expect(so.first?.snippet == "中文 & 摘要")
        let sogou = AlternativeSearchParser.results(from: Self.sogouHTML, engine: "sogou")
        #expect(sogou.first?.url == "https://www.sogou.com/link?url=result&id=1")
        #expect(sogou.first?.snippet == "真实的中文摘要")
        #expect(AlternativeSearchParser.results(from: "<title>访问异常页面</title><p>请验证</p>", engine: "so360").isEmpty)
    }

    @Test func sendsQueriesToSelectedEngineAndReturnsParsedResults() async throws {
        for (engine, host, path, parameter, html) in [
            ("so360", "m.so.com", "/s", "q", Self.soHTML),
            ("sogou", "www.sogou.com", "/web", "query", Self.sogouHTML)
        ] {
            let http = AlternativeSearchHTTP(html: html)
            let client = NativeWebSearchClient(httpClient: http)
            let result = try await client.search(query: "中文 & C++", engine: engine, maxResults: 1)
            #expect(result.results.count == 1)
            #expect(result.engine == engine)
            let request = try #require(await http.request)
            let url = try #require(request.url)
            #expect(url.host == host)
            #expect(url.path == path)
            #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.name == parameter)
            #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "中文 & C++")
        }
    }
}

private actor AlternativeSearchHTTP: NativeWebHTTPClient {
    let html: String
    var request: URLRequest?
    init(html: String) { self.html = html }
    func data(for request: URLRequest) async throws -> NativeWebHTTPResponse {
        self.request = request
        return NativeWebHTTPResponse(data: Data(html.utf8), statusCode: 200, mimeType: "text/html", finalURL: request.url, textEncodingName: "utf-8")
    }
}
