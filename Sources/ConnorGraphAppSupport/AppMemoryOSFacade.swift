import Foundation
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore
import ConnorGraphSearch


private extension MemoryOSSearchKernelLayer {
    init(retrievalLayer: MemoryOSRetrievalLayer) {
        switch retrievalLayer {
        case .l0: self = .l0
        case .l1: self = .l1
        case .l2: self = .l2
        case .l3: self = .l3
        case .l4: self = .l4
        }
    }
}

private extension MemoryOSRetrievalLayer {
    init(searchKernelLayer: MemoryOSSearchKernelLayer) {
        switch searchKernelLayer {
        case .l0: self = .l0
        case .l1: self = .l1
        case .l2: self = .l2
        case .l3: self = .l3
        case .l4: self = .l4
        }
    }
}

private extension MemoryOSRetrievalHit {
    init(searchKernelHit hit: MemoryOSSearchKernelHit) {
        var metadata: [String: String] = [
            "backend": "tantivy-embedded",
            "record_kind": hit.recordKind,
            "matched_channel": hit.matchedChannel,
            "rank_reason": hit.rankReason
        ]
        metadata["kernel_metadata_json"] = hit.metadataJSON
        self.init(
            layer: MemoryOSRetrievalLayer(searchKernelLayer: hit.layer),
            recordID: hit.recordID,
            title: hit.title,
            summary: hit.snippet,
            matchedText: hit.snippet,
            score: hit.score,
            entityRefs: hit.layer == .l4 ? [hit.recordID] : [],
            canReadRaw: hit.layer != .l4,
            canExpandDepth: hit.layer == .l4,
            metadata: metadata
        )
    }
}

public struct AppMemoryOSOperationalSummary: Sendable, Equatable, Codable {
    public var healthReport: MemoryOSStoreHealthReport
    public var queueSnapshot: MemoryOSQueueOperationalSnapshot
    public var expiredLeaseCount: Int
    public var l0ProvenanceObjectCount: Int
    public var l1PendingCaptureCount: Int
    public var l1PendingQueueCount: Int
    public var l1DeadLetterCount: Int
    public var l1RetryScheduledCount: Int
    public var l1ExpiredLeaseCount: Int
    public var l2StatementCount: Int
    public var l2DiagnosticCount: Int
    public var l3KnowledgeRecordCount: Int
    public var l4EntityCount: Int
    public var checkedAt: Date

    public init(
        healthReport: MemoryOSStoreHealthReport,
        queueSnapshot: MemoryOSQueueOperationalSnapshot = MemoryOSQueueOperationalSnapshot(),
        expiredLeaseCount: Int = 0,
        l0ProvenanceObjectCount: Int = 0,
        l1PendingCaptureCount: Int = 0,
        l1PendingQueueCount: Int = 0,
        l1DeadLetterCount: Int = 0,
        l1RetryScheduledCount: Int = 0,
        l1ExpiredLeaseCount: Int = 0,
        l2StatementCount: Int = 0,
        l2DiagnosticCount: Int = 0,
        l3KnowledgeRecordCount: Int = 0,
        l4EntityCount: Int = 0,
        checkedAt: Date = Date()
    ) {
        self.healthReport = healthReport
        self.queueSnapshot = queueSnapshot
        self.expiredLeaseCount = expiredLeaseCount
        self.l0ProvenanceObjectCount = l0ProvenanceObjectCount
        self.l1PendingCaptureCount = l1PendingCaptureCount
        self.l1PendingQueueCount = l1PendingQueueCount
        self.l1DeadLetterCount = l1DeadLetterCount
        self.l1RetryScheduledCount = l1RetryScheduledCount
        self.l1ExpiredLeaseCount = l1ExpiredLeaseCount
        self.l2StatementCount = l2StatementCount
        self.l2DiagnosticCount = l2DiagnosticCount
        self.l3KnowledgeRecordCount = l3KnowledgeRecordCount
        self.l4EntityCount = l4EntityCount
        self.checkedAt = checkedAt
    }
}

