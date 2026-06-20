import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Commercial Readiness Snapshot Builder Tests")
struct CommercialReadinessSnapshotBuilderTests {
    @Test func snapshotBuilderAggregatesExistingRuntimeObjectsIntoReadinessInput() {
        let session = AgentSession(id: "session-1", title: "Commercial Session")
        let source = MCPSourceRuntimeConfiguration(
            sourceID: "linear",
            displayName: "Linear",
            transport: .stdio(command: "npx", arguments: []),
            status: .enabled,
            credentialRequirement: .apiKeyHeader,
            allowedCapabilities: [.readSession, .externalNetwork],
            toolNamePrefix: "linear"
        )
        let skill = SkillRuntimeDefinition(
            slug: "superpowers",
            scope: .home,
            manifest: SkillRuntimeManifest(
                name: "Superpowers",
                description: "TDD workflow",
                triggers: [.manual],
                requiredCapabilities: [.readSession]
            ),
            instructions: "Use disciplined TDD.",
            skillURL: URL(fileURLWithPath: "/tmp/SKILL.md")
        )
        let automation = ProductOSAutomationConfig(rules: [
            ProductOSAutomationRule(
                id: "rule-1",
                name: "Review",
                trigger: ProductOSAutomationTrigger(kind: .sessionStatusChanged, status: .needsReview),
                actions: [ProductOSAutomationAction(kind: .appendTimelineEvent, message: "review")]
            )
        ])
        let graphDashboard = GraphMemoryDashboard(
            summary: GraphMemoryDashboardSummary(pendingCandidateCount: 2, openHoldCount: 1, recentChangeCount: 3),
            cards: []
        )

        let input = CommercialReadinessSnapshotBuilder().build(
            sessions: [session],
            governanceConfig: .default,
            artifactDirectoriesReady: true,
            modelProvider: .ready(
                providerMode: .anthropicMessages,
                connectionKind: .anthropicCompatible,
                modelID: "claude-sonnet-4-5",
                healthStatus: "ok"
            ),
            sources: [source],
            skills: [skill],
            automationConfig: automation,
            graphMemoryDashboard: graphDashboard,
            shell: .default,
            settingsPanelsReady: true
        )
        let dashboard = CommercialReadinessGate().evaluate(input)

        #expect(dashboard.overallStatus == .ready)
        #expect(dashboard.cards[0].metrics["sessions"] == "1")
        #expect(dashboard.cards[1].evidence.contains("anthropic_messages"))
        #expect(dashboard.cards[1].evidence.contains("claude-sonnet-4-5"))
        #expect(dashboard.cards[2].metrics == ["sources": "1", "skills": "1", "automations": "1"])
        #expect(dashboard.cards[3].metrics == ["candidates": "2", "holds": "1", "changes": "3"])
        #expect(dashboard.cards[4].metrics["settings"] == "ready")
    }

    @Test func snapshotBuilderMarksMissingCriticalCommercialSubsystemsAsBlocked() {
        let input = CommercialReadinessSnapshotBuilder().build(
            sessions: [],
            governanceConfig: .default,
            artifactDirectoriesReady: false,
            modelProvider: .missing("Native model provider has not been configured"),
            sources: [],
            skills: [],
            automationConfig: ProductOSAutomationConfig(rules: []),
            graphMemoryDashboard: nil,
            shell: .default,
            settingsPanelsReady: false
        )
        let dashboard = CommercialReadinessGate().evaluate(input)

        #expect(dashboard.overallStatus == .blocked)
        let blockedPhases = dashboard.cards.filter { $0.status == .blocked }.map(\.phase)
        #expect(blockedPhases == [
            .sessionGovernance,
            .nativeModelProviders,
            .sourcesSkillsAutomations,
            .graphMemoryLoop,
            .nativeCommercialUI
        ])
        #expect(dashboard.cards[4].status == .blocked)
        #expect(dashboard.cards[4].metrics["settings"] == "partial")
        #expect(dashboard.cards.last?.phase == .nativeMailSystem)
        #expect(dashboard.cards.last?.status == .ready)
    }
}
