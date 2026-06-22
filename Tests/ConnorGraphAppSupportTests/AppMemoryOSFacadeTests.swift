import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

@Test func appMemoryOSFacadeBuildsOperationalSummaryFromStore() throws {
    let store = try SQLiteMemoryOSStore(path: ":memory:")
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 1_782_096_000)

    _ = try facade.ingestChatMessage(
        messageID: "message-1",
        sessionID: "session-1",
        role: "user",
        content: "Connor Memory OS should persist evidence before projection.",
        occurredAt: now
    )

    let summary = try facade.operationalSummary(now: now)
    let presentation = try facade.dashboardPresentation(now: now)

    #expect(summary.healthReport.status == .healthy)
    #expect(summary.dashboardSnapshot.l0ProvenanceObjectCount == 1)
    #expect(summary.dashboardSnapshot.l1PendingCaptureCount == 1)
    #expect(presentation.title == "Connor Memory OS")
}

@Test func appMemoryOSFacadeDetectsExpiredQueueLeases() throws {
    let store = try SQLiteMemoryOSStore(path: ":memory:")
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 1_782_096_000)
    let item = MemoryOSQueueItem(
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
    )
    try store.enqueue(item)

    let summary = try facade.operationalSummary(now: now)

    #expect(summary.expiredLeaseCount == 1)
    #expect(facade.shouldRecover(queueItem: item, now: now))
}
