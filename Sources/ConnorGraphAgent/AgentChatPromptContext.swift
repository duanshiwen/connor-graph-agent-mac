import Foundation
import ConnorGraphCore

public struct AgentChatPromptContext: Sendable, Equatable {
    public var userPrompt: String
    public var sessionSummary: AgentSessionSummary?
    public var recentMessages: [AgentMessage]

    public init(
        userPrompt: String,
        sessionSummary: AgentSessionSummary? = nil,
        recentMessages: [AgentMessage] = []
    ) {
        self.userPrompt = userPrompt
        self.sessionSummary = sessionSummary
        self.recentMessages = recentMessages
    }

    public var renderedPrompt: String {
        let summaryContent = trimmedSummaryContent
        let shouldRenderSummary = !summaryContent.isEmpty
        let shouldRenderRecentMessages = !recentMessages.isEmpty

        guard shouldRenderSummary || shouldRenderRecentMessages else {
            return userPrompt
        }

        var blocks: [String] = []
        if shouldRenderSummary {
            blocks.append("""
            Previous session summary:
            \(summaryContent)
            """)
        }
        if shouldRenderRecentMessages {
            let renderedMessages = recentMessages.map(Self.render).joined(separator: "\n")
            blocks.append("""
            Recent conversation:
            \(renderedMessages)
            """)
        }
        blocks.append("""
        Current user request:
        \(userPrompt)
        """)
        return blocks.joined(separator: "\n\n")
    }

    public var inspection: AgentChatPromptInspection {
        AgentChatPromptInspection(
            includesSummary: !trimmedSummaryContent.isEmpty,
            recentMessageCount: recentMessages.count,
            currentRequest: userPrompt,
            renderedPrompt: renderedPrompt
        )
    }

    private var trimmedSummaryContent: String {
        sessionSummary?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
