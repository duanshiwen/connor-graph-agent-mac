import Foundation
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore
import ConnorGraphSearch

public struct AppMemoryOSCLIInspector: Sendable {
    public var store: SQLiteMemoryOSStore
    public var databasePath: String
    public var searchKernel: MemoryOSSearchKernel?

    public init(store: SQLiteMemoryOSStore, databasePath: String = "memory-os.sqlite", searchKernel: MemoryOSSearchKernel? = nil) {
        self.store = store
        self.databasePath = databasePath
        self.searchKernel = searchKernel
    }

    public func status(now: Date = Date()) throws -> MemoryOSCLIStatus {
        let health = try store.schemaHealthReport(now: now)
        let queue = try store.queueOperationalSnapshot(now: now)
        let layers = try layerCounts()
        let metrics = try store.recentMetricSums(names: [
            "memory_os.projection.accepted",
            "memory_os.projection.rejected",
            "memory_os.projection.degraded_accepted",
            "memory_os.projection.records.repaired",
            "memory_os.projection.records.degraded",
            "memory_os.projection.records.dropped"
        ])
        return MemoryOSCLIStatus(
            databasePath: databasePath,
            schema: MemoryOSCLISchemaStatus(
                expectedVersion: health.expectedVersion,
                actualVersion: health.actualVersion,
                health: health.status.rawValue,
                missingTables: health.missingTables,
                missingIndexes: health.missingIndexes
            ),
            layers: MemoryOSCLIStatusLayerCounts(
                l0ProvenanceObjects: layers.l0.objects,
                l0ProvenanceSpans: layers.l0.spans,
                l1CaptureEvents: layers.l1.captureEvents,
                l1PendingCaptureEvents: layers.l1.pending,
                l1QueueItems: layers.l1.queueItems,
                l2Nodes: layers.l2.nodes,
                l2Statements: layers.l2.statements,
                l3Beliefs: layers.l3.beliefs,
                l4Entities: layers.l4.entities,
                l4EntityStatements: layers.l4.entityStatements
            ),
            queue: MemoryOSCLIQueueCounts(
                pending: queue.pending,
                leased: queue.leased,
                processing: queue.processing,
                retryScheduled: queue.retryScheduled,
                succeeded: queue.succeeded,
                failed: queue.failed,
                deadLetter: queue.deadLetter,
                expiredLeases: queue.expiredLeases
            ),
            observability: MemoryOSCLIObservabilityStatus(
                acceptedProjectionCount: Int(metrics["memory_os.projection.accepted", default: 0]),
                rejectedProjectionCount: Int(metrics["memory_os.projection.rejected", default: 0]),
                degradedAcceptedProjectionCount: Int(metrics["memory_os.projection.degraded_accepted", default: 0]),
                repairedRecordCount: Int(metrics["memory_os.projection.records.repaired", default: 0]),
                degradedRecordCount: Int(metrics["memory_os.projection.records.degraded", default: 0]),
                droppedRecordCount: Int(metrics["memory_os.projection.records.dropped", default: 0])
            )
        )
    }

    public func stats() throws -> MemoryOSCLIStats {
        var tables: [String: Int] = [:]
        for table in MemoryOSCLIInspectorTable.defaultTables {
            tables[table] = try count(table)
        }
        return MemoryOSCLIStats(tables: tables)
    }

    public func layers() throws -> MemoryOSCLILayerSummary {
        try layerCounts()
    }

    public func listL0Objects(limit: Int = 20) throws -> [MemoryOSCLIRow] {
        try rows(sql: """
        SELECT id, source_type, source_id, title, content, content_hash, occurred_at, ingested_at, session_id, work_object_id, confidentiality, status, metadata_json
        FROM memory_l0_provenance_objects
        ORDER BY occurred_at DESC, id ASC
        LIMIT \(safeLimit(limit))
        """, columns: ["id", "source_type", "source_id", "title", "content", "content_hash", "occurred_at", "ingested_at", "session_id", "work_object_id", "confidentiality", "status", "metadata_json"])
    }

    public func listL0Spans(limit: Int = 20) throws -> [MemoryOSCLIRow] {
        try rows(sql: """
        SELECT id, provenance_object_id, start_offset, end_offset, text, metadata_json
        FROM memory_l0_provenance_spans
        ORDER BY id ASC
        LIMIT \(safeLimit(limit))
        """, columns: ["id", "provenance_object_id", "start_offset", "end_offset", "text", "metadata_json"])
    }


    public func listL1Pending(limit: Int = 20) throws -> [MemoryOSCLIRow] {
        try rows(sql: """
        SELECT c.id, c.provenance_object_id, c.event_type, c.occurred_at, c.token_estimate, c.processing_state, c.metadata_json, o.title, o.content, o.content
        FROM memory_l1_capture_events c
        JOIN memory_l0_provenance_objects o ON o.id = c.provenance_object_id
        WHERE c.processing_state IN ('pending', 'queued')
        ORDER BY c.occurred_at ASC, c.id ASC
        LIMIT \(safeLimit(limit))
        """, columns: ["id", "provenance_object_id", "event_type", "occurred_at", "token_estimate", "processing_state", "metadata_json", "provenance_title", "provenance_content", "content"])
    }

    public func listL2Statements(limit: Int = 20) throws -> [MemoryOSCLIRow] {
        try rows(sql: """
        SELECT id, subject_id, predicate, object_id, text, assertion_kind, confidence, valid_at, committed_at, evidence_span_ids_json, source_artifact_id, metadata_json
        FROM memory_l2_statements
        ORDER BY committed_at DESC, id ASC
        LIMIT \(safeLimit(limit))
        """, columns: ["id", "subject_id", "predicate", "object_id", "text", "assertion_kind", "confidence", "valid_at", "committed_at", "evidence_span_ids_json", "source_artifact_id", "metadata_json"])
    }

    public func findL2Entities(names: String) throws -> MemoryOSL2FindEntitiesResult {
        try AppMemoryOSFacade(store: store, searchKernel: searchKernel).findMemoryOSL2Entities(MemoryOSL2FindEntitiesRequest(names: names))
    }

