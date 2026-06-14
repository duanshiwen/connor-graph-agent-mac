import Foundation
import ConnorGraphAgent
import ConnorGraphAppSupport

struct AppChatSummaryPresentation {
    var freshness: AgentSessionSummaryFreshness?
    var contextMessage: String
    var refreshState: AgentSessionSummaryRefreshState
}

struct AppChatSummaryPresentationBuilder {
    func build(
        latestSummary: AgentSessionSummary?,
        activeSession: AgentSession,
        isSummarizing: Bool,
        hasTranscriptMessages: Bool
    ) -> AppChatSummaryPresentation {
        let freshness = latestSummary?.freshness(for: activeSession)
        let contextMessage: String
        if let freshness {
            if freshness.isFresh {
                contextMessage = "会话摘要已是最新，将包含在下一次回答中。"
            } else {
                contextMessage = "会话摘要已过期：还有 \(freshness.uncoveredMessageCount) 条消息未覆盖，因此不会包含在下一次回答中。"
            }
        } else {
            contextMessage = ""
        }
        let refreshState = AgentSessionSummaryRefreshState(
            isSummarizing: isSummarizing,
            hasTranscriptMessages: hasTranscriptMessages,
            freshness: freshness
        )
        return AppChatSummaryPresentation(
            freshness: freshness,
            contextMessage: contextMessage,
            refreshState: refreshState
        )
    }
}
