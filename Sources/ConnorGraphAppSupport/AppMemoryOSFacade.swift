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
            l2DiagnosticCount: 0,
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

    public func runProjectionQueueOnce(workerID: String = "memory-os-projection-worker", limit: Int = 5, now: Date = Date()) throws -> [MemoryOSProjectionRunSummary] {
        let candidates = try store.runnableQueueItems(kind: "project_artifact", limit: limit, now: now)
        var summaries: [MemoryOSProjectionRunSummary] = []
        for candidate in candidates {
            guard let leased = try store.leaseQueueItem(id: candidate.id, workerID: workerID, now: now) else { continue }
            do {
                let payload = try store.decode(MemoryOSProjectionQueuePayload.self, leased.payloadJSON)
                let summary = try projectAndRecordLLMArtifact(rawContent: payload.rawContent, modelID: payload.modelID, queueItem: leased, processingRunID: payload.processingRunID, artifactType: payload.artifactType, schemaName: payload.schemaName, now: now)
                summaries.append(summary)
            } catch {
                let failed = try recordQueueFailure(leased, errorCode: "projection_payload_decode_failed", errorMessage: String(describing: error), now: now)
                summaries.append(MemoryOSProjectionRunSummary(artifactID: leased.id, accepted: false, issues: [MemoryOSValidationIssue(code: failed.errorCode ?? "projection_payload_decode_failed", message: failed.errorMessage ?? String(describing: error))]))
            }
        }
        return summaries
    }

    public func projectAndRecordLLMArtifact(
        rawContent: String,
        modelID: String,
        queueItem: MemoryOSQueueItem? = nil,
        processingRunID: String? = nil,
        artifactType: String = "graph_structured_extraction",
        schemaName: String = "GraphStructuredExtractionOutput",
        now: Date = Date()
    ) throws -> MemoryOSProjectionRunSummary {
        let envelope = MemoryOSArtifactEnvelopeService().envelope(rawContent: rawContent, artifactType: artifactType, schemaName: schemaName, modelID: modelID, queueItemID: queueItem?.id, processingRunID: processingRunID, now: now)
        try store.save(artifact: envelope)
        let validation = MemoryOSLLMArtifactValidator().validateStructuredExtractionArtifact(envelope)
        let build = MemoryOSProjectionService().projectionBatch(from: envelope, validation: validation, now: now)
        guard build.accepted, let batch = build.batch else {
            try store.save(audit: MemoryOSAuditEvent(
                eventType: "memory_os.projection.rejected",
                actor: "memory-os",
                subjectID: envelope.id,
                payload: ["issue_count": String(build.validation.issues.count), "model_id": modelID],
                createdAt: now
            ))
            try store.save(metric: MemoryOSProcessingMetric(name: "memory_os.projection.accepted", value: 0, dimensions: ["model_id": modelID], createdAt: now))
            if let queueItem {
                _ = try recordQueueFailure(queueItem, errorCode: "projection_validation_failed", errorMessage: build.validation.issues.map(\.message).joined(separator: "; "), now: now)
            }
            return MemoryOSProjectionRunSummary(artifactID: envelope.id, accepted: false, issues: build.validation.issues)
        }
        try store.saveProjectionBatch(batch)
        if let queueItem {
            _ = try recordQueueSuccess(queueItem, now: now)
        }
        try store.save(audit: MemoryOSAuditEvent(
            eventType: "memory_os.projection.succeeded",
            actor: "memory-os",
            subjectID: envelope.id,
            payload: [
                "node_count": String(batch.nodes.count),
                "statement_count": String(batch.statements.count),
                "entity_count": String(batch.entities.count),
                "entity_statement_count": String(batch.entityStatements.count),
                "belief_count": String(batch.beliefs.count)
            ],
            createdAt: now
        ))
        try store.save(metric: MemoryOSProcessingMetric(name: "memory_os.projection.accepted", value: 1, dimensions: ["model_id": modelID], createdAt: now))
        return MemoryOSProjectionRunSummary(
            artifactID: envelope.id,
            accepted: true,
            nodeCount: batch.nodes.count,
            statementCount: batch.statements.count,
            entityCount: batch.entities.count,
            entityStatementCount: batch.entityStatements.count,
            beliefCount: batch.beliefs.count
        )
    }

    public func enqueueL1ToL2BackgroundJobs(policy: MemoryOSL1ProcessingTriggerPolicy = MemoryOSL1ProcessingTriggerPolicy(), now: Date = Date()) throws -> [MemoryOSQueueItem] {
        let events = try pendingCaptureEvents(limit: max(policy.minPendingCount * 2, policy.maxEventsPerBlock * 4))
        let drafts = MemoryOSL1ToL2JobPlanner(policy: policy).planJobs(from: events, now: now)
        return try drafts.map { draft in
            let payload = store.json(draft)
            let item = MemoryOSQueueItem(
                kind: draft.kind,
                priority: 10,
                payloadJSON: payload,
                nextRunAt: now,
                idempotencyKey: "\(draft.kind):\(draft.captureEventIDs.joined(separator: ","))",
                payloadHash: String(payload.hashValue),
                createdAt: now,
                updatedAt: now
            )
            try store.enqueue(item)
            return item
        }
    }

    public func enqueueL2ToKnowledgeBackgroundJobs(policy: MemoryOSL2KnowledgeSynthesisTriggerPolicy = MemoryOSL2KnowledgeSynthesisTriggerPolicy(), now: Date = Date()) throws -> [MemoryOSQueueItem] {
        let states = try store.l2ProcessingStates(processingKind: .knowledgeSynthesis, status: .pending, limit: max(policy.minPendingStatementCount * 2, policy.maxStatementsPerBlock * 4))
        let statements = try statements(for: states.map(\.statementID))
        let drafts = MemoryOSL2ToKnowledgeJobPlanner(policy: policy).planJobs(from: statements, now: now)
        return try drafts.map { draft in
            let payload = store.json(draft)
            let item = MemoryOSQueueItem(
                kind: draft.kind,
                priority: 5,
                payloadJSON: payload,
                nextRunAt: now,
                idempotencyKey: "\(draft.kind):\(draft.statementIDs.joined(separator: ","))",
                payloadHash: String(payload.hashValue),
                createdAt: now,
                updatedAt: now
            )
            try store.enqueue(item)
            return item
        }
    }

    public func recordQueueSuccess(_ item: MemoryOSQueueItem, now: Date = Date()) throws -> MemoryOSQueueItem {
        let transitioned = MemoryOSQueueTransitionService().markSucceeded(item, now: now)
        try store.enqueue(transitioned)
        try store.saveQueueAttempt(queueItemID: item.id, attemptNumber: transitioned.attemptCount, status: transitioned.status, startedAt: item.lockedAt ?? now, finishedAt: now)
        try store.save(audit: MemoryOSAuditEvent(eventType: "memory_os.queue.succeeded", subjectID: item.id, payload: ["status": transitioned.status.rawValue], createdAt: now))
        return transitioned
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

    private func pendingCaptureEvents(limit: Int) throws -> [MemoryOSCaptureEvent] {
        try store.query(sql: """
        SELECT id, provenance_object_id, event_type, occurred_at, token_estimate, processing_state, metadata_json
        FROM memory_l1_capture_events
        WHERE processing_state = 'pending'
        ORDER BY occurred_at ASC
        LIMIT \(limit)
        """).map { row in
            MemoryOSCaptureEvent(
                id: row[0],
                provenanceObjectID: row[1],
                eventType: row[2],
                occurredAt: parseDate(row[3]),
                tokenEstimate: Int(row[4]) ?? 0,
                processingState: MemoryOSQueueStatus(rawValue: row[5]) ?? .pending,
                metadata: (try? store.decode([String: String].self, row[6])) ?? [:]
            )
        }
    }

    private func statements(for ids: [String]) throws -> [MemoryOSStatement] {
        guard !ids.isEmpty else { return [] }
        let quoted = ids.map { store.quote($0) }.joined(separator: ",")
        return try store.query(sql: """
        SELECT id, subject_id, predicate, object_id, text, assertion_kind, confidence, valid_at, committed_at, evidence_span_ids_json, source_artifact_id, metadata_json
        FROM memory_l2_statements
        WHERE id IN (\(quoted))
        ORDER BY committed_at ASC
        """).map { row in
            MemoryOSStatement(
                id: row[0],
                subjectID: row[1],
                predicate: row[2],
                objectID: row[3].isEmpty ? nil : row[3],
                text: row[4],
                assertionKind: MemoryOSAssertionKind(rawValue: row[5]) ?? .observed,
                confidence: Double(row[6]) ?? 0,
                validAt: parseDate(row[7]),
                committedAt: parseDate(row[8]),
                evidenceSpanIDs: (try? store.decode([String].self, row[9])) ?? [],
                sourceArtifactID: row[10].isEmpty ? nil : row[10],
                metadata: ((try? store.decode([String: String].self, row[11])) ?? [:]).merging(["processing_state": "pending_knowledge_synthesis"]) { current, _ in current }
            )
        }
    }

    private func parseDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value) ?? Date(timeIntervalSince1970: 0)
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
