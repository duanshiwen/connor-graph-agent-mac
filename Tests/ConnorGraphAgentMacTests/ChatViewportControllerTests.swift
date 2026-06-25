import Testing
@testable import ConnorGraphAgentMac

@MainActor
@Suite("Chat Viewport Controller Tests")
struct ChatViewportControllerTests {
    @Test func jumpToLatestPublishesBottomScrollCommand() {
        let controller = ChatViewportController(configuration: .init())

        controller.jumpToLatest()

        #expect(controller.snapshot.mode == .programmaticScroll(.bottom(animated: true)))
        #expect(controller.snapshot.isPinnedToBottom)
        #expect(controller.pendingScrollCommand?.target == .bottom(animated: true))
    }

    @Test func consumingScrollCommandClearsPendingCommand() {
        let controller = ChatViewportController(configuration: .init())

        controller.jumpToLatest()
        let command = controller.consumePendingScrollCommand()

        #expect(command?.target == .bottom(animated: true))
        #expect(controller.pendingScrollCommand == nil)
    }

    @Test func freeBrowsingAppendIncrementsPendingCountWithoutCommand() {
        let controller = ChatViewportController(configuration: .init(bottomPinThreshold: 64))
        controller.updateMetrics(.init(viewportHeight: 600, contentHeight: 1_200, distanceToBottom: 160, distanceToTop: 440))

        controller.notifyDataChange(.append(count: 2))

        #expect(controller.snapshot.mode == .freeBrowsing)
        #expect(controller.snapshot.pendingNewItemCount == 2)
        #expect(controller.pendingScrollCommand == nil)
    }

    @Test func pinnedAppendPublishesBottomScrollCommand() {
        let controller = ChatViewportController(configuration: .init(bottomPinThreshold: 64))
        controller.updateMetrics(.init(viewportHeight: 600, contentHeight: 1_200, distanceToBottom: 0, distanceToTop: 600))

        controller.notifyDataChange(.append(count: 1))

        #expect(controller.pendingScrollCommand?.target == .bottom(animated: true))
        #expect(controller.snapshot.pendingNewItemCount == 0)
    }
}
