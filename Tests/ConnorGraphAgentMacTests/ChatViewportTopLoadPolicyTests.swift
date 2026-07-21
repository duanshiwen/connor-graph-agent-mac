import CoreGraphics
import Testing
@testable import ConnorGraphAgentMac

@Suite("Chat Viewport Top Load Policy Tests")
struct ChatViewportTopLoadPolicyTests {
    @Test func initialAnchorOnlyReevaluatesWhenContentDoesNotFillViewport() {
        #expect(ChatViewportTopLoadPolicy.shouldReevaluateAfterInitialAnchor(
            viewportHeight: 600,
            contentHeight: 480
        ))
        #expect(!ChatViewportTopLoadPolicy.shouldReevaluateAfterInitialAnchor(
            viewportHeight: 600,
            contentHeight: 1_200
        ))
    }

    @Test func nativeScrollMetricsHandleFlippedAndUnflippedDocuments() {
        let document = CGRect(x: 0, y: 0, width: 800, height: 2_000)

        let flippedMetrics = ChatViewportNativeScrollMetrics.calculate(
            documentBounds: document,
            visibleBounds: CGRect(x: 0, y: 320, width: 800, height: 600),
            isFlipped: true
        )
        #expect(flippedMetrics.distanceToTop == 320)
        #expect(flippedMetrics.distanceToBottom == 1_080)

        let unflippedMetrics = ChatViewportNativeScrollMetrics.calculate(
            documentBounds: document,
            visibleBounds: CGRect(x: 0, y: 1_080, width: 800, height: 600),
            isFlipped: false
        )
        #expect(unflippedMetrics.distanceToTop == 320)
        #expect(unflippedMetrics.distanceToBottom == 1_080)
    }

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
