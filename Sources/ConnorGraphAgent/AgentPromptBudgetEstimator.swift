import Foundation
import ConnorGraphCore

public struct AgentPromptBudgetEstimate: Sendable, Equatable {
    public var characterCount: Int
    public var estimatedTokenCount: Int

    public init(characterCount: Int, estimatedTokenCount: Int) {
        self.characterCount = characterCount
        self.estimatedTokenCount = estimatedTokenCount
    }
}

public struct AgentPromptBudgetEstimator: Sendable, Equatable {
    public var tokenEstimator: AgentTextTokenEstimator

    public init(tokenEstimator: AgentTextTokenEstimator = AgentTextTokenEstimator()) {
        self.tokenEstimator = tokenEstimator
    }

    public func estimate(_ text: String) -> AgentPromptBudgetEstimate {
        let characterCount = text.count
        let estimatedTokenCount = tokenEstimator.estimateTokenCount(text)
        return AgentPromptBudgetEstimate(
            characterCount: characterCount,
            estimatedTokenCount: estimatedTokenCount
        )
    }

    public func status(estimatedTokenCount: Int) -> AgentPromptBudgetStatus {
        if estimatedTokenCount >= 160_000 { return .over }
        if estimatedTokenCount >= 120_000 { return .warning }
        return .safe
    }
}
