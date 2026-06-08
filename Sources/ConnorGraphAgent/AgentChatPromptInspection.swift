import ConnorGraphCore

public struct AgentChatPromptInspection: Sendable, Equatable {
    public var includesSummary: Bool
    public var recentMessageCount: Int
    public var currentRequest: String
    public var renderedPrompt: String

    public init(
        includesSummary: Bool,
        recentMessageCount: Int,
        currentRequest: String,
        renderedPrompt: String
    ) {
        self.includesSummary = includesSummary
        self.recentMessageCount = recentMessageCount
        self.currentRequest = currentRequest
        self.renderedPrompt = renderedPrompt
    }
}

public extension AgentPromptInspectionSnapshot {
    init(_ inspection: AgentChatPromptInspection, includeRenderedPrompt: Bool = true) {
        self.init(
            includesSummary: inspection.includesSummary,
            recentMessageCount: inspection.recentMessageCount,
            currentRequest: inspection.currentRequest,
            renderedPrompt: includeRenderedPrompt ? inspection.renderedPrompt : nil
        )
    }
}
