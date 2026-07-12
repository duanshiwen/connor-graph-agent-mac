import Foundation
import Testing
import ConnorGraphAgent

private actor FluxResponseQueue { var responses: [AgentHTTPResponse]; var requests: [AgentHTTPRequest] = []; init(_ responses: [AgentHTTPResponse]) { self.responses = responses }; func next(_ request: AgentHTTPRequest) -> AgentHTTPResponse { requests.append(request); return responses.removeFirst() }; func captured() -> [AgentHTTPRequest] { requests } }
private struct FluxQueuedClient: AgentHTTPClient { let queue: FluxResponseQueue; mutating func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse { await queue.next(request) } }

@Test func fluxImageProviderSubmitsPollsAndDownloadsArtifact() async throws {
    let image = Data([1, 2, 3, 4]); let queue = FluxResponseQueue([
        AgentHTTPResponse(statusCode: 200, body: Data(#"{"id":"flux-job-1"}"#.utf8)),
        AgentHTTPResponse(statusCode: 200, body: Data(#"{"status":"Pending"}"#.utf8)),
        AgentHTTPResponse(statusCode: 200, body: Data(#"{"status":"Ready","result":{"sample":"https://cdn.example/image.png"}}"#.utf8)),
        AgentHTTPResponse(statusCode: 200, body: image)
    ])
    let provider = FluxImageGeneratedMediaProvider(config: FluxImageGeneratedMediaConfig(apiKey: "flux-key", pollInterval: 0, maxPollAttempts: 3), httpClient: FluxQueuedClient(queue: queue))
    var artifact: AgentGeneratedMediaArtifact?
    for try await event in provider.generateMedia(AgentGeneratedMediaRequest(kind: .image, prompt: "A mountain")) { if case .completed(let value) = event { artifact = value } }
    let completed = try #require(artifact); defer { try? FileManager.default.removeItem(at: completed.temporaryFileURL) }
    #expect(try Data(contentsOf: completed.temporaryFileURL) == image)
    #expect(completed.generationMetadata.responseID == "flux-job-1")
    let requests = await queue.captured(); #expect(requests.count == 4); #expect(requests[0].headers["x-key"] == "flux-key"); #expect(requests[1].url.absoluteString.contains("get_result?id=flux-job-1"))
}

@Test func fluxImageProviderSurfacesTerminalFailure() async throws {
    let queue = FluxResponseQueue([AgentHTTPResponse(statusCode: 200, body: Data(#"{"id":"job"}"#.utf8)), AgentHTTPResponse(statusCode: 200, body: Data(#"{"status":"Failed","error":"moderated"}"#.utf8))])
    let provider = FluxImageGeneratedMediaProvider(config: FluxImageGeneratedMediaConfig(apiKey: "key", pollInterval: 0), httpClient: FluxQueuedClient(queue: queue))
    do { for try await _ in provider.generateMedia(AgentGeneratedMediaRequest(kind: .image, prompt: "test")) {}; Issue.record("Expected failure") } catch { #expect(error as? FluxImageGeneratedMediaError == .failed("moderated")) }
}

@Test func fluxImageProviderTimesOutAfterConfiguredPollingLimit() async throws {
    let queue = FluxResponseQueue([AgentHTTPResponse(statusCode: 200, body: Data(#"{"id":"job"}"#.utf8)), AgentHTTPResponse(statusCode: 200, body: Data(#"{"status":"Pending"}"#.utf8))])
    let provider = FluxImageGeneratedMediaProvider(config: FluxImageGeneratedMediaConfig(apiKey: "key", pollInterval: 0, maxPollAttempts: 1), httpClient: FluxQueuedClient(queue: queue))
    do { for try await _ in provider.generateMedia(AgentGeneratedMediaRequest(kind: .image, prompt: "test")) {}; Issue.record("Expected timeout") } catch { #expect(error as? FluxImageGeneratedMediaError == .timedOut) }
}
