import Foundation

public struct AnyAgentBackend: AgentBackend {
    private let chatHandler: @Sendable (AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error>
    private let abortHandler: @Sendable (String) -> Void
    private let resolveApprovalHandler: @Sendable (AgentPendingApproval, AgentPendingApprovalStatus, String, String) async throws -> Void

    public init<Backend: AgentBackend>(_ backend: Backend) {
        self.chatHandler = { request in backend.chat(request) }
        self.abortHandler = { runID in backend.abort(runID: runID) }
        self.resolveApprovalHandler = { approval, status, reason, actor in
            try await backend.resolveApproval(approval, status: status, reason: reason, actor: actor)
        }
    }

    public init(
        chat: @escaping @Sendable (AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error>,
        abort: @escaping @Sendable (String) -> Void = { _ in },
        resolveApproval: @escaping @Sendable (AgentPendingApproval, AgentPendingApprovalStatus, String, String) async throws -> Void = { _, _, _, _ in }
    ) {
        self.chatHandler = chat
        self.abortHandler = abort
        self.resolveApprovalHandler = resolveApproval
    }

    public func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        chatHandler(request)
    }

    public func abort(runID: String) {
        abortHandler(runID)
    }

    public func resolveApproval(_ approval: AgentPendingApproval, status: AgentPendingApprovalStatus, reason: String, actor: String = "human-reviewer") async throws {
        try await resolveApprovalHandler(approval, status, reason, actor)
    }
}