    public func updateL2Entities(_ request: MemoryOSL2UpdateEntitiesRequest) throws -> MemoryOSL2UpdateEntitiesResult {
        try AppMemoryOSFacade(store: store, searchKernel: searchKernel).updateMemoryOSL2Entities(request)
    }

    public func listL3Beliefs(limit: Int = 20) throws -> [MemoryOSCLIRow] {
        try rows(sql: """
        SELECT id, statement, domain, related_object_names, created_at, updated_at
        FROM memory_l3_beliefs
        ORDER BY updated_at DESC, id ASC
        LIMIT \(safeLimit(limit))
        """, columns: ["id", "statement", "domain", "related_object_names", "created_at", "updated_at"])
    }

    public func listL3Domains() throws -> [MemoryOSL3DomainSummary] {
        try store.listL3Domains()
    }

    public func expandL3Belief(beliefID: String? = nil, topic: String? = nil, text: String? = nil, limit: Int = 20) throws -> MemoryOSGraphSubgraph {
        try AppMemoryOSFacade(store: store, searchKernel: searchKernel).expandMemoryOSL3Belief(beliefID: beliefID, topic: topic, text: text, limit: safeLimit(limit))
    }

    public func listL4Entities(limit: Int = 20) throws -> [MemoryOSCLIRow] {
        try rows(sql: """
        SELECT id, stable_key, entity_type, name, aliases_json, summary, confidence, created_at, updated_at, valid_from, metadata_json
        FROM memory_l4_entities
        ORDER BY updated_at DESC, id ASC
        LIMIT \(safeLimit(limit))
        """, columns: ["id", "stable_key", "entity_type", "name", "aliases_json", "summary", "confidence", "created_at", "updated_at", "valid_from", "metadata_json"])
    }

    public func listL4Predicates() -> [MemoryOSCLIL4Predicate] {
        MemoryOSL4RelationPredicate.allCases.map { predicate in
            MemoryOSCLIL4Predicate(
                predicate: predicate.rawValue,
                category: predicate.category.rawValue,
                inverse: predicate.inverse?.rawValue,
                symmetric: predicate.isSymmetric,
                transitive: predicate.isTransitive,
                strict: predicate.isStrict,
                retrievalWeight: predicate.retrievalWeight,
                description: predicate.description
            )
        }.sorted { lhs, rhs in
            if lhs.category != rhs.category { return lhs.category < rhs.category }
            return lhs.predicate < rhs.predicate
        }
    }

    public func findL4Entity(text: String, limit: Int = 20) throws -> MemoryOSGraphSubgraph {
        try AppMemoryOSFacade(store: store, searchKernel: searchKernel).findMemoryOSL4Entity(text: text, limit: safeLimit(limit))
    }

    public func listL4Neighbors(entityID: String, direction: MemoryOSGraphDirection = .both, predicates: [String] = [], limit: Int = 100) throws -> MemoryOSGraphSubgraph {
        try AppMemoryOSFacade(store: store, searchKernel: searchKernel).queryMemoryOSL4Neighbors(entityID: entityID, direction: direction, predicates: predicates, limit: safeLimit(limit))
    }

    public func listL4Instances(classEntityIDs: [String], predicates: [String] = [MemoryOSL4RelationPredicate.instanceOf.rawValue], limit: Int = 100) throws -> MemoryOSGraphSubgraph {
        try SQLiteMemoryOSGraphRetrievalService(store: store).l4Instances(MemoryOSL4InstanceQuery(classEntityIDs: classEntityIDs, predicates: predicates, limit: safeLimit(limit)))
    }

    public func queue(limit: Int = 20, status: String? = nil, kind: String? = nil) throws -> [MemoryOSCLIRow] {
        let statusClause = status.map { " AND status = \(store.quote($0))" } ?? ""
        let kindClause = kind.map { " AND kind = \(store.quote($0))" } ?? ""
        let baseRows = try rows(sql: """
        SELECT id, kind, status, priority, payload_json, attempt_count, max_attempts, next_run_at, locked_at, locked_by, lease_expires_at, idempotency_key, payload_hash, created_at, updated_at, error_code, error_message
        FROM memory_l1_processing_queue
        WHERE 1 = 1\(statusClause)\(kindClause)
        ORDER BY created_at DESC, priority DESC, id ASC
        LIMIT \(safeLimit(limit))
        """, columns: ["id", "kind", "status", "priority", "payload_json", "attempt_count", "max_attempts", "next_run_at", "locked_at", "locked_by", "lease_expires_at", "idempotency_key", "payload_hash", "created_at", "updated_at", "error_code", "error_message"])
        return try baseRows.map { row in
            var values = row.values
            values["context_text"] = try queueContextText(for: row)
            return MemoryOSCLIRow(values: values)
        }
    }

    public func runs(limit: Int = 20) throws -> [MemoryOSBackgroundRunRecord] {
        try store.backgroundRuns(limit: safeLimit(limit))
    }

    public func runMessages(runID: String) throws -> [MemoryOSBackgroundMessageRecord] {
        try store.backgroundMessages(runID: runID)
    }

    public func runToolCalls(runID: String) throws -> [MemoryOSBackgroundToolCallRecord] {
        try store.backgroundToolCalls(runID: runID)
    }

    public func l1History(limit: Int = 20) throws -> [MemoryOSCLIRow] {
        let l1Kinds = MemoryOSBackgroundJobKind.l1ExecutableRawValues.map { store.quote($0) }.joined(separator: ", ")
        let rows = try rows(sql: """
            SELECT id, kind, status, attempt_count, max_attempts, next_run_at, locked_at, locked_by, lease_expires_at, error_code, error_message, created_at, updated_at
            FROM memory_l1_processing_queue
            WHERE kind IN (\(l1Kinds))
            ORDER BY created_at DESC
            LIMIT \(safeLimit(limit))
            """, columns: ["id", "kind", "status", "attempt_count", "max_attempts", "next_run_at", "locked_at", "locked_by", "lease_expires_at", "error_code", "error_message", "created_at", "updated_at"])
        return try rows.map { row in
            var values = row.values
            values["context_text"] = try queueContextText(for: row)
            return MemoryOSCLIRow(values: values)
        }
    }

