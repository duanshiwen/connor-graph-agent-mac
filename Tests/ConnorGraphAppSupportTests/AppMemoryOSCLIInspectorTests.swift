import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore
import ConnorGraphAppSupport

@Suite("Memory OS CLI Inspector Tests")
struct AppMemoryOSCLIInspectorTests {
    @Test func memoryOSCLIInspectorReportsEmptyStoreStatus() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        let inspector = AppMemoryOSCLIInspector(store: store)

        let status = try inspector.status(now: Date(timeIntervalSince1970: 1_000))

        #expect(status.databasePath.hasSuffix(".sqlite"))
        #expect(status.schema.expectedVersion == SQLiteMemoryOSStore.currentSchemaVersion)
        #expect(status.schema.health == "healthy")
        #expect(status.layers.l0ProvenanceObjects == 0)
        #expect(status.layers.l1CaptureEvents == 0)
        #expect(status.layers.l2Statements == 0)
        #expect(status.layers.l3Beliefs == 0)
        #expect(status.layers.l4Entities == 0)
        #expect(status.queue.pending == 0)
    }

    @Test func memoryOSCLIInspectorReportsLayerCounts() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let stats = try inspector.stats()
        let layers = try inspector.layers()

        #expect(stats.tables["memory_l0_provenance_objects"] == 1)
        #expect(stats.tables["memory_l0_provenance_spans"] == 1)
        #expect(stats.tables["memory_l1_capture_events"] == 1)
        #expect(stats.tables["memory_l2_statements"] == 1)
        #expect(stats.tables["memory_l2_statement_processing_state"] == 1)
        #expect(stats.tables["memory_l3_beliefs"] == 1)
        #expect(stats.tables["memory_l4_entities"] == 1)
        #expect(layers.l0.objects == 1)
        #expect(layers.l0.spans == 1)
        #expect(layers.l1.captureEvents == 1)
        #expect(layers.l1.pending == 1)
        #expect(layers.l2.statements == 1)
        #expect(layers.l2.knowledgePending == 1)
        #expect(layers.l3.beliefs == 1)
        #expect(layers.l4.entities == 1)
    }

    @Test func memoryOSCLIInspectorListsL0ObjectsAndSpans() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let objects = try inspector.listL0Objects(limit: 10)
        let spans = try inspector.listL0Spans(limit: 10)

        #expect(objects.count == 1)
        #expect(objects[0].values["id"] == "object-1")
        #expect(objects[0].values["source_type"] == "chat_message")
        #expect(objects[0].values["title"] == "User message")
        #expect(spans.count == 1)
        #expect(spans[0].values["id"] == "span-1")
        #expect(spans[0].values["provenance_object_id"] == "object-1")
        #expect(spans[0].values["text"] == "Connor Memory OS CLI")
    }

    @Test func memoryOSCLIInspectorListsL1PendingCaptureEvents() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let events = try inspector.listL1Pending(limit: 10)

        #expect(events.count == 1)
        #expect(events[0].values["id"] == "event-1")
        #expect(events[0].values["processing_state"] == "pending")
        #expect(events[0].values["token_estimate"] == "12")
    }

    @Test func memoryOSCLIInspectorListsL2StatementsAndPendingKnowledge() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let statements = try inspector.listL2Statements(limit: 10)
        let pending = try inspector.listL2PendingKnowledge(limit: 10)

        #expect(statements.count == 1)
        #expect(statements[0].values["id"] == "stmt-1")
        #expect(statements[0].values["predicate"] == "describes")
        #expect(statements[0].values["source_artifact_id"] == "artifact-1")
        #expect(pending.count == 1)
        #expect(pending[0].values["statement_id"] == "stmt-1")
        #expect(pending[0].values["processing_kind"] == "knowledge_synthesis")
        #expect(pending[0].values["status"] == "pending")
    }

    @Test func memoryOSCLIInspectorListsL3Beliefs() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let beliefs = try inspector.listL3Beliefs(limit: 10)

        #expect(beliefs.count == 1)
        #expect(beliefs[0].values["id"] == "belief-1")
        #expect(beliefs[0].values["topic"] == "Connor Memory OS")
        #expect(beliefs[0].values["source_artifact_id"] == "artifact-2")
    }

    @Test func memoryOSCLIInspectorListsL4Entities() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let entities = try inspector.listL4Entities(limit: 10)

        #expect(entities.count == 1)
        #expect(entities[0].values["id"] == "entity-1")
        #expect(entities[0].values["entity_type"] == "concept")
        #expect(entities[0].values["name"] == "Connor Memory OS")
    }

    @Test func memoryOSCLIInspectorReadsRecordByLayerAndID() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let l0 = try #require(try inspector.read(layer: "L0", id: "object-1"))
        let l1 = try #require(try inspector.read(layer: "L1", id: "event-1"))
        let l2 = try #require(try inspector.read(layer: "L2", id: "stmt-1"))
        let l3 = try #require(try inspector.read(layer: "L3", id: "belief-1"))
        let l4 = try #require(try inspector.read(layer: "L4", id: "entity-1"))

        #expect(l0.layer == "L0")
        #expect(l0.record.values["id"] == "object-1")
        #expect(l1.layer == "L1")
        #expect(l1.record.values["id"] == "event-1")
        #expect(l2.layer == "L2")
        #expect(l2.record.values["id"] == "stmt-1")
        #expect(l3.layer == "L3")
        #expect(l3.record.values["id"] == "belief-1")
        #expect(l4.layer == "L4")
        #expect(l4.record.values["id"] == "entity-1")
    }

    @Test func memoryOSCLIInspectorReturnsNilForMissingRecord() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let missing = try inspector.read(layer: "L2", id: "missing-statement")

        #expect(missing == nil)
    }

    @Test func memoryOSCLIInspectorAcceptsLayerAliases() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        #expect(try inspector.read(layer: "provenance", id: "object-1")?.layer == "L0")
        #expect(try inspector.read(layer: "capture", id: "event-1")?.layer == "L1")
        #expect(try inspector.read(layer: "statement", id: "stmt-1")?.layer == "L2")
        #expect(try inspector.read(layer: "belief", id: "belief-1")?.layer == "L3")
        #expect(try inspector.read(layer: "entity", id: "entity-1")?.layer == "L4")
    }

    @Test func memoryOSCLIInspectorSearchesL2Statements() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let result = try inspector.search(query: "Connor", layers: ["L2"], limit: 10)

        #expect(result.query == "Connor")
        #expect(result.hits.count == 1)
        #expect(result.hits[0].layer == "L2")
        #expect(result.hits[0].id == "stmt-1")
    }

    @Test func memoryOSCLIInspectorSearchesAcrossL3AndL4() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let result = try inspector.search(query: "Memory", layers: ["L3", "L4"], limit: 10)

        #expect(result.hits.map(\.layer).contains("L3"))
        #expect(result.hits.map(\.layer).contains("L4"))
    }

    @Test func memoryOSCLIInspectorSearchRespectsLayerFilterAndLimit() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let result = try inspector.search(query: "Memory", layers: ["L4"], limit: 1)

        #expect(result.hits.count == 1)
        #expect(result.hits.allSatisfy { $0.layer == "L4" })
    }

    @Test func memoryOSCLIInspectorListsQueueItems() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        let now = Date(timeIntervalSince1970: 20_000)
        try store.enqueue(MemoryOSQueueItem(kind: MemoryOSBackgroundJobKind.l1ProcessBlockToL2.rawValue, priority: 10, payloadJSON: "{}", nextRunAt: now, idempotencyKey: "queue-test", payloadHash: "hash", createdAt: now, updatedAt: now))
        let inspector = AppMemoryOSCLIInspector(store: store)

        let queue = try inspector.queue(limit: 10, status: "pending", kind: MemoryOSBackgroundJobKind.l1ProcessBlockToL2.rawValue)

        #expect(queue.count == 1)
        #expect(queue[0].values["kind"] == MemoryOSBackgroundJobKind.l1ProcessBlockToL2.rawValue)
        #expect(queue[0].values["status"] == "pending")
    }

    @Test func memoryOSCLIInspectorReportsPipelinePolicy() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        let inspector = AppMemoryOSCLIInspector(store: store)

        let policy = inspector.pipelinePolicy()

        #expect(policy.l1ToL2.maxPendingAgeSeconds == 86_400)
        #expect(policy.l2ToKnowledge.maxPendingAgeSeconds == 86_400)
        #expect(policy.l1ToL2.minPendingCount == 100)
        #expect(policy.l2ToKnowledge.minPendingStatementCount == 80)
    }

    @Test func memoryOSCLIInspectorPlansL1AndL2JobsThroughFacade() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        let now = Date(timeIntervalSince1970: 30_000)
        try seedMemoryOSCLIInspectorFixture(store: store, now: now)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let l1Plan = try inspector.planL1(policy: MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 1, maxEventsPerBlock: 10), now: now)
        let l2Plan = try inspector.planL2(policy: MemoryOSL2KnowledgeSynthesisTriggerPolicy(minPendingStatementCount: 1, maxStatementsPerBlock: 10), now: now)

        #expect(l1Plan.plannedJobs == 1)
        #expect(l1Plan.kind == MemoryOSBackgroundJobKind.l1ProcessBlockToL2.rawValue)
        #expect(l1Plan.jobIDs.count == 1)
        #expect(l2Plan.plannedJobs == 1)
        #expect(l2Plan.kind == MemoryOSBackgroundJobKind.l2SynthesizeKnowledge.rawValue)
        #expect(l2Plan.jobIDs.count == 1)
    }

    @Test func memoryOSCLIRouterRoutesStatusCommand() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        let output = try AppMemoryOSCLIRouter.route(args: ["status"], inspector: AppMemoryOSCLIInspector(store: store), encoder: memoryOSCLITestEncoder())

        #expect(output.contains("\"schema\""))
        #expect(output.contains("\"layers\""))
    }

    @Test func memoryOSCLIRouterRoutesLayerListCommands() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let output = try AppMemoryOSCLIRouter.route(args: ["l2", "statements", "--limit", "5"], inspector: inspector, encoder: memoryOSCLITestEncoder())

        #expect(output.contains("stmt-1"))
        #expect(output.contains("describes"))
    }

    @Test func memoryOSCLIRouterRoutesReadCommand() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let output = try AppMemoryOSCLIRouter.route(args: ["read", "L4", "entity-1"], inspector: inspector, encoder: memoryOSCLITestEncoder())

        #expect(output.contains("\"layer\" : \"L4\""))
        #expect(output.contains("entity-1"))
    }

    @Test func memoryOSCLIRouterRoutesSearchCommand() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        try seedMemoryOSCLIInspectorFixture(store: store)
        let inspector = AppMemoryOSCLIInspector(store: store)

        let output = try AppMemoryOSCLIRouter.route(args: ["search", "Memory", "--layers", "L3,L4", "--limit", "5"], inspector: inspector, encoder: memoryOSCLITestEncoder())

        #expect(output.contains("\"query\" : \"Memory\""))
        #expect(output.contains("\"layer\" : \"L3\"") || output.contains("\"layer\" : \"L4\""))
    }

    @Test func memoryOSCLIRouterReturnsHelpfulErrors() throws {
        let store = try makeMemoryOSCLIInspectorStore()
        let inspector = AppMemoryOSCLIInspector(store: store)

        let output = try AppMemoryOSCLIRouter.route(args: ["read", "L2"], inspector: inspector, encoder: memoryOSCLITestEncoder())

        #expect(output.contains("missing_layer_or_id"))
    }
}

