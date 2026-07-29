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

    @Test func federatedImageSearchMergesSourceAndLicenseMetadata() async throws {
        let client = NativeImageSearchClient(httpClient: FakeNativeWebHTTPClient(responsesByHost: [
            "api.openverse.org": .json(openverseImageResponseJSON),
            "commons.wikimedia.org": .json(wikimediaCommonsImageResponseJSON, url: "https://commons.wikimedia.org/w/api.php")
        ]))

        let result = try await client.search(englishQuery: "Golden Gate Bridge", maxResults: 5, licenseFilter: .commercial)

        #expect(result.provider == "openverse+wikimedia_commons")
        #expect(result.licenseFilter == .commercial)
        #expect(result.results.count == 2)
        let openverse = try #require(result.results.first)
        let commons = try #require(result.results.dropFirst().first)
        #expect(openverse.imageURL == "https://images.example.com/golden-gate.jpg")
        #expect(commons.imageURL == "https://upload.wikimedia.org/golden-gate-1200.jpg")
        #expect(openverse.sourcePageURL == "https://source.example.com/golden-gate")
        #expect(openverse.license == "by 4.0")
        #expect(commons.license == "CC BY-SA 4.0")
        #expect(openverse.width == 2400)
        #expect(result.markdown.contains("Source page: https://source.example.com/golden-gate"))
        #expect(result.markdown.contains("Attribution: Golden Gate Bridge by Example Photographer, CC BY 4.0"))
        #expect(result.retryAdvice == .notNeeded)
        #expect(result.diagnostics.map(\.status) == [.succeeded, .succeeded])
    }

    @Test func imageSearchUsesAvailableProviderWhenTheOtherProviderFails() async throws {
        let client = NativeImageSearchClient(httpClient: FakeNativeWebHTTPClient(
            responsesByHost: ["commons.wikimedia.org": .json(wikimediaCommonsImageResponseJSON, url: "https://commons.wikimedia.org/w/api.php")],
            errorsByHost: ["api.openverse.org": URLError(.cannotConnectToHost)]
        ))

        let result = try await client.search(englishQuery: "Golden Gate Bridge", maxResults: 3, licenseFilter: .all)

        #expect(result.provider == "wikimedia_commons")
        #expect(result.results.count == 1)
        #expect(result.retryAdvice == .notNeeded)
        #expect(result.diagnostics.first?.status == .failed)
        #expect(result.diagnostics.first?.retryAdvice == .retryLater)
        #expect(result.diagnostics.last?.status == .succeeded)
    }

    @Test func imageSearchExplainsWhenBothProvidersAreNetworkInaccessible() async throws {
        let client = NativeImageSearchClient(httpClient: FakeNativeWebHTTPClient(errorsByHost: [
            "api.openverse.org": URLError(.cannotConnectToHost),
            "commons.wikimedia.org": URLError(.timedOut)
        ]))

        let result = try await client.search(englishQuery: "Golden Gate Bridge", maxResults: 3, licenseFilter: .all)

        #expect(result.provider == "none")
        #expect(result.results.isEmpty)
        #expect(result.retryAdvice == .retryLater)
        #expect(result.diagnostics.allSatisfy { $0.status == .failed })
        #expect(result.diagnostics.allSatisfy { $0.reason.contains("Network request failed") })
    }

    @Test func imageSearchRejectsNonEnglishQueryWithoutNetworkRequests() async throws {
        let client = NativeImageSearchClient(httpClient: FakeNativeWebHTTPClient())

        let result = try await client.search(englishQuery: "金门大桥", maxResults: 3, licenseFilter: .all)

        #expect(result.results.isEmpty)
        #expect(result.retryAdvice == .retryWithEnglishQuery)
        #expect(result.diagnostics == [NativeImageSearchProviderDiagnostic(
            provider: "input",
            status: .invalidQuery,
            reason: "englishQuery does not contain English search terms.",
            retryAdvice: .retryWithEnglishQuery
        )])
    }

    @Test func imageSearchToolReturnsStructuredCandidatesAndSourceCitations() async throws {
        let client = NativeImageSearchClient(httpClient: FakeNativeWebHTTPClient(response: .json(openverseImageResponseJSON)))
        let tool = NativeImageSearchTool(client: client)
        let context = AgentToolExecutionContext(
            runID: "run-image-search",
            sessionID: "session-image-search",
            groupID: "default",
            userPrompt: "Find a Golden Gate Bridge image",
            toolCallID: "call-image-search",
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )

        let result = try await tool.execute(
            arguments: AgentToolArguments(values: [
                "englishQuery": .string("Golden Gate Bridge"),
                "maxResults": .int(3),
                "licenseFilter": .string("commercial")
            ]),
            context: context
        )

        #expect(result.toolName == "image_search")
        #expect(result.citations == ["https://source.example.com/golden-gate"])
        let data = try #require(result.contentJSON?.data(using: String.Encoding.utf8))
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(payload["provider"] as? String == "openverse")
        #expect(payload["queryLanguage"] as? String == "en")
        #expect(payload["retryAdvice"] as? String == "not_needed")
        #expect(payload["fallbackAction"] as? String == "use_candidates_if_relevant")
        #expect(payload["licenseFilter"] as? String == "commercial")
        let providers = try #require(payload["providers"] as? [[String: Any]])
        #expect(providers.count == 2)
        #expect(providers[0]["provider"] as? String == "openverse")
        #expect(providers[1]["provider"] as? String == "wikimedia_commons")
        let candidates = try #require(payload["results"] as? [[String: Any]])
        #expect(candidates.count == 1)
        #expect(candidates[0]["imageURL"] as? String == "https://images.example.com/golden-gate.jpg")
        #expect(candidates[0]["sourcePageURL"] as? String == "https://source.example.com/golden-gate")
    }

    @Test func imageSearchToolAdvertisesEnglishQueryAndNormalizesLegacyArguments() async throws {
        let tool = NativeImageSearchTool(client: NativeImageSearchClient(httpClient: FakeNativeWebHTTPClient(response: .json(openverseImageResponseJSON))))
        let schema = tool.inputSchema.jsonObject
        let properties = try #require(schema["properties"] as? [String: Any])
        let required = try #require(schema["required"] as? [String])

        #expect(properties["englishQuery"] != nil)
        #expect(properties["query"] == nil)
        #expect(required == ["englishQuery"])
        let englishQuerySchema = try #require(properties["englishQuery"] as? [String: Any])
        let englishQueryDescription = try #require(englishQuerySchema["description"] as? String)
        #expect(englishQueryDescription.contains("Exactly one concise English image-search phrase"))
        #expect(englishQueryDescription.contains("Do not provide a list or alternatives"))
        #expect(tool.description.contains("never pack alternative queries into englishQuery"))
        #expect(tool.description.contains("never issue multiple image_search calls in parallel"))

        let normalized = tool.normalizeLegacyArguments(AgentToolArguments(values: [
            "query": .string("West Lake Hangzhou"),
            "max_results": .int(4),
            "license_filter": .string("commercial")
        ]))
        #expect(normalized.string("englishQuery") == "West Lake Hangzhou")
        #expect(normalized.int("maxResults") == 4)
        #expect(normalized.string("licenseFilter") == "commercial")
        #expect(normalized.values["query"] == nil)

        var registry = AgentToolRegistry()
        registry.register(tool)
        let legacyResult = try await registry.execute(
            AgentToolCall(name: "image_search", argumentsJSON: #"{"query":"West Lake Hangzhou","max_results":4}"#),
            context: AgentToolExecutionContext(
                runID: "run-image-legacy",
                sessionID: "session-image-legacy",
                groupID: "default",
                userPrompt: "Find an image",
                toolCallID: "call-image-legacy",
                policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
            )
        )
        #expect(legacyResult.contentJSON?.contains("West Lake Hangzhou") == true)
    }

    @Test func imageSearchToolReturnsTextOnlyFallbackWhenProvidersAreInaccessible() async throws {
        let client = NativeImageSearchClient(httpClient: FakeNativeWebHTTPClient(errorsByHost: [
            "api.openverse.org": URLError(.cannotConnectToHost),
            "commons.wikimedia.org": URLError(.timedOut)
        ]))
        let tool = NativeImageSearchTool(client: client)
        let context = AgentToolExecutionContext(
            runID: "run-image-fallback",
            sessionID: "session-image-fallback",
            groupID: "default",
            userPrompt: "Find an image",
            toolCallID: "call-image-fallback",
            policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
        )

        let result = try await tool.execute(
            arguments: AgentToolArguments(values: ["englishQuery": .string("West Lake Hangzhou")]),
            context: context
        )

        #expect(result.error != nil)
        #expect(result.contentText.contains("currently unreachable or temporarily unavailable"))
        #expect(result.contentText.contains("Do not retry image_search again in this run"))
        #expect(result.contentText.contains("Continue the user's task without image search or an inserted image"))
        let data = try #require(result.contentJSON?.data(using: .utf8))
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(payload["retryAdvice"] as? String == "retry_later")
        #expect(payload["fallbackAction"] as? String == "continue_without_image")
        let providers = try #require(payload["providers"] as? [[String: Any]])
        #expect(providers.allSatisfy { ($0["reason"] as? String)?.contains("Network request failed") == true })
    }
}