    public func pipelinePolicy() -> MemoryOSCLIPipelinePolicy {
        let l1 = MemoryOSL1ProcessingTriggerPolicy()
        return MemoryOSCLIPipelinePolicy(
            l1UnifiedProjection: MemoryOSCLIL1PipelinePolicy(
                minPendingCount: l1.minPendingCount,
                maxEventsPerBlock: l1.maxEventsPerBlock,
                maxTokensPerBlock: l1.maxTokensPerBlock,
                maxPendingAgeSeconds: l1.maxPendingAge.map(Int.init)
            )
        )
    }

    public func planL1(policy: MemoryOSL1ProcessingTriggerPolicy = MemoryOSL1ProcessingTriggerPolicy(), now: Date = Date()) throws -> MemoryOSCLIPlanResult {
        let jobs = try AppMemoryOSFacade(store: store).enqueueL1UnifiedProjectionBackgroundJobs(policy: policy, now: now)
        return MemoryOSCLIPlanResult(plannedJobs: jobs.count, kind: MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue, jobIDs: jobs.map(\.id))
    }

    public func ingestChatMessage(
        content: String,
        sessionID: String,
        messageID: String,
        intentNormalizer: AnyMemoryOSUserIntentNormalizer,
        now: Date = Date()
    ) async -> MemoryOSCLIChatIngestionResult {
        var retrievalText: String?
        var normalizationStatus = MemoryOSIntentNormalizationStatus.failed
        var modelID: String?
        var errorMessage: String?
        do {
            let normalization = try await intentNormalizer.normalize(message: content)
            retrievalText = normalization.retrievalText
            normalizationStatus = .succeeded
            modelID = normalization.modelID
        } catch {
            errorMessage = String(describing: error)
        }

        do {
            let ingestion = try AppMemoryOSFacade(store: store, searchKernel: searchKernel).ingestChatMessage(
                messageID: messageID,
                sessionID: sessionID,
                role: "user",
                content: content,
                occurredAt: now,
                retrievalText: retrievalText,
                normalizationStatus: normalizationStatus,
                metadata: ["source": "cli_memory_test"]
            )
            return MemoryOSCLIChatIngestionResult(
                status: "ingested",
                messageID: messageID,
                provenanceObjectID: ingestion.provenanceObject?.id,
                captureEventID: ingestion.captureEvent?.id,
                normalizationStatus: normalizationStatus.rawValue,
                retrievalText: retrievalText,
                modelID: modelID,
                originalCharacterCount: content.count,
                error: errorMessage
            )
        } catch {
            return MemoryOSCLIChatIngestionResult(
                status: "failed",
                messageID: messageID,
                normalizationStatus: normalizationStatus.rawValue,
                retrievalText: retrievalText,
                modelID: modelID,
                originalCharacterCount: content.count,
                error: String(describing: error)
            )
        }
    }

    public func hasRunnableBackgroundAIJob(kind: String? = nil, limit: Int = 1, now: Date = Date()) throws -> Bool {
        let effectiveLimit = safeLimit(limit)
        let executableKinds = kind.map { [$0] } ?? MemoryOSBackgroundJobKind.l1ExecutableRawValues
        for executableKind in executableKinds where try !store.runnableQueueItems(kind: executableKind, limit: effectiveLimit, now: now).isEmpty {
            return true
        }
        return false
    }

    public func debugRunNextBackgroundAI(kind: String? = nil, limit: Int = 1) throws -> MemoryOSCLIDebugAIRunResult {
        MemoryOSCLIDebugAIRunResult(
            status: "no_runnable_jobs",
            command: "memory pipeline debug-run-next",
            requestedKind: kind,
            requestedLimit: safeLimit(limit),
            queueRuns: []
        )
    }

    public func debugRunNextBackgroundAI<Model: MemoryOSBackgroundToolLoopModel>(kind: String? = nil, limit: Int = 1, model: Model, configuration: MemoryOSBackgroundToolLoopConfiguration = MemoryOSBackgroundToolLoopConfiguration(), now: Date = Date(), logHandler: MemoryOSLoopLogHandler? = nil) throws -> MemoryOSCLIDebugAIRunResult {
        let effectiveLimit = safeLimit(limit)
        let executableKinds = kind.map { [$0] } ?? MemoryOSBackgroundJobKind.l1ExecutableRawValues
        let plannedCandidates = try executableKinds.flatMap { executableKind in
            try store.runnableQueueItems(kind: executableKind, limit: effectiveLimit, now: now)
        }.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return lhs.createdAt < rhs.createdAt
        }.prefix(effectiveLimit)
        guard !plannedCandidates.isEmpty else {
            return MemoryOSCLIDebugAIRunResult(status: "no_runnable_jobs", command: "memory pipeline debug-run-next", requestedKind: kind, requestedLimit: effectiveLimit, queueRuns: [])
        }

