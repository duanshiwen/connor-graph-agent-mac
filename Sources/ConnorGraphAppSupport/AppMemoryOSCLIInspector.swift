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
                l2PendingKnowledge: layers.l2.knowledgePending,
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
        SELECT c.id, c.provenance_object_id, c.event_type, c.occurred_at, c.token_estimate, c.processing_state, c.metadata_json, o.title, o.content
        FROM memory_l1_capture_events c
        JOIN memory_l0_provenance_objects o ON o.id = c.provenance_object_id
        WHERE c.processing_state IN ('pending', 'queued')
        ORDER BY c.occurred_at ASC, c.id ASC
        LIMIT \(safeLimit(limit))
        """, columns: ["id", "provenance_object_id", "event_type", "occurred_at", "token_estimate", "processing_state", "metadata_json", "provenance_title", "provenance_content"])
    }

    public func listL2Statements(limit: Int = 20) throws -> [MemoryOSCLIRow] {
        try rows(sql: """
        SELECT id, subject_id, predicate, object_id, text, assertion_kind, confidence, valid_at, committed_at, evidence_span_ids_json, source_artifact_id, metadata_json
        FROM memory_l2_statements
        ORDER BY committed_at DESC, id ASC
        LIMIT \(safeLimit(limit))
        """, columns: ["id", "subject_id", "predicate", "object_id", "text", "assertion_kind", "confidence", "valid_at", "committed_at", "evidence_span_ids_json", "source_artifact_id", "metadata_json"])
    }

    public func listL2PendingKnowledge(limit: Int = 20) throws -> [MemoryOSCLIRow] {
        try rows(sql: """
        SELECT p.statement_id, p.processing_kind, p.status, p.source_artifact_id, p.processed_by_artifact_id, p.last_attempt_at, p.metadata_json, s.subject_id, s.predicate, s.object_id, s.text, s.evidence_span_ids_json, COALESCE(GROUP_CONCAT(sp.text, '\n---\n'), '')
        FROM memory_l2_statement_processing_state p
        JOIN memory_l2_statements s ON s.id = p.statement_id
        LEFT JOIN memory_l0_provenance_spans sp ON INSTR(s.evidence_span_ids_json, sp.id) > 0
        WHERE p.processing_kind = 'knowledge_synthesis' AND p.status = 'pending'
        GROUP BY p.statement_id, p.processing_kind, p.status, p.source_artifact_id, p.processed_by_artifact_id, p.last_attempt_at, p.metadata_json, s.subject_id, s.predicate, s.object_id, s.text, s.evidence_span_ids_json
        ORDER BY p.last_attempt_at ASC, p.statement_id ASC
        LIMIT \(safeLimit(limit))
        """, columns: ["statement_id", "processing_kind", "status", "source_artifact_id", "processed_by_artifact_id", "last_attempt_at", "metadata_json", "subject_id", "predicate", "object_id", "statement_text", "evidence_span_ids_json", "evidence_span_texts"])
    }

    public func findL2Statements(text: String = "", subjectID: String? = nil, predicates: [String] = [], limit: Int = 50) throws -> MemoryOSGraphSubgraph {
        try AppMemoryOSFacade(store: store, searchKernel: searchKernel).findMemoryOSL2Statements(text: text, subjectID: subjectID, predicates: predicates, limit: safeLimit(limit))
    }

    public func listL3Beliefs(limit: Int = 20) throws -> [MemoryOSCLIRow] {
        try rows(sql: """
        SELECT id, topic, statement, projection_kind, confidence, evidence_statement_ids_json, valid_at, projected_at, source_artifact_id, metadata_json
        FROM memory_l3_beliefs
        ORDER BY projected_at DESC, id ASC
        LIMIT \(safeLimit(limit))
        """, columns: ["id", "topic", "statement", "projection_kind", "confidence", "evidence_statement_ids_json", "valid_at", "projected_at", "source_artifact_id", "metadata_json"])
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

    public func findL4Entity(text: String, limit: Int = 20) throws -> MemoryOSGraphSubgraph {
        try AppMemoryOSFacade(store: store, searchKernel: searchKernel).findMemoryOSL4Entity(text: text, limit: safeLimit(limit))
    }

    public func listL4Neighbors(entityID: String, direction: MemoryOSGraphDirection = .both, predicates: [String] = [], limit: Int = 100) throws -> MemoryOSGraphSubgraph {
        try AppMemoryOSFacade(store: store, searchKernel: searchKernel).queryMemoryOSL4Neighbors(entityID: entityID, direction: direction, predicates: predicates, limit: safeLimit(limit))
    }

    public func listL4Instances(classEntityIDs: [String], predicates: [String] = ["P31"], limit: Int = 100) throws -> MemoryOSGraphSubgraph {
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

    public func pipelinePolicy() -> MemoryOSCLIPipelinePolicy {
        let l1 = MemoryOSL1ProcessingTriggerPolicy()
        let l2 = MemoryOSL2KnowledgeSynthesisTriggerPolicy()
        return MemoryOSCLIPipelinePolicy(
            l1ToL2: MemoryOSCLIL1PipelinePolicy(
                minPendingCount: l1.minPendingCount,
                maxEventsPerBlock: l1.maxEventsPerBlock,
                maxTokensPerBlock: l1.maxTokensPerBlock,
                maxPendingAgeSeconds: l1.maxPendingAge.map(Int.init)
            ),
            l2ToKnowledge: MemoryOSCLIL2PipelinePolicy(
                minPendingStatementCount: l2.minPendingStatementCount,
                maxStatementsPerBlock: l2.maxStatementsPerBlock,
                maxTokensPerBlock: l2.maxTokensPerBlock,
                maxPendingAgeSeconds: l2.maxPendingAge.map(Int.init)
            )
        )
    }

    public func planL1(policy: MemoryOSL1ProcessingTriggerPolicy = MemoryOSL1ProcessingTriggerPolicy(), now: Date = Date()) throws -> MemoryOSCLIPlanResult {
        let jobs = try AppMemoryOSFacade(store: store).enqueueL1ToL2BackgroundJobs(policy: policy, now: now)
        return MemoryOSCLIPlanResult(plannedJobs: jobs.count, kind: MemoryOSBackgroundJobKind.l1ProcessBlockToL2.rawValue, jobIDs: jobs.map(\.id))
    }

    public func planL2(policy: MemoryOSL2KnowledgeSynthesisTriggerPolicy = MemoryOSL2KnowledgeSynthesisTriggerPolicy(), now: Date = Date()) throws -> MemoryOSCLIPlanResult {
        let jobs = try AppMemoryOSFacade(store: store).enqueueL2ToKnowledgeBackgroundJobs(policy: policy, now: now)
        return MemoryOSCLIPlanResult(plannedJobs: jobs.count, kind: MemoryOSBackgroundJobKind.l2SynthesizeKnowledge.rawValue, jobIDs: jobs.map(\.id))
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

        let meta: MemoryOSCLISearchIndexMeta?
        do {
            meta = try readSearchIndexMeta(indexDirectory: searchKernel.indexDirectory, fileManager: fileManager)
            check("connor_meta_exists", true, AppMemoryOSSearchKernelFactory.connorMetaFilename)
            check("schema_version_current", meta?.indexSchemaVersion == AppMemoryOSSearchKernelFactory.currentIndexSchemaVersion, "expected \(AppMemoryOSSearchKernelFactory.currentIndexSchemaVersion), actual \(meta?.indexSchemaVersion ?? -1)")
            check("document_count_positive", (meta?.documentCount ?? 0) > 0, "documentCount=\(meta?.documentCount ?? 0)")
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
                    score: hit.score,
                    evidenceRefs: hit.evidenceRefs,
                    provenanceRefs: hit.provenanceRefs,
                    entityRefs: hit.entityRefs
                )
            }
        )
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
            SELECT id, provenance_object_id, event_type, occurred_at, token_estimate, processing_state, metadata_json
            FROM memory_l1_capture_events WHERE id = \(store.quote(id)) LIMIT 1
            """, columns: ["id", "provenance_object_id", "event_type", "occurred_at", "token_estimate", "processing_state", "metadata_json"])
        case "L2":
            return try firstRecord(layer: "L2", sql: """
            SELECT id, subject_id, predicate, object_id, text, assertion_kind, confidence, valid_at, committed_at, evidence_span_ids_json, source_artifact_id, metadata_json
            FROM memory_l2_statements WHERE id = \(store.quote(id)) LIMIT 1
            """, columns: ["id", "subject_id", "predicate", "object_id", "text", "assertion_kind", "confidence", "valid_at", "committed_at", "evidence_span_ids_json", "source_artifact_id", "metadata_json"])
        case "L3":
            return try firstRecord(layer: "L3", sql: """
            SELECT id, topic, statement, projection_kind, confidence, evidence_statement_ids_json, valid_at, projected_at, source_artifact_id, metadata_json
            FROM memory_l3_beliefs WHERE id = \(store.quote(id)) LIMIT 1
            """, columns: ["id", "topic", "statement", "projection_kind", "confidence", "evidence_statement_ids_json", "valid_at", "projected_at", "source_artifact_id", "metadata_json"])
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
                statements: try count("memory_l2_statements"),
                knowledgePending: try count("memory_l2_statement_processing_state", where: "processing_kind = 'knowledge_synthesis' AND status = 'pending'"),
                processingStates: try count("memory_l2_statement_processing_state")
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
        case MemoryOSBackgroundJobKind.l1ProcessBlockToL2.rawValue:
            let draft = try? store.decode(MemoryOSL1ToL2JobDraft.self, payload)
            return try provenanceContent(forCaptureEventIDs: draft?.captureEventIDs ?? [])
        case MemoryOSBackgroundJobKind.l2SynthesizeKnowledge.rawValue:
            let draft = try? store.decode(MemoryOSL2ToKnowledgeJobDraft.self, payload)
            return try statementText(forStatementIDs: draft?.statementIDs ?? [])
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
    public var score: Double
    public var evidenceRefs: [String]
    public var provenanceRefs: [String]
    public var entityRefs: [String]

    enum CodingKeys: String, CodingKey {
        case layer
        case id
        case title
        case snippet
        case score
        case evidenceRefs = "evidence_refs"
        case provenanceRefs = "provenance_refs"
        case entityRefs = "entity_refs"
    }
}

