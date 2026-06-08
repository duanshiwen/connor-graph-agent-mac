import ConnorGraphCore

public struct AgentSessionSummaryRefreshState: Sendable, Equatable {
    public var isSummarizing: Bool
    public var hasTranscriptMessages: Bool
    public var freshness: AgentSessionSummaryFreshness?

    public init(
        isSummarizing: Bool,
        hasTranscriptMessages: Bool,
        freshness: AgentSessionSummaryFreshness?
    ) {
        self.isSummarizing = isSummarizing
        self.hasTranscriptMessages = hasTranscriptMessages
        self.freshness = freshness
    }

    public var buttonTitle: String {
        if isSummarizing { return "摘要生成中…" }
        if freshness?.isFresh == false { return "刷新摘要" }
        return "生成会话摘要"
    }

    public var canSubmit: Bool {
        !isSummarizing && hasTranscriptMessages
    }

    public var successMessage: String {
        "会话摘要已刷新，将包含在下一次回答中。"
    }
}
