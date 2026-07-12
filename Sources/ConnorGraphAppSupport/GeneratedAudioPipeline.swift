import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public struct GeneratedAudioPipelineResult: Sendable, Equatable {
    public var attachment: AgentAttachmentManifest
    public var streamSnapshot: AgentAudioStreamSnapshot
}

public struct GeneratedAudioPipeline: Sendable {
    public var ingestionService: GeneratedMediaIngestionService
    public var streamConfiguration: AgentAudioStreamConfiguration

    public init(ingestionService: GeneratedMediaIngestionService, streamConfiguration: AgentAudioStreamConfiguration = AgentAudioStreamConfiguration()) {
        self.ingestionService = ingestionService
        self.streamConfiguration = streamConfiguration
    }

    public func run<Provider: AgentGeneratedMediaProvider>(
        provider: Provider,
        request: AgentGeneratedMediaRequest,
        sessionID: String,
        onPlayableFrame: @escaping @Sendable (AgentGeneratedAudioFormat, Data) async throws -> Void = { _, _ in }
    ) async throws -> GeneratedAudioPipelineResult {
        let streamSession = AgentAudioStreamSession(configuration: streamConfiguration)
        var audioFormat: AgentGeneratedAudioFormat?
        var providerArtifact: AgentGeneratedMediaArtifact?
        do {
            for try await event in provider.generateMedia(request) {
                switch event {
                case .audioStreamStarted(let format):
                    audioFormat = format
                    try await streamSession.start(format: format)
                case .audioChunk(let sequence, let data, _):
                    guard let audioFormat else { throw AgentAudioStreamSessionError.notStarted }
                    for frame in try await streamSession.append(sequence: sequence, data: data) {
                        try await onPlayableFrame(audioFormat, frame)
                    }
                case .completed(let artifact):
                    providerArtifact = artifact
                case .started, .progress, .preview:
                    break
                }
            }
            guard let providerArtifact else { throw OpenAISpeechGeneratedMediaError.emptyAudio }
            let wavURL = try await streamSession.finish()
            try? FileManager.default.removeItem(at: providerArtifact.temporaryFileURL)
            let wavBytes = try AppSessionAttachmentStore.byteCount(forItemAt: wavURL)
            let wavArtifact = AgentGeneratedMediaArtifact(
                temporaryFileURL: wavURL,
                mimeType: "audio/wav",
                byteCount: wavBytes,
                generationMetadata: providerArtifact.generationMetadata
            )
            let manifest = try ingestionService.ingest(artifact: wavArtifact, sessionID: sessionID)
            return GeneratedAudioPipelineResult(attachment: manifest, streamSnapshot: await streamSession.snapshot())
        } catch {
            await streamSession.cancel()
            if let providerArtifact { try? FileManager.default.removeItem(at: providerArtifact.temporaryFileURL) }
            throw error
        }
    }
}
