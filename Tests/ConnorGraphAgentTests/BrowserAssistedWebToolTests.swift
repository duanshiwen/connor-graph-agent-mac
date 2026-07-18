import Foundation
import Testing
@testable import ConnorGraphAgent

@Suite("Browser Assisted Web Tool Tests")
struct BrowserAssistedWebToolTests {
    @Test func nativeWebToolsDoNotRequirePythonConfiguration() {
        let searchTool = NativeWebSearchTool()
        let fetchTool = NativeWebFetchTool()

        #expect(searchTool.name == "web_search")
        #expect(fetchTool.name == "web_fetch")
        #expect(searchTool.description.contains("native web search client"))
        #expect(fetchTool.description.contains("native HTTP extractor"))
        #expect(fetchTool.description.contains("normally be tried before browser_fetch"))
        #expect(fetchTool.description.contains("HTTP 403"))
        #expect(fetchTool.description.contains("authenticated session"))

        let browserFetchTool = BrowserFetchTool()
        #expect(browserFetchTool.description.contains("fallback when web_fetch"))
        #expect(browserFetchTool.description.contains("HTTP 403"))
        #expect(browserFetchTool.description.contains("authenticated browser session"))
        #expect(browserFetchTool.description.contains("Never use it to bypass authorization"))
        let legacySourceName = "search-engine" + "-mcp"
        #expect(!searchTool.description.contains(legacySourceName))
        #expect(!fetchTool.description.contains(legacySourceName))
    }

    @Test func duckDuckGoWebSearchUsesNativeClientWithoutPythonRuntime() async throws {
        let html = """
        <html><body>
          <div class="result">
            <a class="result__a" href="https://example.com/native-search">Native Search Result</a>
            <div class="result__snippet">Found by Swift search.</div>
          </div>
        </body></html>
        """
        let nativeClient = NativeWebSearchClient(httpClient: FakeNativeWebHTTPClient(response: .html(html, url: "https://duckduckgo.com/html/?q=native")))
        let tool = NativeWebSearchTool(nativeSearchClient: nativeClient)

        let result = try await tool.execute(
            arguments: AgentToolArguments(values: [
                "query": .string("native"),
                "engine": .string("duckduckgo"),
                "max_results": .int(1)
            ]),
            context: Self.context()
        )

        #expect(result.contentText.contains("Native Search Result"))
        #expect(result.contentText.contains("https://example.com/native-search"))
        #expect(result.contentText.contains("Found by Swift search."))
        #expect(result.contentJSON?.contains("native") == true)
        #expect(result.citations == ["https://example.com/native-search"])
    }

    @Test func googleWebSearchUsesBrowserAssistedHandler() async throws {
        try await assertSearchUsesBrowserAssistedHandler(
            engine: "google",
            query: "Connor Graph Agent",
            expectedURLPart: "www.google.com/search",
            expectedQueryParameter: "q="
        )
    }

    @Test func bingWebSearchUsesBrowserAssistedHandler() async throws {
        try await assertSearchUsesBrowserAssistedHandler(
            engine: "bing",
            query: "康纳同学",
            expectedURLPart: "www.bing.com/search",
            expectedQueryParameter: "q="
        )
    }

    @Test func baiduWebSearchUsesBrowserAssistedHandler() async throws {
        try await assertSearchUsesBrowserAssistedHandler(
            engine: "baidu",
            query: "康纳同学",
            expectedURLPart: "www.baidu.com/s",
            expectedQueryParameter: "wd="
        )
    }

