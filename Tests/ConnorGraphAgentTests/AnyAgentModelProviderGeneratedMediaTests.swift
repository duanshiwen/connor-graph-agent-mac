import Foundation
import Testing
@testable import ConnorGraphAgent

private struct GeneratedMediaCapableProvider: AgentModelProvider, AgentGeneratedMediaProvider {
    let modelID = "gpt-5.6"
    let capabilities = AgentModelCapabilities(
        supportsStreaming: true,
        supportsToolCalling: true,
        supportsParallelToolCalls: false,
        supportsStructuredOutput: false,
        supportsVision: true,
        generatedMediaCapabilities: [.imageGeneration]
    )

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        AgentModelResponse(text: request.messages.last?.content ?? "")
    }

    func generateMedia(_ request: AgentGeneratedMediaRequest) -> AsyncThrowingStream<AgentGeneratedMediaEvent, Error> {
        AsyncThrowingStream { continuation in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
            let data = Data([0x89, 0x50, 0x4E, 0x47])
            try? data.write(to: url)
            continuation.yield(.started)
            continuation.yield(.completed(AgentGeneratedMediaArtifact(
                temporaryFileURL: url,
                mimeType: "image/png",
                byteCount: Int64(data.count),
                generationMetadata: AgentAttachmentGenerationMetadata(providerID: "openai", modelID: modelID, revisedPrompt: request.prompt)
            )))
            continuation.finish()
        }
    }
}

@Suite("Any Agent Model Provider Generated Media Tests")
struct AnyAgentModelProviderGeneratedMediaTests {
    @Test func typeErasurePreservesGeneratedMediaExecutionAndCapabilities() async throws {
        let provider = AnyAgentModelProvider(GeneratedMediaCapableProvider())
        #expect(provider.modelID == "gpt-5.6")
        #expect(provider.capabilities.generatedMediaCapabilities == [.imageGeneration])
        #expect(provider.supportsGeneratedMediaExecution)

        var completedArtifact: AgentGeneratedMediaArtifact?
        for try await event in provider.generateMedia(AgentGeneratedMediaRequest(kind: .image, prompt: "A quiet lake")) {
            if case .completed(let artifact) = event { completedArtifact = artifact }
        }
        let artifact = try #require(completedArtifact)
        defer { try? FileManager.default.removeItem(at: artifact.temporaryFileURL) }
        #expect(artifact.generationMetadata.revisedPrompt == "A quiet lake")
    }

    @Test func closureInitializerCanExposeGeneratedMediaExecution() async throws {
        let provider = AnyAgentModelProvider(
            modelID: "closure-model",
            capabilities: AgentModelCapabilities(
                supportsStreaming: false,
                supportsToolCalling: true,
                supportsParallelToolCalls: false,
                supportsStructuredOutput: false,
                supportsVision: false,
                generatedMediaCapabilities: [.imageGeneration]
            ),
            complete: { _ in AgentModelResponse(text: "ok") },
            generateMedia: { request in
                AsyncThrowingStream { continuation in
                    continuation.yield(.progress(request.prompt == "test" ? 1 : 0))
                    continuation.finish()
                }
            }
        )

        #expect(provider.supportsGeneratedMediaExecution)
        var events: [AgentGeneratedMediaEvent] = []
        for try await event in provider.generateMedia(AgentGeneratedMediaRequest(kind: .image, prompt: "test")) { events.append(event) }
        #expect(events == [.progress(1)])
    }

    @Test func unavailableGeneratedMediaExecutionReturnsTypedError() async throws {
        let provider = AnyAgentModelProvider(modelID: "text-only") { _ in AgentModelResponse(text: "ok") }
        #expect(provider.supportsGeneratedMediaExecution == false)

        do {
            for try await _ in provider.generateMedia(AgentGeneratedMediaRequest(kind: .image, prompt: "test")) {}
            Issue.record("Expected generated media execution to fail")
        } catch let error as AnyAgentModelProviderError {
            #expect(error == .generatedMediaUnavailable(modelID: "text-only"))
        }
    }

    @Test func completionFallbackStillWorksAfterMediaTypeErasureChange() async throws {
        let provider = AnyAgentModelProvider(GeneratedMediaCapableProvider())
        let response = try await provider.complete(AgentModelRequest(messages: [.init(role: .user, content: "hello")]))
        #expect(response.text == "hello")

        var streamed: [AgentModelStreamEvent] = []
        for try await event in provider.streamComplete(AgentModelRequest(messages: [.init(role: .user, content: "stream")])) { streamed.append(event) }
        #expect(streamed == [.completed(AgentModelResponse(text: "stream"))])
    }
}
