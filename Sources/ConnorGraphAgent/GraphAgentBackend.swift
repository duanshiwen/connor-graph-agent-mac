import Foundation
import ConnorGraphCore

public struct AgentChatRequest: Sendable, Equatable {
    public var runID: String
    public var sessionID: String
    public var groupID: String
    public var userMessage: String
    public var sessionSummary: AgentSessionSummary?
    public var recentMessages: [AgentMessage]
    public var permissionMode: AgentPermissionMode
    public var attachmentRefs: [AgentMessageAttachmentRef]
    public var attachmentContextPlan: AttachmentContextPlan
    /// Compression anchor state from prior rounds.
    public var anchorState: SessionAnchorState?

    public init(
        runID: String = UUID().uuidString,
        sessionID: String,
        groupID: String = "default",
        userMessage: String,
        sessionSummary: AgentSessionSummary? = nil,
        recentMessages: [AgentMessage] = [],
        permissionMode: AgentPermissionMode = .askToWrite,
        attachmentRefs: [AgentMessageAttachmentRef] = [],
        attachmentContextPlan: AttachmentContextPlan = AttachmentContextPlan(),
        anchorState: SessionAnchorState? = nil
    ) {
        self.runID = runID
        self.sessionID = sessionID
        self.groupID = groupID
        self.userMessage = userMessage
        self.sessionSummary = sessionSummary
        self.recentMessages = recentMessages
        self.permissionMode = permissionMode
        self.attachmentRefs = attachmentRefs
        self.attachmentContextPlan = attachmentContextPlan
        self.anchorState = anchorState
    }

    public var normalizedPrompt: String {
        AgentChatPromptContext(
            userPrompt: userMessage,
            sessionSummary: sessionSummary,
            recentMessages: recentMessages,
            anchorState: anchorState
        ).renderedPrompt
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

    public func abort(runID: String) {
        loopController.abort(runID: runID)
    }

    public func resolveApproval(_ approval: AgentPendingApproval, status: AgentPendingApprovalStatus, reason _: String, actor _: String) async throws {
        await loopController.resolveApproval(approval, status: status)
    }
}
