import Foundation
import Testing
@testable import ConnorGraphAgent

@Suite("Native Web Client Tests")
struct NativeWebClientTests {
    @Test func webFetchExtractsMarkdownFromHTMLWithoutPythonRuntime() async throws {
        let html = """
        <!doctype html>
        <html>
          <head><title>Example Article</title><style>.hidden{display:none}</style></head>
          <body>
            <nav>Navigation should not appear</nav>
            <main>
              <h1>Example Article</h1>
              <p>Hello <a href="/docs">docs</a> world.</p>
              <ul><li>First point</li><li>Second point</li></ul>
            </main>
            <script>console.log('ignore')</script>
          </body>
        </html>
        """
        let client = NativeWebFetchClient(httpClient: FakeNativeWebHTTPClient(response: .html(html, url: "https://example.com/article")))

        let result = try await client.fetch(
            urlString: "https://example.com/article",
            extractMode: "markdown",
            timeoutMilliseconds: 30_000
        )

        #expect(result.urlString == "https://example.com/article")
        #expect(result.finalURLString == "https://example.com/article")
        #expect(result.title == "Example Article")
        #expect(result.contentText.contains("# Example Article"))
        #expect(result.contentText.contains("Hello [docs](https://example.com/docs) world."))
        #expect(result.contentText.contains("- First point"))
        #expect(!result.contentText.contains("Navigation should not appear"))
        #expect(!result.contentText.contains("console.log"))
        #expect(result.engine == "native-urlsession")
    }

    @Test func webFetchCanReturnPlainText() async throws {
        let html = """
        <html><head><title>Plain</title></head><body><h1>Plain</h1><p>One&nbsp;two</p></body></html>
        """
        let client = NativeWebFetchClient(httpClient: FakeNativeWebHTTPClient(response: .html(html, url: "https://example.com/plain")))

        let result = try await client.fetch(
            urlString: "https://example.com/plain",
            extractMode: "text",
            timeoutMilliseconds: 30_000
        )

        #expect(result.contentText.contains("Plain"))
        #expect(result.contentText.contains("One two"))
        #expect(!result.contentText.contains("# Plain"))
    }

    @Test func duckDuckGoSearchParsesNativeHTMLResults() async throws {
        let html = """
        <html><body>
          <div class="result">
            <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fone">First Result</a>
            <a class="result__snippet">First snippet text.</a>
          </div>
          <div class="result">
            <a class="result__a" href="https://example.org/two">Second Result</a>
            <div class="result__snippet">Second snippet text.</div>
          </div>
        </body></html>
        """
        let client = NativeWebSearchClient(httpClient: FakeNativeWebHTTPClient(response: .html(html, url: "https://duckduckgo.com/html/?q=connor")))

        let result = try await client.search(query: "connor", engine: "duckduckgo", maxResults: 2)

        #expect(result.query == "connor")
        #expect(result.engine == "duckduckgo")
        #expect(result.results.count == 2)
        #expect(result.results[0].title == "First Result")
        #expect(result.results[0].url == "https://example.com/one")
        #expect(result.results[0].snippet == "First snippet text.")
        #expect(result.results[1].url == "https://example.org/two")
        #expect(result.markdown.contains("1. First Result"))
        #expect(result.markdown.contains("URL: https://example.com/one"))
    }

    @Test func nativeSearchRejectsUnsupportedHTTPParserEngines() async throws {
        let client = NativeWebSearchClient(httpClient: FakeNativeWebHTTPClient(response: .html("", url: "https://example.com")))

        await #expect(throws: AgentToolError.self) {
            _ = try await client.search(query: "connor", engine: "google", maxResults: 3)
        }
    }
}

private struct FakeNativeWebHTTPClient: NativeWebHTTPClient {
    var response: NativeWebHTTPResponse

    func data(for request: URLRequest) async throws -> NativeWebHTTPResponse {
        response
    }
}

private extension NativeWebHTTPResponse {
    static func html(_ html: String, url: String) -> NativeWebHTTPResponse {
        NativeWebHTTPResponse(
            data: Data(html.utf8),
            statusCode: 200,
            mimeType: "text/html",
            finalURL: URL(string: url),
            textEncodingName: "utf-8"
        )
    }
}
