import Foundation

public enum AgentModelContextOverflowKind: Sendable, Equatable {
    case currentInput
    case conversation
    case currentRunToolTrace
}

public struct AgentModelContextLimitError: Error, Sendable, Equatable, CustomStringConvertible {
    public var kind: AgentModelContextOverflowKind
    public var estimatedInputTokens: Int
    public var maximumInputTokens: Int

    public init(kind: AgentModelContextOverflowKind, estimatedInputTokens: Int, maximumInputTokens: Int) {
        self.kind = kind
        self.estimatedInputTokens = estimatedInputTokens
        self.maximumInputTokens = maximumInputTokens
    }

    public var description: String {
        switch kind {
        case .currentInput:
            "当前输入本身超过模型上下文限制（预计 \(estimatedInputTokens) tokens，可用 \(maximumInputTokens)）。请把内容拆分成多条消息后重试。"
        case .conversation:
            "滚动摘要、最近对话和当前请求仍超过模型上下文限制（预计 \(estimatedInputTokens) tokens，可用 \(maximumInputTokens)）。请新建一个对话后继续。"
        case .currentRunToolTrace:
            "本轮工具调用结果已超过模型上下文限制（预计 \(estimatedInputTokens) tokens，可用 \(maximumInputTokens)）。本轮已停止，跨轮摘要未被修改；请缩小任务范围后重试。"
        }
    }
}

public struct AgentVisionTokenEstimator: Sendable, Equatable {
    public var conservativeTokensPerImage: Int

    public init(conservativeTokensPerImage: Int = 8_192) {
        self.conservativeTokensPerImage = max(1, conservativeTokensPerImage)
    }

    public func estimateImageTokenCount(dataURL: String) -> Int {
        dataURL.isEmpty ? 0 : conservativeTokensPerImage
    }
}

public struct AgentModelContextGuard: Sendable {
    public var estimator: AgentPromptBudgetEstimator
    public var visionEstimator: AgentVisionTokenEstimator

    public init(
        estimator: AgentPromptBudgetEstimator = .init(),
        visionEstimator: AgentVisionTokenEstimator = .init()
    ) {
        self.estimator = estimator
        self.visionEstimator = visionEstimator
    }

    public func maximumInputTokens(
        contextWindowTokens: Int,
        configuredPromptLimit: Int,
        reservedOutputTokens: Int
    ) -> Int {
        max(1, min(configuredPromptLimit, contextWindowTokens - max(1, reservedOutputTokens)))
    }

    public func estimatedInputTokens(_ request: AgentModelRequest) -> Int {
        let messageTokens = request.messages.reduce(0) { partial, message in
            var total = partial + estimator.estimate(message.content).estimatedTokenCount
            for part in message.contentParts ?? [] where part.kind == .imageDataURL {
                total += visionEstimator.estimateImageTokenCount(dataURL: part.dataURL ?? "")
            }
            if let toolCalls = message.toolCalls {
                total += toolCalls.reduce(0) {
                    $0 + estimator.estimate($1.name + $1.argumentsJSON).estimatedTokenCount
                }
            }
            return total
        }
        let toolTokens = request.tools.reduce(0) { partial, tool in
            let schemaData = try? JSONSerialization.data(withJSONObject: tool.inputSchema.jsonObject, options: [.sortedKeys])
            let schema = schemaData.map { String(decoding: $0, as: UTF8.self) } ?? ""
            return partial + estimator.estimate(tool.name + tool.description + schema).estimatedTokenCount
        }
        return messageTokens + toolTokens
    }

    public func validate(
        _ request: AgentModelRequest,
        currentUserInput: String,
        currentAttachmentEstimatedTokens: Int,
        contextWindowTokens: Int,
        configuredPromptLimit: Int,
        reservedOutputTokens: Int,
        isAfterToolExecution: Bool
    ) throws {
        let limit = maximumInputTokens(
            contextWindowTokens: contextWindowTokens,
            configuredPromptLimit: configuredPromptLimit,
            reservedOutputTokens: reservedOutputTokens
        )
        let estimated = estimatedInputTokens(request)
        guard estimated > limit else { return }
        let kind: AgentModelContextOverflowKind
        if isAfterToolExecution {
            kind = .currentRunToolTrace
        } else if estimator.estimate(currentUserInput).estimatedTokenCount + currentAttachmentEstimatedTokens > limit {
            kind = .currentInput
        } else {
            kind = .conversation
        }
        throw AgentModelContextLimitError(
            kind: kind,
            estimatedInputTokens: estimated,
            maximumInputTokens: limit
        )
    }
}
