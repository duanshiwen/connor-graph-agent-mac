import Foundation
import Testing
import ConnorGraphAgent

private struct GeminiCapturingClient: AgentHTTPClient {
    final class Storage: @unchecked Sendable { var request: AgentHTTPRequest? }
    var response: AgentHTTPResponse
    var storage = Storage()
    mutating func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse { storage.request = request; return response }
}

@Test func geminiImageProviderGeneratesTemporaryImageArtifact() async throws {
    let png = Data([0x89, 0x50, 0x4E, 0x47])
    let body = Data(#"{"id":"interaction-1","output_image":{"data":"\#(png.base64EncodedString())","mime_type":"image/png"}}"#.utf8)
    let client = GeminiCapturingClient(response: AgentHTTPResponse(statusCode: 200, body: body))
    let provider = GeminiImageGeneratedMediaProvider(config: GeminiImageGeneratedMediaConfig(apiKey: "gemini-secret", model: "gemini-3.1-flash-image"), httpClient: client)
    var artifact: AgentGeneratedMediaArtifact?

    for try await event in provider.generateMedia(AgentGeneratedMediaRequest(kind: .image, prompt: "A quiet lake", options: ["aspect_ratio": "16:9", "image_size": "2K"])) {
        if case .completed(let value) = event { artifact = value }
    }
    let completed = try #require(artifact)
    defer { try? FileManager.default.removeItem(at: completed.temporaryFileURL) }

    #expect(try Data(contentsOf: completed.temporaryFileURL) == png)
    #expect(completed.generationMetadata.providerID == "google-gemini-image")
    #expect(client.storage.request?.url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/interactions")
    #expect(client.storage.request?.headers["x-goog-api-key"] == "gemini-secret")
    let requestBody = try #require(client.storage.request?.body)
    let object = try #require(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
    #expect(object["model"] as? String == "gemini-3.1-flash-image")
    let format = try #require(object["response_format"] as? [String: Any])
    #expect(format["aspect_ratio"] as? String == "16:9")
    #expect(format["image_size"] as? String == "2K")
}

@Test func geminiImageProviderRejectsUnsupportedModelBeforeNetwork() async throws {
    let client = GeminiCapturingClient(response: AgentHTTPResponse(statusCode: 200, body: Data()))
    let provider = GeminiImageGeneratedMediaProvider(config: GeminiImageGeneratedMediaConfig(apiKey: "key", model: "gemini-chat-only"), httpClient: client)
    do {
        for try await _ in provider.generateMedia(AgentGeneratedMediaRequest(kind: .image, prompt: "test")) {}
        Issue.record("Expected unsupported model")
    } catch {
        #expect(error as? GeminiImageGeneratedMediaError == .unsupportedModel("gemini-chat-only"))
    }
    #expect(client.storage.request == nil)
}

@Test func geminiImageProviderReportsMissingImage() async throws {
    let client = GeminiCapturingClient(response: AgentHTTPResponse(statusCode: 200, body: Data(#"{"id":"empty"}"#.utf8)))
    let provider = GeminiImageGeneratedMediaProvider(config: GeminiImageGeneratedMediaConfig(apiKey: "key"), httpClient: client)
    do {
        for try await _ in provider.generateMedia(AgentGeneratedMediaRequest(kind: .image, prompt: "test")) {}
        Issue.record("Expected missing image")
    } catch { #expect(error as? GeminiImageGeneratedMediaError == .missingImage) }
}