        logHandler?("Found \(plannedCandidates.count) runnable job(s). Starting execution...\n")
        let facade = AppMemoryOSFacade(store: store, searchKernel: searchKernel)
        let executor = MemoryOSHeadlessKnowledgeLoopExecutor(
            model: model,
            toolExecutor: MemoryOSBackgroundToolExecutor(facade: facade),
            store: store,
            configuration: configuration,
            now: { now },
            logHandler: logHandler
        )
        let summaries = try facade.runBackgroundAIQueueOnce(executor: executor, limit: effectiveLimit, now: now, kinds: executableKinds)
        let queueRuns = try plannedCandidates.enumerated().map { index, candidate in
            let runID = "memory-run:\(candidate.id)"
            let messages = try store.backgroundMessages(runID: runID)
            let toolCalls = try store.backgroundToolCalls(runID: runID)
            let run = try store.backgroundRuns(limit: max(20, effectiveLimit * 4)).first { $0.id == runID }
            return MemoryOSCLIDebugAIQueueRun(
                queueItemID: candidate.id,
                kind: candidate.kind,
                runID: run?.id ?? (messages.isEmpty && toolCalls.isEmpty ? nil : runID),
                modelID: run?.modelID ?? model.modelID,
                status: run?.status.rawValue ?? (summaries.indices.contains(index) ? (summaries[index].accepted ? "succeeded" : "failed") : "unknown"),
                messageCount: messages.count,
                toolCallCount: toolCalls.count,
                projectionSummary: summaries.indices.contains(index) ? summaries[index] : nil,
                messages: messages,
                toolCalls: toolCalls
            )
        }
        return MemoryOSCLIDebugAIRunResult(
            status: queueRuns.isEmpty ? "no_runnable_jobs" : "completed",
            command: "memory pipeline debug-run-next",
            requestedKind: kind,
            requestedLimit: effectiveLimit,
            queueRuns: queueRuns
        )
    }

    public func searchIndexStats(fileManager: FileManager = .default) throws -> MemoryOSCLISearchIndexStats {
        guard let searchKernel else { throw MemoryOSCLISearchIndexError.kernelUnavailable }
        let meta = try readSearchIndexMeta(indexDirectory: searchKernel.indexDirectory, fileManager: fileManager)
        let size = directorySize(searchKernel.indexDirectory, fileManager: fileManager)
        let tantivyMetaURL = searchKernel.indexDirectory.appendingPathComponent("meta.json")
        let segmentCount = tantivySegmentCount(tantivyMetaURL: tantivyMetaURL)
        return MemoryOSCLISearchIndexStats(
            libraryPath: searchKernel.libraryURL.path,
            indexDirectory: searchKernel.indexDirectory.path,
            connorMeta: meta,
            indexSizeBytes: size,
            tantivySegmentCount: segmentCount
        )
    }

    public func rebuildSearchIndex(now: Date = Date()) throws -> MemoryOSCLISearchIndexRebuildResult {
        guard let searchKernel else { throw MemoryOSCLISearchIndexError.kernelUnavailable }
        let count = try searchKernel.rebuildFromSQLite(databaseURL: URL(fileURLWithPath: databasePath))
        try AppMemoryOSSearchKernelFactory.writeMeta(indexDirectory: searchKernel.indexDirectory, databaseURL: URL(fileURLWithPath: databasePath), documentCount: count, builtAt: now)
        return MemoryOSCLISearchIndexRebuildResult(
            status: "rebuilt",
            documentCount: count,
            databasePath: databasePath,
            indexDirectory: searchKernel.indexDirectory.path,
            schemaVersion: AppMemoryOSSearchKernelFactory.currentIndexSchemaVersion
        )
    }

    public func verifySearchIndex(fileManager: FileManager = .default) throws -> MemoryOSCLISearchIndexVerifyResult {
        guard let searchKernel else { throw MemoryOSCLISearchIndexError.kernelUnavailable }
        var checks: [MemoryOSCLISearchIndexCheck] = []
        func check(_ name: String, _ passed: Bool, _ message: String) {
            checks.append(MemoryOSCLISearchIndexCheck(name: name, passed: passed, message: message))
        }

        check("library_exists", fileManager.fileExists(atPath: searchKernel.libraryURL.path), searchKernel.libraryURL.path)
        check("database_exists", fileManager.fileExists(atPath: databasePath), databasePath)
        check("index_directory_exists", fileManager.fileExists(atPath: searchKernel.indexDirectory.path), searchKernel.indexDirectory.path)

        var meta: MemoryOSCLISearchIndexMeta?
        do {
            meta = try readSearchIndexMeta(indexDirectory: searchKernel.indexDirectory, fileManager: fileManager)
            check("connor_meta_exists", true, AppMemoryOSSearchKernelFactory.connorMetaFilename)
            check("schema_version_current", meta?.indexSchemaVersion == AppMemoryOSSearchKernelFactory.currentIndexSchemaVersion, "expected \(AppMemoryOSSearchKernelFactory.currentIndexSchemaVersion), actual \(meta?.indexSchemaVersion ?? -1)")
            check("document_count_positive", (meta?.documentCount ?? 0) > 0, "documentCount=\(meta?.documentCount ?? 0)")
            if let indexed = meta?.sourceDatabaseFingerprint {
                let current = try currentSearchIndexFingerprint(fileManager: fileManager)
                check("source_database_fingerprint_current", indexed.isCurrentEnough(comparedTo: current), indexed.diffSummary(comparedTo: current))
            } else {
                check("source_database_fingerprint_current", false, "missing sourceDatabaseFingerprint in \(AppMemoryOSSearchKernelFactory.connorMetaFilename)")
            }
        } catch {
            meta = nil
            check("connor_meta_exists", false, error.localizedDescription)
        }

        let smokeQueries = (meta?.documentCount ?? 0) < 100 ? ["Memory"] : ["中国", "Q148", "国家", "有哪些国家", "P31"]
        var smokeResults: [String: Int] = [:]
        for query in smokeQueries {
            do {
                let response = try searchKernel.search(MemoryOSSearchKernelRequest(query: query, layers: [.l4], limit: 5))
                smokeResults[query] = response.hits.count
                check("smoke_\(query)", !response.hits.isEmpty, "hits=\(response.hits.count)")
            } catch {
                smokeResults[query] = 0
                check("smoke_\(query)", false, error.localizedDescription)
            }
        }
        return MemoryOSCLISearchIndexVerifyResult(status: checks.allSatisfy(\.passed) ? "ok" : "failed", checks: checks, smokeResults: smokeResults, meta: meta)
    }

    public func search(query: String, layers: [String] = [], limit: Int = 20) throws -> MemoryOSCLISearchResult {
        let normalizedLayers = layers.compactMap(normalizedLayer)
        let retrievalLayers = normalizedLayers.isEmpty
            ? MemoryOSRetrievalLayer.allCases
            : normalizedLayers.compactMap(MemoryOSRetrievalLayer.init(rawValue:))
        let hits = try AppMemoryOSFacade(store: store, searchKernel: searchKernel).searchMemoryOS(MemoryOSRetrievalQuery(text: query, layers: retrievalLayers, limit: safeLimit(limit), depth: 0))
        return MemoryOSCLISearchResult(
            query: query,
            hits: Array(hits.prefix(safeLimit(limit))).map { hit in
                MemoryOSCLISearchHit(
                    layer: hit.layer.rawValue,
                    id: hit.recordID,
                    title: hit.title,
                    snippet: hit.summary.isEmpty ? hit.matchedText : hit.summary,
                    content: searchHitContent(for: hit),
                    score: hit.score,
                    evidenceRefs: hit.evidenceRefs,
                    provenanceRefs: hit.provenanceRefs,
                    entityRefs: hit.entityRefs
                )
            }
        )
    }

    public func context(query: String) throws -> [String] {
        let terms = MemorySearchQueryParser.parse(query).terms
        guard !terms.isEmpty else { return [] }
        let facade = AppMemoryOSFacade(store: store)
        return try facade.memoryOSRecentContext(terms: terms) + facade.memoryOSKnowledgeContext(terms: terms)
    }

    private func searchHitContent(for hit: MemoryOSRetrievalHit) -> String {
        return hit.matchedText
    }

    public func read(layer: String, id: String) throws -> MemoryOSCLIRecord? {
        switch normalizedLayer(layer) {
        case "L0":
            return try firstRecord(layer: "L0", sql: """
            SELECT id, source_type, source_id, title, content, content_hash, occurred_at, ingested_at, session_id, work_object_id, confidentiality, status, metadata_json
            FROM memory_l0_provenance_objects WHERE id = \(store.quote(id)) LIMIT 1
            """, columns: ["id", "source_type", "source_id", "title", "content", "content_hash", "occurred_at", "ingested_at", "session_id", "work_object_id", "confidentiality", "status", "metadata_json"])
        case "L1":
            return try firstRecord(layer: "L1", sql: """
            SELECT c.id, c.provenance_object_id, c.event_type, c.occurred_at, c.token_estimate, c.processing_state, c.metadata_json, o.title, o.content, o.content
            FROM memory_l1_capture_events c
            JOIN memory_l0_provenance_objects o ON o.id = c.provenance_object_id
            WHERE c.id = \(store.quote(id))
            LIMIT 1
            """, columns: ["id", "provenance_object_id", "event_type", "occurred_at", "token_estimate", "processing_state", "metadata_json", "provenance_title", "provenance_content", "content"])
        case "L2":
            return try firstRecord(layer: "L2", sql: """
            SELECT id, subject_id, predicate, object_id, text, assertion_kind, confidence, valid_at, committed_at, evidence_span_ids_json, source_artifact_id, metadata_json
            FROM memory_l2_statements WHERE id = \(store.quote(id)) LIMIT 1
            """, columns: ["id", "subject_id", "predicate", "object_id", "text", "assertion_kind", "confidence", "valid_at", "committed_at", "evidence_span_ids_json", "source_artifact_id", "metadata_json"])
        case "L3":
            return try firstRecord(layer: "L3", sql: """
            SELECT id, statement, domain, related_object_names, created_at, updated_at
            FROM memory_l3_beliefs WHERE id = \(store.quote(id)) LIMIT 1
            """, columns: ["id", "statement", "domain", "related_object_names", "created_at", "updated_at"])
        case "L4":
            return try firstRecord(layer: "L4", sql: """
            SELECT id, stable_key, entity_type, name, aliases_json, summary, confidence, created_at, updated_at, valid_from, metadata_json
            FROM memory_l4_entities WHERE id = \(store.quote(id)) LIMIT 1
            """, columns: ["id", "stable_key", "entity_type", "name", "aliases_json", "summary", "confidence", "created_at", "updated_at", "valid_from", "metadata_json"])
        default:
            return nil
        }
    }

    private func readSearchIndexMeta(indexDirectory: URL, fileManager: FileManager) throws -> MemoryOSCLISearchIndexMeta {
        let metaURL = indexDirectory.appendingPathComponent(AppMemoryOSSearchKernelFactory.connorMetaFilename)
        let data = try Data(contentsOf: metaURL)
        return try JSONDecoder().decode(MemoryOSCLISearchIndexMeta.self, from: data)
    }

    private func directorySize(_ url: URL, fileManager: FileManager) -> Int64 {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    private func currentSearchIndexFingerprint(fileManager: FileManager) throws -> MemoryOSCLISearchIndexFingerprint {
        let object = AppMemoryOSSearchKernelFactory.sourceDatabaseFingerprint(databaseURL: URL(fileURLWithPath: databasePath), fileManager: fileManager)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try JSONDecoder().decode(MemoryOSCLISearchIndexFingerprint.self, from: data)
    }

    private func tantivySegmentCount(tantivyMetaURL: URL) -> Int {
        guard let data = try? Data(contentsOf: tantivyMetaURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let segments = object["segments"] as? [Any]
        else { return 0 }
        return segments.count
    }

    private func layerCounts() throws -> MemoryOSCLILayerSummary {
        MemoryOSCLILayerSummary(
            l0: MemoryOSCLIL0Counts(
                objects: try count("memory_l0_provenance_objects"),
                spans: try count("memory_l0_provenance_spans")
            ),
            l1: MemoryOSCLIL1Counts(
                captureEvents: try count("memory_l1_capture_events"),
                pending: try count("memory_l1_capture_events", where: "processing_state IN ('pending', 'queued')"),
                queueItems: try count("memory_l1_processing_queue"),
                deadLetters: try count("memory_l1_dead_letter_queue")
            ),
            l2: MemoryOSCLIL2Counts(
                nodes: try count("memory_l2_nodes"),
                statements: try count("memory_l2_statements")
            ),
            l3: MemoryOSCLIL3Counts(
                beliefs: try count("memory_l3_beliefs")
            ),
            l4: MemoryOSCLIL4Counts(
                entities: try count("memory_l4_entities"),
                entityStatements: try count("memory_l4_entity_statements")
            )
        )
    }

    private func count(_ table: String, where predicate: String? = nil) throws -> Int {
        let whereClause = predicate.map { " WHERE \($0)" } ?? ""
        return Int(try store.query(sql: "SELECT COUNT(*) FROM \(table)\(whereClause);").first?.first ?? "0") ?? 0
    }

    private func rows(sql: String, columns: [String]) throws -> [MemoryOSCLIRow] {
        try store.query(sql: sql).map { row in
            MemoryOSCLIRow(values: Dictionary(uniqueKeysWithValues: zip(columns, row)))
        }
    }

    private func firstRecord(layer: String, sql: String, columns: [String]) throws -> MemoryOSCLIRecord? {
        try rows(sql: sql, columns: columns).first.map { MemoryOSCLIRecord(layer: layer, record: $0) }
    }

    private func queueContextText(for row: MemoryOSCLIRow) throws -> String {
        guard let kind = row.values["kind"], let payload = row.values["payload_json"] else { return "" }
        switch kind {
        case let rawKind where MemoryOSBackgroundJobKind.isL1KnowledgeKind(rawKind):
            let draft = try? store.decode(MemoryOSL1UnifiedProjectionJobDraft.self, payload)
            return try provenanceContent(forCaptureEventIDs: draft?.captureEventIDs ?? [])
        default:
            return ""
        }
    }

    private func provenanceContent(forCaptureEventIDs ids: [String]) throws -> String {
        guard !ids.isEmpty else { return "" }
        let quotedIDs = ids.map(store.quote).joined(separator: ", ")
        let rows = try store.query(sql: """
        SELECT o.content
        FROM memory_l1_capture_events c
        JOIN memory_l0_provenance_objects o ON o.id = c.provenance_object_id
        WHERE c.id IN (\(quotedIDs))
        ORDER BY c.occurred_at ASC, c.id ASC
        """)
        return rows.map { $0.first ?? "" }.filter { !$0.isEmpty }.joined(separator: "\n---\n")
    }

    private func statementText(forStatementIDs ids: [String]) throws -> String {
        guard !ids.isEmpty else { return "" }
        let quotedIDs = ids.map(store.quote).joined(separator: ", ")
        let rows = try store.query(sql: """
        SELECT text
        FROM memory_l2_statements
        WHERE id IN (\(quotedIDs))
        ORDER BY committed_at ASC, id ASC
        """)
        return rows.map { $0.first ?? "" }.filter { !$0.isEmpty }.joined(separator: "\n---\n")
    }

    private func normalizedLayer(_ layer: String) -> String? {
        switch layer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "l0", "provenance", "object", "provenance_object": "L0"
        case "l1", "capture", "event", "capture_event": "L1"
        case "l2", "statement": "L2"
        case "l3", "belief", "knowledge": "L3"
        case "l4", "entity": "L4"
        default: nil
        }
    }

    private func safeLimit(_ limit: Int) -> Int {
        min(max(limit, 1), 500)
    }
}

