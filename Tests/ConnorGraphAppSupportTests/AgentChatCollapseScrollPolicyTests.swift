import Testing
@testable import ConnorGraphAppSupport

@Test func collapsedAssistantMessageDoesNotScrollWhenTranscriptFitsViewport() {
    let policy = AgentChatCollapseScrollPolicy()

    let decision = policy.decisionAfterAssistantMessageCollapse(
        contentHeight: 520,
        viewportHeight: 700
    )

    #expect(decision == .doNotScroll)
}

@Test func collapsedAssistantMessageScrollsToBottomWhenTranscriptStillOverflowsViewport() {
    let policy = AgentChatCollapseScrollPolicy()

    let decision = policy.decisionAfterAssistantMessageCollapse(
        contentHeight: 900,
        viewportHeight: 700
    )

    #expect(decision == .scrollToBottom)
}
