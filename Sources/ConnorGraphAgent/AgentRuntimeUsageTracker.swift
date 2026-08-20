import Foundation

public actor AgentRuntimeUsageTracker: Sendable {
    public let configuration: AgentBudgetConfiguration
    private var promptTokens: Int = 0
    private var completionTokens: Int = 0

    public init(configuration: AgentBudgetConfiguration = AgentBudgetConfiguration()) {
        self.configuration = configuration
    }

    public func record(_ usage: AgentModelUsage?) -> AgentBudgetSnapshot {
        if let usage {
            promptTokens += usage.promptTokens
            completionTokens += usage.completionTokens
        }
        return snapshot()
    }

    public func snapshot() -> AgentBudgetSnapshot {
        let total = promptTokens + completionTokens
        let warning = Int(Double(configuration.maxTotalTokens) * configuration.warningThresholdRatio)
        let status: AgentBudgetStatus
        if total > configuration.maxTotalTokens {
            status = .exceeded
        } else if total >= warning {
            status = .warning
        } else {
            status = .ok
        }
        return AgentBudgetSnapshot(
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: total,
            status: status,
            warningThresholdTokens: warning,
            maxTotalTokens: configuration.maxTotalTokens
        )
    }
}
