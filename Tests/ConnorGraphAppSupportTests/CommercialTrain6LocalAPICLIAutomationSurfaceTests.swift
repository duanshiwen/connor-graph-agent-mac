import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Commercial Train 6 Local API CLI Automation Surface Tests")
struct CommercialTrain6LocalAPICLIAutomationSurfaceTests {
    @Test func localAPICatalogExposesGovernedRoutes() {
        let presentation = ConnorLocalAutomationSurfacePresentation.default

        #expect(presentation.endpoints.count >= 8)
        #expect(presentation.endpoints.contains { $0.id == .readiness && $0.method == .get })
        #expect(presentation.endpoints.contains { $0.id == .automationEvaluate && $0.riskLevel == .reviewRequired })
        #expect(presentation.endpoints.contains { $0.id == .automationExecuteReviewed && $0.requiresReview })
        #expect(presentation.endpoints.allSatisfy { $0.authMode == .localProcess })
        #expect(presentation.localOnly)
    }

    @Test func cliCatalogMapsCommandsToLocalAPIRoutes() throws {
        let commands = ConnorLocalAutomationSurfaceCatalog.defaultCommands

        #expect(commands.contains { $0.id == .readiness && $0.apiRoute == .readiness })
        #expect(commands.contains { $0.id == .automationEvaluate && $0.apiRoute == .automationEvaluate })
        let execute = try #require(commands.first { $0.id == .automationExecuteReviewed })
        #expect(execute.riskLevel == .stateChanging)
        #expect(execute.requiresReview)
        #expect(execute.usage.contains("--reviewed"))
    }

    @Test func automationDryRunEvaluationProducesGovernedPlanWithoutExecution() {
        let request = ConnorAutomationSurfaceTriggerRequest(
            triggerKind: .sessionLabelAdded,
            sessionID: "session-1",
            labelID: "important",
            dryRun: true
        )
        let evaluation = ConnorAutomationSurfaceEvaluator().evaluate(request: request, config: .default)

        #expect(evaluation.matchedRuleIDs == ["important-label-adds-review-note"])
        #expect(evaluation.actionPlans.count == 1)
        #expect(evaluation.pendingReviewActionCount == 0)
        #expect(evaluation.canExecuteWithoutReview)
        #expect(evaluation.auditSummary.contains("dry-run"))
    }

    @Test func reviewedExecutionGateBlocksUnreviewedAndKeepsPendingReviewBlocked() throws {
        let request = ConnorAutomationSurfaceTriggerRequest(
            triggerKind: .sessionLabelAdded,
            sessionID: "session-1",
            labelID: "important",
            dryRun: true
        )
        let evaluator = ConnorAutomationSurfaceEvaluator()
        let evaluation = evaluator.evaluate(request: request, config: .default)

        let unreviewedGate = evaluator.executionGate(for: evaluation, reviewed: false)
        #expect(unreviewedGate.status == .reviewRequired)
        #expect(unreviewedGate.executablePlanIDs.isEmpty)
        #expect(unreviewedGate.blockedPlanIDs.count == evaluation.actionPlans.count)

        let reviewedGate = evaluator.executionGate(for: evaluation, reviewed: true)
        #expect(reviewedGate.status == .stateChanging)
        #expect(reviewedGate.executablePlanIDs.count == evaluation.actionPlans.count)
        #expect(reviewedGate.blockedPlanIDs.isEmpty)
    }


    @Test func commercialReadinessGateIncludesTrain6LocalAutomationSurfacePhase() {
        let input = CommercialReadinessInput(
            sessionGovernance: .ready(sessionCount: 1, statusDefinitionCount: 5, labelDefinitionCount: 5, artifactDirectoriesReady: true),
            claudeSidecar: .ready(runtimeStatus: .ready, sdkSessionID: "sdk-1", healthStatus: "ok"),
            extensionRuntime: .ready(enabledSourceCount: 1, loadedSkillCount: 1, enabledAutomationRuleCount: 2),
            graphMemory: .ready(pendingCandidateCount: 0, openHoldCount: 0, recentChangeCount: 1, contextReady: true, ingestionReady: true, distillationReady: true),
            nativeUI: .ready(shellItemCount: 12, commandCount: 11, settingsPanelsReady: true, homeSurfaceReady: true, commandPaletteReady: true, readinessDashboardLinked: true, primaryActionCount: 6, emptyStateCount: 4, keyboardShortcutCount: 10, settingsSectionCount: 7),
            localAutomationSurface: .ready(endpointCount: 8, cliCommandCount: 10, automationTriggerCount: 7, dryRunEvaluationReady: true, reviewedExecutionGateReady: true, auditSurfaceReady: true, localOnly: true)
        )

        let dashboard = CommercialReadinessGate().evaluate(input)

        #expect(dashboard.cards.map(\.phase).contains(.localAPICLIAutomationSurface))
        #expect(dashboard.cards.count == 6)
        #expect(dashboard.overallStatus == .ready)
        #expect(dashboard.summary == "6/6 commercial readiness phases ready")
    }

    @Test func localAutomationSurfaceBlocksReadinessWhenExecutionGateIsUnsafe() {
        let input = CommercialReadinessInput(
            sessionGovernance: .ready(sessionCount: 1, statusDefinitionCount: 5, labelDefinitionCount: 5, artifactDirectoriesReady: true),
            claudeSidecar: .ready(runtimeStatus: .ready, sdkSessionID: nil, healthStatus: "ok"),
            extensionRuntime: .ready(enabledSourceCount: 1, loadedSkillCount: 1, enabledAutomationRuleCount: 1),
            graphMemory: .ready(pendingCandidateCount: 0, openHoldCount: 0, recentChangeCount: 0, contextReady: true, ingestionReady: true, distillationReady: true),
            nativeUI: .ready(shellItemCount: 12, commandCount: 11, settingsPanelsReady: true, homeSurfaceReady: true, commandPaletteReady: true, readinessDashboardLinked: true, primaryActionCount: 6, emptyStateCount: 4, keyboardShortcutCount: 10, settingsSectionCount: 7),
            localAutomationSurface: .ready(endpointCount: 8, cliCommandCount: 10, automationTriggerCount: 7, dryRunEvaluationReady: true, reviewedExecutionGateReady: false, auditSurfaceReady: true, localOnly: false)
        )

        let card = try! #require(CommercialReadinessGate().evaluate(input).cards.first { $0.phase == .localAPICLIAutomationSurface })
        #expect(card.status == .blocked)
        #expect(card.blockingReasons.contains("Reviewed execution gate is not ready"))
        #expect(card.blockingReasons.contains("Local API surface must remain local-only in this phase"))
    }

    @Test func shellAndCommandPaletteExposeLocalAutomationSurface() {
        let shell = ConnorNativeShellPresentation.default
        let palette = ConnorCommandPalettePresentation.build(shell: shell)

        #expect(shell.item(for: .localAutomationSurface)?.title == "Local API / CLI")
        #expect(shell.command(for: .openLocalAutomationSurface)?.target == .localAutomationSurface)
        #expect(palette.search("cli automation").contains { $0.target == .localAutomationSurface })
    }
}
