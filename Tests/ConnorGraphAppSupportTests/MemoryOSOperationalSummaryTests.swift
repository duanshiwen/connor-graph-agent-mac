import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

@Test func memoryOSOperationalSummaryTracksLayerCountsWithoutUIPresentation() throws {
    let store = try SQLiteMemoryOSStore(path: ":memory:")
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 1_782_096_000)

    _ = try facade.ingestChatMessage(
        messageID: "message-1",
        sessionID: "session-1",
        role: "user",
        content: "Memory OS should remain a hidden background substrate.",
        occurredAt: now
    )

    let summary = try facade.operationalSummary(now: now)

    #expect(summary.healthReport.status == .healthy)
    #expect(summary.l0ProvenanceObjectCount == 1)
    #expect(summary.l1PendingCaptureCount == 1)
    #expect(summary.l2StatementCount == 0)
    #expect(summary.l3KnowledgeRecordCount == 0)
    #expect(summary.l4EntityCount == 0)
}

@Test func memoryOSOperationalSummaryTracksQueueRecoveryMetricsWithoutUIPresentation() throws {
    let store = try SQLiteMemoryOSStore(path: ":memory:")
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 1_782_096_000)
    try store.enqueue(MemoryOSQueueItem(
        id: "queue-1",
        kind: "projection",
        status: .leased,
        priority: 1,
        payloadJSON: "{}",
        nextRunAt: now.addingTimeInterval(-60),
        lockedAt: now.addingTimeInterval(-120),
        lockedBy: "worker-1",
        leaseExpiresAt: now.addingTimeInterval(-30),
        idempotencyKey: "queue-1",
        payloadHash: "hash",
        createdAt: now.addingTimeInterval(-120),
        updatedAt: now.addingTimeInterval(-60)
    ))

    let summary = try facade.operationalSummary(now: now)

    #expect(summary.l1PendingQueueCount == 1)
    #expect(summary.l1ExpiredLeaseCount == 1)
    #expect(summary.expiredLeaseCount == 1)
}
