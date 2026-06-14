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
