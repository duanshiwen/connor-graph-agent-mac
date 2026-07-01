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

// MARK: - L4 Direct Write Types

public struct MemoryOSL4EntityInput: Codable, Sendable, Equatable {
    public var name: String
    public var type: String
    public var domain: String?
    public var summary: String?
    public var aliases: String?

    public init(name: String, type: String = "concept", domain: String? = nil, summary: String? = nil, aliases: String? = nil) {
        self.name = name; self.type = type; self.domain = domain; self.summary = summary; self.aliases = aliases
    }
}

public struct MemoryOSL4RelationInput: Codable, Sendable, Equatable {
    public var subjectName: String
    public var predicate: MemoryOSL4RelationPredicate
    public var objectName: String
    public var text: String?

    public init(subjectName: String, predicate: MemoryOSL4RelationPredicate, objectName: String, text: String? = nil) {
        self.subjectName = subjectName; self.predicate = predicate; self.objectName = objectName; self.text = text
    }
}

public struct MemoryOSL4WriteResult: Codable, Sendable, Equatable {
    public var sourceID: String
    public var createdEntityCount: Int
    public var createdRelationCount: Int
    public var entityNames: [String]

    public init(sourceID: String, createdEntityCount: Int, createdRelationCount: Int, entityNames: [String]) {
        self.sourceID = sourceID; self.createdEntityCount = createdEntityCount; self.createdRelationCount = createdRelationCount; self.entityNames = entityNames
    }
}

// MARK: - L3 Direct Write Types

public struct MemoryOSL3BeliefInput: Codable, Sendable, Equatable {
    public var statement: String
    public var domain: String?
    public var relatedEntityNames: String?

    public init(statement: String, domain: String? = nil, relatedEntityNames: String? = nil) {
        self.statement = statement; self.domain = domain; self.relatedEntityNames = relatedEntityNames
    }
}

public struct MemoryOSL3WriteResult: Codable, Sendable, Equatable {
    public var sourceID: String
    public var createdBeliefCount: Int

