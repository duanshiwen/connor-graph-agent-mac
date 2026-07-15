import SwiftUI
import Testing
@testable import ConnorGraphAgentMac

@MainActor
struct RetainedRouteHostControllerTests {
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

    private func makeHost() -> RetainedRouteHostController {
        RetainedRouteHostController(
            pane: .list,
            tracker: AppRoutePerformanceTracker(),
            routeFactory: { route in AnyView(Text(route.rawValue)) }
        )
    }
}
