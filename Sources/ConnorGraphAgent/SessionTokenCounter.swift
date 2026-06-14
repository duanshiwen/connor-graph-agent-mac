import Foundation

// MARK: - Session Token Counter

/// Estimates cumulative token count across all messages in a session.
///
/// Unlike `AgentPromptBudgetEstimator` (which estimates a single
/// rendered prompt), `SessionTokenCounter` sums the token footprint
/// of **every message** in the conversation history.  This gives the
/// compression pipeline an accurate picture of how much context the
/// model is actually carrying.
public struct SessionTokenCounter: Sendable {
    public struct Estimate: Sendable, Equatable {
        public let totalTokenCount: Int
        public let messageCount: Int
        public let lastMessageTokenCount: Int
    }

    private let estimator: AgentPromptBudgetEstimator

    public init(estimator: AgentPromptBudgetEstimator = .init()) {
        self.estimator = estimator
    }

    /// Estimate cumulative tokens for a list of messages.
    public func estimate(messages: [AgentMessage]) -> Estimate {
        var total = 0
        for message in messages {
            total += estimator.estimate(message.content).estimatedTokenCount
        }
        return Estimate(
            totalTokenCount: total,
            messageCount: messages.count,
            lastMessageTokenCount: messages.last.map { estimator.estimate($0.content).estimatedTokenCount } ?? 0
        )
    }
}
