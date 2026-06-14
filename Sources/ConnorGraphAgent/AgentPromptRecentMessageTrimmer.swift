import Foundation
import ConnorGraphCore

public struct AgentPromptRecentMessageTrimmer: Sendable, Equatable {
    public var maxConversationTokens: Int
    public var estimator: AgentPromptBudgetEstimator

    public init(
        maxConversationTokens: Int,
        estimator: AgentPromptBudgetEstimator = AgentPromptBudgetEstimator()
    ) {
        self.maxConversationTokens = max(0, maxConversationTokens)
        self.estimator = estimator
    }

    public func trim(_ messages: [AgentMessage]) -> [AgentMessage] {
        guard maxConversationTokens > 0, !messages.isEmpty else { return [] }
        var keptReversed: [AgentMessage] = []
        var usedTokens = 0

        for message in messages.reversed() {
            let messageTokens = estimator.estimate(message.content).estimatedTokenCount
            if keptReversed.isEmpty {
                if messageTokens <= maxConversationTokens {
                    keptReversed.append(message)
                    usedTokens += messageTokens
                }
                continue
            }
            guard usedTokens + messageTokens <= maxConversationTokens else { break }
            keptReversed.append(message)
            usedTokens += messageTokens
        }

        return keptReversed.reversed()
    }
}
