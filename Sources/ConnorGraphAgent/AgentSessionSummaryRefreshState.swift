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
        if isSummarizing { return "Summarizing…" }
        if freshness?.isFresh == false { return "Refresh Summary" }
        return "Summarize Session"
    }

    public var canSubmit: Bool {
        !isSummarizing && hasTranscriptMessages
    }

    public var successMessage: String {
        "Summary refreshed and will be included in the next answer."
    }
}
