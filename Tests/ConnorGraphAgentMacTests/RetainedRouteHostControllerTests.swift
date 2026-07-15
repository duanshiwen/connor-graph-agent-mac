import SwiftUI
import Testing
@testable import ConnorGraphAgentMac

@MainActor
struct RetainedRouteHostControllerTests {
    private final class ContentOwner {}

    @Test func hotRouteControllersKeepIdentityAcrossRoundTrips() throws {
        let host = makeHost()

        host.activate(.agentChat)
        let chatIdentity = try #require(host.controllerIdentity(for: .agentChat))
        host.activate(.mail)
        let mailIdentity = try #require(host.controllerIdentity(for: .mail))
        host.activate(.rss)
        host.activate(.agentChat)
        host.activate(.mail)

        #expect(host.controllerIdentity(for: .agentChat) == chatIdentity)
        #expect(host.controllerIdentity(for: .mail) == mailIdentity)
        #expect(host.cachedRoutes == [.agentChat, .mail, .rss])
        #expect(host.attachedControllerCount == 3)
        #expect(host.isRouteVisible(.mail))
        #expect(!host.isRouteVisible(.agentChat))
        #expect(!host.isRouteVisible(.rss))
    }

    @Test func repeatedHotRouteSwitchingKeepsControllersInstalledAndOnlyLatestVisible() {
        let host = makeHost()
        let routes: [SidebarItem] = [.agentChat, .mail, .rss]

        for index in 0..<100 {
            host.activate(routes[index % routes.count])
        }

        #expect(host.cachedControllerCount == 3)
        #expect(host.attachedControllerCount == 3)
        #expect(host.isRouteVisible(.agentChat))
        #expect(!host.isRouteVisible(.mail))
        #expect(!host.isRouteVisible(.rss))
    }

    @Test func coldRoutesUseOneEntryMRUWithoutEvictingHotRoutes() {
        let host = makeHost()

        host.activate(.agentChat)
        host.activate(.mail)
        host.activate(.rss)
        host.activate(.calendar)
        #expect(host.cachedRoutes == [.agentChat, .mail, .rss, .calendar])

        host.activate(.contacts)
        #expect(host.cachedRoutes == [.agentChat, .mail, .rss, .contacts])
        #expect(host.cachedControllerCount == 4)
        #expect(host.attachedControllerCount == 4)
        #expect(host.isRouteVisible(.contacts))
        #expect(!host.isRouteVisible(.calendar))
    }

    @Test func repeatedSwitchingNeverExceedsBoundAndLatestRouteWins() {
        let host = makeHost()
        let sequence: [SidebarItem] = [.agentChat, .mail, .rss, .calendar, .contacts, .sources, .skills]

        for index in 0..<100 {
            host.activate(sequence[index % sequence.count])
            #expect(host.cachedControllerCount <= 4)
        }
        host.activate(.rss)

        #expect(host.activeRoute == .rss)
        #expect(host.cachedControllerCount <= 4)
    }

    @Test func unchangedContentOwnerPreservesCachedControllerIdentity() throws {
        let owner = ContentOwner()
        let host = makeHost(owner: owner)

        host.activate(.agentChat)
        let identity = try #require(host.controllerIdentity(for: .agentChat))
        host.updateContent(
            owner: ObjectIdentifier(owner),
            routeFactory: { route in AnyView(Text("updated-\(route.rawValue)")) }
        )
        host.activate(.agentChat)

        #expect(host.controllerIdentity(for: .agentChat) == identity)
    }

    @Test func changedContentOwnerInvalidatesEveryCachedController() throws {
        let placeholderOwner = ContentOwner()
        let liveOwner = ContentOwner()
        let host = makeHost(owner: placeholderOwner)

        host.activate(.agentChat)
        host.activate(.mail)
        let placeholderChatIdentity = try #require(host.controllerIdentity(for: .agentChat))
        let placeholderMailIdentity = try #require(host.controllerIdentity(for: .mail))

        host.updateContent(
            owner: ObjectIdentifier(liveOwner),
            routeFactory: { route in AnyView(Text("live-\(route.rawValue)")) }
        )

        #expect(host.cachedRoutes.isEmpty)
        #expect(host.activeRoute == nil)

        host.activate(.agentChat)
        host.activate(.mail)
        #expect(host.controllerIdentity(for: .agentChat) != placeholderChatIdentity)
        #expect(host.controllerIdentity(for: .mail) != placeholderMailIdentity)
    }

    @Test func cachePolicyEvictionIsDeterministic() {
        let policy = RetainedRouteCachePolicy.sidebar
        let candidate = policy.evictionCandidate(
            cachedRoutes: [.agentChat, .mail, .rss, .calendar],
            coldRoutesByRecency: [.calendar],
            activating: .contacts
        )
        #expect(candidate == .calendar)
        #expect(policy.evictionCandidate(
            cachedRoutes: [.agentChat, .mail, .rss],
            coldRoutesByRecency: [],
            activating: .calendar
        ) == nil)
    }

    private func makeHost(owner: ContentOwner = ContentOwner()) -> RetainedRouteHostController {
        RetainedRouteHostController(
            pane: .list,
            tracker: AppRoutePerformanceTracker(),
            contentOwner: ObjectIdentifier(owner),
            routeFactory: { route in AnyView(Text(route.rawValue)) }
        )
    }
}
