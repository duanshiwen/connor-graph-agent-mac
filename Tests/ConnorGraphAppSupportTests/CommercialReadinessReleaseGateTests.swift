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
        #expect(result.summary == "BLOCKED · 6/7 commercial readiness phases ready · 1 blocked")
    }

    @Test func nativeLocalWorkspaceToolSurfaceHasCommercialGuardrails() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-readiness-local-tools-")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let policy = LocalWorkspacePolicy(workingDirectory: workspace)
        let tools: [any AgentTool] = [
            LocalReadFileTool(policy: policy),
            LocalListDirectoryTool(policy: policy),
            LocalGlobTool(policy: policy),
            LocalGrepTool(policy: policy),
            LocalWriteFileTool(policy: policy),
            LocalEditFileTool(policy: policy),
            LocalMultiEditTool(policy: policy),
            LocalBashTool(policy: policy)
        ]

        #expect(tools.map(\.name) == ["Read", "LS", "Glob", "Grep", "Write", "Edit", "MultiEdit", "Bash"])
        #expect(tools.map(\.permission).contains(.readWorkspaceFile))
        #expect(tools.map(\.permission).contains(.writeWorkspaceFile))
        #expect(tools.map(\.permission).contains(.editWorkspaceFile))
        #expect(LocalShellCommandPolicy.classify("sudo rm -rf /").risk == .destructive)
        #expect(throws: LocalWorkspacePolicyError.self) {
            try policy.validateWritablePath(workspace.appendingPathComponent(".env"), operation: .overwriteFile)
        }
    }

    @Test func nativeShellIncludesOneClickCommercialReadinessCheck() {
        let command = ConnorNativeShellPresentation.default.command(for: .checkCommercialReadiness)

        #expect(command?.title == "Check Commercial Readiness")
        #expect(command?.target == .productOS)
        #expect(command?.systemImage == "checkmark.seal")
        #expect(command?.isPrimaryAction == true)
    }
}
