import Foundation
import ConnorGraphCore

public struct AgentChatRequest: Sendable, Equatable {
    public var runID: String
    public var sessionID: String
    public var groupID: String
    public var userMessage: String
    public var sessionSummary: AgentSessionSummary?
    public var permissionMode: AgentPermissionMode

    public init(
        runID: String = UUID().uuidString,
        sessionID: String,
        groupID: String = "default",
        userMessage: String,
        sessionSummary: AgentSessionSummary? = nil,
        permissionMode: AgentPermissionMode = .askToWrite
    ) {
        self.runID = runID
        self.sessionID = sessionID
        self.groupID = groupID
        self.userMessage = userMessage
        self.sessionSummary = sessionSummary
        self.permissionMode = permissionMode
    }
}

public protocol AgentBackend: Sendable {
    func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error>
    func abort(runID: String)
    func resolveApproval(_ approval: AgentPendingApproval, status: AgentPendingApprovalStatus, reason: String, actor: String) async throws
}

public extension AgentBackend {
    func abort(runID: String) {}
    func resolveApproval(_ approval: AgentPendingApproval, status: AgentPendingApprovalStatus, reason: String, actor: String = "human-reviewer") async throws {}
}

public typealias GraphAgentBackend = AgentBackend

public struct AgentLoopBackend<Provider: AgentModelProvider>: AgentBackend {
    public var loopController: AgentLoopController<Provider>

    public init(loopController: AgentLoopController<Provider>) {
        self.loopController = loopController
    }

    public func chat(_ request: AgentChatRequest) -> AsyncThrowingStream<AgentEvent, Error> {
        loopController.run(request)
    }
}
