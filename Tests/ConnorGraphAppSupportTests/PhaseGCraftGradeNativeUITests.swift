import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Phase G Craft-grade Native UI Tests")
struct PhaseGCraftGradeNativeUITests {
    @Test func nativeShellBuildsCraftGradeSidebarGroupsAndCommands() {
        let shell = ConnorNativeShellPresentation.default

        #expect(shell.title == "Connor")
        #expect(shell.defaultSelection == .runtimeCenter)
        #expect(shell.sidebarGroups.map(\.title) == ["Run", "Memory", "Governance", "System"])
        #expect(shell.sidebarGroups.flatMap(\.items).map(\.id).prefix(5) == [
            ConnorNativeShellItem.runtimeCenter,
            .agentChat,
            .browserWorkspace,
            .graphMemory,
            .search
        ])
        #expect(shell.sidebarGroups.flatMap(\.items).allSatisfy { !$0.title.isEmpty && !$0.systemImage.isEmpty })
        #expect(shell.commands.map(\.id) == [
            .newSession,
            .toggleBrowser,
            .openRuntimeCenter,
            .openGraphMemoryReview,
            .openApprovals,
            .openSettings
        ])
        #expect(shell.commands.first?.keyboardShortcut == "⌘N")
        #expect(shell.commands[2].target == .runtimeCenter)
    }

    @Test func nativeShellFindsItemsByIdentifierForDeepLinks() {
        let shell = ConnorNativeShellPresentation.default

        #expect(shell.item(for: .graphMemory)?.title == "Graph Memory")
        #expect(shell.item(for: .automation)?.badgeStyle == .warning)
        #expect(shell.command(for: .openSettings)?.target == .settings)
    }

    @Test func nativeShellRouteResolverMapsCraftItemsToAppRoutes() {
        let resolver = ConnorNativeShellRouteResolver()

        #expect(resolver.route(for: .runtimeCenter).legacySidebarID == "runtimeCenter")
        #expect(resolver.route(for: .agentChat).legacySidebarID == "agentChat")
        #expect(resolver.route(for: .graphMemory).legacySidebarID == "graphWriteCandidates")
        #expect(resolver.route(for: .approvals).legacySidebarID == "pendingApprovals")
        #expect(resolver.route(for: .settings).legacySidebarID == "llmSettings")
        #expect(resolver.route(for: .browserWorkspace).requiresBrowserVisible == true)
        #expect(resolver.route(for: .sources).isPlaceholder == true)
        #expect(resolver.route(for: .skills).placeholderTitle == "Skills runtime UI is not wired yet")
    }

    @Test func runtimeCenterAggregatesSessionsEventsApprovalsAutomationAndMemory() {
        let now = Date(timeIntervalSince1970: 10_000)
        let session = AgentSession(
            id: "session-1",
            title: "Production hardening",
            createdAt: now.addingTimeInterval(-600),
            updatedAt: now.addingTimeInterval(-60),
            governance: AgentSessionGovernanceMetadata(status: .inProgress)
        )
        let approval = AgentPendingApproval(
            id: "approval-1",
            requestID: "permission-1",
            runID: "run-1",
            sessionID: "session-1",
            capability: .commitGraphWrite,
            toolName: "graph.commit"
        )
        let automation = ProductOSAutomationTriggerRecord(
            id: "automation-1",
            ruleID: "rule-1",
            ruleName: "Archive done sessions",
            trigger: .sessionStatusChanged,
            sessionID: "session-1",
            actionSummaries: ["setSessionStatus(done)"],
            requiresReview: false,
            createdAt: now
        )
        let memoryDashboard = GraphMemoryDashboard(
            summary: GraphMemoryDashboardSummary(pendingCandidateCount: 2, openHoldCount: 1, recentChangeCount: 3),
            cards: [GraphMemoryProductCard(
                id: "memory-card-1",
                kind: .admissionHold,
                title: "Missing evidence",
                detail: "Need grounding",
                severity: .needsReview,
                createdAt: now
            )]
        )
        let event = AgentEvent.graphMemoryHeld(AgentGraphMemoryLifecycleEvent(
            runID: "run-1",
            sessionID: "session-1",
            memoryID: "memory-card-1",
            message: "Need grounding"
        ))

        let center = ConnorRuntimeCenterPresentation.build(
            sessions: [session],
            events: [AgentEventPresenter().presentation(for: event)],
            pendingApprovals: [approval],
            automationTriggers: [automation],
            graphMemoryDashboard: memoryDashboard,
            now: now
        )

        #expect(center.hero.title == "Production hardening")
        #expect(center.hero.statusText == "in_progress")
        #expect(center.metricTiles.map(\.id) == [.activeSessions, .pendingApprovals, .memoryReviews, .automationTriggers])
        #expect(center.metricTiles.map(\.value) == ["1", "1", "3", "1"])
        #expect(center.sections.map(\.id) == [.runTimeline, .reviewQueue, .graphMemory, .automation])
        #expect(center.sections[0].items.first?.title == "Graph memory held")
        #expect(center.sections[1].items.first?.severity == .warning)
        #expect(center.sections[2].items.first?.subtitle == "admissionHold · needsReview")
    }
}
