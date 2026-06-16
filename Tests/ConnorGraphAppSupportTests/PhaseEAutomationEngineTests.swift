import Foundation
import Testing
import ConnorGraphAgent
import ConnorGraphCore
import ConnorGraphAppSupport
import ConnorGraphStore

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
                ProductOSAutomationAction(kind: .addSessionLabel, label: AgentSessionLabel(id: "research"), message: "Suggest research label.")
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

    @Test func automationEngineExecutesReadySessionGovernanceActions() throws {
        let root = temporaryPhaseERoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let store = try SQLiteGraphKernelStore(path: paths.databaseURL.path)
        try store.migrate()
        let sessionRepository = AppChatSessionRepository(store: store, storagePaths: paths)
        try sessionRepository.saveSession(AgentSession(id: "session-1", title: "Automation Target"))
        let repository = AppProductOSAutomationRepository(storagePaths: paths)
        let rule = ProductOSAutomationRule(
            id: "important-ready-actions",
            name: "Important Ready Actions",
            trigger: ProductOSAutomationTrigger(kind: .sessionLabelAdded, labelID: "important"),
            actions: [
                ProductOSAutomationAction(kind: .appendTimelineEvent, message: "Important label changed."),
                ProductOSAutomationAction(kind: .addSessionLabel, label: AgentSessionLabel(id: "research"), message: "Add research."),
                ProductOSAutomationAction(kind: .setSessionStatus, status: .needsReview, message: "Move to Needs Review.")
            ],
            requiresReview: false
        )
        try repository.save(ProductOSAutomationConfig(rules: [rule]))
        let engine = AutomationEngine(repository: repository)
        let run = try engine.evaluate(context: ProductOSAutomationEventContext(
            triggerKind: .sessionLabelAdded,
            sessionID: "session-1",
            labelID: "important"
        ))

        let result = try engine.execute(run: run, sessionRepository: sessionRepository)
        let session = try #require(try sessionRepository.loadSession(id: "session-1"))

        #expect(result.appliedPlans.count == 3)
        #expect(result.skippedPlans.isEmpty)
        #expect(session.governance.status == .needsReview)
        #expect(session.governance.labels.map(\.id).contains("research"))
        #expect(result.events.contains { $0.kind == .sessionLabelsChanged })
        #expect(result.events.contains { $0.kind == .sessionStatusChanged })
        #expect(result.events.contains { $0.kind == .automationTriggered })
    }

    @Test func automationEngineDoesNotExecutePendingReviewActions() throws {
        let root = temporaryPhaseERoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let store = try SQLiteGraphKernelStore(path: paths.databaseURL.path)
        try store.migrate()
        let sessionRepository = AppChatSessionRepository(store: store, storagePaths: paths)
        try sessionRepository.saveSession(AgentSession(id: "session-1", title: "Automation Target"))
        let repository = AppProductOSAutomationRepository(storagePaths: paths)
        let rule = ProductOSAutomationRule(
            id: "review-required-actions",
            name: "Review Required Actions",
            trigger: ProductOSAutomationTrigger(kind: .sessionStatusChanged, status: .needsReview),
            actions: [ProductOSAutomationAction(kind: .addSessionLabel, label: AgentSessionLabel(id: "research"), message: "Add research.")],
            requiresReview: true
        )
        try repository.save(ProductOSAutomationConfig(rules: [rule]))
        let engine = AutomationEngine(repository: repository)
        let run = try engine.evaluate(context: ProductOSAutomationEventContext(
            triggerKind: .sessionStatusChanged,
            sessionID: "session-1",
            status: .needsReview
        ))

        let result = try engine.execute(run: run, sessionRepository: sessionRepository)
        let session = try #require(try sessionRepository.loadSession(id: "session-1"))

        #expect(result.appliedPlans.isEmpty)
        #expect(result.skippedPlans.count == 1)
        #expect(session.governance.labels.isEmpty)
        #expect(result.events.contains { $0.kind == .automationTriggered })
    }

    @Test func automationEnginePersistsExecutionHistory() throws {
        let root = temporaryPhaseERoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let paths = AppStoragePaths(applicationSupportDirectory: root)
        try paths.ensureDirectoryHierarchy()
        let store = try SQLiteGraphKernelStore(path: paths.databaseURL.path)
        try store.migrate()
        let sessionRepository = AppChatSessionRepository(store: store, storagePaths: paths)
        try sessionRepository.saveSession(AgentSession(id: "session-1", title: "Automation Target"))
        let repository = AppProductOSAutomationRepository(storagePaths: paths)
        let rule = ProductOSAutomationRule(
            id: "history-rule",
            name: "History Rule",
            trigger: ProductOSAutomationTrigger(kind: .sessionLabelAdded, labelID: "important"),
            actions: [ProductOSAutomationAction(kind: .appendTimelineEvent, message: "Persist this execution.")],
            requiresReview: false
        )
        try repository.save(ProductOSAutomationConfig(rules: [rule]))
        let engine = AutomationEngine(repository: repository)
        let run = try engine.evaluate(context: ProductOSAutomationEventContext(
            triggerKind: .sessionLabelAdded,
            sessionID: "session-1",
            labelID: "important"
        ))

        _ = try engine.execute(run: run, sessionRepository: sessionRepository)
        let history = try repository.loadRecentExecutionHistory(limit: 10)
        let record = try #require(history.first)

        #expect(record.sessionID == "session-1")
        #expect(record.trigger == .sessionLabelAdded)
        #expect(record.ruleIDs == ["history-rule"])
        #expect(record.appliedActionCount == 1)
        #expect(record.skippedActionCount == 0)
        #expect(record.outcome == .completed)
        #expect(FileManager.default.fileExists(atPath: repository.executionHistoryURL.path))
    }

    @Test func automationEngineRateLimitsRepeatedTriggers() throws {
        let root = temporaryPhaseERoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = AppProductOSAutomationRepository(storagePaths: AppStoragePaths(applicationSupportDirectory: root))
        let rule = ProductOSAutomationRule(
            id: "limited-rule",
            name: "Limited Rule",
            trigger: ProductOSAutomationTrigger(kind: .sessionLabelAdded, labelID: "important"),
            actions: [ProductOSAutomationAction(kind: .appendTimelineEvent, message: "Limited action.")],
            requiresReview: false
        )
        try repository.save(ProductOSAutomationConfig(rules: [rule]))
        let limiter = AutomationRateLimiter(maxEvents: 1, interval: 60)
        let engine = AutomationEngine(repository: repository, rateLimiter: limiter)
        let context = ProductOSAutomationEventContext(
            triggerKind: .sessionLabelAdded,
            sessionID: "session-1",
            labelID: "important"
        )

        _ = try engine.evaluate(context: context, now: Date(timeIntervalSince1970: 1_000))
        #expect(throws: AutomationEngineError.self) {
            _ = try engine.evaluate(context: context, now: Date(timeIntervalSince1970: 1_010))
        }
        let later = try engine.evaluate(context: context, now: Date(timeIntervalSince1970: 1_061))
        #expect(later.matchedRules.map(\.id) == ["limited-rule"])
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