public struct MemoryOSCLIRow: Codable, Sendable, Equatable {
    public var values: [String: String]

    public init(values: [String: String]) {
        self.values = values
    }
}

public struct MemoryOSCLIRecord: Codable, Sendable, Equatable {
    public var layer: String
    public var record: MemoryOSCLIRow

    public init(layer: String, record: MemoryOSCLIRow) {
        self.layer = layer
        self.record = record
    }
}

public struct MemoryOSCLISearchResult: Codable, Sendable, Equatable {
    public var query: String
    public var hits: [MemoryOSCLISearchHit]
}

public enum MemoryOSCLISearchIndexError: Error, Sendable {
    case kernelUnavailable
}

public struct MemoryOSCLISearchIndexMeta: Codable, Sendable, Equatable {
    public var indexSchemaVersion: Int
    public var searchKernelVersion: String
    public var sourceDatabasePath: String
    public var indexedLayers: [String]
    public var documentCount: Int
    public var builtAt: String
    public var sourceDatabaseFingerprint: MemoryOSCLISearchIndexFingerprint?

    enum CodingKeys: String, CodingKey {
        case indexSchemaVersion
        case searchKernelVersion
        case sourceDatabasePath
        case indexedLayers
        case documentCount
        case builtAt
        case sourceDatabaseFingerprint
    }
}

