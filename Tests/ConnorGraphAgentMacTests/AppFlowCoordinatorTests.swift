import Foundation
import Testing
@testable import ConnorGraphAgentMac

@MainActor
@Test func appFlowCoordinatorForwardsTypedIntentsExactlyOnce() {
    var received: [AppFlowIntent] = []
    let coordinator = AppFlowCoordinator { received.append($0) }
    let request = RSSFollowRequest(
        itemID: "rss-item",
        title: "Example",
        url: URL(string: "https://example.com/article")!
    )

    coordinator.send(.navigate(.rss))
    coordinator.send(.openSessionNotification("session-1"))
    coordinator.send(.followRSSItem(request))

    #expect(received == [
        .navigate(.rss),
        .openSessionNotification("session-1"),
        .followRSSItem(request)
    ])
}
