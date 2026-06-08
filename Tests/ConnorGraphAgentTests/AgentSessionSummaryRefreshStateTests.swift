import Testing
import ConnorGraphCore
import ConnorGraphAgent

@Test func agentSessionSummaryRefreshStateShowsRefreshTitleWhenSummaryIsStale() {
    let state = AgentSessionSummaryRefreshState(
        isSummarizing: false,
        hasTranscriptMessages: true,
        freshness: AgentSessionSummaryFreshness(coveredMessageCount: 2, currentMessageCount: 3)
    )

    #expect(state.buttonTitle == "Refresh Summary")
    #expect(state.canSubmit)
}

@Test func agentSessionSummaryRefreshStateShowsSummarizeTitleWhenSummaryIsFresh() {
    let state = AgentSessionSummaryRefreshState(
        isSummarizing: false,
        hasTranscriptMessages: true,
        freshness: AgentSessionSummaryFreshness(coveredMessageCount: 2, currentMessageCount: 2)
    )

    #expect(state.buttonTitle == "Summarize Session")
    #expect(state.canSubmit)
}

@Test func agentSessionSummaryRefreshStateDisablesSubmitWithoutTranscriptMessages() {
    let state = AgentSessionSummaryRefreshState(
        isSummarizing: false,
        hasTranscriptMessages: false,
        freshness: nil
    )

    #expect(state.buttonTitle == "Summarize Session")
    #expect(!state.canSubmit)
}

@Test func agentSessionSummaryRefreshStateShowsSummarizingTitleAndDisablesSubmitWhileRunning() {
    let state = AgentSessionSummaryRefreshState(
        isSummarizing: true,
        hasTranscriptMessages: true,
        freshness: AgentSessionSummaryFreshness(coveredMessageCount: 2, currentMessageCount: 3)
    )

    #expect(state.buttonTitle == "Summarizing…")
    #expect(!state.canSubmit)
}

@Test func agentSessionSummaryRefreshStateProvidesRefreshSuccessMessage() {
    let state = AgentSessionSummaryRefreshState(
        isSummarizing: false,
        hasTranscriptMessages: true,
        freshness: AgentSessionSummaryFreshness(coveredMessageCount: 3, currentMessageCount: 3)
    )

    #expect(state.successMessage == "Summary refreshed and will be included in the next answer.")
}
