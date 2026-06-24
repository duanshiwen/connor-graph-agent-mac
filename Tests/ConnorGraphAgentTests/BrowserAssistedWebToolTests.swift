import Foundation
import Testing
@testable import ConnorGraphAgent

@Suite("Browser Assisted Web Tool Tests")
struct BrowserAssistedWebToolTests {
    @Test func searchEngineMCPConfigurationDoesNotUseLocalCraftDefaults() {
        let configuration = SearchEngineMCPConfiguration(environment: [:])

        #expect(configuration.pythonExecutable == nil)
        #expect(configuration.sourceDirectory == nil)
        #expect(!configuration.isConfigured)
    }

    @Test func searchEngineMCPConfigurationReadsExplicitEnvironment() {
        let configuration = SearchEngineMCPConfiguration(environment: [
            "CONNOR_SEARCH_ENGINE_MCP_PYTHON": "/opt/search-engine-mcp/venv/bin/python",
            "CONNOR_SEARCH_ENGINE_MCP_DIR": "/opt/search-engine-mcp"
        ])

        #expect(configuration.pythonExecutable == "/opt/search-engine-mcp/venv/bin/python")
        #expect(configuration.sourceDirectory == "/opt/search-engine-mcp")
        #expect(configuration.isConfigured)
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

    @Test func javascriptWebFetchReturnsExtractedContentFromBrowserAssistedHandler() async throws {
        final class Recorder: @unchecked Sendable {
            var requests: [BrowserAssistedWebFetchRequest] = []
        }
        let recorder = Recorder()
        let tool = SearchEngineMCPWebFetchTool(browserAssistedWebFetchHandler: { request in
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

    @Test func javascriptWebFetchReportsUserInterventionWhenBrowserRequiresChallenge() async throws {
        let tool = SearchEngineMCPWebFetchTool(browserAssistedWebFetchHandler: { request in
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
        let tool = SearchEngineMCPTool(browserAssistedSearchHandler: { request in
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
