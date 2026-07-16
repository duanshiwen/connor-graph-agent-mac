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
@Test func shellSelectionIgnoresRepeatedRoute() {
    let model = AppShellFeatureModel()

    #expect(model.select(.agentChat) == false)
    #expect(model.selection == .agentChat)
    #expect(model.select(.mail) == true)
    #expect(model.selection == .mail)
    #expect(model.select(.mail) == false)
    #expect(model.selection == .mail)
}

@Test func primarySidebarUsesShellAsItsSingleSelectionWriter() throws {
    let source = try String(
        contentsOf: projectSourceURL(named: "AppPrimarySidebarView.swift"),
        encoding: .utf8
    )
    let selectionMethod = try #require(source.range(of: "private func select(_ item: SidebarItem)"))
    let suffix = source[selectionMethod.lowerBound...]
    let methodEnd = try #require(suffix.range(of: "\n    }"))
    let methodSource = suffix[..<methodEnd.upperBound]

    #expect(methodSource.contains("graph.shell.select(item)"))
    #expect(!methodSource.contains("selection = item"))
}

@Test func appSurfacesShareSemanticTypographyAndSpacingTokens() throws {
    let designSystem = try String(
        contentsOf: projectSourceURL(named: "AppShellDesignSystem.swift"),
        encoding: .utf8
    )
    let chatDesignSystem = try String(
        contentsOf: projectSourceURL(named: "AgentChatDesignSystem.swift"),
        encoding: .utf8
    )
    let browserDesignSystem = try String(
        contentsOf: projectSourceURL(named: "BrowserWorkspaceFloatingViews.swift"),
        encoding: .utf8
    )

    #expect(designSystem.contains("enum AppTypography"))
    #expect(designSystem.contains("static let body: Font = .body"))
    #expect(designSystem.contains("static let pageHorizontalPadding: CGFloat = 24"))
    #expect(chatDesignSystem.contains("static let body = AppTypography.body"))
    #expect(chatDesignSystem.contains("static let spaceM = AppShellLayout.spaceM"))
    #expect(browserDesignSystem.contains("static let messageBody = AppTypography.body"))
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
    #expect(model.selectedSettingsSection == .calendar)
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

private func projectSourceURL(named filename: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/ConnorGraphAgentMac")
        .appendingPathComponent(filename)
}
