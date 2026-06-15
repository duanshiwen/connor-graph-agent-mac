import Testing
@testable import ConnorGraphAppSupport

@Test func collapsedAssistantMessageResetsToTopWhenTranscriptFitsViewport() {
    let policy = AgentChatCollapseScrollPolicy()

    let decision = policy.decisionAfterAssistantMessageCollapse(
        contentHeight: 520,
        viewportHeight: 700
    )

    #expect(decision == .scrollToTop)
}

@Test func collapsedAssistantMessageScrollsToBottomWhenTranscriptStillOverflowsViewport() {
    let policy = AgentChatCollapseScrollPolicy()

    let decision = policy.decisionAfterAssistantMessageCollapse(
        contentHeight: 900,
        viewportHeight: 700
    )

    #expect(decision == .scrollToBottom)
}

@Test func sessionSwitchResetsToTopWhenTranscriptFitsViewport() {
    let policy = AgentChatCollapseScrollPolicy()

    let decision = policy.decisionAfterSessionSwitch(
        contentHeight: 520,
        viewportHeight: 700
    )

    #expect(decision == .scrollToTop)
}

@Test func collapseScrollScheduleIncludesPostAnimationLayoutProbe() {
    #expect(AgentChatCollapseScrollSchedule.decisionDelays.contains { $0 >= 0.3 })
}

@Test func collapseResetScrollIdentityWhenTranscriptShrinksFromOverflowingToFittingViewport() {
    let policy = AgentChatCollapseScrollPolicy()

    let shouldReset = policy.shouldResetScrollIdentityAfterCollapse(
        previousContentHeight: 980,
        newContentHeight: 560,
        viewportHeight: 700
    )

    #expect(shouldReset)
}

@Test func collapseDoesNotResetScrollIdentityWhenTranscriptStillOverflowsViewport() {
    let policy = AgentChatCollapseScrollPolicy()

    let shouldReset = policy.shouldResetScrollIdentityAfterCollapse(
        previousContentHeight: 980,
        newContentHeight: 760,
        viewportHeight: 700
    )

    #expect(!shouldReset)
}

@Test func collapseDoesNotResetScrollIdentityWithoutPriorOverflow() {
    let policy = AgentChatCollapseScrollPolicy()

    let shouldReset = policy.shouldResetScrollIdentityAfterCollapse(
        previousContentHeight: 620,
        newContentHeight: 560,
        viewportHeight: 700
    )

    #expect(!shouldReset)
}