private func makeMemoryOSCLIInspectorStore() throws -> SQLiteMemoryOSStore {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("memory-os-cli-inspector-\(UUID().uuidString).sqlite")
    let store = try SQLiteMemoryOSStore(path: url.path)
    try store.migrate()
    return store
}

private func memoryOSCLITestEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}

private func seedMemoryOSCLIInspectorFixture(store: SQLiteMemoryOSStore, now: Date = Date(timeIntervalSince1970: 10_000)) throws {
    let object = MemoryOSProvenanceObject(
        id: "object-1",
        sourceType: .chatMessage,
        sourceID: "message-1",
        title: "User message",
        content: "诗闻正在测试 Connor Memory OS CLI。",
        contentHash: "hash-1",
        occurredAt: now,
        ingestedAt: now,
        sessionID: "session-1",
        metadata: ["fixture": "true"]
    )
    try store.upsert(provenance: object)
    let span = MemoryOSProvenanceSpan(id: "span-1", provenanceObjectID: object.id, startOffset: 0, endOffset: 18, text: "Connor Memory OS CLI", metadata: ["kind": "title"])
    try store.upsert(span: span)
    let event = MemoryOSCaptureEvent(id: "event-1", provenanceObjectID: object.id, eventType: "chat_message", occurredAt: now, tokenEstimate: 12, processingState: .pending, metadata: ["source": "test"])
    try store.upsert(captureEvent: event)

    let node = MemoryOSNode(id: "node-1", stableKey: "node:connor", nodeType: "project", name: "Connor Memory OS", summary: "Memory system", createdAt: now, updatedAt: now)
    try store.upsert(node: node)
    let statement = MemoryOSStatement(id: "stmt-1", subjectID: node.id, predicate: "describes", text: "Connor Memory OS 是康纳同学的重要系统。", confidence: 0.91, validAt: now, committedAt: now, evidenceSpanIDs: [span.id], sourceArtifactID: "artifact-1", metadata: ["stage": "l2"])
    try store.upsert(statement: statement)
    try store.upsert(l2ProcessingState: MemoryOSL2StatementProcessingState(statementID: statement.id, processingKind: .knowledgeSynthesis, status: .pending, sourceArtifactID: "artifact-1", lastAttemptAt: nil, metadata: ["reason": "new_statement"]))

    let belief = MemoryOSBelief(id: "belief-1", topic: "Connor Memory OS", statement: "Memory OS should be observable from CLI.", projectionKind: .summarized, confidence: 0.84, evidenceStatementIDs: [statement.id], validAt: now, projectedAt: now, sourceArtifactID: "artifact-2", metadata: ["stage": "l3"])
    try store.upsert(belief: belief)
    let entity = MemoryOSEntity(id: "entity-1", stableKey: "concept:connor-memory-os", entityType: "concept", name: "Connor Memory OS", aliases: ["Memory OS"], summary: "康纳同学的长期记忆系统", confidence: 0.93, createdAt: now, updatedAt: now, validFrom: now, metadata: ["stage": "l4"])
    try store.upsert(entity: entity)
}
