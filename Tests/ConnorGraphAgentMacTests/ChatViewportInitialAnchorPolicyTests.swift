import Testing
@testable import ConnorGraphAgentMac

@Suite("Chat Viewport Initial Anchor Policy Tests")
struct ChatViewportInitialAnchorPolicyTests {
    @Test func emptyItemsDoNotRetryInitialLatestAnchor() {
        let decision = ChatViewportInitialAnchorPolicy.decision(
            itemCount: 0,
            viewportHeight: 600,
            contentHeight: 1200,
            distanceToBottom: 300,
            bottomPinThreshold: 64,
            isLoadingOlderItems: false,
            isPrependingOlderItems: false,
            isResolvingInitialAnchor: true,
            isPinnedToBottom: true
        )

        #expect(decision == .stop)
    }

    @Test func waitsForMeasuredViewportAndContent() {
        let decision = ChatViewportInitialAnchorPolicy.decision(
            itemCount: 12,
            viewportHeight: 0,
            contentHeight: 1200,
            distanceToBottom: 300,
            bottomPinThreshold: 64,
            isLoadingOlderItems: false,
            isPrependingOlderItems: false,
            isResolvingInitialAnchor: true,
            isPinnedToBottom: true
        )

        #expect(decision == .wait)
    }

    @Test func underfilledContentSettlesWithoutProgrammaticScroll() {
        let decision = ChatViewportInitialAnchorPolicy.decision(
            itemCount: 2,
            viewportHeight: 600,
            contentHeight: 320,
            distanceToBottom: 0,
            bottomPinThreshold: 64,
            isLoadingOlderItems: false,
            isPrependingOlderItems: false,
            isResolvingInitialAnchor: true,
            isPinnedToBottom: true
        )

        #expect(decision == .settleWithoutScroll)
    }

    @Test func overflowingContentRetriesWhenNotNearBottom() {
        let decision = ChatViewportInitialAnchorPolicy.decision(
            itemCount: 80,
            viewportHeight: 600,
            contentHeight: 2400,
            distanceToBottom: 480,
            bottomPinThreshold: 64,
            isLoadingOlderItems: false,
            isPrependingOlderItems: false,
            isResolvingInitialAnchor: true,
            isPinnedToBottom: true
        )

        #expect(decision == .scrollToLatest)
    }

    @Test func nearBottomSettlesWithoutAdditionalRetry() {
        let decision = ChatViewportInitialAnchorPolicy.decision(
            itemCount: 80,
            viewportHeight: 600,
            contentHeight: 2400,
            distanceToBottom: 32,
            bottomPinThreshold: 64,
            isLoadingOlderItems: false,
            isPrependingOlderItems: false,
            isResolvingInitialAnchor: true,
            isPinnedToBottom: true
        )

        #expect(decision == .settleWithoutScroll)
    }

    @Test func loadingOlderItemsStopsInitialRetry() {
        let decision = ChatViewportInitialAnchorPolicy.decision(
            itemCount: 80,
            viewportHeight: 600,
            contentHeight: 2400,
            distanceToBottom: 480,
            bottomPinThreshold: 64,
            isLoadingOlderItems: true,
            isPrependingOlderItems: false,
            isResolvingInitialAnchor: true,
            isPinnedToBottom: true
        )

        #expect(decision == .stop)
    }

    @Test func prependCorrectionStopsInitialRetry() {
        let decision = ChatViewportInitialAnchorPolicy.decision(
            itemCount: 120,
            viewportHeight: 600,
            contentHeight: 3200,
            distanceToBottom: 900,
            bottomPinThreshold: 64,
            isLoadingOlderItems: false,
            isPrependingOlderItems: true,
            isResolvingInitialAnchor: true,
            isPinnedToBottom: true
        )

        #expect(decision == .stop)
    }

    @Test func freeBrowsingStopsInitialRetry() {
        let decision = ChatViewportInitialAnchorPolicy.decision(
            itemCount: 80,
            viewportHeight: 600,
            contentHeight: 2400,
            distanceToBottom: 480,
            bottomPinThreshold: 64,
            isLoadingOlderItems: false,
            isPrependingOlderItems: false,
            isResolvingInitialAnchor: false,
            isPinnedToBottom: false
        )

        #expect(decision == .stop)
    }
}
