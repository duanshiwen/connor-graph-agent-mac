import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Phase I Command Palette Deep-link Navigation Tests")
struct PhaseICommandPaletteNavigationTests {
    @Test func commandPaletteBuildsSearchableEntriesFromShellItemsAndCommands() {
        let palette = ConnorCommandPalettePresentation.build(shell: ConnorNativeShellPresentation.default)

        #expect(palette.entries.contains { $0.id == "command.newSession" && $0.kind == ConnorCommandPaletteEntryKind.command })
        #expect(palette.entries.contains { $0.id == "item.sources" && $0.kind == ConnorCommandPaletteEntryKind.destination })
        #expect(palette.entries.contains { $0.id == "item.skills" && $0.kind == ConnorCommandPaletteEntryKind.destination })
        #expect(palette.entries.contains { $0.id == "item.automation" && $0.kind == ConnorCommandPaletteEntryKind.destination })
        #expect(palette.entries.allSatisfy { $0.id != "command.openRuntimeCenter" })
        #expect(palette.search("source").map(\.target).contains(ConnorNativeShellItem.sources))
        #expect(palette.search("⌘N").first?.target == ConnorNativeShellItem.agentChat)
        #expect(palette.search("approval").contains { $0.target == ConnorNativeShellItem.approvals })
    }

    @Test func shellCommandsIncludeRuntimeSystemDestinationsForNativeMenuBinding() {
        let commands = ConnorNativeShellPresentation.default.commands
        let sources = commands.first { $0.id == ConnorNativeShellCommandID.openSources }
        let skills = commands.first { $0.id == ConnorNativeShellCommandID.openSkills }
        let automation = commands.first { $0.id == ConnorNativeShellCommandID.openAutomation }

        #expect(sources?.target == ConnorNativeShellItem.sources)
        #expect(sources?.keyboardShortcut == "⌘4")
        #expect(skills?.target == ConnorNativeShellItem.skills)
        #expect(skills?.keyboardShortcut == "⌘5")
        #expect(automation?.target == ConnorNativeShellItem.automation)
        #expect(automation?.keyboardShortcut == "⌘6")
    }

    @Test func deepLinkNavigatorResolvesSupportedConnorURLsToShellRoutes() throws {
        let navigator = ConnorDeepLinkNavigator(routeResolver: ConnorNativeShellRouteResolver())

        let sources = try navigator.resolve(URL(string: "connor://open/sources")!)
        let automation = try navigator.resolve(URL(string: "connor://open/automation?focus=history")!)
        let browser = try navigator.resolve(URL(string: "connor://open/browserWorkspace")!)

        #expect(sources.item == ConnorNativeShellItem.sources)
        #expect(sources.sidebarItem == "sources")
        #expect(sources.focus == nil)
        #expect(automation.item == ConnorNativeShellItem.automation)
        #expect(automation.focus == "history")
        #expect(browser.requiresBrowserVisible == true)
    }

    @Test func runtimeCenterMetricAndSectionsExposeClickThroughDestinations() {
        let now = Date(timeIntervalSince1970: 10_000)
        let approval = AgentPendingApproval(
            requestID: "request-1",
            runID: "run-1",
            sessionID: "session-1",
            capability: .externalNetwork,
            toolName: "linear.list_issues",
            payloadJSON: "{}",
            status: .pending,
            createdAt: now,
            updatedAt: now
        )
        let trigger = ProductOSAutomationTriggerRecord(
            id: "trigger-1",
            ruleID: "rule-1",
            ruleName: "Rule One",
            trigger: .sessionStatusChanged,
            sessionID: "session-1",
            actionSummaries: ["append timeline"],
            requiresReview: true
        )
        let presentation = ConnorRuntimeCenterPresentation.build(
            sessions: [],
            events: [],
            pendingApprovals: [approval],
            automationTriggers: [trigger],
            graphMemoryDashboard: nil,
            now: now
        )

        let pendingApprovalsTile = presentation.metricTiles.first { $0.id == ConnorRuntimeMetricID.pendingApprovals }
        let automationTile = presentation.metricTiles.first { $0.id == ConnorRuntimeMetricID.automationTriggers }
        let reviewSection = presentation.sections.first { $0.id == ConnorRuntimeSectionID.reviewQueue }
        let automationSection = presentation.sections.first { $0.id == ConnorRuntimeSectionID.automation }

        #expect(pendingApprovalsTile?.target == ConnorNativeShellItem.approvals)
        #expect(automationTile?.target == ConnorNativeShellItem.automation)
        #expect(reviewSection?.target == ConnorNativeShellItem.approvals)
        #expect(automationSection?.target == ConnorNativeShellItem.automation)
        #expect(reviewSection?.items.first?.target == ConnorNativeShellItem.approvals)
        #expect(automationSection?.items.first?.target == ConnorNativeShellItem.automation)
    }
}
