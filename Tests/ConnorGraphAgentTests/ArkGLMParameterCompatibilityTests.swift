import Foundation
import Testing
import ConnorGraphAgent

private actor ArkGLMRequestCapture {
    var requests: [AgentHTTPRequest] = []
    func record(_ request: AgentHTTPRequest) { requests.append(request) }
}

private struct ArkGLMValidationClient: AgentHTTPClient, AgentSSEHTTPClient {
    let capture: ArkGLMRequestCapture
    var status = 400
    var alwaysReject = false
    var emitsBeforeFailure = false
    var rejectsAtHandshake = false

    private func rejects(_ request: AgentHTTPRequest) throws -> Bool {
        let object = try JSONSerialization.jsonObject(with: request.body) as? [String: Any]
        return alwaysReject || object?["thinking"] != nil
    }

    mutating func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse {
        await capture.record(request)
        if try rejects(request) {
            return AgentHTTPResponse(statusCode: status, body: Data(#"{"error":{"message":"A parameter specified in the request is not valid Request id: regression-id"}}"#.utf8))
        }
        return AgentHTTPResponse(statusCode: 200, body: Data(#"{"choices":[{"message":{"role":"assistant","content":"OK"},"finish_reason":"stop"}]}"#.utf8))
    }

    func stream(_ request: AgentHTTPRequest) async throws -> AsyncThrowingStream<String, Error> {
        await capture.record(request)
        let rejected = try rejects(request)
        let error = OpenAICompatibleProviderError.httpStatus(status, message: "A parameter specified in the request is not valid Request id: regression-id")
        if rejected && rejectsAtHandshake { throw error }
        return AsyncThrowingStream { continuation in
            if rejected {
                if emitsBeforeFailure {
                    continuation.yield(#"data: {"choices":[{"delta":{"content":"partial"}}]}"# + "\n")
                }
                continuation.finish(throwing: error)
            } else {
                continuation.yield(#"data: {"choices":[{"delta":{"content":"OK"},"finish_reason":"stop"}]}"# + "\n")
                continuation.finish()
            }
        }
    }
}

private func arkGLMProvider(_ client: ArkGLMValidationClient, url: String = "https://ark.cn-beijing.volces.com/api/plan/v3") -> OpenAICompatibleProvider<ArkGLMValidationClient> {
    OpenAICompatibleProvider(
        config: OpenAICompatibleConfig(baseURL: URL(string: url)!, apiKey: "test-key", model: "glm-5.3-flash", reasoningEffort: "high", thinkingEnabled: true, topP: 0.95, temperatureOverride: 1),
        httpClient: client, sseClient: client
    )
}

@Test(arguments: [false, true]) func arkGLMParameterFallbackPreservesRequest(streaming: Bool) async throws {
    let capture = ArkGLMRequestCapture()
    let provider = arkGLMProvider(ArkGLMValidationClient(capture: capture))
    let request = AgentModelRequest(
        messages: [AgentModelMessage(role: .user, content: "Search")],
        tools: [AgentToolDefinition(name: "search", description: "Search", inputSchema: .object(properties: [:], required: []))],
        maxTokens: 16_384
    )
    if streaming {
        for try await event in provider.streamComplete(request) {
            if case .completed(let response) = event { #expect(response.text == "OK") }
        }
    } else {
        let response = try await provider.complete(request)
        #expect(response.text == "OK")
    }
    let requests = await capture.requests
    #expect(requests.count == 2)
    let first = try #require(requests.first)
    let last = try #require(requests.last)
    var expected = try #require(try JSONSerialization.jsonObject(with: first.body) as? [String: Any])
    for key in ["thinking", "reasoning_effort", "temperature", "top_p"] { expected.removeValue(forKey: key) }
    let actual = try #require(try JSONSerialization.jsonObject(with: last.body) as? [String: Any])
    #expect(NSDictionary(dictionary: expected).isEqual(to: actual))
    #expect(first.url == last.url)
    #expect(first.headers == last.headers)
    #expect(first.timeoutInterval == last.timeoutInterval)
}

@Test(arguments: ["handshake", "partial", "unauthorized", "second-failure", "other-host"])
func arkGLMParameterFallbackIsBounded(scenario: String) async throws {
    let capture = ArkGLMRequestCapture()
    let client = ArkGLMValidationClient(capture: capture, status: scenario == "unauthorized" ? 401 : 400, alwaysReject: scenario == "second-failure", emitsBeforeFailure: scenario == "partial", rejectsAtHandshake: scenario == "handshake")
    let provider = arkGLMProvider(client, url: scenario == "other-host" ? "https://volces.com.example/api/plan/v3" : "https://ark.cn-beijing.volces.com/api/plan/v3")
    var completed = false
    do {
        for try await event in provider.streamComplete(AgentModelRequest(messages: [AgentModelMessage(role: .user, content: "Hello")])) {
            if case .completed = event { completed = true }
        }
        #expect(scenario == "handshake")
    } catch let error as OpenAICompatibleProviderError {
        #expect(scenario != "handshake")
        if case .httpStatus = error { } else { Issue.record("Expected original HTTP failure") }
    }
    #expect(completed == (scenario == "handshake"))
    let requests = await capture.requests
    #expect(requests.count == ((scenario == "handshake" || scenario == "second-failure") ? 2 : 1))
}
