import Foundation
import Testing
import ConnorGraphAgent
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
        #expect(result.summary == "READY · 7/7 commercial readiness phases ready")
    }

    @Test func releaseGateBlocksCommercialReleaseWhenAnyPhaseIsBlocked() {
        let blocked = CommercialReadinessCard(
            phase: .nativeModelProviders,
            status: .blocked,
            evidence: "Native model provider has not been configured"
        )
        let readyCards = CommercialReadinessPhase.allCases
            .filter { $0 != .nativeModelProviders }
            .map { CommercialReadinessCard(phase: $0, status: .ready, evidence: "ready") }
        let dashboard = CommercialReadinessDashboard(cards: readyCards + [blocked])

        let result = CommercialReadinessReleaseGate().evaluate(dashboard, generatedAt: Date(timeIntervalSince1970: 1_780_000_000))

        #expect(result.status == .blocked)
        #expect(!result.isCommercialReady)
        #expect(result.blockingCards.map(\.phase) == [.nativeModelProviders])
        #expect(result.summary == "BLOCKED · 6/7 commercial readiness phases ready · 1 blocked")
    }

    @Test func nativeLocalWorkspaceToolSurfaceHasCommercialGuardrails() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-readiness-local-tools-")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let policy = LocalWorkspacePolicy(workingDirectory: workspace)
        let tools: [any AgentTool] = [
            LocalShellTool(policy: policy),
            LocalApplyPatchTool(policy: policy)
        ]

        #expect(tools.map(\.name) == ["Shell", "ApplyPatch"])
        #expect(tools.map(\.permission).contains(.runReadOnlyShellCommand))
        #expect(tools.map(\.permission).contains(.editWorkspaceFile))
        #expect(LocalShellCommandPolicy.classify("sudo rm -rf /").risk == .destructive)
        #expect(throws: LocalWorkspacePolicyError.self) {
            try policy.validateWritablePath(workspace.appendingPathComponent(".env"), operation: .overwriteFile)
        }
    }

    @Test func nativeShellNoLongerBundlesOneClickCommercialReadinessCheck() {
        // Product OS 导航链移除后，一键商业就绪检查不再出现在默认命令列表中。
        let command = ConnorNativeShellPresentation.default.command(for: .checkCommercialReadiness)

        #expect(command == nil)
    }
}
