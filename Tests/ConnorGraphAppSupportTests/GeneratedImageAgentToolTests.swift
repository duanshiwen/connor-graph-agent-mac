import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
@testable import ConnorGraphAppSupport

private actor GeneratedImageRequestRecorder {
    var requests: [AgentGeneratedMediaRequest] = []
    func record(_ request: AgentGeneratedMediaRequest) { requests.append(request) }
}

private func generatedImageToolContext(sessionID: String = "image-session") -> AgentToolExecutionContext {
    AgentToolExecutionContext(
        runID: "run-1",
        sessionID: sessionID,
        groupID: "default",
        userPrompt: "Generate an image",
        toolCallID: "call-1",
        policyEngine: AgentPolicyEngine(permissionMode: .allowAll)
    )
}

private func generatedImageTestPaths() throws -> AppStoragePaths {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let paths = AppStoragePaths(applicationSupportDirectory: root)
    try paths.ensureDirectoryHierarchy()
    return paths
}

private let validGeneratedPNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

@Suite("Generated Image Agent Tool Tests")
struct GeneratedImageAgentToolTests {
    @Test func generatesPersistsAndReturnsStronglyTypedAttachmentPayload() async throws {
        let paths = try generatedImageTestPaths()
        defer { try? FileManager.default.removeItem(at: paths.applicationSupportDirectory) }
        let recorder = GeneratedImageRequestRecorder()
        let metadata = AgentAttachmentGenerationMetadata(
            providerID: "openai-responses",
            modelID: "gpt-5.6",
            responseID: "resp-1",
            toolCallID: "image-call-1",
            revisedPrompt: "A revised lake prompt"
        )
        let provider = AnyAgentModelProvider(
            modelID: "gpt-5.6",
            capabilities: AgentModelCapabilities(
                supportsStreaming: true,
                supportsToolCalling: true,
                supportsParallelToolCalls: false,
                supportsStructuredOutput: false,
                supportsVision: true,
                generatedMediaCapabilities: [.imageGeneration]
            ),
            complete: { _ in AgentModelResponse(text: "unused") },
            generateMedia: { request in
                AsyncThrowingStream { continuation in
                    Task {
                        await recorder.record(request)
                        let temporaryURL = paths.applicationSupportDirectory.appendingPathComponent("provider-result.png")
                        do {
                            try validGeneratedPNG.write(to: temporaryURL)
                            continuation.yield(.started)
                            continuation.yield(.completed(AgentGeneratedMediaArtifact(
                                temporaryFileURL: temporaryURL,
                                mimeType: "image/png",
                                byteCount: Int64(validGeneratedPNG.count),
                                generationMetadata: metadata
                            )))
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                }
            }
        )
        let tool = GeneratedImageAgentTool(
            provider: provider,
            ingestionService: GeneratedMediaIngestionService(store: AppSessionAttachmentStore(paths: paths))
        )

        let result = try await tool.execute(
            arguments: AgentToolArguments(values: ["prompt": .string("  A quiet lake  ")]),
            context: generatedImageToolContext()
        )

        let requests = await recorder.requests
        #expect(requests == [AgentGeneratedMediaRequest(kind: .image, prompt: "A quiet lake")])
        #expect(result.toolName == "generate_image")
        #expect(result.runID == "run-1")
        #expect(result.sessionID == "image-session")
        let payloadData = try #require(result.contentJSON?.data(using: .utf8))
        let payload = try JSONDecoder().decode(GeneratedImageToolResultPayload.self, from: payloadData)
        #expect(payload.generationMetadata == metadata)
        #expect(payload.attachment.kind == .image)
        let manifest = try AppSessionAttachmentStore(paths: paths).loadManifest(sessionID: "image-session", attachmentID: payload.attachment.id)
        #expect(manifest.origin == .modelGenerated)
        #expect(manifest.generationMetadata == metadata)
        #expect(manifest.messageRef == payload.attachment)
    }

    @Test func rejectsUnsupportedCurrentModelBeforeCallingProvider() async throws {
        let paths = try generatedImageTestPaths()
        defer { try? FileManager.default.removeItem(at: paths.applicationSupportDirectory) }
        let provider = AnyAgentModelProvider(modelID: "text-only") { _ in AgentModelResponse(text: "unused") }
        let tool = GeneratedImageAgentTool(provider: provider, ingestionService: GeneratedMediaIngestionService(store: AppSessionAttachmentStore(paths: paths)))

        do {
            _ = try await tool.execute(arguments: AgentToolArguments(values: ["prompt": .string("A lake")]), context: generatedImageToolContext())
            Issue.record("Expected unsupported model error")
        } catch let error as GeneratedImageAgentToolError {
            if case .unsupportedByCurrentModel(let reason) = error {
                #expect(reason.contains("text-only"))
            } else {
                Issue.record("Unexpected generated image error: \(error)")
            }
        }
    }

    @Test func requiresCompletedArtifact() async throws {
        let paths = try generatedImageTestPaths()
        defer { try? FileManager.default.removeItem(at: paths.applicationSupportDirectory) }
        let provider = AnyAgentModelProvider(
            modelID: "gpt-5.6",
            capabilities: AgentModelCapabilities(
                supportsStreaming: true,
                supportsToolCalling: true,
                supportsParallelToolCalls: false,
                supportsStructuredOutput: false,
                supportsVision: true,
                generatedMediaCapabilities: [.imageGeneration]
            ),
            complete: { _ in AgentModelResponse(text: "unused") },
            generateMedia: { _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.started)
                    continuation.finish()
                }
            }
        )
        let tool = GeneratedImageAgentTool(provider: provider, ingestionService: GeneratedMediaIngestionService(store: AppSessionAttachmentStore(paths: paths)))

        await #expect(throws: GeneratedImageAgentToolError.completedArtifactMissing) {
            try await tool.execute(arguments: AgentToolArguments(values: ["prompt": .string("A lake")]), context: generatedImageToolContext())
        }
    }

    @Test func rejectsEmptyPrompt() async throws {
        let paths = try generatedImageTestPaths()
        defer { try? FileManager.default.removeItem(at: paths.applicationSupportDirectory) }
        let provider = AnyAgentModelProvider(modelID: "gpt-5.6") { _ in AgentModelResponse(text: "unused") }
        let tool = GeneratedImageAgentTool(provider: provider, ingestionService: GeneratedMediaIngestionService(store: AppSessionAttachmentStore(paths: paths)))
        await #expect(throws: GeneratedImageAgentToolError.emptyPrompt) {
            try await tool.execute(arguments: AgentToolArguments(values: ["prompt": .string("  ")]), context: generatedImageToolContext())
        }
    }
}