public struct MemoryOSCLISearchIndexFingerprint: Codable, Sendable, Equatable {
    public var databaseFileSize: Int64
    public var databaseModifiedAt: String
    public var walFileSize: Int64
    public var walModifiedAt: String
    public var shmFileSize: Int64
    public var shmModifiedAt: String
    public var tableCounts: [String: Int]?
}

private extension MemoryOSCLISearchIndexFingerprint {
    func isCurrentEnough(comparedTo current: MemoryOSCLISearchIndexFingerprint) -> Bool {
        databaseFileSize == current.databaseFileSize
            && walFileSize == current.walFileSize
            && tableCounts == current.tableCounts
    }

    func diffSummary(comparedTo current: MemoryOSCLISearchIndexFingerprint) -> String {
        var diffs: [String] = []
        if databaseFileSize != current.databaseFileSize { diffs.append("databaseFileSize indexed=\(databaseFileSize) current=\(current.databaseFileSize)") }
        if walFileSize != current.walFileSize { diffs.append("walFileSize indexed=\(walFileSize) current=\(current.walFileSize)") }
        let indexedCounts = tableCounts ?? [:]
        let currentCounts = current.tableCounts ?? [:]
        let keys = Set(indexedCounts.keys).union(currentCounts.keys).sorted()
        for key in keys where indexedCounts[key] != currentCounts[key] {
            diffs.append("\(key) indexed=\(indexedCounts[key] ?? -1) current=\(currentCounts[key] ?? -1)")
        }
        return diffs.isEmpty ? "source database fingerprint is current" : diffs.joined(separator: "; ")
    }
}

public struct MemoryOSCLISearchIndexStats: Codable, Sendable, Equatable {
    public var libraryPath: String
    public var indexDirectory: String
    public var connorMeta: MemoryOSCLISearchIndexMeta
    public var indexSizeBytes: Int64
    public var tantivySegmentCount: Int

    enum CodingKeys: String, CodingKey {
        case libraryPath = "library_path"
        case indexDirectory = "index_directory"
        case connorMeta = "connor_meta"
        case indexSizeBytes = "index_size_bytes"
        case tantivySegmentCount = "tantivy_segment_count"
    }
}

