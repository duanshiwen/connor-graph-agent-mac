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

    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_processing_queue WHERE kind = '\(MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue)';").first?.first == "4")

    let enqueued = try coordinator.evaluateAfterL1Capture(now: now.addingTimeInterval(99))
    #expect(enqueued.isEmpty)
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

private func temporaryCoordinatorDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("app-memory-os-trigger-coordinator-\(UUID().uuidString).sqlite")
}
