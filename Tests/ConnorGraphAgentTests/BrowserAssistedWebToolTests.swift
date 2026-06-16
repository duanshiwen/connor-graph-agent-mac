import Foundation
import Testing
@testable import ConnorGraphAgent

@Suite("Browser Assisted Web Tool Tests")
struct BrowserAssistedWebToolTests {
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

    @Test func javascriptWebFetchUsesBrowserAssistedHandler() async throws {
        final class Recorder: @unchecked Sendable {
            var requests: [BrowserAssistedSearchRequest] = []
        }
        let recorder = Recorder()
        let tool = SearchEngineMCPWebFetchTool(browserAssistedSearchHandler: { request in
            recorder.requests.append(request)
            return BrowserAssistedSearchResult(
                taskID: "task-2",
                sessionID: "session-2",
                tabID: "tab-2",
                urlString: request.urlString,
                status: "running"
            )
        })

        let result = try await tool.execute(
            arguments: AgentToolArguments(values: [
                "url": .string("https://example.com/app"),
                "render_mode": .string("js")
            ]),
            context: Self.context()
        )

        #expect(recorder.requests.count == 1)
        #expect(recorder.requests.first?.engine == "direct-url")
        #expect(recorder.requests.first?.urlString == "https://example.com/app")
        #expect(result.contentText.contains("built-in browser background runner"))
        #expect(result.contentText.contains("Task ID: task-2"))
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
