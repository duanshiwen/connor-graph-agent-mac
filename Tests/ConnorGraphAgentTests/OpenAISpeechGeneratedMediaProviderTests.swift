import Foundation
import Testing
@testable import ConnorGraphAgent

private struct CapturingByteStreamClient: AgentByteStreamHTTPClient {
    final class Storage: @unchecked Sendable { var request: AgentHTTPRequest? }
    var chunks: [Data]
    var storage = Storage()
    func stream(_ request: AgentHTTPRequest) async throws -> AsyncThrowingStream<Data, Error> {
        storage.request = request
        return AsyncThrowingStream { continuation in
            chunks.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}

@Suite("OpenAI Speech Generated Media Provider Tests")
struct OpenAISpeechGeneratedMediaProviderTests {
    @Test func streamsPCMChunksUsingCurrentModel() async throws {
        let client = CapturingByteStreamClient(chunks: [Data([0, 1]), Data([2, 3])])
        let capabilities = AgentModelCapabilities(
            supportsStreaming: true,
            supportsToolCalling: false,
            supportsParallelToolCalls: false,
            supportsStructuredOutput: false,
            supportsVision: false,
            generatedMediaCapabilities: [.speechGeneration, .streamingAudioOutput]
        )
        let provider = OpenAISpeechGeneratedMediaProvider(
            baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "key", modelID: "gpt-4o-mini-tts", capabilities: capabilities, client: client
        )
        var sequences: [Int] = []
        var artifact: AgentGeneratedMediaArtifact?
        for try await event in provider.generateMedia(AgentGeneratedMediaRequest(kind: .speech, prompt: "Hello", options: ["voice": "coral"])) {
            if case .audioChunk(let sequence, _, _) = event { sequences.append(sequence) }
            if case .completed(let value) = event { artifact = value }
        }
        #expect(sequences == [0, 1])
        let completed = try #require(artifact)
        #expect(try Data(contentsOf: completed.temporaryFileURL) == Data([0, 1, 2, 3]))
        defer { try? FileManager.default.removeItem(at: completed.temporaryFileURL) }
        let request = try #require(client.storage.request)
        #expect(request.url.absoluteString == "https://api.openai.com/v1/audio/speech")
        let body = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        #expect(body["model"] as? String == "gpt-4o-mini-tts")
        #expect(body["voice"] as? String == "coral")
        #expect(body["response_format"] as? String == "pcm")
    }

    @Test func unsupportedModelDoesNotOpenByteStream() async throws {
        let client = CapturingByteStreamClient(chunks: [])
        let provider = OpenAISpeechGeneratedMediaProvider(
            baseURL: URL(string: "https://api.openai.com/v1")!, apiKey: "key", modelID: "gpt-text", capabilities: AgentModelCapabilities(supportsStreaming: true, supportsToolCalling: true, supportsParallelToolCalls: false, supportsStructuredOutput: false, supportsVision: false), client: client
        )
        do {
            for try await _ in provider.generateMedia(AgentGeneratedMediaRequest(kind: .speech, prompt: "Hello")) {}
            Issue.record("Expected unsupported model")
        } catch let error as OpenAISpeechGeneratedMediaError {
            if case .unsupportedByCurrentModel = error {} else { Issue.record("Unexpected error") }
        }
        #expect(client.storage.request == nil)
    }
}
