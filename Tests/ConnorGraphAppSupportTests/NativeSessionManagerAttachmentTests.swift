import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

@Test func nativeSessionManagerPersistsUserMessageAttachments() async throws {
    let backend = RecordingAttachmentBackend()
    let store = try SQLiteGraphKernelStore(path: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite").path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    let session = AgentSession(id: "attachment-session", title: "New Chat")
    try repository.saveSession(session)
    var manager = NativeSessionManager(backend: backend, sessionRepository: repository, session: session)
    let ref = AgentMessageAttachmentRef(
        id: "attachment-1",
        displayName: "notes.md",
        kind: .markdown,
        byteCount: 42,
        lifecycleStatus: .ready,
        extractionStatus: .extracted,
        manifestRelativePath: "attachments/attachment-1/manifest.json",
        previewText: "Preview"
    )

    _ = try await manager.submit(
        "Use this",
        sessionSummary: Optional<AgentSessionSummary>.none,
        attachments: [ref]
    )

    #expect(manager.session.messages.first?.attachments == [ref])
    #expect(backend.requests.first?.attachmentRefs == [ref])
}

@Test func nativeSessionManagerBindsGeneratedImageToolResultsToAssistantMessage() async throws {
    let generatedRef = AgentMessageAttachmentRef(
        id: "generated-image-1",
        displayName: "generated.png",
        kind: .image,
        byteCount: 8,
        lifecycleStatus: .ready,
        extractionStatus: .pending,
        manifestRelativePath: "attachments/generated-image-1/manifest.json"
    )
    let metadata = AgentAttachmentGenerationMetadata(providerID: "openai-responses", modelID: "gpt-5.6")
    let backend = GeneratedImageAttachmentBackend(attachment: generatedRef, metadata: metadata)
    let store = try SQLiteGraphKernelStore(path: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite").path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    let session = AgentSession(id: "generated-image-session", title: "New Chat")
    try repository.saveSession(session)
    var manager = NativeSessionManager(backend: backend, sessionRepository: repository, session: session)

    _ = try await manager.submit("Generate a lake", sessionSummary: Optional<AgentSessionSummary>.none)

    let assistant = try #require(manager.session.messages.last)
    #expect(assistant.role == AgentRole.assistant)
    #expect(assistant.content == "Here is the image.")
    #expect(assistant.attachments == [generatedRef])
    let loadedSession = try repository.loadSession(id: session.id)
    let reloaded = try #require(loadedSession)
    #expect(reloaded.messages.last?.attachments == [generatedRef])
}

@Test func nativeSessionManagerRejectsSpoofedOrMismatchedGeneratedImageResults() async throws {
    let generatedRef = AgentMessageAttachmentRef(
        id: "spoofed-image",
        displayName: "spoofed.png",
        kind: .image,
        byteCount: 8,
        lifecycleStatus: .ready,
        extractionStatus: .pending,
        manifestRelativePath: "attachments/spoofed-image/manifest.json"
    )
    let backend = SpoofedGeneratedImageAttachmentBackend(attachment: generatedRef)
    let store = try SQLiteGraphKernelStore(path: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).sqlite").path)
    try store.migrate()
    let repository = AppChatSessionRepository(store: store)
    let session = AgentSession(id: "spoof-test-session", title: "New Chat")
    try repository.saveSession(session)
    var manager = NativeSessionManager(backend: backend, sessionRepository: repository, session: session)

    _ = try await manager.submit("Do not accept spoofed attachments", sessionSummary: Optional<AgentSessionSummary>.none)

    #expect(manager.session.messages.last?.attachments.isEmpty == true)
}

private struct GeneratedImageAttachmentBackend: AgentBackend {
    var attachment: AgentMessageAttachmentRef
    var metadata: AgentAttachmentGenerationMetadata

    func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let payload = GeneratedImageToolResultPayload(attachment: attachment, generationMetadata: metadata)
            let data = try! JSONEncoder().encode(payload)
            let contentJSON = String(decoding: data, as: UTF8.self)
            let result = AgentToolResult(
                runID: request.runID,
                sessionID: request.sessionID,
                toolCallID: "image-call",
                toolName: "generate_image",
                contentText: "generated",
                contentJSON: contentJSON
            )
            continuation.yield(.toolFinished(result))
            continuation.yield(.toolFinished(result))
            continuation.yield(.textComplete(AgentTextCompleteEvent(runID: request.runID, sessionID: request.sessionID, text: "Here is the image.")))
            continuation.finish()
        }
    }
}

private struct SpoofedGeneratedImageAttachmentBackend: AgentBackend {
    var attachment: AgentMessageAttachmentRef

    func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let payload = GeneratedImageToolResultPayload(
                attachment: attachment,
                generationMetadata: AgentAttachmentGenerationMetadata(providerID: "fake", modelID: "fake")
            )
            let contentJSON = String(decoding: try! JSONEncoder().encode(payload), as: UTF8.self)
            continuation.yield(.toolFinished(AgentToolResult(
                runID: "wrong-run",
                sessionID: request.sessionID,
                toolCallID: "wrong-run-call",
                toolName: "generate_image",
                contentText: "generated",
                contentJSON: contentJSON
            )))
            continuation.yield(.toolFinished(AgentToolResult(
                runID: request.runID,
                sessionID: request.sessionID,
                toolCallID: "wrong-tool-call",
                toolName: "read_file",
                contentText: "generated",
                contentJSON: contentJSON
            )))
            continuation.yield(.toolFinished(AgentToolResult(
                runID: request.runID,
                sessionID: request.sessionID,
                toolCallID: "invalid-json-call",
                toolName: "generate_image",
                contentText: "generated",
                contentJSON: "not-json"
            )))
            continuation.yield(.textComplete(AgentTextCompleteEvent(runID: request.runID, sessionID: request.sessionID, text: "No attachment.")))
            continuation.finish()
        }
    }
}

private final class RecordingAttachmentBackend: AgentBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [AgentChatRequest] = []

    var requests: [AgentChatRequest] {
        lock.withLock { _requests }
    }

    func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        lock.withLock { _requests.append(request) }
        return AsyncThrowingStream { continuation in
            continuation.yield(.textComplete(AgentTextCompleteEvent(
                runID: request.runID,
                sessionID: request.sessionID,
                text: "ok"
            )))
            continuation.finish()
        }
    }
}
