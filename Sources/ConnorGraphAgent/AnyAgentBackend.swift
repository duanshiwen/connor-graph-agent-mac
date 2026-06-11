import Foundation

public struct AnyAgentBackend: AgentBackend {
    private let chatHandler: @Sendable (AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error>
    private let abortHandler: @Sendable (String) -> Void

    public init<Backend: AgentBackend>(_ backend: Backend) {
        self.chatHandler = { request in backend.chat(request) }
        self.abortHandler = { runID in backend.abort(runID: runID) }
    }

    public init(
        chat: @escaping @Sendable (AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error>,
        abort: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.chatHandler = chat
        self.abortHandler = abort
    }

    public func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        chatHandler(request)
    }

    public func abort(runID: String) {
        abortHandler(runID)
    }
}
