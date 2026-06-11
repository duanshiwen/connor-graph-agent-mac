import Foundation
import Testing
import ConnorGraphAppSupport

@Suite("Commercial Readiness Release Gate Tests")
struct CommercialReadinessReleaseGateTests {
    @Test func releaseGateAllowsCommercialReleaseWhenAllPhasesAreReady() {
        let generatedAt = Date(timeIntervalSince1970: 1_780_000_000)
        let dashboard = CommercialReadinessDashboard(cards: CommercialReadinessPhase.allCases.map { phase in
            CommercialReadinessCard(
                phase: phase,
                status: .ready,
                evidence: "ready"
            )
        })

        let result = CommercialReadinessReleaseGate().evaluate(dashboard, generatedAt: generatedAt)

        #expect(result.status == .ready)
        #expect(result.isCommercialReady)
        #expect(result.generatedAt == generatedAt)
        #expect(result.blockingCards.isEmpty)
        #expect(result.summary == "READY · 5/5 commercial readiness phases ready")
    }

    @Test func releaseGateBlocksCommercialReleaseWhenAnyPhaseIsBlocked() {
        let blocked = CommercialReadinessCard(
            phase: .claudeSDKSidecar,
            status: .blocked,
            evidence: "Claude SDK sidecar runtime has not been initialized"
        )
        let readyCards = CommercialReadinessPhase.allCases
            .filter { $0 != .claudeSDKSidecar }
            .map { CommercialReadinessCard(phase: $0, status: .ready, evidence: "ready") }
        let dashboard = CommercialReadinessDashboard(cards: readyCards + [blocked])

        let result = CommercialReadinessReleaseGate().evaluate(dashboard, generatedAt: Date(timeIntervalSince1970: 1_780_000_000))

        #expect(result.status == .blocked)
        #expect(!result.isCommercialReady)
        #expect(result.blockingCards.map(\.phase) == [.claudeSDKSidecar])
        #expect(result.summary == "BLOCKED · 4/5 commercial readiness phases ready · 1 blocked")
    }

    @Test func commandPaletteIncludesOneClickCommercialReadinessCheck() {
        let palette = ConnorCommandPalettePresentation.build(shell: .default)
        let matches = palette.search("commercial readiness")

        let command = matches.first { $0.id == "command.checkCommercialReadiness" }
        #expect(command?.title == "Check Commercial Readiness")
        #expect(command?.target == .productOS)
        #expect(command?.kind == .command)
        #expect(command?.systemImage == "checkmark.seal")
    }
}
