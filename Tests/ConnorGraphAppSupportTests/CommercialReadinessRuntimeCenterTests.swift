import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Commercial Readiness Runtime Center Tests")
struct CommercialReadinessRuntimeCenterTests {
    @Test func runtimeCenterIncludesCommercialReadinessWhenDashboardIsProvided() throws {
        let dashboard = CommercialReadinessDashboard(cards: [
            CommercialReadinessCard(phase: .sessionGovernance, status: .ready, evidence: "sessions ready"),
            CommercialReadinessCard(phase: .claudeSDKSidecar, status: .ready, evidence: "sidecar ready"),
            CommercialReadinessCard(phase: .sourcesSkillsAutomations, status: .blocked, evidence: "source missing", blockingReasons: ["source missing"]),
            CommercialReadinessCard(phase: .graphMemoryLoop, status: .ready, evidence: "graph ready"),
            CommercialReadinessCard(phase: .nativeCommercialUI, status: .ready, evidence: "ui ready")
        ])

        let presentation = ConnorRuntimeCenterPresentation.build(
            sessions: [],
            events: [],
            pendingApprovals: [],
            automationTriggers: [],
            graphMemoryDashboard: nil,
            commercialReadinessDashboard: dashboard,
            now: Date(timeIntervalSince1970: 10_000)
        )

        #expect(presentation.metricTiles.map(\.id).contains(.commercialReadiness))
        let readinessTile = try #require(presentation.metricTiles.first { $0.id == .commercialReadiness })
        #expect(readinessTile.value == "4/5")
        #expect(readinessTile.severity == .warning)
        #expect(readinessTile.target == .productOS)

        let readinessSection = try #require(presentation.sections.first { $0.id == .commercialReadiness })
        #expect(readinessSection.title == "Commercial Readiness")
        #expect(readinessSection.subtitle == "4/5 commercial readiness phases ready · 1 blocked")
        #expect(readinessSection.target == .productOS)
        #expect(readinessSection.items.map(\.title) == [
            "Phase 1 · Session Governance",
            "Phase 2 · Claude SDK Sidecar",
            "Phase 3 · Sources / Skills / Automations",
            "Phase 4 · Graph Memory Loop",
            "Phase 5 · Native Commercial UI"
        ])
        #expect(readinessSection.items[2].severity == .warning)
        #expect(readinessSection.items[2].detail == "source missing")
    }
}
