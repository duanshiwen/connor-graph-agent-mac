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
        #expect(fetchTool.description.contains("up to 10 independent pages concurrently"))
        #expect(fetchTool.description.contains("automatically falls back"))
        #expect(fetchTool.description.contains("retained login session"))
        #expect(fetchTool.description.contains("Never use browser assistance to bypass authorization"))
        let legacySourceName = "search-engine" + "-mcp"
        #expect(!searchTool.description.contains(legacySourceName))
        #expect(!fetchTool.description.contains(legacySourceName))
    }

    @Test func browserControlToolsExposeStructuredSchemasAndForwardBoundedRequests() async throws {
        final class Recorder: @unchecked Sendable {
            var request: BrowserControlRequest?
        }
        let recorder = Recorder()
        let handler: BrowserControlHandler = { request in
            recorder.request = request
            return BrowserControlResponse(
                contentText: "snapshot",
                contentJSON: #"{"nodes":[]}"#,
                modelContentParts: [.imageDataURL("data:image/png;base64,AA==", mimeType: "image/png")]
            )
        }
        let tool = BrowserSnapshotTool(handler: handler)
        let result = try await tool.execute(
            arguments: AgentToolArguments(values: [
                "tabID": .string("tab-1"),
                "maxNodes": .int(9_999)
            ]),
            context: Self.context()
        )

        #expect(recorder.request?.operation == .snapshot)
        #expect(recorder.request?.sessionID == "session-1")
        #expect(recorder.request?.tabID == "tab-1")
        #expect(recorder.request?.maxNodes == 500)
        #expect(result.contentText == "snapshot")
        #expect(result.modelContentParts?.first?.kind == .imageDataURL)

        let tabsTool = BrowserTabsTool(handler: handler)
        #expect(tabsTool.description.contains("tabID"))
        #expect(BrowserSnapshotTool(handler: handler).description.contains("nodeRef"))
        let snapshotSchema = tool.inputSchema.jsonObject
        let snapshotProperties = try #require(snapshotSchema["properties"] as? [String: Any])
        let tabSchema = try #require(snapshotProperties["tabID"] as? [String: Any])
        #expect((tabSchema["description"] as? String)?.contains("copy it without renaming") == true)
        let interactSchema = BrowserInteractTool(handler: handler).inputSchema.jsonObject
        let interactProperties = try #require(interactSchema["properties"] as? [String: Any])
        let nodeSchema = try #require(interactProperties["nodeRef"] as? [String: Any])
        #expect((nodeSchema["description"] as? String)?.contains("copy it without renaming") == true)

        let audit = BrowserQualityAuditTool(handler: handler)
        _ = try await audit.execute(
            arguments: AgentToolArguments(values: [
                "tabID": .string("tab-1"),
                "viewportWidth": .int(100),
                "viewportHeight": .int(9_999),
                "fullPage": .bool(true)
            ]),
            context: Self.context()
        )
        #expect(recorder.request?.operation == .qualityAudit)
        #expect(recorder.request?.viewportWidth == 320)
        #expect(recorder.request?.viewportHeight == 1_600)
        #expect(recorder.request?.fullPage == true)
        #expect(audit.description.contains("before claiming"))

        var registry = AgentToolRegistry()
        registry.register(tabsTool)
        registry.register(BrowserSnapshotTool(handler: handler))
        registry.register(BrowserNavigateTool(handler: handler))
        registry.register(BrowserWaitTool(handler: handler))
        registry.register(BrowserScreenshotTool(handler: handler))
        registry.register(BrowserQualityAuditTool(handler: handler))
        registry.register(BrowserInteractTool(handler: handler))
        registry.register(BrowserSubmitTool(handler: handler))
        registry.register(BrowserUploadTool(handler: handler))
        registry.register(BrowserDownloadTool(handler: handler))
        registry.register(BrowserHandoffTool(handler: handler))
        #expect(registry.schemaValidationIssues.isEmpty)
    }

    @Test func browserInteractionApprovalRedactsTypedValuesAndCommitUsesRuntimeTargetDescription() async throws {
        let interact = BrowserInteractTool()
        let secret = "private form value"
        let interactPayload = await interact.approvalPayloadJSON(
            for: AgentToolCall(name: "browser_interact", argumentsJSON: #"{"action":"fill","nodeRef":"node-1","value":"private form value"}"#),
            context: Self.context()
        )
        #expect(!interactPayload.contains(secret))
        #expect(interactPayload.contains(#""valueCharacterCount":18"#))

        let submit = BrowserSubmitTool(handler: { request in
            #expect(request.operation == .describe)
            #expect(request.nodeReference == "node-2")
            return BrowserControlResponse(contentText: "target", contentJSON: #"{"host":"example.com","name":"Send"}"#)
        })
        let submitPayload = await submit.approvalPayloadJSON(
            for: AgentToolCall(name: "browser_submit", argumentsJSON: #"{"nodeRef":"node-2"}"#),
            context: Self.context()
        )
        #expect(submitPayload.contains("example.com"))
        #expect(submitPayload.contains("Send"))
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
                "maxResults": .int(1)
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

    @Test func webFetchUsesMergedSystemBrowserCapabilityWhenRequested() async throws {
        let tool = NativeWebFetchTool(browserAssistedWebFetchHandler: { request in
            #expect(request.urlString == "https://example.com/protected")
            #expect(request.extractMode == "markdown")
            #expect(request.timeoutMilliseconds == 30_000)
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
            arguments: try AgentToolArguments(json: #"{"url":"https://example.com/protected","renderMode":"js"}"#),
            context: Self.context()
        )

        #expect(result.contentText == "Authenticated browser content")
        #expect(result.contentJSON?.contains("\"tabID\":\"tab-browser-fetch\"") == true)
        #expect(result.contentJSON?.contains("\"tab_id\"") == false)
        #expect(result.contentJSON?.contains(#""engine":"wkwebview""#) == true)
        #expect(result.contentJSON?.contains(#""browserAssisted":true"#) == true)
    }

    @Test func mergedBrowserFetchPathFailsAtItsPerPageDeadline() async throws {
        let tool = NativeWebFetchTool(browserAssistedWebFetchHandler: { _ in
            try? await Task.sleep(for: .seconds(10))
            return nil
        })

        do {
            _ = try await tool.execute(
                arguments: AgentToolArguments(values: [
                    "url": .string("https://example.com/slow-browser"),
                    "renderMode": .string("js"),
                    "timeoutMs": .int(1_000)
                ]),
                context: Self.context()
            )
            Issue.record("Expected web_fetch to time out")
        } catch {
            #expect(error as? AgentToolError == .invalidArguments("web_fetch timed out after 1000ms"))
        }
    }

    @Test func webPageDecoderDecodesGBKMetaCharsetChineseText() throws {
        let html = """
        <html><head><meta charset=\"gbk\"></head><body>科技新闻</body></html>
        """
        let data = try #require(html.data(using: WebPageDecodingSupport.gb18030TestEncoding))

        let decoded = WebPageDecodingSupport.decodeWebPageText(data: data, responseEncodingName: nil)

        #expect(decoded.text.contains("科技新闻"))
        #expect(decoded.encodingName == "gbk")
        #expect(decoded.mojibakeRepaired == false)
    }

    @Test func webPageDecoderRepairsLatin1DecodedGBKChineseMojibake() throws {
        let mojibake = "¿Æ¼¼ÐÂÎÅ"
        let data = try #require(mojibake.data(using: .utf8))

        let decoded = WebPageDecodingSupport.decodeWebPageText(data: data, responseEncodingName: "utf-8")

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
                "renderMode": .string("http"),
                "extractMode": .string("markdown")
            ]),
            context: Self.context()
        )

        #expect(result.contentText.contains("# Native Fetch"))
        #expect(result.contentText.contains("Fetched by Swift."))
        #expect(result.contentJSON?.contains("native-urlsession") == true)
        #expect(result.citations == ["https://example.com/native"])
    }

    @Test func webFetchAcceptsURLsAndFetchesThemConcurrentlyInInputOrder() async throws {
        let httpClient = ConcurrentNativeWebHTTPClient()
        let tool = NativeWebFetchTool(nativeFetchClient: NativeWebFetchClient(httpClient: httpClient))
        let schema = tool.inputSchema.jsonObject
        let properties = try #require(schema["properties"] as? [String: Any])
        let urlsSchema = try #require(properties["urls"] as? [String: Any])
        #expect(urlsSchema["type"] as? String == "array")
        #expect((schema["required"] as? [String])?.isEmpty == true)

        let urls = [
            "https://one.example/page",
            "https://two.example/page",
            "https://three.example/page"
        ]
        let result = try await tool.execute(
            arguments: AgentToolArguments(values: [
                "urls": .array(urls.map(SendableJSONValue.string)),
                "renderMode": .string("http")
            ]),
            context: Self.context()
        )

        #expect(await httpClient.maximumConcurrentRequests() > 1)
        let firstRange = try #require(result.contentText.range(of: "[1] \(urls[0])"))
        let secondRange = try #require(result.contentText.range(of: "[2] \(urls[1])"))
        let thirdRange = try #require(result.contentText.range(of: "[3] \(urls[2])"))
        #expect(firstRange.lowerBound < secondRange.lowerBound)
        #expect(secondRange.lowerBound < thirdRange.lowerBound)
        #expect(result.contentJSON?.contains(#""requestedCount":3"#) == true)
        #expect(result.contentJSON?.contains(#""succeededCount":3"#) == true)
        #expect(result.contentJSON?.contains(#""maximumConcurrency":4"#) == true)
        #expect(result.citations == urls)
    }

    @Test func webFetchFailsAtItsTotalDeadline() async throws {
        let nativeClient = NativeWebFetchClient(httpClient: DelayedNativeWebHTTPClient(
            delay: .seconds(10),
            response: .html("<html></html>", url: "https://example.com/slow")
        ))
        let tool = NativeWebFetchTool(nativeFetchClient: nativeClient)

        do {
            _ = try await tool.execute(
                arguments: AgentToolArguments(values: [
                    "url": .string("https://example.com/slow"),
                    "renderMode": .string("http"),
                    "timeoutMs": .int(1_000)
                ]),
                context: Self.context()
            )
            Issue.record("Expected web_fetch to time out")
        } catch {
            #expect(error as? AgentToolError == .invalidArguments("web_fetch timed out after 1000ms"))
        }
    }

    @Test func webFetchCapsTimeoutPassedToBrowserFallback() async throws {
        final class Recorder: @unchecked Sendable {
            var timeoutMilliseconds: Int?
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
            recorder.timeoutMilliseconds = request.timeoutMilliseconds
            return BrowserAssistedWebFetchResult(
                status: .fetched,
                urlString: request.urlString,
                finalURLString: request.urlString,
                title: "Fetched",
                contentText: "Fetched in browser",
                taskID: "task-timeout-cap",
                sessionID: "session-timeout-cap",
                tabID: "tab-timeout-cap",
                errorMessage: nil,
                interventionReason: nil,
                truncated: false,
                originalCharacterCount: 18
            )
        }, nativeFetchClient: nativeClient)

        _ = try await tool.execute(
            arguments: AgentToolArguments(values: [
                "url": .string("https://example.com/protected"),
                "renderMode": .string("auto"),
                "timeoutMs": .int(720_000)
            ]),
            context: Self.context()
        )

        #expect(recorder.timeoutMilliseconds == 60_000)
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
                "renderMode": .string("js"),
                "extractMode": .string("markdown")
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
                "renderMode": .string("auto")
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
                    "renderMode": .string("http")
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
                "renderMode": .string("js")
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
                "maxResults": .int(3)
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
        #expect(result.contentJSON?.contains("\"tabID\":\"tab-\(engine)\"") == true)
        #expect(result.contentJSON?.contains("\"tab_id\"") == false)
    }

    private struct FakeNativeWebHTTPClient: NativeWebHTTPClient {
        var response: NativeWebHTTPResponse

        func data(for request: URLRequest) async throws -> NativeWebHTTPResponse {
            response
        }
    }

    private struct DelayedNativeWebHTTPClient: NativeWebHTTPClient {
        var delay: Duration
        var response: NativeWebHTTPResponse

        func data(for request: URLRequest) async throws -> NativeWebHTTPResponse {
            try await Task.sleep(for: delay)
            return response
        }
    }

    private actor ConcurrentNativeWebHTTPClient: NativeWebHTTPClient {
        private var activeRequestCount = 0
        private var observedMaximumConcurrentRequests = 0

        func data(for request: URLRequest) async throws -> NativeWebHTTPResponse {
            activeRequestCount += 1
            observedMaximumConcurrentRequests = max(observedMaximumConcurrentRequests, activeRequestCount)
            defer { activeRequestCount -= 1 }
            try await Task.sleep(for: .milliseconds(50))
            guard let url = request.url else { throw URLError(.badURL) }
            let title = url.host ?? "Fetched page"
            return .html("<html><head><title>\(title)</title></head><body>\(url.absoluteString)</body></html>", url: url.absoluteString)
        }

        func maximumConcurrentRequests() -> Int {
            observedMaximumConcurrentRequests
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