public struct AppMemoryOSFacade: @unchecked Sendable {
    public var store: SQLiteMemoryOSStore
    public var repository: AppMemoryOSRepository
    public var ingestionService: MemoryOSIngestionService
    public var backgroundRunner: AppMemoryOSBackgroundJobRunner
    public var searchKernel: MemoryOSSearchKernel?

    public init(
        store: SQLiteMemoryOSStore,
        repository: AppMemoryOSRepository? = nil,
        ingestionService: MemoryOSIngestionService = MemoryOSIngestionService(),
        backgroundRunner: AppMemoryOSBackgroundJobRunner = AppMemoryOSBackgroundJobRunner(),
        searchKernel: MemoryOSSearchKernel? = nil
    ) {
        self.store = store
        self.repository = repository ?? AppMemoryOSRepository(store: store)
        self.ingestionService = ingestionService
        self.backgroundRunner = backgroundRunner
        self.searchKernel = searchKernel
    }

    public func operationalSummary(now: Date = Date()) throws -> AppMemoryOSOperationalSummary {
        let health = try store.schemaHealthReport(now: now)
        let queueSnapshot = try store.queueOperationalSnapshot(now: now)
        let l1PendingQueueCount = queueSnapshot.pending + queueSnapshot.leased + queueSnapshot.processing
        try store.saveHealthReport(health)
        try store.save(metric: MemoryOSProcessingMetric(name: "memory_os.queue.pending", value: Double(queueSnapshot.pending), createdAt: now))
        return AppMemoryOSOperationalSummary(
            healthReport: health,
            queueSnapshot: queueSnapshot,
            expiredLeaseCount: queueSnapshot.expiredLeases,
            l0ProvenanceObjectCount: try count("memory_l0_provenance_objects"),
            l1PendingCaptureCount: try count("memory_l1_capture_events", where: "processing_state IN ('pending', 'queued')"),
            l1PendingQueueCount: l1PendingQueueCount,
            l1DeadLetterCount: queueSnapshot.deadLetter,
            l1RetryScheduledCount: queueSnapshot.retryScheduled,
            l1ExpiredLeaseCount: queueSnapshot.expiredLeases,
            l2StatementCount: try count("memory_l2_statements"),
            l2DiagnosticCount: 0,
            l3KnowledgeRecordCount: try count("memory_l3_beliefs"),
            l4EntityCount: try count("memory_l4_entities"),
            checkedAt: now
        )
    }

    public func searchMemoryOS(_ query: MemoryOSRetrievalQuery) throws -> [MemoryOSRetrievalHit] {
        if let searchKernel {
            let response = try searchKernel.search(MemoryOSSearchKernelRequest(
                query: query.text,
                layers: query.layers.map(MemoryOSSearchKernelLayer.init(retrievalLayer:)),
                limit: query.limit
            ))
            return response.hits.map(MemoryOSRetrievalHit.init(searchKernelHit:))
        }
        return try SQLiteMemoryOSUnifiedRetrievalService(store: store).search(query)
    }

    @discardableResult
    public func ensureCurrentUserAnchor(now: Date = Date()) throws -> MemoryOSEntity {
        try MemoryOSPersonIdentityService().ensureCurrentUserAnchor(store: store, now: now)
    }

    public func currentUserProfileContext(limit: Int = 12, focus: String? = nil, now: Date = Date()) throws -> MemoryOSCurrentUserProfileContext {
        let anchor = try ensureCurrentUserAnchor(now: now)
        _ = anchor
        return try MemoryOSPersonIdentityService().currentUserProfileContext(store: store, limit: limit, focus: focus, now: now)
    }

    public func expandMemoryOSL4(entityID: String, depth: Int = 1, limit: Int = 20) throws -> [MemoryOSL4ExpansionHit] {
        try SQLiteMemoryOSUnifiedRetrievalService(store: store).expandL4(entityID: entityID, depth: depth, limit: limit)
    }

