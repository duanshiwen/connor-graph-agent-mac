import Testing
@testable import ConnorGraphAgentMac

@Suite("Chat Viewport State Machine Tests")
struct ChatViewportStateMachineTests {
    @Test func initialUnderfilledContentIsBottomAnchoredWhenConfigured() {
        let machine = ChatViewportStateMachine(configuration: .init(preservesBottomAnchorForUnderfilledContent: true))

        let snapshot = machine.reduce(
            snapshot: .initial,
            event: .metricsChanged(.init(viewportHeight: 600, contentHeight: 240, distanceToBottom: 0, distanceToTop: 0))
        )

        #expect(snapshot.mode == .initialBottomAnchored)
        #expect(snapshot.isPinnedToBottom)
        #expect(!snapshot.shouldShowJumpToLatest)
    }

    @Test func distanceWithinThresholdPinsToBottom() {
        let machine = ChatViewportStateMachine(configuration: .init(bottomPinThreshold: 64))
        let browsing = ChatViewportSnapshot(mode: .freeBrowsing, isPinnedToBottom: false, shouldShowJumpToLatest: true, pendingNewItemCount: 2)

        let snapshot = machine.reduce(
            snapshot: browsing,
            event: .metricsChanged(.init(viewportHeight: 600, contentHeight: 1_200, distanceToBottom: 24, distanceToTop: 576))
        )

        #expect(snapshot.mode == .pinnedToBottom)
        #expect(snapshot.isPinnedToBottom)
        #expect(!snapshot.shouldShowJumpToLatest)
        #expect(snapshot.pendingNewItemCount == 0)
    }

    @Test func distanceBeyondThresholdEntersFreeBrowsing() {
        let machine = ChatViewportStateMachine(configuration: .init(bottomPinThreshold: 64))
        let pinned = ChatViewportSnapshot(mode: .pinnedToBottom, isPinnedToBottom: true, shouldShowJumpToLatest: false, pendingNewItemCount: 0)

        let snapshot = machine.reduce(
            snapshot: pinned,
            event: .metricsChanged(.init(viewportHeight: 600, contentHeight: 1_200, distanceToBottom: 160, distanceToTop: 440))
        )

        #expect(snapshot.mode == .freeBrowsing)
        #expect(!snapshot.isPinnedToBottom)
        #expect(snapshot.shouldShowJumpToLatest)
    }

    @Test func pinnedAppendAutoFollows() {
        let machine = ChatViewportStateMachine(configuration: .init())
        let pinned = ChatViewportSnapshot(mode: .pinnedToBottom, isPinnedToBottom: true, shouldShowJumpToLatest: false, pendingNewItemCount: 0)

        let snapshot = machine.reduce(snapshot: pinned, event: .dataChanged(.append(count: 3)))

        #expect(snapshot.mode == .programmaticScroll(.bottom(animated: true)))
        #expect(snapshot.isPinnedToBottom)
        #expect(!snapshot.shouldShowJumpToLatest)
        #expect(snapshot.pendingNewItemCount == 0)
    }

    @Test func freeBrowsingAppendDoesNotAutoFollowAndIncrementsPendingCount() {
        let machine = ChatViewportStateMachine(configuration: .init())
        let browsing = ChatViewportSnapshot(mode: .freeBrowsing, isPinnedToBottom: false, shouldShowJumpToLatest: true, pendingNewItemCount: 2)

        let snapshot = machine.reduce(snapshot: browsing, event: .dataChanged(.append(count: 3)))

        #expect(snapshot.mode == .freeBrowsing)
        #expect(!snapshot.isPinnedToBottom)
        #expect(snapshot.shouldShowJumpToLatest)
        #expect(snapshot.pendingNewItemCount == 5)
    }

    @Test func jumpToLatestClearsPendingCountAndRequestsBottomScroll() {
        let machine = ChatViewportStateMachine(configuration: .init())
        let browsing = ChatViewportSnapshot(mode: .freeBrowsing, isPinnedToBottom: false, shouldShowJumpToLatest: true, pendingNewItemCount: 5)

        let snapshot = machine.reduce(snapshot: browsing, event: .jumpToLatestRequested)

        #expect(snapshot.mode == .programmaticScroll(.bottom(animated: true)))
        #expect(snapshot.isPinnedToBottom)
        #expect(!snapshot.shouldShowJumpToLatest)
        #expect(snapshot.pendingNewItemCount == 0)
    }

    @Test func prepareForPrependEntersCorrectionMode() {
        let machine = ChatViewportStateMachine(configuration: .init())
        let browsing = ChatViewportSnapshot(mode: .freeBrowsing, isPinnedToBottom: false, shouldShowJumpToLatest: true, pendingNewItemCount: 0)

        let snapshot = machine.reduce(snapshot: browsing, event: .prepareForPrepend(anchorItemID: "message-42"))

        #expect(snapshot.mode == .correctingAfterDataChange(.prepend(anchorItemID: "message-42")))
        #expect(!snapshot.isPinnedToBottom)
        #expect(snapshot.shouldShowJumpToLatest)
    }

    @Test func prependAfterPreparationRequestsAnchorRestoration() {
        let machine = ChatViewportStateMachine(configuration: .init())
        let browsing = ChatViewportSnapshot(mode: .freeBrowsing, isPinnedToBottom: false, shouldShowJumpToLatest: true, pendingNewItemCount: 1)
        let prepared = machine.reduce(snapshot: browsing, event: .prepareForPrepend(anchorItemID: "message-42"))

        let snapshot = machine.reduce(snapshot: prepared, event: .dataChanged(.prepend(count: 20)))

        #expect(snapshot.mode == .programmaticScroll(.item(id: "message-42", anchor: .top, animated: false)))
        #expect(!snapshot.isPinnedToBottom)
        #expect(snapshot.shouldShowJumpToLatest)
        #expect(snapshot.pendingNewItemCount == 1)
    }

    @Test func explicitPrependAnchorRequestsAnchorRestoration() {
        let machine = ChatViewportStateMachine(configuration: .init())
        let browsing = ChatViewportSnapshot(mode: .freeBrowsing, isPinnedToBottom: false, shouldShowJumpToLatest: true, pendingNewItemCount: 0)

        let snapshot = machine.reduce(snapshot: browsing, event: .dataChanged(.prepend(count: 10, anchorItemID: "message-7")))

        #expect(snapshot.mode == .programmaticScroll(.item(id: "message-7", anchor: .top, animated: false)))
    }

    @Test func completedPrependCorrectionReturnsToFreeBrowsing() {
        let machine = ChatViewportStateMachine(configuration: .init())
        let correcting = ChatViewportSnapshot(
            mode: .programmaticScroll(.item(id: "message-42", anchor: .top, animated: false)),
            isPinnedToBottom: false,
            shouldShowJumpToLatest: true,
            pendingNewItemCount: 2
        )

        let snapshot = machine.reduce(snapshot: correcting, event: .programmaticScrollCompleted)

        #expect(snapshot.mode == .freeBrowsing)
        #expect(!snapshot.isPinnedToBottom)
        #expect(snapshot.shouldShowJumpToLatest)
        #expect(snapshot.pendingNewItemCount == 2)
    }
}
