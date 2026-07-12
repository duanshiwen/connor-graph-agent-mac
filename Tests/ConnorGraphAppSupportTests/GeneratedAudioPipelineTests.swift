import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
@testable import ConnorGraphAppSupport

private struct FixtureAudioProvider: AgentGeneratedMediaProvider {
    var modelID = "gpt-4o-mini-tts"
    var capabilities = AgentModelCapabilities(supportsStreaming: true, supportsToolCalling: false, supportsParallelToolCalls: false, supportsStructuredOutput: false, supportsVision: false, generatedMediaCapabilities: [.speechGeneration, .streamingAudioOutput])
    var rawURL: URL

    func generateMedia(_ request: AgentGeneratedMediaRequest) -> AsyncThrowingStream<AgentGeneratedMediaEvent, Error> {
        AsyncThrowingStream { continuation in
            let format = AgentGeneratedAudioFormat(encoding: "pcm_s16le", sampleRate: 24_000, channelCount: 1, bitsPerChannel: 16)
            continuation.yield(.audioStreamStarted(format))
            continuation.yield(.audioChunk(sequence: 0, data: Data([0, 0]), presentationTime: nil))
            continuation.yield(.audioChunk(sequence: 1, data: Data([1, 0]), presentationTime: nil))
            continuation.yield(.completed(AgentGeneratedMediaArtifact(
                temporaryFileURL: rawURL,
                mimeType: "audio/pcm",
                byteCount: 4,
                generationMetadata: AgentAttachmentGenerationMetadata(providerID: "openai-speech", modelID: modelID)
            )))
            continuation.finish()
        }
    }
}

@Suite("Generated Audio Pipeline Tests")
struct GeneratedAudioPipelineTests {
    actor Frames { var values: [Data] = []; func append(_ data: Data) { values.append(data) } }

    @Test func streamsFramesThenPersistsCompletedWAVAttachment() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let raw = root.appendingPathComponent("provider.pcm")
        try Data([0, 0, 1, 0]).write(to: raw)
        let frames = Frames()
        let pipeline = GeneratedAudioPipeline(
            ingestionService: GeneratedMediaIngestionService(store: AppSessionAttachmentStore(paths: paths)),
            streamConfiguration: AgentAudioStreamConfiguration(startupBufferBytes: 2, maximumBufferedBytes: 32)
        )
        let result = try await pipeline.run(
            provider: FixtureAudioProvider(rawURL: raw),
            request: AgentGeneratedMediaRequest(kind: .speech, prompt: "Hello"),
            sessionID: "s",
            onPlayableFrame: { _, data in await frames.append(data) }
        )
        #expect(await frames.values == [Data([0, 0]), Data([1, 0])])
        #expect(result.attachment.kind == .audio)
        #expect(result.attachment.mimeType == "audio/wav")
        #expect(result.attachment.origin == .modelGenerated)
        let reloaded = try AppSessionAttachmentStore(paths: paths).loadManifest(sessionID: "s", attachmentID: result.attachment.id)
        #expect(reloaded.mediaMetadata?.sampleRate == 24_000)
        #expect(reloaded.mediaMetadata?.channelCount == 1)
        #expect(!FileManager.default.fileExists(atPath: raw.path))
    }
}