    public func memoryOSContext(_ request: MemoryOSContextRequest, generatedAt: Date = Date()) throws -> MemoryOSContextPackage {
        try MemoryOSContextDeliveryService(store: store).context(request, generatedAt: generatedAt)
    }

    public func queryMemoryOSGraph(_ query: MemoryOSGraphQuery) throws -> MemoryOSGraphSubgraph {
        try SQLiteMemoryOSGraphRetrievalService(store: store).queryGraph(query)
    }

    public func traceMemoryOSEvidence(spanIDs: [String] = [], statementIDs: [String] = [], beliefIDs: [String] = [], limit: Int = 100) throws -> MemoryOSGraphSubgraph {
        try SQLiteMemoryOSGraphRetrievalService(store: store).traceEvidence(MemoryOSEvidenceTraceQuery(spanIDs: spanIDs, statementIDs: statementIDs, beliefIDs: beliefIDs, limit: limit))
    }

    public func findMemoryOSL2Statements(text: String = "", subjectID: String? = nil, predicates: [String] = [], limit: Int = 50) throws -> MemoryOSGraphSubgraph {
        try SQLiteMemoryOSGraphRetrievalService(store: store).l2FindStatements(MemoryOSL2StatementFindQuery(text: text, subjectID: subjectID, predicates: predicates, limit: limit))
    }

    public func expandMemoryOSL3Belief(beliefID: String? = nil, topic: String? = nil, text: String? = nil, limit: Int = 20) throws -> MemoryOSGraphSubgraph {
        try SQLiteMemoryOSGraphRetrievalService(store: store).l3ExpandBelief(MemoryOSL3BeliefExpandQuery(beliefID: beliefID, topic: topic, text: text, limit: limit))
    }

    public func findMemoryOSL4Entity(text: String, limit: Int = 20) throws -> MemoryOSGraphSubgraph {
        try SQLiteMemoryOSGraphRetrievalService(store: store).l4FindEntity(MemoryOSL4EntityFindQuery(text: text, limit: limit))
    }

    public func queryMemoryOSL4Neighbors(entityID: String, direction: MemoryOSGraphDirection = .both, predicates: [String] = [], limit: Int = 100) throws -> MemoryOSGraphSubgraph {
        try SQLiteMemoryOSGraphRetrievalService(store: store).l4Neighbors(MemoryOSL4NeighborsQuery(entityID: entityID, direction: direction, predicates: predicates, limit: limit))
    }

