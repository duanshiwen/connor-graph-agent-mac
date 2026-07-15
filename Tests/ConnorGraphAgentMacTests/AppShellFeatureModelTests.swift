import Foundation
import Testing
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@MainActor
@Test func shellNavigationPreservesHiddenMemoryOSFallbackAndVisibleRoutes() {
    let model = AppShellFeatureModel()

    model.applyNavigation(.graphMemory)
    #expect(model.selection == .agentChat)

    let routes: [(ConnorNativeShellItem, SidebarItem)] = [
        (.search, .search),
        (.graphEntities, .entities),
        (.approvals, .pendingApprovals),
        (.automation, .scheduledTasks),
        (.productOS, .productOS),
        (.calendar, .calendar),
        (.contacts, .contacts),
        (.mail, .mail),
        (.rss, .rss),
        (.sources, .sources),
        (.skills, .skills),
        (.settings, .llmSettings)
    ]
    for (route, selection) in routes {
        model.applyNavigation(route)
        #expect(model.selection == selection)
    }
}

@MainActor
@Test func shellSettingsAndFocusHaveNarrowStateOwnership() {
    let model = AppShellFeatureModel()

    #expect(model.focusTopSearchRequestID == nil)
    model.requestTopSearchFocus()
    let firstRequest = model.focusTopSearchRequestID
    model.requestTopSearchFocus()

    #expect(firstRequest != nil)
    #expect(model.focusTopSearchRequestID != firstRequest)

    model.selectSettingsSection(.calendar)
    #expect(model.shellFeatureModel.selectedSettingsSection == .calendar)
    #expect(model.selection == .llmSettings)
}

@MainActor
@Test func appCommandRouterForwardsTypedCommandsExactlyOnce() {
    var commands: [AppCommand] = []
    let router = AppCommandRouter { commands.append($0) }
    let request = RSSFollowRequest(
        itemID: "rss-item",
        title: "Example",
        url: URL(string: "https://example.com")!
    )

    router.send(.shortcut(.newSession))
    router.send(.newNote)
    router.send(.selectSidebar(.contacts))
    router.send(.navigate(.rss))
    router.send(.openSessionNotification("session-1"))
    router.send(.openCalendarSettings)
    router.send(.followRSSItem(request))

    #expect(commands == [
        .shortcut(.newSession),
        .newNote,
        .selectSidebar(.contacts),
        .navigate(.rss),
        .openSessionNotification("session-1"),
        .openCalendarSettings,
        .followRSSItem(request)
    ])
}