    @Test func browserFetchUsesSystemBrowserHandlerWhenAvailable() async throws {
        let tool = BrowserFetchTool(browserAssistedWebFetchHandler: { request in
            #expect(request.urlString == "https://example.com/protected")
            #expect(request.extractMode == "text")
            return BrowserAssistedWebFetchResult(
                status: .fetched,
                urlString: request.urlString,
                finalURLString: request.urlString,
                title: "Protected page",
                contentText: "Authenticated browser content",
                taskID: "task-browser-fetch",
                sessionID: "session-browser-fetch",
                tabID: "tab-browser-fetch",
                errorMessage: nil,
                interventionReason: nil,
                truncated: false,
                originalCharacterCount: 29
            )
        })

        let result = try await tool.execute(
            arguments: try AgentToolArguments(json: #"{"url":"https://example.com/protected"}"#),
            context: Self.context()
        )

        #expect(result.contentText == "Authenticated browser content")
        #expect(result.contentJSON?.contains(#""engine":"wkwebview""#) == true)
        #expect(result.contentJSON?.contains(#""browserAssisted":true"#) == true)
    }

    @Test func browserFetchDecodesGBKMetaCharsetChineseText() throws {
        let html = """
        <html><head><meta charset=\"gbk\"></head><body>科技新闻</body></html>
        """
        let data = try #require(html.data(using: BrowserFetchTool.gb18030TestEncoding))

        let decoded = BrowserFetchTool.decodeWebPageText(data: data, responseEncodingName: nil)

        #expect(decoded.text.contains("科技新闻"))
        #expect(decoded.encodingName == "gbk")
        #expect(decoded.mojibakeRepaired == false)
    }

    @Test func browserFetchRepairsLatin1DecodedGBKChineseMojibake() throws {
        let mojibake = "¿Æ¼¼ÐÂÎÅ"
        let data = try #require(mojibake.data(using: .utf8))

        let decoded = BrowserFetchTool.decodeWebPageText(data: data, responseEncodingName: "utf-8")

        #expect(decoded.text == "科技新闻")
        #expect(decoded.encodingName == "utf-8→gb18030")
        #expect(decoded.mojibakeRepaired == true)
    }

    @Test func httpWebFetchUsesNativeClientWithoutPythonRuntime() async throws {
        let html = """
        <html><head><title>Native Fetch</title></head><body><h1>Native Fetch</h1><p>Fetched by Swift.</p></body></html>
        """
        let nativeClient = NativeWebFetchClient(httpClient: FakeNativeWebHTTPClient(response: .html(html, url: "https://example.com/native")))
        let tool = NativeWebFetchTool(nativeFetchClient: nativeClient)

        let result = try await tool.execute(
            arguments: AgentToolArguments(values: [
                "url": .string("https://example.com/native"),
                "render_mode": .string("http"),
                "extract_mode": .string("markdown")
            ]),
            context: Self.context()
        )

        #expect(result.contentText.contains("# Native Fetch"))
        #expect(result.contentText.contains("Fetched by Swift."))
        #expect(result.contentJSON?.contains("native-urlsession") == true)
        #expect(result.citations == ["https://example.com/native"])
    }

    @Test func javascriptWebFetchReturnsExtractedContentFromBrowserAssistedHandler() async throws {
        final class Recorder: @unchecked Sendable {
            var requests: [BrowserAssistedWebFetchRequest] = []
        }
        let recorder = Recorder()
        let tool = NativeWebFetchTool(browserAssistedWebFetchHandler: { request in
            recorder.requests.append(request)
            return BrowserAssistedWebFetchResult(
                status: .fetched,
                urlString: request.urlString,
                finalURLString: "https://example.com/app#ready",
                title: "Rendered App",
                contentText: "# Rendered App\n\nClient rendered content",
                taskID: "task-js-fetch",
                sessionID: "session-js-fetch",
                tabID: "tab-js-fetch",
                errorMessage: nil,
                interventionReason: nil,
                truncated: false,
                originalCharacterCount: 23
            )
        })

        let result = try await tool.execute(
            arguments: AgentToolArguments(values: [
                "url": .string("https://example.com/app"),
                "render_mode": .string("js"),
                "extract_mode": .string("markdown")
            ]),
            context: Self.context()
        )

        #expect(recorder.requests.count == 1)
        #expect(recorder.requests.first?.urlString == "https://example.com/app")
        #expect(recorder.requests.first?.extractMode == "markdown")
        #expect(result.contentText.contains("Client rendered content"))
        #expect(result.contentText.contains("Rendered App"))
        #expect(result.contentJSON?.contains("wkwebview") == true)
        #expect(result.contentJSON?.contains("fetched") == true)
    }

    @Test func automaticWebFetchFallsBackToBrowserWhenNativeHTTPFails() async throws {
        final class Recorder: @unchecked Sendable {
            var requests: [BrowserAssistedWebFetchRequest] = []
        }
        let recorder = Recorder()
        let nativeClient = NativeWebFetchClient(httpClient: FakeNativeWebHTTPClient(response: NativeWebHTTPResponse(
            data: Data(),
            statusCode: 403,
            mimeType: "text/html",
            finalURL: URL(string: "https://example.com/protected"),
            textEncodingName: "utf-8"
        )))
        let tool = NativeWebFetchTool(browserAssistedWebFetchHandler: { request in
            recorder.requests.append(request)
            return BrowserAssistedWebFetchResult(
                status: .fetched,
                urlString: request.urlString,
                finalURLString: request.urlString,
                title: "Browser Fetch",
                contentText: "Content from the retained browser session",
                taskID: "task-auto-fallback",
                sessionID: "session-auto-fallback",
                tabID: "tab-auto-fallback",
                errorMessage: nil,
                interventionReason: nil,
                truncated: false,
                originalCharacterCount: 41
            )
        }, nativeFetchClient: nativeClient)

        let result = try await tool.execute(
            arguments: AgentToolArguments(values: [
                "url": .string("https://example.com/protected"),
                "render_mode": .string("auto")
            ]),
            context: Self.context()
        )

        #expect(recorder.requests.count == 1)
        #expect(result.contentText.contains("retained browser session"))
        #expect(result.contentJSON?.contains("wkwebview") == true)
        #expect(result.contentJSON?.contains("\"renderMode\":\"auto\"") == true)
    }

    @Test func explicitHTTPWebFetchDoesNotFallBackToBrowser() async {
        final class Recorder: @unchecked Sendable {
            var requestCount = 0
        }
        let recorder = Recorder()
        let nativeClient = NativeWebFetchClient(httpClient: FakeNativeWebHTTPClient(response: NativeWebHTTPResponse(
            data: Data(),
            statusCode: 403,
            mimeType: "text/html",
            finalURL: URL(string: "https://example.com/protected"),
            textEncodingName: "utf-8"
        )))
        let tool = NativeWebFetchTool(browserAssistedWebFetchHandler: { request in
            recorder.requestCount += 1
            return nil
        }, nativeFetchClient: nativeClient)

        do {
            _ = try await tool.execute(
                arguments: AgentToolArguments(values: [
                    "url": .string("https://example.com/protected"),
                    "render_mode": .string("http")
                ]),
                context: Self.context()
            )
            Issue.record("Expected the HTTP 403 fetch to fail")
        } catch {
            #expect(String(describing: error).contains("HTTP status 403"))
        }
        #expect(recorder.requestCount == 0)
    }

    @Test func javascriptWebFetchReportsUserInterventionWhenBrowserRequiresChallenge() async throws {
        let tool = NativeWebFetchTool(browserAssistedWebFetchHandler: { request in
            BrowserAssistedWebFetchResult(
                status: .needsUserIntervention,
                urlString: request.urlString,
                finalURLString: request.urlString,
                title: "Security Check",
                contentText: "",
                taskID: "task-challenge",
                sessionID: "session-challenge",
                tabID: "tab-challenge",
                errorMessage: nil,
                interventionReason: "CAPTCHA requires user action",
                truncated: false,
                originalCharacterCount: 0
            )
        })

        let result = try await tool.execute(
            arguments: AgentToolArguments(values: [
                "url": .string("https://example.com/challenge"),
                "render_mode": .string("js")
            ]),
            context: Self.context()
        )

        #expect(result.contentText.contains("requires user intervention"))
        #expect(result.contentText.contains("CAPTCHA requires user action"))
        #expect(result.contentJSON?.contains("needsUserIntervention") == true)
        #expect(result.citations == ["https://example.com/challenge"])
    }

    private func assertSearchUsesBrowserAssistedHandler(
        engine: String,
        query: String,
        expectedURLPart: String,
        expectedQueryParameter: String
    ) async throws {
        final class Recorder: @unchecked Sendable {
            var requests: [BrowserAssistedSearchRequest] = []
        }
        let recorder = Recorder()
        let tool = NativeWebSearchTool(browserAssistedSearchHandler: { request in
            recorder.requests.append(request)
            return BrowserAssistedSearchResult(
                taskID: "task-\(engine)",
                sessionID: "session-\(engine)",
                tabID: "tab-\(engine)",
                urlString: request.urlString,
                status: "running"
            )
        })

        let result = try await tool.execute(
            arguments: AgentToolArguments(values: [
                "query": .string(query),
                "engine": .string(engine),
                "max_results": .int(3)
            ]),
            context: Self.context()
        )

        #expect(recorder.requests.count == 1)
        #expect(recorder.requests.first?.engine == engine)
        #expect(recorder.requests.first?.revealImmediately == false)
        #expect(recorder.requests.first?.urlString.contains(expectedURLPart) == true)
        #expect(recorder.requests.first?.urlString.contains(expectedQueryParameter) == true)
        #expect(result.contentText.contains("built-in browser background runner"))
        #expect(result.contentText.contains("Task ID: task-\(engine)"))
    }

    private struct FakeNativeWebHTTPClient: NativeWebHTTPClient {
        var response: NativeWebHTTPResponse

        func data(for request: URLRequest) async throws -> NativeWebHTTPResponse {
            response
        }
    }

    private static func context() -> AgentToolExecutionContext {
        let audit = InMemoryAgentAuditLog()
        let policy = AgentPolicyEngine(permissionMode: .allowAll, auditLog: audit)
        return AgentToolExecutionContext(
            runID: "run-1",
            sessionID: "session-1",
            groupID: "default",
            userPrompt: "search",
            toolCallID: "tool-call-1",
            policyEngine: policy
        )
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
