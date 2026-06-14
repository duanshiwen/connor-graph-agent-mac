import Foundation
import ConnorGraphCore

public struct AgentChatPromptContext: Sendable, Equatable {
    public var userPrompt: String
    public var sessionSummary: AgentSessionSummary?
    public var recentMessages: [AgentMessage]
    /// Compression anchor state — takes priority over `sessionSummary`
    /// when both are present.
    public var anchorState: SessionAnchorState?

    public init(
        userPrompt: String,
        sessionSummary: AgentSessionSummary? = nil,
        recentMessages: [AgentMessage] = [],
        anchorState: SessionAnchorState? = nil
    ) {
        self.userPrompt = userPrompt
        self.sessionSummary = sessionSummary
        self.recentMessages = recentMessages
        self.anchorState = anchorState
    }

    public var renderedPrompt: String {
        var blocks: [String] = []

        // Anchor state takes priority over session summary
        if let anchor = anchorState, anchor.compressionCycles > 0 {
            blocks.append(renderAnchorState(anchor))
        } else if !trimmedSummaryContent.isEmpty {
            blocks.append("""
            Previous session summary:
            \(trimmedSummaryContent)
            """)
        }

        if !recentMessages.isEmpty {
            let renderedMessages = recentMessages.map(Self.render).joined(separator: "\n")
            blocks.append("""
            Recent conversation:
            \(renderedMessages)
            """)
        }

        // Only add the "Current user request" prefix if there's context to prepend
        if !blocks.isEmpty {
            blocks.append("""
            Current user request:
            \(userPrompt)
            """)
            return blocks.joined(separator: "\n\n")
        }
        
        return userPrompt
    }

    public var inspection: AgentChatPromptInspection {
        let renderedPrompt = renderedPrompt
        let estimator = AgentPromptBudgetEstimator()
        let estimate = estimator.estimate(renderedPrompt)
        return AgentChatPromptInspection(
            includesSummary: !trimmedSummaryContent.isEmpty || anchorState != nil,
            recentMessageCount: recentMessages.count,
            currentRequest: userPrompt,
            renderedPrompt: renderedPrompt,
            renderedPromptCharacterCount: estimate.characterCount,
            estimatedPromptTokenCount: estimate.estimatedTokenCount,
            promptBudgetStatus: estimator.status(estimatedTokenCount: estimate.estimatedTokenCount)
        )
    }

    /// Whether this context was built from a compression anchor.
    public var isCompressed: Bool {
        (anchorState?.compressionCycles ?? 0) > 0
    }

    // MARK: - Private

    private var trimmedSummaryContent: String {
        sessionSummary?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func renderAnchorState(_ anchor: SessionAnchorState) -> String {
        var lines: [String] = [
            "Session context (compressed from \(anchor.compressionCycles) prior rounds):",
            "- Intent: \(anchor.intent)",
        ]
        if !anchor.decisions.isEmpty {
            lines.append("- Key decisions: \(anchor.decisions.joined(separator: "; "))")
        }
        if !anchor.changes.isEmpty {
            lines.append("- Changes made: \(anchor.changes.joined(separator: "; "))")
        }
        if !anchor.pendingWork.isEmpty {
            lines.append("- Pending work: \(anchor.pendingWork.joined(separator: "; "))")
        }
        if !anchor.preservedDetails.isEmpty {
            lines.append("- Important details: \(anchor.preservedDetails)")
        }
        return lines.joined(separator: "\n")
    }

    private static func render(message: AgentMessage) -> String {
        switch message.role {
        case .user:
            return "User: \(message.content)"
        case .assistant:
            return "Assistant: \(message.content)"
        case .system:
            return "System: \(message.content)"
        }
    }
}
