import ConnorGraphCore

public struct AgentChatPromptInspection: Sendable, Equatable {
    public var includesSummary: Bool
    public var recentMessageCount: Int
    public var currentRequest: String
    public var renderedPrompt: String
    public var renderedPromptCharacterCount: Int
    public var estimatedPromptTokenCount: Int

    public init(
        includesSummary: Bool,
        recentMessageCount: Int,
        currentRequest: String,
        renderedPrompt: String
    ) {
        let estimate = AgentPromptBudgetEstimator().estimate(renderedPrompt)
        self.init(
            includesSummary: includesSummary,
            recentMessageCount: recentMessageCount,
            currentRequest: currentRequest,
            renderedPrompt: renderedPrompt,
            renderedPromptCharacterCount: estimate.characterCount,
            estimatedPromptTokenCount: estimate.estimatedTokenCount
        )
    }

    public init(
        includesSummary: Bool,
        recentMessageCount: Int,
        currentRequest: String,
        renderedPrompt: String,
        renderedPromptCharacterCount: Int,
        estimatedPromptTokenCount: Int
    ) {
        self.includesSummary = includesSummary
        self.recentMessageCount = recentMessageCount
        self.currentRequest = currentRequest
        self.renderedPrompt = renderedPrompt
        self.renderedPromptCharacterCount = renderedPromptCharacterCount
        self.estimatedPromptTokenCount = estimatedPromptTokenCount
    }
}

public extension AgentPromptInspectionSnapshot {
    init(_ inspection: AgentChatPromptInspection, includeRenderedPrompt: Bool = true) {
        self.init(
            includesSummary: inspection.includesSummary,
            recentMessageCount: inspection.recentMessageCount,
            currentRequest: inspection.currentRequest,
            renderedPrompt: includeRenderedPrompt ? inspection.renderedPrompt : nil,
            renderedPromptCharacterCount: inspection.renderedPromptCharacterCount,
            estimatedPromptTokenCount: inspection.estimatedPromptTokenCount
        )
    }
}
