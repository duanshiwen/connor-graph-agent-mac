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
}

private func makeMemoryOSCLIInspectorStore() throws -> SQLiteMemoryOSStore {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("memory-os-cli-inspector-\(UUID().uuidString).sqlite")
    let store = try SQLiteMemoryOSStore(path: url.path)
    try store.migrate()
    return store
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
