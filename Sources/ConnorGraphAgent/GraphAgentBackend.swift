import Foundation
import ConnorGraphCore

public struct AgentChatRequest: Sendable, Equatable {
    public var runID: String
    public var sessionID: String
    public var groupID: String
    public var userMessage: String
    public var currentUserMessageID: String?
    public var sessionSummary: AgentSessionSummary?
    public var recentMessages: [AgentMessage]
    public var permissionMode: AgentPermissionMode
    public var attachmentRefs: [AgentMessageAttachmentRef]
    public var attachmentContextPlan: AttachmentContextPlan
    /// Compression anchor state from prior rounds.
    public var anchorState: SessionAnchorState?
    /// Skill instructions to inject into the system prompt for this turn.
    public var skillInstructions: String?
    /// Active skill metadata for auditing/presentation. The actual instructions remain in `skillInstructions`.
    public var activeSkillSlug: String?
    public var activeSkillDisplayName: String?
    /// Structured people explicitly selected in Composer for this turn.
    public var personReferences: [PersonReference]

    public init(
        runID: String = UUID().uuidString,
        sessionID: String,
        groupID: String = "default",
        userMessage: String,
        currentUserMessageID: String? = nil,
        sessionSummary: AgentSessionSummary? = nil,
        recentMessages: [AgentMessage] = [],
        permissionMode: AgentPermissionMode = .askToWrite,
        attachmentRefs: [AgentMessageAttachmentRef] = [],
        attachmentContextPlan: AttachmentContextPlan = AttachmentContextPlan(),
        anchorState: SessionAnchorState? = nil,
        skillInstructions: String? = nil,
        activeSkillSlug: String? = nil,
        activeSkillDisplayName: String? = nil
    ) {
        self.init(
            runID: runID,
            sessionID: sessionID,
            groupID: groupID,
            userMessage: userMessage,
            currentUserMessageID: currentUserMessageID,
            sessionSummary: sessionSummary,
            recentMessages: recentMessages,
            permissionMode: permissionMode,
            attachmentRefs: attachmentRefs,
            attachmentContextPlan: attachmentContextPlan,
            anchorState: anchorState,
            skillInstructions: skillInstructions,
            activeSkillSlug: activeSkillSlug,
            activeSkillDisplayName: activeSkillDisplayName,
            personReferences: []
        )
    }

    public init(
        runID: String = UUID().uuidString,
        sessionID: String,
        groupID: String = "default",
        userMessage: String,
        currentUserMessageID: String? = nil,
        sessionSummary: AgentSessionSummary? = nil,
        recentMessages: [AgentMessage] = [],
        permissionMode: AgentPermissionMode = .askToWrite,
        attachmentRefs: [AgentMessageAttachmentRef] = [],
        attachmentContextPlan: AttachmentContextPlan = AttachmentContextPlan(),
        anchorState: SessionAnchorState? = nil,
        skillInstructions: String? = nil,
        activeSkillSlug: String? = nil,
        activeSkillDisplayName: String? = nil,
        personReferences: [PersonReference]
    ) {
        self.runID = runID
        self.sessionID = sessionID
        self.groupID = groupID
        self.userMessage = userMessage
        self.currentUserMessageID = currentUserMessageID
        self.sessionSummary = sessionSummary
        self.recentMessages = recentMessages
        self.permissionMode = permissionMode
        self.attachmentRefs = attachmentRefs
        self.attachmentContextPlan = attachmentContextPlan
        self.anchorState = anchorState
        self.skillInstructions = skillInstructions
        self.activeSkillSlug = activeSkillSlug
        self.activeSkillDisplayName = activeSkillDisplayName
        self.personReferences = personReferences
    }

    public var normalizedPrompt: String {
        let personContext = AgentPersonContextSection(references: personReferences)?.renderedText
        let currentUserMessage = [personContext, userMessage]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let basePrompt = AgentChatPromptContext(
            userPrompt: currentUserMessage,
            sessionSummary: sessionSummary,
            recentMessages: recentMessages,
            anchorState: anchorState
        ).renderedPrompt
        guard let skillInstructions = skillInstructions?.trimmingCharacters(in: .whitespacesAndNewlines), !skillInstructions.isEmpty else {
            return basePrompt
        }
        return [
            basePrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            "<connor-active-selected-skill>\n\(skillInstructions)\n</connor-active-selected-skill>"
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
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
