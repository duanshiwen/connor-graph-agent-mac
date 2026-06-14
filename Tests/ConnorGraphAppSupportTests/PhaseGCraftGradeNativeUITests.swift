import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Phase G Craft-grade Native UI Tests")
struct PhaseGCraftGradeNativeUITests {
    @Test func nativeShellBuildsCraftGradeSidebarGroupsAndCommands() {
        let shell = ConnorNativeShellPresentation.default

        #expect(shell.title == "康纳同学")
        #expect(shell.defaultSelection == .agentChat)
        #expect(shell.sidebarGroups.map(\.title) == ["Work", "Memory", "Governance", "Extensions", "System"])
        #expect(shell.sidebarGroups.flatMap(\.items).map(\.id).prefix(5) == [
            ConnorNativeShellItem.agentChat,
            .browserWorkspace,
            .graphMemory,
            .search,
            .graphEntities
        ])
        #expect(shell.sidebarGroups.flatMap(\.items).allSatisfy { !$0.title.isEmpty && !$0.systemImage.isEmpty })
        #expect(shell.commands.map(\.id) == [
            .newSession,
            .toggleBrowser,
            .openGraphMemoryReview,
            .openApprovals,
            .openSources,
            .openSkills,
            .openAutomation,
            .openLocalAutomationSurface,
            .checkCommercialReadiness,
            .openSettings
        ])
        #expect(shell.commands.first?.keyboardShortcut == "⌘N")
        #expect(shell.commands[2].target == .graphMemory)
    }

    @Test func nativeShellFindsItemsByIdentifierForDeepLinks() {
        let shell = ConnorNativeShellPresentation.default

        #expect(shell.item(for: .graphMemory)?.title == "Graph Memory")
        #expect(shell.item(for: .automation)?.badgeStyle == .warning)
        #expect(shell.command(for: .openSettings)?.target == .settings)
    }

    @Test func nativeShellRouteResolverMapsCraftItemsToAppRoutes() {
        let resolver = ConnorNativeShellRouteResolver()

        #expect(resolver.route(for: .agentChat).legacySidebarID == "agentChat")
        #expect(resolver.route(for: .graphMemory).legacySidebarID == "graphWriteCandidates")
        #expect(resolver.route(for: .approvals).legacySidebarID == "pendingApprovals")
        #expect(resolver.route(for: .settings).legacySidebarID == "llmSettings")
        #expect(resolver.route(for: .browserWorkspace).requiresBrowserVisible == true)
        #expect(resolver.route(for: .sources).legacySidebarID == "sources")
        #expect(resolver.route(for: .skills).legacySidebarID == "skills")
        #expect(resolver.route(for: .sources).isPlaceholder == false)
        #expect(resolver.route(for: .skills).isPlaceholder == false)
    }

}
