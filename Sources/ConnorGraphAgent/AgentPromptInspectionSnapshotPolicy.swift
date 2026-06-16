import Foundation
import ConnorGraphCore

public struct AgentPromptInspectionSnapshotPolicy: Sendable, Equatable {
    public var includeRenderedPrompt: Bool
    public var maxRenderedPromptCharacters: Int

    public init(
        includeRenderedPrompt: Bool = false,
        maxRenderedPromptCharacters: Int = 4_000
    ) {
        self.includeRenderedPrompt = includeRenderedPrompt
        self.maxRenderedPromptCharacters = max(0, maxRenderedPromptCharacters)
    }

    public func snapshot(for inspection: AgentChatPromptInspection) -> AgentPromptInspectionSnapshot {
        AgentPromptInspectionSnapshot(
            includesSummary: inspection.includesSummary,
            recentMessageCount: inspection.recentMessageCount,
            currentRequest: inspection.currentRequest,
            renderedPrompt: renderedPromptSnapshot(from: inspection.renderedPrompt),
            renderedPromptCharacterCount: inspection.renderedPromptCharacterCount,
            estimatedPromptTokenCount: inspection.estimatedPromptTokenCount,
            promptBudgetStatus: inspection.promptBudgetStatus
        )
    }

    private func renderedPromptSnapshot(from renderedPrompt: String) -> String? {
        guard includeRenderedPrompt else { return nil }
        let redactedPrompt = Self.redacted(renderedPrompt)
        guard redactedPrompt.count > maxRenderedPromptCharacters else { return redactedPrompt }
        let prefix = String(redactedPrompt.prefix(maxRenderedPromptCharacters))
        return "\(prefix)… [truncated]"
    }

    private static func redacted(_ text: String) -> String {
        var redacted = text
        redacted = redacted.replacingOccurrences(
            of: #"Bearer\s+[^\s]+"#,
            with: "Bearer [REDACTED]",
            options: .regularExpression
        )
        redacted = redacted.replacingOccurrences(
            of: #"(?i)(api[_-]?key\s*=\s*)[^\s&]+"#,
            with: "$1[REDACTED]",
            options: .regularExpression
        )
        redacted = redacted.replacingOccurrences(
            of: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            with: "[REDACTED_EMAIL]",
            options: [.regularExpression, .caseInsensitive]
        )
        return redacted
    }
}