public struct MemoryOSCLISearchIndexRebuildResult: Codable, Sendable, Equatable {
    public var status: String
    public var documentCount: Int
    public var databasePath: String
    public var indexDirectory: String
    public var schemaVersion: Int

    enum CodingKeys: String, CodingKey {
        case status
        case documentCount = "document_count"
        case databasePath = "database_path"
        case indexDirectory = "index_directory"
        case schemaVersion = "schema_version"
    }
}

public struct MemoryOSCLISearchIndexCheck: Codable, Sendable, Equatable {
    public var name: String
    public var passed: Bool
    public var message: String
}

public struct MemoryOSCLISearchIndexVerifyResult: Codable, Sendable, Equatable {
    public var status: String
    public var checks: [MemoryOSCLISearchIndexCheck]
    public var smokeResults: [String: Int]
    public var meta: MemoryOSCLISearchIndexMeta?

    enum CodingKeys: String, CodingKey {
        case status
        case checks
        case smokeResults = "smoke_results"
        case meta
    }
}

public struct MemoryOSCLISearchHit: Codable, Sendable, Equatable {
    public var layer: String
    public var id: String
    public var title: String
    public var snippet: String
    public var content: String
    public var score: Double
    public var evidenceRefs: [String]
    public var provenanceRefs: [String]
    public var entityRefs: [String]

    enum CodingKeys: String, CodingKey {
        case layer
        case id
        case title
        case snippet
        case content
        case score
        case evidenceRefs = "evidence_refs"
        case provenanceRefs = "provenance_refs"
        case entityRefs = "entity_refs"
    }
}

public struct MemoryOSCLIPipelinePolicy: Codable, Sendable, Equatable {
    public var l1UnifiedProjection: MemoryOSCLIL1PipelinePolicy

    enum CodingKeys: String, CodingKey {
        case l1UnifiedProjection = "l1_unified_projection"
    }
}

public struct MemoryOSCLIL1PipelinePolicy: Codable, Sendable, Equatable {
    public var minPendingCount: Int
    public var maxEventsPerBlock: Int
    public var maxTokensPerBlock: Int
    public var maxPendingAgeSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case minPendingCount = "min_pending_count"
        case maxEventsPerBlock = "max_events_per_block"
        case maxTokensPerBlock = "max_tokens_per_block"
        case maxPendingAgeSeconds = "max_pending_age_seconds"
    }
}

public struct MemoryOSCLIPlanResult: Codable, Sendable, Equatable {
    public var plannedJobs: Int
    public var kind: String
    public var jobIDs: [String]

    enum CodingKeys: String, CodingKey {
        case plannedJobs = "planned_jobs"
        case kind
        case jobIDs = "job_ids"
    }
}

public struct MemoryOSCLIChatIngestionResult: Codable, Sendable, Equatable {
    public var status: String
    public var messageID: String
    public var provenanceObjectID: String?
    public var captureEventID: String?
    public var normalizationStatus: String
    public var retrievalText: String?
    public var modelID: String?
    public var originalCharacterCount: Int
    public var error: String?

    public init(status: String, messageID: String, provenanceObjectID: String? = nil, captureEventID: String? = nil, normalizationStatus: String, retrievalText: String? = nil, modelID: String? = nil, originalCharacterCount: Int, error: String? = nil) {
        self.status = status
        self.messageID = messageID
        self.provenanceObjectID = provenanceObjectID
        self.captureEventID = captureEventID
        self.normalizationStatus = normalizationStatus
        self.retrievalText = retrievalText
        self.modelID = modelID
        self.originalCharacterCount = originalCharacterCount
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case status
        case messageID = "message_id"
        case provenanceObjectID = "provenance_object_id"
        case captureEventID = "capture_event_id"
        case normalizationStatus = "normalization_status"
        case retrievalText = "retrieval_text"
        case modelID = "model_id"
        case originalCharacterCount = "original_character_count"
        case error
    }
}

public struct MemoryOSCLIDebugAIRunResult: Codable, Sendable, Equatable {
    public var status: String
    public var command: String
    public var requestedKind: String?
    public var requestedLimit: Int
    public var queueRuns: [MemoryOSCLIDebugAIQueueRun]

    public init(status: String, command: String, requestedKind: String? = nil, requestedLimit: Int, queueRuns: [MemoryOSCLIDebugAIQueueRun]) {
        self.status = status
        self.command = command
        self.requestedKind = requestedKind
        self.requestedLimit = requestedLimit
        self.queueRuns = queueRuns
    }

    enum CodingKeys: String, CodingKey {
        case status
        case command
        case requestedKind = "requested_kind"
        case requestedLimit = "requested_limit"
        case queueRuns = "queue_runs"
    }
}

public struct MemoryOSCLIDebugAIQueueRun: Codable, Sendable, Equatable {
    public var queueItemID: String
    public var kind: String
    public var runID: String?
    public var modelID: String?
    public var status: String
    public var messageCount: Int
    public var toolCallCount: Int
    public var projectionSummary: MemoryOSProjectionRunSummary?
    public var messages: [MemoryOSBackgroundMessageRecord]
    public var toolCalls: [MemoryOSBackgroundToolCallRecord]

    public init(
        queueItemID: String,
        kind: String,
        runID: String?,
        modelID: String?,
        status: String,
        messageCount: Int,
        toolCallCount: Int,
        projectionSummary: MemoryOSProjectionRunSummary? = nil,
        messages: [MemoryOSBackgroundMessageRecord] = [],
        toolCalls: [MemoryOSBackgroundToolCallRecord] = []
    ) {
        self.queueItemID = queueItemID
        self.kind = kind
        self.runID = runID
        self.modelID = modelID
        self.status = status
        self.messageCount = messageCount
        self.toolCallCount = toolCallCount
        self.projectionSummary = projectionSummary
        self.messages = messages
        self.toolCalls = toolCalls
    }

    enum CodingKeys: String, CodingKey {
        case queueItemID = "queue_item_id"
        case kind
        case runID = "run_id"
        case modelID = "model_id"
        case status
        case messageCount = "message_count"
        case toolCallCount = "tool_call_count"
        case projectionSummary = "projection_summary"
        case messages
        case toolCalls = "tool_calls"
    }
}

