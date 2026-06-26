import Testing
@testable import ConnorGraphAgentMac

@Suite("Chat Viewport Top Load Policy Tests")
struct ChatViewportTopLoadPolicyTests {
    @Test func doesNotRequestOlderItemsWhileInitialAnchorIsResolving() {
        let shouldRequest = ChatViewportTopLoadPolicy.shouldRequestOlderItems(
            hasOlderItems: true,
            isLoadingOlderItems: false,
            didRequestOlderItemsForCurrentTopReach: false,
            viewportHeight: 600,
            distanceToTop: 0,
            topLoadTriggerOffset: 96,
            isResolvingInitialAnchor: true
        )

        #expect(!shouldRequest)
    }

    @Test func requestsOlderItemsWhenUserReachesTopAfterInitialAnchorSettles() {
        let shouldRequest = ChatViewportTopLoadPolicy.shouldRequestOlderItems(
            hasOlderItems: true,
            isLoadingOlderItems: false,
            didRequestOlderItemsForCurrentTopReach: false,
            viewportHeight: 600,
            distanceToTop: 24,
            topLoadTriggerOffset: 96,
            isResolvingInitialAnchor: false
        )

        #expect(shouldRequest)
    }

    @Test func shortConversationWithoutOlderItemsDoesNotRequestOlderItems() {
        let shouldRequest = ChatViewportTopLoadPolicy.shouldRequestOlderItems(
            hasOlderItems: false,
            isLoadingOlderItems: false,
            didRequestOlderItemsForCurrentTopReach: false,
            viewportHeight: 600,
            distanceToTop: 0,
            topLoadTriggerOffset: 96,
            isResolvingInitialAnchor: false
        )

        #expect(!shouldRequest)
    }

    @Test func doesNotRequestOlderItemsWithoutViewportHeight() {
        let shouldRequest = ChatViewportTopLoadPolicy.shouldRequestOlderItems(
            hasOlderItems: true,
            isLoadingOlderItems: false,
            didRequestOlderItemsForCurrentTopReach: false,
            viewportHeight: 0,
            distanceToTop: 0,
            topLoadTriggerOffset: 96,
            isResolvingInitialAnchor: false
        )

        #expect(!shouldRequest)
    }

    @Test func doesNotRepeatTopReachRequestUntilUserScrollsAway() {
        let shouldRequest = ChatViewportTopLoadPolicy.shouldRequestOlderItems(
            hasOlderItems: true,
            isLoadingOlderItems: false,
            didRequestOlderItemsForCurrentTopReach: true,
            viewportHeight: 600,
            distanceToTop: 0,
            topLoadTriggerOffset: 96,
            isResolvingInitialAnchor: false
        )

        #expect(!shouldRequest)
        #expect(ChatViewportTopLoadPolicy.shouldResetTopReachRequest(distanceToTop: 193, topLoadTriggerOffset: 96))
        #expect(!ChatViewportTopLoadPolicy.shouldResetTopReachRequest(distanceToTop: 192, topLoadTriggerOffset: 96))
    }
}
