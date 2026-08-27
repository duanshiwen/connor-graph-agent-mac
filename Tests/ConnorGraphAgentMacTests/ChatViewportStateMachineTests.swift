import Testing
@testable import ConnorGraphAgentMac

@Suite("Chat Viewport State Machine Tests")
struct ChatViewportStateMachineTests {
    @Test func metricsDoNotInterruptProgrammaticBottomAnchor() {
        let machine = ChatViewportStateMachine(configuration: .init(bottomPinThreshold: 64))
        let scrolling = ChatViewportSnapshot(
            mode: .programmaticScroll(.bottom(animated: false)),
            isPinnedToBottom: true,
            shouldShowJumpToLatest: false,
            pendingNewItemCount: 0
        )

        let updated = machine.reduce(
            snapshot: scrolling,
            event: .metricsChanged(.init(
                viewportHeight: 600,
                contentHeight: 2_400,
                distanceToBottom: 1_800,
                distanceToTop: 0
            ))
        )

        #expect(updated == scrolling)
    }

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

    @Test func agentChatOnlyAutoFollowsWhenVisuallyAtTheBottom() {
        let machine = ChatViewportStateMachine(configuration: .init(
            bottomPinThreshold: AgentChatLayout.chatBottomPinnedThreshold
        ))
        let pinned = ChatViewportSnapshot(
            mode: .pinnedToBottom,
            isPinnedToBottom: true,
            shouldShowJumpToLatest: false,
            pendingNewItemCount: 0
        )

        let browsing = machine.reduce(
            snapshot: pinned,
            event: .metricsChanged(.init(
                viewportHeight: 600,
                contentHeight: 1_200,
                distanceToBottom: 24,
                distanceToTop: 576
            ))
        )

        #expect(AgentChatLayout.chatBottomPinnedThreshold == 8)
        #expect(browsing.mode == .freeBrowsing)
        #expect(!browsing.isPinnedToBottom)
        #expect(browsing.shouldShowJumpToLatest)
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

    /// 复现 AgentChatView 的真实时序：仓库分页 prepend 后，`onChange(of: transcript.count)`
    /// 先发出 .append（错误通知），随后 `onChange(of: visibleMessageLimit)` 才发出 .prepend。
    /// 期望：最终仍生成锚点恢复命令（顺序 append→prepend 时纠正保留，但 pendingNewItemCount 被错误累加）。
    @Test func appendDuringPrependCorrectionKeepsAnchorRestorationButLeaksPendingCount() {
        let machine = ChatViewportStateMachine(configuration: .init())
        let browsing = ChatViewportSnapshot(mode: .freeBrowsing, isPinnedToBottom: false, shouldShowJumpToLatest: true, pendingNewItemCount: 0)
        let prepared = machine.reduce(snapshot: browsing, event: .prepareForPrepend(anchorItemID: "message-42"))

        // onChange(of: transcript.count) 先触发：prepend 被误报为 .append
        let afterAppend = machine.reduce(snapshot: prepared, event: .dataChanged(.append(count: 20)))
        #expect(afterAppend.mode == .freeBrowsing)

        // onChange(of: visibleMessageLimit) 后触发：真正的 prepend 通知
        let final = machine.reduce(snapshot: afterAppend, event: .dataChanged(.prepend(count: 20, anchorItemID: "message-42")))
        #expect(final.mode == .programmaticScroll(.item(id: "message-42", anchor: .top, animated: false)))
        // 缺陷：pendingNewItemCount 被错误累加 → “跳到最新”按钮错误出现
        #expect(final.pendingNewItemCount == 20)
    }

    /// 复现最坏时序：prepend 纠正命令已生成（prepend 通知先于 append 通知），
    /// 随后 onChange(of: transcript.count) 的 .append 误通知把纠正状态覆盖为 freeBrowsing，
    /// 导致锚点恢复滚动命令丢失——新消息插入顶部后视口不滚动，用户仍停留在旧内容位置。
    @Test func appendAfterAnchorRestorationCancelsCorrectionCommand() {
        let machine = ChatViewportStateMachine(configuration: .init())
        let browsing = ChatViewportSnapshot(mode: .freeBrowsing, isPinnedToBottom: false, shouldShowJumpToLatest: true, pendingNewItemCount: 0)
        let prepared = machine.reduce(snapshot: browsing, event: .prepareForPrepend(anchorItemID: "message-42"))

        // prepend 通知先到：锚点恢复命令已生成
        let corrected = machine.reduce(snapshot: prepared, event: .dataChanged(.prepend(count: 20)))
        #expect(corrected.mode == .programmaticScroll(.item(id: "message-42", anchor: .top, animated: false)))

        // .append 误通知随后覆盖：纠正命令丢失
        let final = machine.reduce(snapshot: corrected, event: .dataChanged(.append(count: 20)))
        #expect(final.mode == .freeBrowsing)
        #expect(final.pendingNewItemCount == 20)
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
