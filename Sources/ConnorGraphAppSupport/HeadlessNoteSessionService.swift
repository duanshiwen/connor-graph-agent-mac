import Foundation
import ConnorGraphAgent
import ConnorGraphCore

public enum HeadlessNoteSessionServiceError: Error, Sendable, Equatable {
    case sessionNotFound(String)
    case managerUnavailable(String)
}

public struct NoteSessionPromptPolicy: Sendable {
    public init() {}
    public func augment(_ prompt: String, kind: AgentSessionKind, hasExistingMessages: Bool) -> String {
        guard kind == .note, !hasExistingMessages else { return prompt }
        return """
        <connor-note-session>
        这是一个笔记会话。用户消息已经由 Session OS 保存，并会通过既有后台摄取链路自动进入 Memory OS L0/L1。
        请理解并处理笔记内容：提炼核心主题、关键观点、概念关系和可以继续探索的方向。
        不要为了保存这条笔记调用 Write、Edit、shell、知识库写入或 Memory 写入工具。
        </connor-note-session>

        \(prompt)
        """
    }
}

public actor HeadlessNoteSessionService: HeadlessNoteSessionRunning {
    public typealias ManagerFactory = @Sendable (AgentSession) -> NativeSessionManager?
    private let repository: AppChatSessionRepository
    private let managerFactory: ManagerFactory
    private let promptPolicy: NoteSessionPromptPolicy
    private let attachmentStore: AppSessionAttachmentStore?
    private var activeManagers: [String: NativeSessionManager] = [:]

    public init(repository: AppChatSessionRepository, managerFactory: @escaping ManagerFactory, promptPolicy: NoteSessionPromptPolicy = .init(), attachmentStore: AppSessionAttachmentStore? = nil) {
        self.repository = repository; self.managerFactory = managerFactory; self.promptPolicy = promptPolicy; self.attachmentStore = attachmentStore
    }

    public func createNoteSession(title: String, now: Date = Date()) throws -> AgentSession {
        var session = try repository.createSession(title: title, now: now)
        session.governance.kind = .note
        return try repository.saveSession(session)
    }

    public func run(_ request: HeadlessNoteSessionRunRequest) async throws -> HeadlessNoteSessionRunResult {
        guard let session = try repository.loadSession(id: request.sessionID) else { throw HeadlessNoteSessionServiceError.sessionNotFound(request.sessionID) }
        guard var manager = managerFactory(session) else { throw HeadlessNoteSessionServiceError.managerUnavailable(request.sessionID) }
        manager.permissionMode = .readOnly
        activeManagers[request.sessionID] = manager
        defer { activeManagers.removeValue(forKey: request.sessionID) }
        let augmented = promptPolicy.augment(request.prompt, kind: session.governance.kind, hasExistingMessages: !session.messages.isEmpty)
        let attachmentRefs = try request.attachmentIDs.map { id -> AgentMessageAttachmentRef in
            guard let attachmentStore else { throw HeadlessNoteSessionServiceError.managerUnavailable("Attachment store unavailable") }
            return try attachmentStore.loadManifest(sessionID: request.sessionID, attachmentID: id).messageRef
        }
        let response = try await manager.submit(augmented, sessionSummary: nil, displayPrompt: request.displayPrompt ?? request.prompt, attachments: attachmentRefs)
        let runID = response.events.compactMap { event -> String? in
            if case .runStarted(let payload) = event { return payload.run.id }
            return nil
        }.first
        return HeadlessNoteSessionRunResult(sessionID: request.sessionID, runID: runID, responseText: response.assistantMessage?.content)
    }

    public func cancel(sessionID: String) async {
        guard var manager = activeManagers[sessionID], let runID = manager.runtimeState.activeRunID else { return }
        manager.cancel(runID: runID, reason: "Note import cancelled")
        activeManagers[sessionID] = manager
    }
}
