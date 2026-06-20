import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Commercial Readiness Gate Tests")
struct CommercialReadinessGateTests {
    @Test func readinessGateBuildsSevenPhaseCommercialDashboard() {
        let input = CommercialReadinessInput(
            sessionGovernance: .ready(
                sessionCount: 3,
                statusDefinitionCount: 7,
                labelDefinitionCount: 6,
                artifactDirectoriesReady: true
            ),
            modelProvider: .ready(
                providerMode: .anthropicMessages,
                connectionKind: .anthropicCompatible,
                modelID: "claude-sonnet-4-5",
                healthStatus: "ok"
            ),
            extensionRuntime: .ready(
                enabledSourceCount: 2,
                loadedSkillCount: 4,
                enabledAutomationRuleCount: 3
            ),
            graphMemory: .ready(
                pendingCandidateCount: 1,
                openHoldCount: 0,
                recentChangeCount: 5
            ),
            nativeUI: .ready(
                shellItemCount: 11,
                commandCount: 9,
                settingsPanelsReady: true
            )
        )

        let dashboard = CommercialReadinessGate().evaluate(input)

        #expect(dashboard.overallStatus == .ready)
        #expect(dashboard.cards.map(\.phase) == [
            .sessionGovernance,
            .nativeModelProviders,
            .sourcesSkillsAutomations,
            .graphMemoryLoop,
            .nativeCommercialUI,
            .localAPICLIAutomationSurface,
            .nativeMailSystem
        ])
        #expect(dashboard.cards.allSatisfy { $0.status == .ready })
        #expect(dashboard.cards[0].title == "Phase 1 · Session Governance")
        #expect(dashboard.cards[1].evidence.contains("anthropic_messages"))
        #expect(dashboard.cards[1].evidence.contains("claude-sonnet-4-5"))
        #expect(dashboard.cards[2].metrics == ["sources": "2", "skills": "4", "automations": "3"])
        #expect(dashboard.cards[3].target == .graphMemory)
        #expect(dashboard.cards[4].target == .settings)
        #expect(dashboard.cards[5].target == .localAutomationSurface)
        #expect(dashboard.cards[6].target == .mail)
        #expect(dashboard.summary == "7/7 commercial readiness phases ready")
    }

    @Test func readinessGateReportsBlockedWhenRequiredPhaseIsMissing() {
        let input = CommercialReadinessInput(
            sessionGovernance: .missing("No persisted session repository configured"),
            modelProvider: .ready(providerMode: .anthropicMessages, connectionKind: .anthropicCompatible, modelID: "claude-sonnet-4-5", healthStatus: "ok"),
            extensionRuntime: .missing("No enabled source runtime"),
            graphMemory: .ready(pendingCandidateCount: 0, openHoldCount: 0, recentChangeCount: 0),
            nativeUI: .ready(shellItemCount: 10, commandCount: 8, settingsPanelsReady: false)
        )

        let dashboard = CommercialReadinessGate().evaluate(input)

        #expect(dashboard.overallStatus == .blocked)
        #expect(dashboard.readyCount == 5)
        #expect(dashboard.blockedCount == 2)
        #expect(dashboard.cards.filter { $0.status == .blocked }.map(\.phase) == [.sessionGovernance, .sourcesSkillsAutomations])
        #expect(dashboard.cards.first?.blockingReasons == ["No persisted session repository configured"])
        #expect(dashboard.summary == "5/7 commercial readiness phases ready · 2 blocked")
    }
}
