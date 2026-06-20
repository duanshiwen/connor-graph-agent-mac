import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Commercial Train 5 Native UI Commercialization Tests")
struct CommercialTrain5NativeUICommercializationTests {
    @Test func nativeShellExposesCommercialInformationArchitecture() {
        let shell = ConnorNativeShellPresentation.default

        #expect(shell.defaultSelection == .agentChat)
        #expect(shell.sidebarGroups.map(\.title) == ["Work", "Memory", "Governance", "Extensions", "System"])
        #expect(shell.item(for: .agentChat)?.isPrimary == true)
        #expect(shell.item(for: .approvals)?.riskLevel == .high)
        #expect(shell.item(for: .agentChat)?.emptyStateActionTitle == "New Session")
        #expect(shell.commands.first?.id == .newSession)
        #expect(shell.commands.filter(\.isPrimaryAction).count >= 5)
        #expect(shell.commands.filter { $0.keyboardShortcut != nil }.count >= 8)
    }

    @Test func nativeShellCommandsSupportGroupsRiskAndPrimaryActions() {
        let shell = ConnorNativeShellPresentation.default

        let readiness = shell.command(for: .checkCommercialReadiness)
        #expect(readiness?.groupID == "governance")
        #expect(readiness?.riskLevel == .medium)
        #expect(readiness?.isPrimaryAction == true)
        #expect(shell.command(for: .newSession)?.target == .agentChat)
        #expect(shell.command(for: .openApprovals)?.riskLevel == .high)
    }


    @Test func nativeCommercialUIPresentationAggregatesShellSettingsAndReadiness() {
        let readiness = CommercialReadinessDashboard(cards: [
            CommercialReadinessCard(phase: .sessionGovernance, status: .ready, evidence: "ok"),
            CommercialReadinessCard(phase: .nativeCommercialUI, status: .ready, evidence: "ui ok")
        ])
        let presentation = ConnorNativeCommercialUIPresentation.build(readinessDashboard: readiness)

        #expect(presentation.hero.status == .ready)
        #expect(presentation.workspaceCards.map(\.target).contains(.agentChat))
        #expect(presentation.primaryActions.count >= 5)
        #expect(presentation.settings.sections.count >= 7)
        #expect(presentation.settings.commercialReadinessFieldCount >= 4)
        #expect(presentation.readinessLinked == true)
        #expect(presentation.emptyStateCount >= 3)
    }

    @Test func commercialReadinessGateUsesTrain5NativeUIEvidence() {
        let readiness = CommercialNativeUIReadiness.ready(
            shellItemCount: 10,
            commandCount: 9,
            settingsPanelsReady: true,
            homeSurfaceReady: true,
            readinessDashboardLinked: true,
            primaryActionCount: 5,
            emptyStateCount: 3,
            keyboardShortcutCount: 8,
            settingsSectionCount: 7
        )
        let input = CommercialReadinessInput(
            sessionGovernance: .ready(sessionCount: 1, statusDefinitionCount: 1, labelDefinitionCount: 1, artifactDirectoriesReady: true),
            modelProvider: .ready(providerMode: .anthropicMessages, connectionKind: .anthropicCompatible, modelID: "claude-sonnet-4-5", healthStatus: "ready"),
            extensionRuntime: .ready(enabledSourceCount: 1, loadedSkillCount: 1, enabledAutomationRuleCount: 1),
            graphMemory: .ready(pendingCandidateCount: 0, openHoldCount: 0, recentChangeCount: 0, contextReady: true, ingestionReady: true, distillationReady: true),
            nativeUI: readiness
        )

        let card = CommercialReadinessGate().evaluate(input).cards.first { $0.phase == .nativeCommercialUI }

        #expect(card?.status == .ready)
        #expect(card?.metrics["homeSurfaceReady"] == "true")
        #expect(card?.metrics["primaryActions"] == "5")
        #expect(card?.metrics["settingsSections"] == "7")
    }
}
