import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphStore
@testable import ConnorGraphAppSupport

private actor GeneratedImageChatScriptedProvider: AgentModelProvider {
    let modelID = "gpt-5.6"
    let capabilities = AgentModelCapabilities(
        supportsStreaming: false,
        supportsToolCalling: true,
        supportsParallelToolCalls: false,
        supportsStructuredOutput: false,
        supportsVision: true,
        generatedMediaCapabilities: [.imageGeneration]
    )
    private var requests: [AgentModelRequest] = []

    func complete(_ request: AgentModelRequest) async throws -> AgentModelResponse {
        requests.append(request)
        if requests.count == 1 {
            return AgentModelResponse(
                text: nil,
                toolCalls: [AgentToolCall(
                    id: "generate-image-call",
                    name: "generate_image",
                    argumentsJSON: #"{"prompt":"A lantern beside a quiet lake at dusk"}"#
                )],
                usage: AgentModelUsage(promptTokens: 10, completionTokens: 3),
                finishReason: .toolCalls
            )
        }
        return AgentModelResponse(
            text: "图片已生成。",
            usage: AgentModelUsage(promptTokens: 20, completionTokens: 4)
        )
    }

    func recordedRequests() -> [AgentModelRequest] { requests }
}

private actor GeneratedImageChatMediaRecorder {
    private var requests: [AgentGeneratedMediaRequest] = []
    func record(_ request: AgentGeneratedMediaRequest) { requests.append(request) }
    func recordedRequests() -> [AgentGeneratedMediaRequest] { requests }
}

@Test func generatedImageChatPipelinePersistsAndReloadsAssistantAttachment() async throws {
    let databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: databaseURL) }
    let store = try SQLiteGraphKernelStore(path: databaseURL.path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    let session = AgentSession(id: "generated-image-chat", title: "New Chat")
    try repository.saveSession(session)

    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppStoragePaths(applicationSupportDirectory: root)
    try paths.ensureDirectoryHierarchy()
    let scriptedProvider = GeneratedImageChatScriptedProvider()
    let mediaRecorder = GeneratedImageChatMediaRecorder()
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    let provider = AnyAgentModelProvider(
        modelID: scriptedProvider.modelID,
        capabilities: scriptedProvider.capabilities,
        complete: { request in try await scriptedProvider.complete(request) },
        generateMedia: { request in
            AsyncThrowingStream { continuation in
                Task {
                    await mediaRecorder.record(request)
                    let temporaryURL = root.appendingPathComponent("generated-provider-result.png")
                    do {
                        try png.write(to: temporaryURL)
                        continuation.yield(.started)
                        continuation.yield(.completed(AgentGeneratedMediaArtifact(
                            temporaryFileURL: temporaryURL,
                            mimeType: "image/png",
                            byteCount: Int64(png.count),
                            generationMetadata: AgentAttachmentGenerationMetadata(
                                providerID: "openai-responses",
                                modelID: "gpt-5.6",
                                responseID: "resp-image-1",
                                toolCallID: "hosted-image-call-1"
                            )
                        )))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    )
    var registry = AgentToolRegistry()
    registry.register(GeneratedImageAgentTool(
        provider: provider,
        ingestionService: GeneratedMediaIngestionService(store: AppSessionAttachmentStore(paths: paths))
    ))
    let loop = AgentLoopController(
        modelProvider: provider,
        toolRegistry: registry,
        configuration: AgentLoopConfiguration(permissionMode: .allowAll)
    )
    var manager = NativeSessionManager(
        backend: AgentLoopBackend(loopController: loop),
        sessionRepository: repository,
        session: session,
        permissionMode: .allowAll
    )

    let response = try await manager.submit("请生成一张黄昏湖边的图片", sessionSummary: Optional<AgentSessionSummary>.none)

    let mediaRequests = await mediaRecorder.recordedRequests()
    #expect(mediaRequests == [AgentGeneratedMediaRequest(kind: .image, prompt: "A lantern beside a quiet lake at dusk")])
    let modelRequests = await scriptedProvider.recordedRequests()
    #expect(modelRequests.count == 2)
    #expect(modelRequests[1].messages.contains { $0.role == .tool && $0.name == "generate_image" })
    #expect(response.events.contains { if case .toolFinished(let result) = $0 { return result.toolName == "generate_image" }; return false })

    let assistant = try #require(response.assistantMessage)
    #expect(assistant.content == "图片已生成。")
    let attachment = try #require(assistant.attachments.first)
    #expect(attachment.kind == .image)
    let manifest = try AppSessionAttachmentStore(paths: paths).loadManifest(sessionID: session.id, attachmentID: attachment.id)
    #expect(manifest.origin == .modelGenerated)
    #expect(manifest.generationMetadata?.modelID == "gpt-5.6")
    let storedURL = paths.sessionArtifactDirectories(sessionID: session.id).root.appendingPathComponent(manifest.storedRelativePath)
    #expect(try Data(contentsOf: storedURL) == png)

    let loadedSession = try repository.loadSession(id: session.id)
    let reloaded = try #require(loadedSession)
    #expect(reloaded.messages.last?.attachments == [attachment])
}