    public init(sourceID: String, createdBeliefCount: Int) {
        self.sourceID = sourceID; self.createdBeliefCount = createdBeliefCount
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

    public func findMemoryOSL2Entities(_ request: MemoryOSL2FindEntitiesRequest) throws -> MemoryOSL2FindEntitiesResult {
        try MemoryOSL2EntityMemoryService(repository: SQLiteMemoryOSL2EntityMemoryRepository(store: store)).findEntities(request)
    }

    public func updateMemoryOSL2Entities(_ request: MemoryOSL2UpdateEntitiesRequest) throws -> MemoryOSL2UpdateEntitiesResult {
        try MemoryOSL2EntityMemoryService(repository: SQLiteMemoryOSL2EntityMemoryRepository(store: store)).updateEntities(request)
    }

    @discardableResult
    public func ensureCurrentUserAnchor(now: Date = Date()) throws -> MemoryOSEntity {
        try MemoryOSPersonIdentityService().ensureCurrentUserAnchor(store: store, now: now)
    }

    public func currentUserProfileContext(now: Date = Date()) throws -> [String] {
        let anchor = try ensureCurrentUserAnchor(now: now)
        _ = anchor
        return try MemoryOSPersonIdentityService().currentUserProfileContext(store: store, now: now)
    }

    public func expandMemoryOSL4(entityName: String, depth: Int = 5, limit: Int = 200) throws -> [MemoryOSL4ExpansionHit] {
        try SQLiteMemoryOSUnifiedRetrievalService(store: store).expandL4(entityName: entityName, depth: depth, limit: limit)
    }

    public func memoryOSContext(_ request: MemoryOSContextRequest, generatedAt: Date = Date()) throws -> MemoryOSContextPackage {
        try MemoryOSContextDeliveryService(store: store, searchKernel: searchKernel).context(request, generatedAt: generatedAt)
    }

    public func memoryOSFlatContext(terms: [String]) throws -> [String] {
        try MemoryOSContextDeliveryService(store: store, searchKernel: searchKernel).flatContext(terms: terms)
    }

    public func findMemoryOSL2Statements(text: String = "", subjectID: String? = nil, predicates: [String] = [], limit: Int = 50) throws -> MemoryOSGraphSubgraph {
        try SQLiteMemoryOSGraphRetrievalService(store: store).l2FindStatements(MemoryOSL2StatementFindQuery(text: text, subjectID: subjectID, predicates: predicates, limit: limit))
    }

    public func expandMemoryOSL3Belief(beliefID: String? = nil, topic: String? = nil, text: String? = nil, limit: Int = 20) throws -> MemoryOSGraphSubgraph {
        try SQLiteMemoryOSGraphRetrievalService(store: store).l3ExpandBelief(MemoryOSL3BeliefExpandQuery(beliefID: beliefID, topic: topic, text: text, limit: limit))
    }

    public func listMemoryOSL3Domains() throws -> [MemoryOSL3DomainSummary] {
        try store.listL3Domains()
    }

    public func findMemoryOSL4Entity(text: String, limit: Int = 20) throws -> MemoryOSGraphSubgraph {
        try SQLiteMemoryOSGraphRetrievalService(store: store).l4FindEntity(MemoryOSL4EntityFindQuery(text: text, limit: limit))
    }

    public func queryMemoryOSL4Neighbors(entityID: String, direction: MemoryOSGraphDirection = .both, predicates: [String] = [], limit: Int = 100) throws -> MemoryOSGraphSubgraph {
        try SQLiteMemoryOSGraphRetrievalService(store: store).l4Neighbors(MemoryOSL4NeighborsQuery(entityID: entityID, direction: direction, predicates: predicates, limit: limit))
    }

    public func queryMemoryOSL4Instances(classEntityIDs: [String], predicates: [String] = [MemoryOSL4RelationPredicate.instanceOf.rawValue], limit: Int = 100) throws -> MemoryOSGraphSubgraph {
        try SQLiteMemoryOSGraphRetrievalService(store: store).l4Instances(MemoryOSL4InstanceQuery(classEntityIDs: classEntityIDs, predicates: predicates, limit: limit))
    }

    // MARK: - Direct L4 Write

    /// Write L4 entities and relations directly (no background pipeline).
    /// Entities are upserted by stableKey; relations are always appended (UUID-based IDs).
    public func writeMemoryOSL4Entities(entities: [MemoryOSL4EntityInput], relations: [MemoryOSL4RelationInput], artifactID: String? = nil, now: Date = Date()) throws -> MemoryOSL4WriteResult {
        let sourceID = artifactID ?? "l4-direct-write:\(UUID().uuidString)"
        var createdEntityCount = 0
        var createdRelationCount = 0
        var entityByName: [String: MemoryOSEntity] = [:]

        for input in entities {
            let normalizedType = MemoryOSEntityType.normalizeRawType(input.type)
            let scope = input.domain ?? "knowledge"
            let stableKey = MemoryOSStableKeyBuilder.stableKey(type: normalizedType, name: input.name, scope: scope)
            let entityID = "l4-entity:\(stableKey)"
            let aliases = MemoryOSL2EntityMemoryService.splitNames(input.aliases ?? "")
            let entity = MemoryOSEntity(
                id: entityID,
                stableKey: stableKey,
                entityType: normalizedType,
                name: input.name,
                aliases: aliases,
                summary: input.summary ?? "",
                confidence: 1.0,
                createdAt: now,
                updatedAt: now,
                validFrom: now,
                metadata: ["artifact_id": sourceID, "domain": scope]
            )
            try store.upsert(entity: entity)
            entityByName[input.name] = entity
            createdEntityCount += 1
        }

        for input in relations {
            guard let subject = entityByName[input.subjectName] else { continue }
            guard let object = entityByName[input.objectName] else { continue }
            let statement = MemoryOSEntityStatement(
                id: "l4-direct-relation:\(sourceID):\(UUID().uuidString)",
                entityID: subject.id,
                predicate: input.predicate,
                objectEntityID: object.id,
                text: input.text ?? "",
                assertionKind: .summarized,
                confidence: 1.0,
                validAt: now,
                committedAt: now,
                evidenceSpanIDs: [],
                sourceArtifactID: sourceID,
                metadata: ["artifact_id": sourceID, "relation_type": "direct_write"]
            )
            try store.upsert(entityStatement: statement)
            createdRelationCount += 1
        }

        return MemoryOSL4WriteResult(
            sourceID: sourceID,
            createdEntityCount: createdEntityCount,
            createdRelationCount: createdRelationCount,
            entityNames: Array(entityByName.keys)
        )
    }

    // MARK: - Direct L3 Write

    public func writeMemoryOSL3Beliefs(_ beliefs: [MemoryOSL3BeliefInput], artifactID: String? = nil, now: Date = Date()) throws -> MemoryOSL3WriteResult {
        let sourceID = artifactID ?? "l3-direct-write:\(UUID().uuidString)"
        var createdCount = 0

        for input in beliefs {
            let belief = MemoryOSBelief(
                id: "l3-knowledge:\(UUID().uuidString)",
                statement: input.statement,
                domain: MemoryOSBelief.normalizedDisciplineDomain(input.domain),
                relatedObjectNames: MemoryOSBelief.normalizedRelatedConceptNames(input.relatedEntityNames ?? ""),
                createdAt: now,
                updatedAt: now
            )
            try store.upsert(belief: belief)
            createdCount += 1
        }

        return MemoryOSL3WriteResult(sourceID: sourceID, createdBeliefCount: createdCount)
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
            metadata: metadata.merging(["source_kind": role == "assistant" ? "assistant_message" : "chat_message"]) { current, _ in current }
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
        schemaName: String = "MemoryOSL1UnifiedProjectionOutput",
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

    public func enqueueL1UnifiedProjectionBackgroundJobs(policy: MemoryOSL1ProcessingTriggerPolicy = MemoryOSL1ProcessingTriggerPolicy(), now: Date = Date()) throws -> [MemoryOSQueueItem] {
        let events = try pendingCaptureEvents(limit: max(policy.minPendingCount * 2, policy.maxEventsPerBlock * 4))
        let drafts = MemoryOSL1UnifiedProjectionJobPlanner(policy: policy).planJobs(from: events, now: now)
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

    public func runBackgroundAIQueueOnce<Executor: MemoryOSBackgroundModelExecutor>(executor: Executor, workerID: String = "memory-os-background-ai-worker", limit: Int = 5, now: Date = Date(), kinds requestedKinds: [String]? = nil) throws -> [MemoryOSProjectionRunSummary] {
        let kinds = requestedKinds ?? MemoryOSBackgroundJobKind.l1ExecutableRawValues
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
                case let kind where MemoryOSBackgroundJobKind.isL1KnowledgeKind(kind):
                    var draft = try store.decode(MemoryOSL1UnifiedProjectionJobDraft.self, leased.payloadJSON)
                    draft.metadata = backgroundRunMetadata(draft.metadata, queueItem: leased)
                    _ = try MemoryOSBackgroundJobWorker(executor: executor).run(draft)
                    // LLM has written L2/L3/L4 directly via tool calls — clean up L1 events.
                    try deleteL1CaptureEvents(ids: draft.captureEventIDs)
                    _ = try recordQueueSuccess(leased, now: now)
                    try saveBackgroundJobAudit(eventType: "memory_os.background_job.completed", subjectID: leased.id, payload: ["event_count": String(draft.captureEventIDs.count)], now: now)
                    summaries.append(MemoryOSProjectionRunSummary(artifactID: leased.id, accepted: true))
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

    private func backgroundRunMetadata(_ metadata: [String: String], queueItem: MemoryOSQueueItem) -> [String: String] {
        metadata.merging([
            "queue_item_id": queueItem.id,
            "background_run_id": "memory-run:\(queueItem.id)"
        ]) { current, _ in current }
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
            SELECT id, statement, domain, related_object_names, created_at, updated_at
            FROM memory_l3_beliefs WHERE id = \(quotedID) LIMIT 1
            """)
            guard let row = rows.first else { throw SQLiteMemoryOSStoreError.missingRecord("Missing L3 knowledge record: \(recordID)") }
            payload = ["layer": "L3", "recordID": row[0], "record": ["id": row[0], "statement": row[1], "domain": row[2], "relatedObjectNames": row[3], "createdAt": row[4], "updatedAt": row[5]], "evidenceRefs": [], "provenanceRefs": [], "entityRefs": []]
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
