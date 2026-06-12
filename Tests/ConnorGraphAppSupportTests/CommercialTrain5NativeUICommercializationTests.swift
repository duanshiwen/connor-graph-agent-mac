import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Commercial Train 5 Native UI Commercialization Tests")
struct CommercialTrain5NativeUICommercializationTests {
    @Test func nativeShellExposesCommercialInformationArchitecture() {
        let shell = ConnorNativeShellPresentation.default

        #expect(shell.defaultSelection == .home)
        #expect(shell.sidebarGroups.map(\.title) == ["Home", "Work", "Memory", "Governance", "Extensions", "System"])
        #expect(shell.item(for: .home)?.isPrimary == true)
        #expect(shell.item(for: .approvals)?.riskLevel == .high)
        #expect(shell.item(for: .agentChat)?.emptyStateActionTitle == "New Session")
        #expect(shell.commands.first?.id == .openHome)
        #expect(shell.commands.filter(\.isPrimaryAction).count >= 6)
        #expect(shell.commands.filter { $0.keyboardShortcut != nil }.count >= 9)
    }

    @Test func commandPaletteSupportsGroupsRiskAndPrimaryActions() {
        let palette = ConnorCommandPalettePresentation.build(shell: .default)

        let readiness = palette.search("readiness").first { $0.id == "command.checkCommercialReadiness" }
        #expect(readiness?.groupID == "governance")
        #expect(readiness?.riskLevel == .medium)
        #expect(readiness?.isPrimaryAction == true)
        #expect(palette.search("approval").contains { $0.target == .approvals && $0.riskLevel == .high })
        #expect(palette.search("runtime dashboard").first?.target == .home)
    }

    @Test func runtimeCenterBuildsNextBestActionsForCommercialHome() {
        let now = Date(timeIntervalSince1970: 10_000)
        let approval = AgentPendingApproval(
            id: "approval-1",
            requestID: "permission-1",
            runID: "run-1",
            sessionID: "session-1",
            capability: .commitGraphWrite,
            toolName: "graph.commit"
        )
        let memoryDashboard = GraphMemoryDashboard(
            summary: GraphMemoryDashboardSummary(pendingCandidateCount: 1, openHoldCount: 1, recentChangeCount: 0),
            cards: []
        )
        let readiness = CommercialReadinessDashboard(cards: [
            CommercialReadinessCard(phase: .sessionGovernance, status: .ready, evidence: "ok"),
            CommercialReadinessCard(phase: .nativeCommercialUI, status: .blocked, evidence: "needs UI", blockingReasons: ["needs UI"])
        ])

        let center = ConnorRuntimeCenterPresentation.build(
            sessions: [],
            events: [],
            pendingApprovals: [approval],
            automationTriggers: [],
            graphMemoryDashboard: memoryDashboard,
            commercialReadinessDashboard: readiness,
            now: now
        )

        #expect(center.hero.title == "Connor Runtime Center")
        #expect(center.metricTiles.map(\.id).contains(.nativeUIHealth))
        #expect(center.sections.first?.id == .nextBestActions)
        #expect(center.nextBestActions.map(\.id).contains("next.approvals"))
        #expect(center.nextBestActions.map(\.id).contains("next.memory"))
        #expect(center.nextBestActions.map(\.id).contains("next.readiness"))
    }

    @Test func nativeCommercialUIPresentationAggregatesShellSettingsAndReadiness() {
        let readiness = CommercialReadinessDashboard(cards: [
            CommercialReadinessCard(phase: .sessionGovernance, status: .ready, evidence: "ok"),
            CommercialReadinessCard(phase: .nativeCommercialUI, status: .ready, evidence: "ui ok")
        ])
        let presentation = ConnorNativeCommercialUIPresentation.build(readinessDashboard: readiness)

        #expect(presentation.hero.status == .ready)
        #expect(presentation.workspaceCards.map(\.target).contains(.home))
        #expect(presentation.primaryActions.count >= 6)
        #expect(presentation.settings.sections.count >= 7)
        #expect(presentation.settings.commercialReadinessFieldCount >= 4)
        #expect(presentation.readinessLinked == true)
        #expect(presentation.emptyStateCount >= 3)
    }

    @Test func commercialReadinessGateUsesTrain5NativeUIEvidence() {
        let readiness = CommercialNativeUIReadiness.ready(
            shellItemCount: 11,
            commandCount: 10,
            settingsPanelsReady: true,
            homeSurfaceReady: true,
            runtimeCenterReady: true,
            commandPaletteReady: true,
            readinessDashboardLinked: true,
            primaryActionCount: 6,
            emptyStateCount: 4,
            keyboardShortcutCount: 9,
            settingsSectionCount: 7
        )
        let input = CommercialReadinessInput(
            sessionGovernance: .ready(sessionCount: 1, statusDefinitionCount: 1, labelDefinitionCount: 1, artifactDirectoriesReady: true),
            claudeSidecar: .ready(runtimeStatus: .ready, sdkSessionID: "sdk", healthStatus: "ready"),
            extensionRuntime: .ready(enabledSourceCount: 1, loadedSkillCount: 1, enabledAutomationRuleCount: 1),
            graphMemory: .ready(pendingCandidateCount: 0, openHoldCount: 0, recentChangeCount: 0, contextReady: true, ingestionReady: true, distillationReady: true),
            nativeUI: readiness
        )

        let card = CommercialReadinessGate().evaluate(input).cards.first { $0.phase == .nativeCommercialUI }

        #expect(card?.status == .ready)
        #expect(card?.metrics["homeSurfaceReady"] == "true")
        #expect(card?.metrics["primaryActions"] == "6")
        #expect(card?.metrics["settingsSections"] == "7")
    }
}
