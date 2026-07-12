import Foundation
import Testing
import ConnorGraphAgent

private struct StabilityCapturingClient: AgentHTTPClient { final class Storage: @unchecked Sendable { var request: AgentHTTPRequest? }; var response: AgentHTTPResponse; var storage = Storage(); mutating func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse { storage.request = request; return response } }

@Test(arguments: [("stable-image-ultra", "stable-image/generate/ultra"), ("stable-image-core", "stable-image/generate/core"), ("sd3.5-large", "stable-image/generate/sd3")])
func stabilityImageProviderRoutesSupportedModels(model: String, path: String) async throws {
    let bytes = Data([9, 8, 7]); let client = StabilityCapturingClient(response: AgentHTTPResponse(statusCode: 200, body: Data("{\"id\":\"stable-1\",\"image\":\"\(bytes.base64EncodedString())\"}".utf8)))
    let provider = StabilityImageGeneratedMediaProvider(config: StabilityImageGeneratedMediaConfig(apiKey: "stable-key", model: model), httpClient: client)
    var artifact: AgentGeneratedMediaArtifact?
    for try await event in provider.generateMedia(AgentGeneratedMediaRequest(kind: .image, prompt: "A forest", options: ["aspect_ratio": "16:9"])) { if case .completed(let item) = event { artifact = item } }
    let completed = try #require(artifact); defer { try? FileManager.default.removeItem(at: completed.temporaryFileURL) }
    #expect(try Data(contentsOf: completed.temporaryFileURL) == bytes); #expect(completed.generationMetadata.providerID == "stability-ai")
    #expect(client.storage.request?.url.path.hasSuffix(path) == true); #expect(client.storage.request?.headers["Authorization"] == "Bearer stable-key")
    let body = String(decoding: try #require(client.storage.request?.body), as: UTF8.self); #expect(body.contains("A forest")); #expect(body.contains("16:9")); if model.hasPrefix("sd3.5") { #expect(body.contains(model)); #expect(body.contains("text-to-image")) }
}

@Test func stabilityImageProviderRejectsUnsupportedModel() async throws {
    let client = StabilityCapturingClient(response: AgentHTTPResponse(statusCode: 200, body: Data()))
    let provider = StabilityImageGeneratedMediaProvider(config: StabilityImageGeneratedMediaConfig(apiKey: "key", model: "unknown"), httpClient: client)
    do { for try await _ in provider.generateMedia(AgentGeneratedMediaRequest(kind: .image, prompt: "test")) {}; Issue.record("Expected unsupported model") } catch { #expect(error as? StabilityImageGeneratedMediaError == .unsupportedModel("unknown")) }
    #expect(client.storage.request == nil)
}
