import Foundation

public struct AgentPromptBudgetEstimate: Sendable, Equatable {
    public var characterCount: Int
    public var estimatedTokenCount: Int

    public init(characterCount: Int, estimatedTokenCount: Int) {
        self.characterCount = characterCount
        self.estimatedTokenCount = estimatedTokenCount
    }
}

public struct AgentPromptBudgetEstimator: Sendable, Equatable {
    public init() {}

    public func estimate(_ text: String) -> AgentPromptBudgetEstimate {
        let characterCount = text.count
        let estimatedTokenCount = characterCount == 0 ? 0 : Int(ceil(Double(characterCount) / 4.0))
        return AgentPromptBudgetEstimate(
            characterCount: characterCount,
            estimatedTokenCount: estimatedTokenCount
        )
    }
}