private let openverseImageResponseJSON = """
{
  "results": [
    {
      "title": "Golden Gate Bridge",
      "url": "https://images.example.com/golden-gate.jpg",
      "thumbnail": "https://images.example.com/golden-gate-small.jpg",
      "foreign_landing_url": "https://source.example.com/golden-gate",
      "creator": "Example Photographer",
      "creator_url": "https://source.example.com/creator",
      "license": "by",
      "license_version": "4.0",
      "license_url": "https://creativecommons.org/licenses/by/4.0/",
      "attribution": "Golden Gate Bridge by Example Photographer, CC BY 4.0",
      "width": 2400,
      "height": 1600
    },
    {
      "title": "Invalid candidate",
      "url": "javascript:alert(1)",
      "foreign_landing_url": "https://source.example.com/invalid"
    }
  ]
}
"""

private let wikimediaCommonsImageResponseJSON = """
{
  "query": {
    "pages": [
      {
        "title": "File:Golden Gate Bridge at sunset.jpg",
        "index": 1,
        "imageinfo": [
          {
            "thumburl": "https://upload.wikimedia.org/golden-gate-1200.jpg",
            "thumbwidth": 1200,
            "thumbheight": 800,
            "url": "https://upload.wikimedia.org/golden-gate-original.jpg",
            "descriptionurl": "https://commons.wikimedia.org/wiki/File:Golden_Gate_Bridge_at_sunset.jpg",
            "extmetadata": {
              "Artist": {"value": "<a href=\\\"https://commons.wikimedia.org/wiki/User:Example\\\">Example Artist</a>"},
              "LicenseShortName": {"value": "CC BY-SA 4.0"},
              "LicenseUrl": {"value": "https://creativecommons.org/licenses/by-sa/4.0/"},
              "Attribution": {"value": "Example Artist, CC BY-SA 4.0"}
            }
          }
        ]
      }
    ]
  }
}
"""

private struct FakeNativeWebHTTPClient: NativeWebHTTPClient {
    var response: NativeWebHTTPResponse?
    var responsesByHost: [String: NativeWebHTTPResponse]
    var errorsByHost: [String: URLError]

    init(
        response: NativeWebHTTPResponse? = nil,
        responsesByHost: [String: NativeWebHTTPResponse] = [:],
        errorsByHost: [String: URLError] = [:]
    ) {
        self.response = response
        self.responsesByHost = responsesByHost
        self.errorsByHost = errorsByHost
    }

    func data(for request: URLRequest) async throws -> NativeWebHTTPResponse {
        let host = request.url?.host ?? ""
        if let error = errorsByHost[host] { throw error }
        if let routed = responsesByHost[host] { return routed }
        if let response { return response }
        throw URLError(.unsupportedURL)
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

    static func json(_ json: String, url: String = "https://api.openverse.org/v1/images/") -> NativeWebHTTPResponse {
        NativeWebHTTPResponse(
            data: Data(json.utf8),
            statusCode: 200,
            mimeType: "application/json",
            finalURL: URL(string: url),
            textEncodingName: "utf-8"
        )
    }
}
