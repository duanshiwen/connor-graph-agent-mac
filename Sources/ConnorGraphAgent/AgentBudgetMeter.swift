import Foundation

public enum AgentBudgetStatus: String, Codable, Sendable, Equatable {
    case ok
    case warning
    case exceeded
    /// 超过硬上限：不再继续工具循环，强制收敛到最终答案（见 AgentLoopController 的 hard-stop 逻辑）。
    case hardExceeded
}

public struct AgentBudgetConfiguration: Codable, Sendable, Equatable {
    public var maxTotalTokens: Int
    public var warningThresholdRatio: Double
    /// 硬上限 = maxTotalTokens × hardLimitRatio。达到硬上限后运行必须收敛（软预算只告警、不终止）。
    public var hardLimitRatio: Double
    public var maxEstimatedCostCents: Double?

    public init(maxTotalTokens: Int = 120_000, warningThresholdRatio: Double = 0.8, hardLimitRatio: Double = 1.25, maxEstimatedCostCents: Double? = nil) {
        self.maxTotalTokens = max(1, maxTotalTokens)
        self.warningThresholdRatio = min(max(0.05, warningThresholdRatio), 0.99)
        self.hardLimitRatio = min(max(1.0, hardLimitRatio), 10.0)
        self.maxEstimatedCostCents = maxEstimatedCostCents
    }

    public var hardThresholdTokens: Int {
        Int(Double(maxTotalTokens) * hardLimitRatio)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            maxTotalTokens: try container.decodeIfPresent(Int.self, forKey: .maxTotalTokens) ?? 120_000,
            warningThresholdRatio: try container.decodeIfPresent(Double.self, forKey: .warningThresholdRatio) ?? 0.8,
            hardLimitRatio: try container.decodeIfPresent(Double.self, forKey: .hardLimitRatio) ?? 1.25,
            maxEstimatedCostCents: try container.decodeIfPresent(Double.self, forKey: .maxEstimatedCostCents)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(maxTotalTokens, forKey: .maxTotalTokens)
        try container.encode(warningThresholdRatio, forKey: .warningThresholdRatio)
        try container.encode(hardLimitRatio, forKey: .hardLimitRatio)
        try container.encodeIfPresent(maxEstimatedCostCents, forKey: .maxEstimatedCostCents)
    }

    private enum CodingKeys: String, CodingKey {
        case maxTotalTokens
        case warningThresholdRatio
        case hardLimitRatio
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
    public var hardThresholdTokens: Int

    public init(promptTokens: Int, completionTokens: Int, totalTokens: Int, status: AgentBudgetStatus, warningThresholdTokens: Int, maxTotalTokens: Int, hardThresholdTokens: Int) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.status = status
        self.warningThresholdTokens = warningThresholdTokens
        self.maxTotalTokens = maxTotalTokens
        self.hardThresholdTokens = hardThresholdTokens
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
        let hardThreshold = configuration.hardThresholdTokens
        let status: AgentBudgetStatus
        if total > hardThreshold {
            status = .hardExceeded
        } else if total > configuration.maxTotalTokens {
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
            maxTotalTokens: configuration.maxTotalTokens,
            hardThresholdTokens: hardThreshold
        )
    }
}