private enum MemoryOSCLIInspectorTable {
    static let defaultTables = [
        "memory_l0_provenance_objects",
        "memory_l0_provenance_spans",
        "memory_l1_capture_events",
        "memory_l1_processing_queue",
        "memory_l1_dead_letter_queue",
        "memory_l2_nodes",
        "memory_l2_statements",
        "memory_l3_beliefs",
        "memory_l4_entities",
        "memory_l4_entity_statements"
    ]
}

public struct MemoryOSCLIStatus: Codable, Sendable, Equatable {
    public var databasePath: String
    public var schema: MemoryOSCLISchemaStatus
    public var layers: MemoryOSCLIStatusLayerCounts
    public var queue: MemoryOSCLIQueueCounts
    public var observability: MemoryOSCLIObservabilityStatus

    enum CodingKeys: String, CodingKey {
        case databasePath = "database_path"
        case schema
        case layers
        case queue
        case observability
    }
}

public struct MemoryOSCLIObservabilityStatus: Codable, Sendable, Equatable {
    public var acceptedProjectionCount: Int
    public var rejectedProjectionCount: Int
    public var degradedAcceptedProjectionCount: Int
    public var repairedRecordCount: Int
    public var degradedRecordCount: Int
    public var droppedRecordCount: Int

    enum CodingKeys: String, CodingKey {
        case acceptedProjectionCount = "accepted_projection_count"
        case rejectedProjectionCount = "rejected_projection_count"
        case degradedAcceptedProjectionCount = "degraded_accepted_projection_count"
        case repairedRecordCount = "repaired_record_count"
        case degradedRecordCount = "degraded_record_count"
        case droppedRecordCount = "dropped_record_count"
    }
}

public struct MemoryOSCLISchemaStatus: Codable, Sendable, Equatable {
    public var expectedVersion: Int
    public var actualVersion: Int
    public var health: String
    public var missingTables: [String]
    public var missingIndexes: [String]

    enum CodingKeys: String, CodingKey {
        case expectedVersion = "expected_version"
        case actualVersion = "actual_version"
        case health
        case missingTables = "missing_tables"
        case missingIndexes = "missing_indexes"
    }
}

public struct MemoryOSCLIStatusLayerCounts: Codable, Sendable, Equatable {
    public var l0ProvenanceObjects: Int
    public var l0ProvenanceSpans: Int
    public var l1CaptureEvents: Int
    public var l1PendingCaptureEvents: Int
    public var l1QueueItems: Int
    public var l2Nodes: Int
    public var l2Statements: Int
    public var l3Beliefs: Int
    public var l4Entities: Int
    public var l4EntityStatements: Int

    enum CodingKeys: String, CodingKey {
        case l0ProvenanceObjects = "l0_provenance_objects"
        case l0ProvenanceSpans = "l0_provenance_spans"
        case l1CaptureEvents = "l1_capture_events"
        case l1PendingCaptureEvents = "l1_pending_capture_events"
        case l1QueueItems = "l1_queue_items"
        case l2Nodes = "l2_nodes"
        case l2Statements = "l2_statements"
        case l3Beliefs = "l3_beliefs"
        case l4Entities = "l4_entities"
        case l4EntityStatements = "l4_entity_statements"
    }
}

public struct MemoryOSCLIQueueCounts: Codable, Sendable, Equatable {
    public var pending: Int
    public var leased: Int
    public var processing: Int
    public var retryScheduled: Int
    public var succeeded: Int
    public var failed: Int
    public var deadLetter: Int
    public var expiredLeases: Int

    enum CodingKeys: String, CodingKey {
        case pending
        case leased
        case processing
        case retryScheduled = "retry_scheduled"
        case succeeded
        case failed
        case deadLetter = "dead_letter"
        case expiredLeases = "expired_leases"
    }
}

public struct MemoryOSCLIStats: Codable, Sendable, Equatable {
    public var tables: [String: Int]
}

public struct MemoryOSCLILayerSummary: Codable, Sendable, Equatable {
    public var l0: MemoryOSCLIL0Counts
    public var l1: MemoryOSCLIL1Counts
    public var l2: MemoryOSCLIL2Counts
    public var l3: MemoryOSCLIL3Counts
    public var l4: MemoryOSCLIL4Counts

    enum CodingKeys: String, CodingKey {
        case l0 = "L0"
        case l1 = "L1"
        case l2 = "L2"
        case l3 = "L3"
        case l4 = "L4"
    }
}

public struct MemoryOSCLIL0Counts: Codable, Sendable, Equatable {
    public var objects: Int
    public var spans: Int
}

public struct MemoryOSCLIL1Counts: Codable, Sendable, Equatable {
    public var captureEvents: Int
    public var pending: Int
    public var queueItems: Int
    public var deadLetters: Int

    enum CodingKeys: String, CodingKey {
        case captureEvents = "capture_events"
        case pending
        case queueItems = "queue_items"
        case deadLetters = "dead_letters"
    }
}

public struct MemoryOSCLIL2Counts: Codable, Sendable, Equatable {
    public var nodes: Int
    public var statements: Int

    enum CodingKeys: String, CodingKey {
        case nodes
        case statements
    }
}

public struct MemoryOSCLIL3Counts: Codable, Sendable, Equatable {
    public var beliefs: Int
}

public struct MemoryOSCLIL4Predicate: Codable, Sendable, Equatable {
    public var predicate: String
    public var category: String
    public var inverse: String?
    public var symmetric: Bool
    public var transitive: Bool
    public var strict: Bool
    public var retrievalWeight: Double
    public var description: String

    enum CodingKeys: String, CodingKey {
        case predicate
        case category
        case inverse
        case symmetric
        case transitive
        case strict
        case retrievalWeight = "retrieval_weight"
        case description
    }
}

public struct MemoryOSCLIL4Counts: Codable, Sendable, Equatable {
    public var entities: Int
    public var entityStatements: Int

    enum CodingKeys: String, CodingKey {
        case entities
        case entityStatements = "entity_statements"
    }
}
