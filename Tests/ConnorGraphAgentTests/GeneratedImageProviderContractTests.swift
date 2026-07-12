import Foundation
import Testing
import ConnorGraphAgent

private struct ContractGeneratedImageProvider: AgentGeneratedMediaProvider {
    let modelID = "contract-image-model"
    let capabilities = AgentModelCapabilities(
        supportsStreaming: false,
        supportsToolCalling: false,
        supportsParallelToolCalls: false,
        supportsStructuredOutput: false,
        supportsVision: false,
        generatedMediaCapabilities: [.imageGeneration]
    )
    let artifact: AgentGeneratedMediaArtifact

    func generateMedia(_ request: AgentGeneratedMediaRequest) -> AsyncThrowingStream<AgentGeneratedMediaEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.started)
            continuation.yield(.completed(artifact))
            continuation.finish()
        }
    }
}

private func assertGeneratedImageProviderContract<P: AgentGeneratedMediaProvider>(
    _ provider: P,
    expectedData: Data,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    #expect(provider.capabilities.generatedMediaCapabilities.contains(.imageGeneration), sourceLocation: sourceLocation)
    var events: [AgentGeneratedMediaEvent] = []
    for try await event in provider.generateMedia(AgentGeneratedMediaRequest(kind: .image, prompt: "contract prompt")) {
        events.append(event)
    }
    #expect(events.first == .started, sourceLocation: sourceLocation)
    let artifact = try #require(events.compactMap { event -> AgentGeneratedMediaArtifact? in
        if case .completed(let artifact) = event { return artifact }
        return nil
    }.last, sourceLocation: sourceLocation)
    #expect(artifact.mimeType.hasPrefix("image/"), sourceLocation: sourceLocation)
    #expect(artifact.byteCount == Int64(expectedData.count), sourceLocation: sourceLocation)
    #expect(artifact.generationMetadata.providerID.isEmpty == false, sourceLocation: sourceLocation)
    #expect(artifact.generationMetadata.modelID == provider.modelID, sourceLocation: sourceLocation)
    #expect(artifact.temporaryFileURL.isFileURL, sourceLocation: sourceLocation)
    #expect(FileManager.default.fileExists(atPath: artifact.temporaryFileURL.path), sourceLocation: sourceLocation)
    #expect(try Data(contentsOf: artifact.temporaryFileURL) == expectedData, sourceLocation: sourceLocation)
}

@Test func generatedImageProviderContractRequiresTemporaryArtifactAndCompleteMetadata() async throws {
    let data = Data([0x89, 0x50, 0x4E, 0x47])
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("contract-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: url) }
    try data.write(to: url)
    let provider = ContractGeneratedImageProvider(artifact: AgentGeneratedMediaArtifact(
        temporaryFileURL: url,
        mimeType: "image/png",
        byteCount: Int64(data.count),
        generationMetadata: AgentAttachmentGenerationMetadata(
            providerID: "contract-provider",
            modelID: "contract-image-model",
            responseID: "response-1"
        )
    ))

    try await assertGeneratedImageProviderContract(provider, expectedData: data)
}
