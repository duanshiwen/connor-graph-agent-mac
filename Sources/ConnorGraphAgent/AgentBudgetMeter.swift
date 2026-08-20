import Foundation

public enum AgentBudgetStatus: String, Codable, Sendable, Equatable {
    case ok
    case warning
    case exceeded
}

public struct AgentBudgetConfiguration: Codable, Sendable, Equatable {
    public var maxTotalTokens: Int
    public var warningThresholdRatio: Double
    public var maxEstimatedCostCents: Double?

    public init(maxTotalTokens: Int = 120_000, warningThresholdRatio: Double = 0.8, maxEstimatedCostCents: Double? = nil) {
        self.maxTotalTokens = max(1, maxTotalTokens)
        self.warningThresholdRatio = min(max(0.05, warningThresholdRatio), 0.99)
        self.maxEstimatedCostCents = maxEstimatedCostCents
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            maxTotalTokens: try container.decodeIfPresent(Int.self, forKey: .maxTotalTokens) ?? 120_000,
            warningThresholdRatio: try container.decodeIfPresent(Double.self, forKey: .warningThresholdRatio) ?? 0.8,
            maxEstimatedCostCents: try container.decodeIfPresent(Double.self, forKey: .maxEstimatedCostCents)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(maxTotalTokens, forKey: .maxTotalTokens)
        try container.encode(warningThresholdRatio, forKey: .warningThresholdRatio)
        try container.encodeIfPresent(maxEstimatedCostCents, forKey: .maxEstimatedCostCents)
    }

    private enum CodingKeys: String, CodingKey {
        case maxTotalTokens
        case warningThresholdRatio
        case maxEstimatedCostCents
    }
}

public struct AgentBudgetSnapshot: Codable, Sendable, Equatable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var totalTokens: Int
    public var status: AgentBudgetStatus
    public var warningThresholdTokens: Int
    public var maxTotalTokens: Int

    public init(promptTokens: Int, completionTokens: Int, totalTokens: Int, status: AgentBudgetStatus, warningThresholdTokens: Int, maxTotalTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.status = status
        self.warningThresholdTokens = warningThresholdTokens
        self.maxTotalTokens = maxTotalTokens
    }
}

public actor AgentBudgetMeter: Sendable {
    public let configuration: AgentBudgetConfiguration
    private var promptTokens = 0
    private var completionTokens = 0

    public init(configuration: AgentBudgetConfiguration = AgentBudgetConfiguration()) {
        self.configuration = configuration
    }

    public func record(_ usage: AgentModelUsage?) -> AgentBudgetSnapshot {
        guard let usage else { return snapshot() }
        promptTokens += usage.promptTokens
        completionTokens += usage.completionTokens
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
