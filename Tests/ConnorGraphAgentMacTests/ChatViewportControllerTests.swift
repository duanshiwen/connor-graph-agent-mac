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

    @Test func prependPublishesAnchorRestorationCommand() {
        let controller = ChatViewportController(configuration: .init(bottomPinThreshold: 64))
        controller.updateMetrics(.init(viewportHeight: 600, contentHeight: 1_200, distanceToBottom: 300, distanceToTop: 300))

        controller.prepareForPrepend(anchorItemID: "message-42")
        controller.notifyDataChange(.prepend(count: 20))

        #expect(controller.pendingScrollCommand?.target == .item(id: "message-42", anchor: .top, animated: false))
        #expect(controller.snapshot.pendingNewItemCount == 0)
    }

    @Test func explicitPrependPublishesAnchorRestorationCommand() {
        let controller = ChatViewportController(configuration: .init(bottomPinThreshold: 64))
        controller.updateMetrics(.init(viewportHeight: 600, contentHeight: 1_200, distanceToBottom: 300, distanceToTop: 300))

        controller.notifyPrepend(count: 20, anchorItemID: "message-7")

        #expect(controller.pendingScrollCommand?.target == .item(id: "message-7", anchor: .top, animated: false))
    }

    @Test func replaceDataResetsSnapshotAndPendingCommand() {
        let controller = ChatViewportController(configuration: .init(bottomPinThreshold: 64))
        controller.updateMetrics(.init(viewportHeight: 600, contentHeight: 1_200, distanceToBottom: 160, distanceToTop: 440))
        controller.notifyDataChange(.append(count: 2))

        #expect(controller.snapshot.mode == .freeBrowsing)
        #expect(controller.snapshot.pendingNewItemCount == 2)

        controller.jumpToLatest()
        #expect(controller.pendingScrollCommand != nil)

        controller.notifyDataChange(.replace)

        #expect(controller.snapshot == .initial)
        #expect(controller.pendingScrollCommand == nil)
    }

    @Test func replacingDataSetResetsStateAndRecordsIdentity() {
        let controller = ChatViewportController(configuration: .init(bottomPinThreshold: 64))
        let firstDataSet = ChatViewportDataSetID.agentChatSession(sessionID: "first", revision: 1)
        let secondDataSet = ChatViewportDataSetID.agentChatSession(sessionID: "second", revision: 1)

        controller.replaceDataSet(id: firstDataSet, itemCount: 4, initialAnchor: .bottom)
        #expect(controller.currentDataSetID == firstDataSet)
        #expect(controller.replacementGeneration == 1)

        controller.updateMetrics(.init(viewportHeight: 600, contentHeight: 1_200, distanceToBottom: 200, distanceToTop: 400))
        _ = controller.consumePendingScrollCommand()
        controller.completeProgrammaticScroll()
        controller.notifyDataChange(.append(count: 2))

        controller.replaceDataSet(id: secondDataSet, itemCount: 3, initialAnchor: .bottom)

        #expect(controller.currentDataSetID == secondDataSet)
        #expect(controller.replacementGeneration == 2)
        #expect(controller.snapshot == .initial)
        #expect(controller.pendingScrollCommand == nil)
    }

    @Test func replacingDataSetSchedulesInitialBottomScrollAfterMetricsArrive() {
        let controller = ChatViewportController(configuration: .init(bottomPinThreshold: 64))
        let dataSet = ChatViewportDataSetID.agentChatSession(sessionID: "session", revision: 1)

        controller.replaceDataSet(id: dataSet, itemCount: 3, initialAnchor: .bottom)
        #expect(controller.pendingScrollCommand == nil)

        controller.updateMetrics(.init(viewportHeight: 600, contentHeight: 1_200, distanceToBottom: 600, distanceToTop: 0))

        #expect(controller.pendingScrollCommand?.target == .bottom(animated: false))
        #expect(controller.snapshot.mode == .programmaticScroll(.bottom(animated: false)))
    }

    @Test func replaceDataSetIfNeededDoesNotIncrementGenerationForSameDataSet() {
        let controller = ChatViewportController(configuration: .init())
        let dataSet = ChatViewportDataSetID.agentChatSession(sessionID: "session", revision: 1)

        controller.replaceDataSetIfNeeded(id: dataSet, itemCount: 2, initialAnchor: .bottom)
        controller.replaceDataSetIfNeeded(id: dataSet, itemCount: 2, initialAnchor: .bottom)

        #expect(controller.replacementGeneration == 1)
        #expect(controller.currentDataSetID == dataSet)
    }
}
