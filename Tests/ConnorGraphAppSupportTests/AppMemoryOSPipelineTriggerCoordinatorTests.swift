import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore
import ConnorGraphAppSupport

@Test func coordinatorEnqueuesL1UnifiedProjectionWhenPendingCaptureCountReaches100() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryCoordinatorDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let coordinator = AppMemoryOSPipelineTriggerCoordinator(facade: facade)
    let now = Date(timeIntervalSince1970: 30_000)
    for index in 0..<99 {
        _ = try facade.ingestChatMessage(messageID: "message-\(index)", sessionID: "session", role: "user", content: "Important memory content \(index)", occurredAt: now.addingTimeInterval(Double(index)))
    }

    #expect(try coordinator.evaluateAfterL1Capture(now: now).isEmpty)
    _ = try facade.ingestChatMessage(messageID: "message-99", sessionID: "session", role: "user", content: "Important memory content 99", occurredAt: now.addingTimeInterval(99))

    let enqueued = try coordinator.evaluateAfterL1Capture(now: now)

    #expect(enqueued.count == 4)
    let runnable = try store.runnableQueueItems(kind: MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue, limit: 10, now: now)
    #expect(runnable.count == 4)
}

@Test func coordinatorDailySweepEnqueuesL1UnifiedProjectionWhenOldestPendingCaptureIs24HoursOld() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryCoordinatorDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let coordinator = AppMemoryOSPipelineTriggerCoordinator(facade: facade)
    let occurredAt = Date(timeIntervalSince1970: 40_000)
    _ = try facade.ingestChatMessage(messageID: "old-message", sessionID: "session", role: "user", content: "Old important memory", occurredAt: occurredAt)

    #expect(try coordinator.runDailySweep(now: occurredAt.addingTimeInterval((24 * 60 * 60) - 1)).isEmpty)
    let enqueued = try coordinator.runDailySweep(now: occurredAt.addingTimeInterval(24 * 60 * 60))

    #expect(enqueued.count == 1)
    #expect(enqueued.first?.kind == MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue)
}

@Test func coordinatorEnqueuesL2ToKnowledgeWhenPendingStatementCountReaches100() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryCoordinatorDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let coordinator = AppMemoryOSPipelineTriggerCoordinator(facade: facade)
    let now = Date(timeIntervalSince1970: 50_000)
    for index in 0..<100 {
        let node = MemoryOSNode(id: "node-\(index)", stableKey: "node-\(index)", nodeType: "topic", name: "Topic \(index)")
        try store.upsert(node: node)
        let statement = MemoryOSStatement(id: "statement-\(index)", subjectID: node.id, predicate: "observed", text: "Reusable pattern \(index)", confidence: 0.8, validAt: now, committedAt: now.addingTimeInterval(Double(index)), evidenceSpanIDs: ["span-\(index)"])
        try store.upsert(statement: statement)
        try store.upsert(l2ProcessingState: MemoryOSL2StatementProcessingState(statementID: statement.id, processingKind: .knowledgeSynthesis, status: .pending, lastAttemptAt: now))
    }

    let enqueued = try coordinator.evaluateAfterL2PendingStatements(now: now)

    #expect(enqueued.count == 4)
    let runnable = try store.runnableQueueItems(kind: MemoryOSBackgroundJobKind.l2SynthesizeKnowledge.rawValue, limit: 10, now: now)
    #expect(runnable.count == 4)
}

@Test func coordinatorDailySweepEnqueuesL2ToKnowledgeWhenOldestPendingStatementIs24HoursOld() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryCoordinatorDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let coordinator = AppMemoryOSPipelineTriggerCoordinator(facade: facade)
    let now = Date(timeIntervalSince1970: 60_000)
    let committedAt = now.addingTimeInterval(-24 * 60 * 60)
    try store.upsert(node: MemoryOSNode(id: "node-old", stableKey: "node-old", nodeType: "topic", name: "Old Topic"))
    try store.upsert(statement: MemoryOSStatement(id: "statement-old", subjectID: "node-old", predicate: "observed", text: "Old reusable pattern", confidence: 0.8, validAt: committedAt, committedAt: committedAt, evidenceSpanIDs: ["span-old"]))
    try store.upsert(l2ProcessingState: MemoryOSL2StatementProcessingState(statementID: "statement-old", processingKind: .knowledgeSynthesis, status: .pending, lastAttemptAt: committedAt))

    let enqueued = try coordinator.runDailySweep(now: now)

    #expect(enqueued.count == 1)
    #expect(enqueued.first?.kind == MemoryOSBackgroundJobKind.l2SynthesizeKnowledge.rawValue)
}

private func temporaryCoordinatorDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("app-memory-os-trigger-coordinator-\(UUID().uuidString).sqlite")
}