    public func queryMemoryOSL4Instances(classEntityIDs: [String], predicates: [String] = ["P31"], limit: Int = 100) throws -> MemoryOSGraphSubgraph {
        try SQLiteMemoryOSGraphRetrievalService(store: store).l4Instances(MemoryOSL4InstanceQuery(classEntityIDs: classEntityIDs, predicates: predicates, limit: limit))
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
            sessionID: sessionID,
            metadata: metadata
        ))
        try repository.save(result)
        _ = try AppMemoryOSPipelineTriggerCoordinator(facade: self).evaluateAfterL1Capture(now: occurredAt)
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
            sessionID: sessionID,
            metadata: metadata
        ))
        try repository.save(result)
        _ = try AppMemoryOSPipelineTriggerCoordinator(facade: self).evaluateAfterL1Capture(now: occurredAt)
        return result
    }

    public func ingestSourceEvent(
        sourceID: String,
        title: String,
        content: String,
        occurredAt: Date,
        sourceKind: String,
        accountID: String? = nil,
        sessionID: String? = nil,
        workObjectID: String? = nil,
        metadata: [String: String] = [:]
    ) throws -> MemoryOSIngestionResult {
        let eventMetadata = metadata.merging([
            "source_kind": sourceKind,
            "account_id": accountID ?? ""
        ]) { current, _ in current }
        let result = ingestionService.ingest(MemoryOSIngestionInput(
            sourceType: .sourceEvent,
            sourceID: sourceID,
            title: title,
            content: content,
            occurredAt: occurredAt,
            sessionID: sessionID,
            workObjectID: workObjectID,
            metadata: eventMetadata
        ))
        try repository.save(result)
        _ = try AppMemoryOSPipelineTriggerCoordinator(facade: self).evaluateAfterL1Capture(now: occurredAt)
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

    public func runBackgroundAIQueueOnce<Executor: MemoryOSBackgroundModelExecutor>(executor: Executor, workerID: String = "memory-os-background-ai-worker", limit: Int = 5, now: Date = Date()) throws -> [MemoryOSProjectionRunSummary] {
        let kinds = [MemoryOSBackgroundJobKind.l1ProcessBlockToL2.rawValue, MemoryOSBackgroundJobKind.l2SynthesizeKnowledge.rawValue]
        let candidates = try kinds.flatMap { kind in
            try store.runnableQueueItems(kind: kind, limit: limit, now: now)
        }.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.createdAt < rhs.createdAt
        }.prefix(limit)

        var summaries: [MemoryOSProjectionRunSummary] = []
        for candidate in candidates {
            guard let leased = try store.leaseQueueItem(id: candidate.id, workerID: workerID, now: now) else { continue }
            do {
                switch leased.kind {
                case MemoryOSBackgroundJobKind.l1ProcessBlockToL2.rawValue:
                    let draft = try store.decode(MemoryOSL1ToL2JobDraft.self, leased.payloadJSON)
                    let result = try MemoryOSBackgroundJobWorker(executor: executor).run(draft)
                    let summary = try projectAndRecordLLMArtifact(rawContent: result.rawArtifactJSON, modelID: result.metadata["model_id"] ?? workerID, queueItem: leased, processingRunID: result.jobID, artifactType: result.artifactType, schemaName: result.schemaName, now: now)
                    if summary.accepted {
                        let statementIDs = try l2StatementIDs(sourceArtifactID: summary.artifactID)
                        try markL2ProcessingStatesPending(statementIDs: statementIDs, sourceArtifactID: summary.artifactID, now: now)
                        try deleteL1CaptureEvents(ids: draft.captureEventIDs)
                        try saveBackgroundJobAudit(eventType: "memory_os.background_job.projected", subjectID: leased.id, payload: ["artifact_id": summary.artifactID], now: now)
                    } else {
                        try saveBackgroundJobAudit(eventType: "memory_os.background_job.artifact_rejected", subjectID: leased.id, payload: ["artifact_id": summary.artifactID, "issue_count": String(summary.issues.count)], now: now)
                    }
                    summaries.append(summary)
                case MemoryOSBackgroundJobKind.l2SynthesizeKnowledge.rawValue:
                    let draft = try store.decode(MemoryOSL2ToKnowledgeJobDraft.self, leased.payloadJSON)
                    let result = try MemoryOSBackgroundJobWorker(executor: executor).run(draft)
                    let summary = try projectAndRecordLLMArtifact(rawContent: result.rawArtifactJSON, modelID: result.metadata["model_id"] ?? workerID, queueItem: leased, processingRunID: result.jobID, artifactType: result.artifactType, schemaName: result.schemaName, now: now)
                    if summary.accepted {
                        try markL2ProcessingStatesSucceeded(statementIDs: draft.statementIDs, artifactID: summary.artifactID, now: now)
                        try saveBackgroundJobAudit(eventType: "memory_os.background_job.projected", subjectID: leased.id, payload: ["artifact_id": summary.artifactID], now: now)
                    } else {
                        try markL2ProcessingStatesFailed(statementIDs: draft.statementIDs, errorCode: "projection_validation_failed", errorMessage: summary.issues.map(\.message).joined(separator: "; "), now: now)
                        try saveBackgroundJobAudit(eventType: "memory_os.background_job.artifact_rejected", subjectID: leased.id, payload: ["artifact_id": summary.artifactID, "issue_count": String(summary.issues.count)], now: now)
                    }
                    summaries.append(summary)
                default:
                    let failed = try recordQueueFailure(leased, errorCode: "unsupported_background_job_kind", errorMessage: "Unsupported Memory OS background job kind: \(leased.kind)", now: now)
                    summaries.append(MemoryOSProjectionRunSummary(artifactID: leased.id, accepted: false, issues: [MemoryOSValidationIssue(code: failed.errorCode ?? "unsupported_background_job_kind", message: failed.errorMessage ?? leased.kind)]))
                }
            } catch {
                let failed = try recordQueueFailure(leased, errorCode: "background_ai_job_failed", errorMessage: String(describing: error), now: now)
                try saveBackgroundJobAudit(eventType: "memory_os.background_job.model_failed", subjectID: leased.id, payload: ["error_code": failed.errorCode ?? "background_ai_job_failed", "status": failed.status.rawValue], now: now)
                if failed.status == .deadLetter {
                    try saveBackgroundJobAudit(eventType: "memory_os.background_job.dead_lettered", subjectID: leased.id, payload: ["error_code": failed.errorCode ?? "background_ai_job_failed"], now: now)
                }
                summaries.append(MemoryOSProjectionRunSummary(artifactID: leased.id, accepted: false, issues: [MemoryOSValidationIssue(code: failed.errorCode ?? "background_ai_job_failed", message: failed.errorMessage ?? String(describing: error))]))
            }
        }
        return summaries
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

    private func deleteL1CaptureEvents(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        let quoted = ids.map { store.quote($0) }.joined(separator: ",")
        try store.execute("DELETE FROM memory_l1_capture_events WHERE id IN (\(quoted));")
    }

    func l2StatementIDs(sourceArtifactID: String) throws -> [String] {
        try store.queryStrings(sql: """
        SELECT id
        FROM memory_l2_statements
        WHERE source_artifact_id = \(store.quote(sourceArtifactID))
        ORDER BY committed_at ASC, id ASC
        """)
    }

    private func markL2ProcessingStatesPending(statementIDs: [String], sourceArtifactID: String, now: Date) throws {
        for statementID in statementIDs {
            try store.upsert(l2ProcessingState: MemoryOSL2StatementProcessingState(
                statementID: statementID,
                processingKind: .knowledgeSynthesis,
                status: .pending,
                sourceArtifactID: sourceArtifactID,
                metadata: ["created_by": "l1_to_l2_projection", "source_artifact_id": sourceArtifactID]
            ))
        }
        _ = try AppMemoryOSPipelineTriggerCoordinator(facade: self).evaluateAfterL2PendingStatements(now: now)
    }

    private func markL2ProcessingStatesSucceeded(statementIDs: [String], artifactID: String, now: Date) throws {
        for statementID in statementIDs {
            try store.upsert(l2ProcessingState: MemoryOSL2StatementProcessingState(
                statementID: statementID,
                processingKind: .knowledgeSynthesis,
                status: .succeeded,
                processedByArtifactID: artifactID,
                lastAttemptAt: now,
                metadata: ["processed_by_artifact_id": artifactID]
            ))
        }
    }

    private func markL2ProcessingStatesFailed(statementIDs: [String], errorCode: String, errorMessage: String, now: Date) throws {
        for statementID in statementIDs {
            try store.upsert(l2ProcessingState: MemoryOSL2StatementProcessingState(
                statementID: statementID,
                processingKind: .knowledgeSynthesis,
                status: .failed,
                lastAttemptAt: now,
                metadata: ["error_code": errorCode, "error_message": errorMessage]
            ))
        }
    }

    private func saveBackgroundJobAudit(eventType: String, subjectID: String, payload: [String: String], now: Date) throws {
        try store.save(audit: MemoryOSAuditEvent(eventType: eventType, actor: "memory-os", subjectID: subjectID, payload: payload, createdAt: now))
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

    public func readMemoryOSRecordJSON(layer: String, recordID: String) throws -> String {
        let normalizedLayer = layer.uppercased()
        let quotedID = store.quote(recordID)
        let payload: [String: Any]
        switch normalizedLayer {
        case "L0":
            guard let object = try store.provenanceObject(id: recordID) else { throw SQLiteMemoryOSStoreError.missingRecord("Missing L0 provenance object: \(recordID)") }
            payload = [
                "layer": "L0",
                "recordID": object.id,
                "record": [
                    "id": object.id,
                    "sourceType": object.sourceType.rawValue,
                    "sourceID": object.sourceID ?? "",
                    "title": object.title,
                    "content": object.content,
                    "contentHash": object.contentHash,
                    "occurredAt": Self.iso8601(object.occurredAt),
                    "ingestedAt": Self.iso8601(object.ingestedAt),
                    "sessionID": object.sessionID ?? "",
                    "workObjectID": object.workObjectID ?? "",
                    "confidentiality": object.confidentiality.rawValue,
                    "status": object.status.rawValue,
                    "metadata": object.metadata
                ],
                "provenanceRefs": [object.id],
                "evidenceRefs": [],
                "entityRefs": []
            ]
        case "L1":
            let rows = try store.query(sql: """
            SELECT id, provenance_object_id, event_type, occurred_at, token_estimate, processing_state, metadata_json
            FROM memory_l1_capture_events WHERE id = \(quotedID) LIMIT 1
            """)
            guard let row = rows.first else { throw SQLiteMemoryOSStoreError.missingRecord("Missing L1 capture event: \(recordID)") }
            let metadata = (try? store.decode([String: String].self, row[6])) ?? [:]
            payload = ["layer": "L1", "recordID": row[0], "record": ["id": row[0], "provenanceObjectID": row[1], "eventType": row[2], "occurredAt": row[3], "tokenEstimate": Int(row[4]) ?? 0, "processingState": row[5], "metadata": metadata], "provenanceRefs": [row[1]], "evidenceRefs": metadata["span_id"].map { [$0] } ?? [], "entityRefs": []]
        case "L2":
            let rows = try store.query(sql: """
            SELECT id, subject_id, predicate, object_id, text, assertion_kind, confidence, valid_at, committed_at, evidence_span_ids_json, source_artifact_id, metadata_json
            FROM memory_l2_statements WHERE id = \(quotedID) LIMIT 1
            """)
            guard let row = rows.first else { throw SQLiteMemoryOSStoreError.missingRecord("Missing L2 statement: \(recordID)") }
            let evidence = (try? store.decode([String].self, row[9])) ?? []
            let metadata = (try? store.decode([String: String].self, row[11])) ?? [:]
            payload = ["layer": "L2", "recordID": row[0], "record": ["id": row[0], "subjectID": row[1], "predicate": row[2], "objectID": row[3], "text": row[4], "assertionKind": row[5], "confidence": Double(row[6]) ?? 0, "validAt": row[7], "committedAt": row[8], "evidenceSpanIDs": evidence, "sourceArtifactID": row[10], "metadata": metadata], "evidenceRefs": evidence, "provenanceRefs": [], "entityRefs": [row[1], row[3]].filter { !$0.isEmpty }]
        case "L3":
            let rows = try store.query(sql: """
            SELECT id, topic, statement, projection_kind, confidence, evidence_statement_ids_json, valid_at, projected_at, source_artifact_id, metadata_json
            FROM memory_l3_beliefs WHERE id = \(quotedID) LIMIT 1
            """)
            guard let row = rows.first else { throw SQLiteMemoryOSStoreError.missingRecord("Missing L3 knowledge record: \(recordID)") }
            let evidence = (try? store.decode([String].self, row[5])) ?? []
            let metadata = (try? store.decode([String: String].self, row[9])) ?? [:]
            payload = ["layer": "L3", "recordID": row[0], "record": ["id": row[0], "topic": row[1], "statement": row[2], "projectionKind": row[3], "confidence": Double(row[4]) ?? 0, "evidenceStatementIDs": evidence, "validAt": row[6], "projectedAt": row[7], "sourceArtifactID": row[8], "metadata": metadata], "evidenceRefs": evidence, "provenanceRefs": [], "entityRefs": []]
        case "L4":
            if let entity = try store.entity(id: recordID) {
                payload = ["layer": "L4", "recordID": entity.id, "record": ["id": entity.id, "stableKey": entity.stableKey, "entityType": entity.entityType, "name": entity.name, "aliases": entity.aliases, "summary": entity.summary, "confidence": entity.confidence, "createdAt": Self.iso8601(entity.createdAt), "updatedAt": Self.iso8601(entity.updatedAt), "validFrom": entity.validFrom.map(Self.iso8601) ?? "", "metadata": entity.metadata], "evidenceRefs": [], "provenanceRefs": [], "entityRefs": [entity.id]]
            } else {
                let rows = try store.query(sql: """
                SELECT id, entity_id, predicate, object_entity_id, text, assertion_kind, confidence, valid_at, committed_at, evidence_span_ids_json, source_artifact_id, metadata_json
                FROM memory_l4_entity_statements WHERE id = \(quotedID) LIMIT 1
                """)
                guard let row = rows.first else { throw SQLiteMemoryOSStoreError.missingRecord("Missing L4 record: \(recordID)") }
                let evidence = (try? store.decode([String].self, row[9])) ?? []
                let metadata = (try? store.decode([String: String].self, row[11])) ?? [:]
                payload = ["layer": "L4", "recordID": row[0], "record": ["id": row[0], "entityID": row[1], "predicate": row[2], "objectEntityID": row[3], "text": row[4], "assertionKind": row[5], "confidence": Double(row[6]) ?? 0, "validAt": row[7], "committedAt": row[8], "evidenceSpanIDs": evidence, "sourceArtifactID": row[10], "metadata": metadata], "evidenceRefs": evidence, "provenanceRefs": [], "entityRefs": [row[1], row[3]].filter { !$0.isEmpty }]
            }
        default:
            throw SQLiteMemoryOSStoreError.missingRecord("Unsupported Memory OS layer: \(layer)")
        }
        return try Self.renderJSON(payload)
    }

    public func readMemoryOSProvenanceJSON(provenanceObjectID: String, spanID: String? = nil) throws -> String {
        guard let object = try store.provenanceObject(id: provenanceObjectID) else { throw SQLiteMemoryOSStoreError.missingRecord("Missing L0 provenance object: \(provenanceObjectID)") }
        var spanPayload: [String: Any]? = nil
        if let spanID, !spanID.isEmpty {
            let rows = try store.query(sql: """
            SELECT id, provenance_object_id, start_offset, end_offset, text, metadata_json
            FROM memory_l0_provenance_spans WHERE id = \(store.quote(spanID)) LIMIT 1
            """)
            guard let row = rows.first else { throw SQLiteMemoryOSStoreError.missingRecord("Missing L0 provenance span: \(spanID)") }
            spanPayload = ["id": row[0], "provenanceObjectID": row[1], "startOffset": Int(row[2]) ?? 0, "endOffset": Int(row[3]) ?? 0, "text": row[4], "metadata": (try? store.decode([String: String].self, row[5])) ?? [:]]
        }
        let payload: [String: Any] = [
            "provenanceObjectID": object.id,
            "spanID": spanID ?? "",
            "title": object.title,
            "content": object.content,
            "metadata": object.metadata,
            "span": spanPayload ?? [:],
            "citations": [object.id, spanID ?? ""].filter { !$0.isEmpty }
        ]
        return try Self.renderJSON(payload)
    }

    private static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func renderJSON(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
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
