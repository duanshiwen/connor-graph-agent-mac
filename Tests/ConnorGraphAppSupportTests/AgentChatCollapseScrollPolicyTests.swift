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

@Test func sessionSwitchDoesNotScrollWhenTranscriptFitsViewport() {
    let policy = AgentChatCollapseScrollPolicy()

    let decision = policy.decisionAfterSessionSwitch(
        contentHeight: 520,
        viewportHeight: 700
    )

    #expect(decision == .doNotScroll)
}

@Test func sessionSwitchScrollsToBottomWhenTranscriptOverflowsViewport() {
    let policy = AgentChatCollapseScrollPolicy()

    let decision = policy.decisionAfterSessionSwitch(
        contentHeight: 1200,
        viewportHeight: 700
    )

    #expect(decision == .scrollToBottom)
}

@Test func collapseScrollScheduleIncludesPostAnimationLayoutProbe() {
    #expect(AgentChatCollapseScrollSchedule.decisionDelays.contains { $0 >= 0.3 })
}

@Test func collapseScrollScheduleIncludesLateProbeForVeryTallBubbleLayout() {
    #expect(AgentChatCollapseScrollSchedule.decisionDelays.contains { $0 >= 0.6 })
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

@Test func collapseDoesNotResetScrollIdentityWhenNormalTranscriptStillOverflowsViewport() {
    let policy = AgentChatCollapseScrollPolicy()

    let shouldReset = policy.shouldResetScrollIdentityAfterCollapse(
        previousContentHeight: 980,
        newContentHeight: 760,
        viewportHeight: 700
    )

    #expect(!shouldReset)
}

@Test func collapseResetsScrollIdentityForVeryTallAssistantBubbleEvenWhenTranscriptStillOverflowsViewport() {
    let policy = AgentChatCollapseScrollPolicy()

    let shouldReset = policy.shouldResetScrollIdentityAfterCollapse(
        previousContentHeight: 6_400,
        newContentHeight: 1_050,
        viewportHeight: 700
    )

    #expect(shouldReset)
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
