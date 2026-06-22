import Foundation
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

public struct AppMemoryOSOperationalSummary: Sendable, Equatable, Codable {
    public var dashboardSnapshot: MemoryOSDashboardSnapshot
    public var healthReport: MemoryOSStoreHealthReport
    public var expiredLeaseCount: Int

    public init(dashboardSnapshot: MemoryOSDashboardSnapshot, healthReport: MemoryOSStoreHealthReport, expiredLeaseCount: Int = 0) {
        self.dashboardSnapshot = dashboardSnapshot
        self.healthReport = healthReport
        self.expiredLeaseCount = expiredLeaseCount
    }
}

public struct AppMemoryOSFacade: @unchecked Sendable {
    public var store: SQLiteMemoryOSStore
    public var repository: AppMemoryOSRepository
    public var ingestionService: MemoryOSIngestionService
    public var dashboardBuilder: MemoryOSDashboardPresentationBuilder
    public var backgroundRunner: AppMemoryOSBackgroundJobRunner

    public init(
        store: SQLiteMemoryOSStore,
        repository: AppMemoryOSRepository? = nil,
        ingestionService: MemoryOSIngestionService = MemoryOSIngestionService(),
        dashboardBuilder: MemoryOSDashboardPresentationBuilder = MemoryOSDashboardPresentationBuilder(),
        backgroundRunner: AppMemoryOSBackgroundJobRunner = AppMemoryOSBackgroundJobRunner()
    ) {
        self.store = store
        self.repository = repository ?? AppMemoryOSRepository(store: store)
        self.ingestionService = ingestionService
        self.dashboardBuilder = dashboardBuilder
        self.backgroundRunner = backgroundRunner
    }

    public func operationalSummary(now: Date = Date()) throws -> AppMemoryOSOperationalSummary {
        let health = try store.schemaHealthReport(now: now)
        let snapshot = MemoryOSDashboardSnapshot(
            healthStatus: health.status,
            l0ProvenanceObjectCount: try count("memory_l0_provenance_objects"),
            l1PendingCaptureCount: try count("memory_l1_capture_events", where: "processing_state IN ('pending', 'queued')"),
            l1PendingQueueCount: try count("memory_l1_processing_queue", where: "status IN ('pending', 'leased')"),
            l1DeadLetterCount: try count("memory_l1_dead_letter_queue"),
            l2StatementCount: try count("memory_l2_statements"),
            l2ConflictCount: try count("memory_l2_conflicts"),
            l3BeliefCount: try count("memory_l3_beliefs"),
            l4EntityCount: try count("memory_l4_entities"),
            lastCheckedAt: now
        )
        return AppMemoryOSOperationalSummary(
            dashboardSnapshot: snapshot,
            healthReport: health,
            expiredLeaseCount: try expiredLeaseCount(now: now)
        )
    }

    public func dashboardPresentation(now: Date = Date()) throws -> MemoryOSDashboardPresentation {
        try dashboardBuilder.presentation(for: operationalSummary(now: now).dashboardSnapshot)
    }

    public func ingestChatMessage(
        messageID: String,
        sessionID: String,
        role: String,
        content: String,
        occurredAt: Date,
        metadata: [String: String] = [:]
    ) throws -> MemoryOSIngestionResult {
        let sourceType: MemoryOSSourceType = role == "assistant" ? .assistantMessage : .chatMessage
        let result = ingestionService.ingest(MemoryOSIngestionInput(
            sourceType: sourceType,
            sourceID: messageID,
            title: "\(role) message",
            content: content,
            occurredAt: occurredAt,
            sessionID: sessionID
        ))
        try repository.save(result)
        return result
    }

    public func shouldRecover(queueItem: MemoryOSQueueItem, now: Date = Date()) -> Bool {
        backgroundRunner.shouldRecover(queueStatus: queueItem.status, leaseExpiresAt: queueItem.leaseExpiresAt, now: now)
    }

    private func count(_ table: String, where clause: String? = nil) throws -> Int {
        let sql = "SELECT COUNT(*) FROM \(table)" + clause.map { " WHERE \($0)" }.orEmpty + ";"
        return Int(try store.query(sql: sql).first?.first ?? "0") ?? 0
    }

    private func expiredLeaseCount(now: Date) throws -> Int {
        let iso = ISO8601DateFormatter().string(from: now)
        let rows = try store.query(sql: "SELECT COUNT(*) FROM memory_l1_processing_queue WHERE status = 'leased' AND lease_expires_at IS NOT NULL AND lease_expires_at < '\(iso)';")
        return Int(rows.first?.first ?? "0") ?? 0
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}
