import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("Phase E Automation Engine Tests")
struct PhaseEAutomationEngineTests {
    @Test func automationEngineBuildsGovernedActionPlanFromMatchingRules() throws {
        let root = temporaryPhaseERoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppProductOSAutomationRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let rule = ProductOSAutomationRule(
            id: "needs-review-plan",
            name: "Needs Review Plan",
            trigger: ProductOSAutomationTrigger(kind: .sessionStatusChanged, status: .needsReview),
            actions: [
                ProductOSAutomationAction(kind: .appendTimelineEvent, message: "Record review timeline entry."),
                ProductOSAutomationAction(kind: .addSessionLabel, label: AgentSessionLabel(id: "graph-review"), message: "Suggest graph review label.")
            ],
            requiresReview: true
        )
        try repository.save(ProductOSAutomationConfig(rules: [rule]))
        let engine = AutomationEngine(repository: repository)

        let run = try engine.evaluate(context: ProductOSAutomationEventContext(
            triggerKind: .sessionStatusChanged,
            sessionID: "session-1",
            status: .needsReview
        ))

        #expect(run.matchedRules.map(\.id) == ["needs-review-plan"])
        #expect(run.actionPlans.count == 2)
        #expect(run.actionPlans.allSatisfy { $0.disposition == .pendingReview })
        #expect(run.actionPlans.map(\.action.kind) == [.appendTimelineEvent, .addSessionLabel])
        #expect(run.events.count == 1)
        #expect(run.events.first?.kind == .automationTriggered)
        #expect(run.records.first?.ruleID == "needs-review-plan")
    }

    @Test func automationEngineMarksNonReviewSafeActionsReady() throws {
        let root = temporaryPhaseERoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppProductOSAutomationRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let rule = ProductOSAutomationRule(
            id: "important-note",
            name: "Important Note",
            trigger: ProductOSAutomationTrigger(kind: .sessionLabelAdded, labelID: "important"),
            actions: [ProductOSAutomationAction(kind: .appendTimelineEvent, message: "Important label changed.")],
            requiresReview: false
        )
        try repository.save(ProductOSAutomationConfig(rules: [rule]))
        let engine = AutomationEngine(repository: repository)

        let run = try engine.evaluate(context: ProductOSAutomationEventContext(
            triggerKind: .sessionLabelAdded,
            sessionID: "session-1",
            labelID: "important"
        ))

        #expect(run.actionPlans.map(\.disposition) == [.ready])
        #expect(run.records.first?.requiresReview == false)
    }

    @Test func automationEngineReturnsEmptyRunForNoMatches() throws {
        let root = temporaryPhaseERoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppProductOSAutomationRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let engine = AutomationEngine(repository: repository)

        let run = try engine.evaluate(context: ProductOSAutomationEventContext(
            triggerKind: .sessionStatusChanged,
            sessionID: "session-1",
            status: .done
        ))

        #expect(run.matchedRules.isEmpty)
        #expect(run.actionPlans.isEmpty)
        #expect(run.events.isEmpty)
        #expect(run.records.isEmpty)
    }
}

private func temporaryPhaseERoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("phase-e-\(UUID().uuidString)", isDirectory: true)
}