public struct MemoryOSCLIPipelinePolicy: Codable, Sendable, Equatable {
    public var l1ToL2: MemoryOSCLIL1PipelinePolicy
    public var l2ToKnowledge: MemoryOSCLIL2PipelinePolicy

    enum CodingKeys: String, CodingKey {
        case l1ToL2 = "l1_to_l2"
        case l2ToKnowledge = "l2_to_knowledge"
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

public struct MemoryOSCLIL2PipelinePolicy: Codable, Sendable, Equatable {
    public var minPendingStatementCount: Int
    public var maxStatementsPerBlock: Int
    public var maxTokensPerBlock: Int
    public var maxPendingAgeSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case minPendingStatementCount = "min_pending_statement_count"
        case maxStatementsPerBlock = "max_statements_per_block"
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

private enum MemoryOSCLIInspectorTable {
    static let defaultTables = [
        "memory_l0_provenance_objects",
        "memory_l0_provenance_spans",
        "memory_l1_capture_events",
        "memory_l1_processing_queue",
        "memory_l1_dead_letter_queue",
        "memory_l2_nodes",
        "memory_l2_statements",
        "memory_l2_statement_processing_state",
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

    enum CodingKeys: String, CodingKey {
        case databasePath = "database_path"
        case schema
        case layers
        case queue
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
    public var l2PendingKnowledge: Int
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
        case l2PendingKnowledge = "l2_pending_knowledge"
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
    public var knowledgePending: Int
    public var processingStates: Int

    enum CodingKeys: String, CodingKey {
        case nodes
        case statements
        case knowledgePending = "knowledge_pending"
        case processingStates = "processing_states"
    }
}

public struct MemoryOSCLIL3Counts: Codable, Sendable, Equatable {
    public var beliefs: Int
}

public struct MemoryOSCLIL4Counts: Codable, Sendable, Equatable {
    public var entities: Int
    public var entityStatements: Int

    enum CodingKeys: String, CodingKey {
        case entities
        case entityStatements = "entity_statements"
    }
}
