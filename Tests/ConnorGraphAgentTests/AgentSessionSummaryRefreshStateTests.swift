import Testing
import ConnorGraphCore
import ConnorGraphAgent

@Test func agentSessionSummaryRefreshStateShowsRefreshTitleWhenSummaryIsStale() {
    let state = AgentSessionSummaryRefreshState(
        isSummarizing: false,
        hasTranscriptMessages: true,
        freshness: AgentSessionSummaryFreshness(coveredMessageCount: 2, currentMessageCount: 3)
    )

    #expect(state.buttonTitle == "刷新摘要")
    #expect(state.canSubmit)
}

@Test func agentSessionSummaryRefreshStateShowsSummarizeTitleWhenSummaryIsFresh() {
    let state = AgentSessionSummaryRefreshState(
        isSummarizing: false,
        hasTranscriptMessages: true,
        freshness: AgentSessionSummaryFreshness(coveredMessageCount: 2, currentMessageCount: 2)
    )

    #expect(state.buttonTitle == "生成会话摘要")
    #expect(state.canSubmit)
}

@Test func agentSessionSummaryRefreshStateDisablesSubmitWithoutTranscriptMessages() {
    let state = AgentSessionSummaryRefreshState(
        isSummarizing: false,
        hasTranscriptMessages: false,
        freshness: nil
    )

    #expect(state.buttonTitle == "生成会话摘要")
    #expect(!state.canSubmit)
}

@Test func agentSessionSummaryRefreshStateShowsSummarizingTitleAndDisablesSubmitWhileRunning() {
    let state = AgentSessionSummaryRefreshState(
        isSummarizing: true,
        hasTranscriptMessages: true,
        freshness: AgentSessionSummaryFreshness(coveredMessageCount: 2, currentMessageCount: 3)
    )

    #expect(state.buttonTitle == "摘要生成中…")
    #expect(!state.canSubmit)
}

@Test func agentSessionSummaryRefreshStateProvidesRefreshSuccessMessage() {
    let state = AgentSessionSummaryRefreshState(
        isSummarizing: false,
        hasTranscriptMessages: true,
        freshness: AgentSessionSummaryFreshness(coveredMessageCount: 3, currentMessageCount: 3)
    )

    #expect(state.successMessage == "会话摘要已刷新，将包含在下一次回答中。")
}
