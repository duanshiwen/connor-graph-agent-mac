import Testing
@testable import ConnorGraphAgentMac

@MainActor
struct AppRoutePerformanceTrackerTests {
    @Test func effectiveSelectionStartsOneTransactionAndRepeatedSelectionStartsNone() {
        var events: [AppRoutePerformanceEvent] = []
        let tracker = AppRoutePerformanceTracker(eventObserver: { events.append($0) })
        let model = AppShellFeatureModel(routePerformanceTracker: tracker)

        #expect(model.select(.mail))
        #expect(tracker.activeTransactionID == 1)
        #expect(!model.select(.mail))
        #expect(tracker.activeTransactionID == 1)
        #expect(events.map(\.kind) == [.began])
    }

    @Test func listAndDetailMayActivateOutOfOrderAndCompleteExactlyOnce() async {
        var events: [AppRoutePerformanceEvent] = []
        let tracker = AppRoutePerformanceTracker(eventObserver: { events.append($0) })

        let transactionID = tracker.begin(route: .rss, from: .agentChat)
        tracker.markActivated(route: .rss, pane: .detail)
        tracker.markActivated(route: .rss, pane: .list)
        tracker.markActivated(route: .rss, pane: .list)
        #expect(events.filter { $0.kind == .completed }.isEmpty)
        tracker.markPresented(route: .rss, pane: .detail)
        tracker.markPresented(route: .rss, pane: .list)
        tracker.markPresented(route: .rss, pane: .list)
        await Task.yield()
        await Task.yield()

        #expect(transactionID == 1)
        #expect(events.filter { $0.kind == .paneActivated }.map(\.pane) == [.detail, .list])
        #expect(events.filter { $0.kind == .panePresented }.map(\.pane) == [.detail, .list])
        #expect(events.filter { $0.kind == .completed }.count == 1)
        #expect(tracker.activeTransactionID == nil)
    }

    @Test func staleActivationCannotCompleteSupersedingRoute() async {
        var events: [AppRoutePerformanceEvent] = []
        let tracker = AppRoutePerformanceTracker(eventObserver: { events.append($0) })

        _ = tracker.begin(route: .mail, from: .agentChat)
        tracker.markActivated(route: .mail, pane: .list)
        let rssTransactionID = tracker.begin(route: .rss, from: .mail)
        tracker.markActivated(route: .mail, pane: .detail)
        tracker.markPresented(route: .mail, pane: .list)
        tracker.markPresented(route: .mail, pane: .detail)
        tracker.markActivated(route: .rss, pane: .detail)
        tracker.markActivated(route: .rss, pane: .list)
        tracker.markPresented(route: .rss, pane: .detail)
        tracker.markPresented(route: .rss, pane: .list)
        await Task.yield()
        await Task.yield()

        #expect(events.contains { $0.kind == .cancelled && $0.route == .mail })
        #expect(events.contains { $0.kind == .completed && $0.transactionID == rssTransactionID })
        #expect(!events.contains { $0.kind == .completed && $0.route == .mail })
    }
}
