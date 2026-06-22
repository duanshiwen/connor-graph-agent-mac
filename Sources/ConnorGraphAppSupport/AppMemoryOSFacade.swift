import Foundation
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

public struct AppMemoryOSOperationalSummary: Sendable, Equatable, Codable {
    public var dashboardSnapshot: MemoryOSDashboardSnapshot
    public var healthReport: MemoryOSStoreHealthReport
    public var queueSnapshot: MemoryOSQueueOperationalSnapshot
    public var expiredLeaseCount: Int

    public init(dashboardSnapshot: MemoryOSDashboardSnapshot, healthReport: MemoryOSStoreHealthReport, queueSnapshot: MemoryOSQueueOperationalSnapshot = MemoryOSQueueOperationalSnapshot(), expiredLeaseCount: Int = 0) {
        self.dashboardSnapshot = dashboardSnapshot
        self.healthReport = healthReport
        self.queueSnapshot = queueSnapshot
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
        let queueSnapshot = try store.queueOperationalSnapshot(now: now)
        let snapshot = MemoryOSDashboardSnapshot(
            healthStatus: health.status,
            l0ProvenanceObjectCount: try count("memory_l0_provenance_objects"),
            l1PendingCaptureCount: try count("memory_l1_capture_events", where: "processing_state IN ('pending', 'queued')"),
            l1PendingQueueCount: queueSnapshot.pending + queueSnapshot.leased + queueSnapshot.processing,
            l1DeadLetterCount: queueSnapshot.deadLetter,
            l1RetryScheduledCount: queueSnapshot.retryScheduled,
            l1ExpiredLeaseCount: queueSnapshot.expiredLeases,
            l2StatementCount: try count("memory_l2_statements"),
            l2ConflictCount: try count("memory_l2_conflicts"),
            l3BeliefCount: try count("memory_l3_beliefs"),
            l4EntityCount: try count("memory_l4_entities"),
            lastCheckedAt: now
        )
        try store.saveHealthReport(health)
        try store.save(metric: MemoryOSProcessingMetric(name: "memory_os.queue.pending", value: Double(queueSnapshot.pending), createdAt: now))
        return AppMemoryOSOperationalSummary(
            dashboardSnapshot: snapshot,
            healthReport: health,
            queueSnapshot: queueSnapshot,
            expiredLeaseCount: queueSnapshot.expiredLeases
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

    public func ingestWebPageEvidence(
        evidenceID: String,
        title: String,
        content: String,
        occurredAt: Date,
        sessionID: String? = nil,
        metadata: [String: String] = [:]
    ) throws -> MemoryOSIngestionResult {
        let result = ingestionService.ingest(MemoryOSIngestionInput(
            sourceType: .webPage,
            sourceID: evidenceID,
            title: title,
            content: content,
            occurredAt: occurredAt,
            sessionID: sessionID
        ))
        try repository.save(result)
        return result
    }

    public func validateAndRecordLLMArtifact(
        rawContent: String,
        modelID: String,
        queueItemID: String? = nil,
        processingRunID: String? = nil,
        now: Date = Date()
    ) throws -> MemoryOSArtifactValidationResult {
        let envelope = MemoryOSArtifactEnvelopeService().envelope(rawContent: rawContent, modelID: modelID, queueItemID: queueItemID, processingRunID: processingRunID, now: now)
        try store.save(artifact: envelope)
        let result = MemoryOSLLMArtifactValidator().validateStructuredExtractionArtifact(envelope)
        try store.save(audit: MemoryOSAuditEvent(
            eventType: result.accepted ? "memory_os.llm_artifact.accepted" : "memory_os.llm_artifact.rejected",
            actor: "memory-os",
            subjectID: envelope.id,
            payload: [
                "schema_name": envelope.schemaName,
                "model_id": envelope.modelID,
                "accepted": String(result.accepted),
                "issue_count": String(result.issues.count),
                "normalized_record_count": String(result.normalizedRecordCount)
            ],
            createdAt: now
        ))
        try store.save(metric: MemoryOSProcessingMetric(name: "memory_os.llm_artifact.accepted", value: result.accepted ? 1 : 0, dimensions: ["schema": envelope.schemaName], createdAt: now))
        return result
    }

    public func recordQueueFailure(_ item: MemoryOSQueueItem, errorCode: String, errorMessage: String, now: Date = Date()) throws -> MemoryOSQueueItem {
        let transitioned = MemoryOSQueueTransitionService().markFailed(item, errorCode: errorCode, errorMessage: errorMessage, now: now)
        try store.enqueue(transitioned)
        try store.saveQueueAttempt(queueItemID: item.id, attemptNumber: transitioned.attemptCount, status: transitioned.status, startedAt: item.lockedAt ?? now, finishedAt: now, errorCode: errorCode, errorMessage: errorMessage)
        if transitioned.status == .deadLetter {
            try store.saveDeadLetter(queueItem: transitioned, now: now)
        }
        try store.save(audit: MemoryOSAuditEvent(eventType: "memory_os.queue.failure", subjectID: item.id, payload: ["status": transitioned.status.rawValue, "error_code": errorCode], createdAt: now))
        return transitioned
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
