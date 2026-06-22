import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore
import ConnorGraphAppSupport

@Test func appMemoryOSFacadeRunsL1ToL2BackgroundJobProjectsArtifactAndPhysicallyClearsL1() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSBackgroundWorkerDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 8_000)
    _ = try facade.ingestChatMessage(messageID: "message-1", sessionID: "session", role: "user", content: "诗闻正在推进 Connor Memory OS。", occurredAt: now)
    _ = try facade.ingestChatMessage(messageID: "message-2", sessionID: "session", role: "user", content: "Memory OS 需要后台 L1 到 L2。", occurredAt: now.addingTimeInterval(1))
    _ = try facade.enqueueL1ToL2BackgroundJobs(policy: MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 2, maxEventsPerBlock: 10), now: now)

    let summaries = try facade.runBackgroundAIQueueOnce(executor: StaticMemoryOSBackgroundExecutor(rawArtifactJSON: try encodedGraphArtifact()), now: now)

    #expect(summaries.count == 1)
    #expect(summaries[0].accepted)
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l2_statements;").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_capture_events;").first?.first == "0")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l0_provenance_objects;").first?.first == "2")
    #expect(try store.runnableQueueItems(kind: MemoryOSBackgroundJobKind.l1ProcessBlockToL2.rawValue, limit: 10, now: now).isEmpty)
}

@Test func appMemoryOSFacadeRunsL2ToKnowledgeJobProjectsArtifactAndMarksProcessingStateSucceeded() throws {
    let store = try SQLiteMemoryOSStore(path: temporaryAppMemoryOSBackgroundWorkerDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 8_000)
    let node = MemoryOSNode(id: "node-1", stableKey: "node-1", nodeType: "topic", name: "供需弹性")
    try store.upsert(node: node)
    let statement = MemoryOSStatement(id: "stmt-1", subjectID: node.id, predicate: "explains", text: "供需弹性可用于分析价格变化下的需求响应。", confidence: 0.82, validAt: now, committedAt: now, evidenceSpanIDs: ["span-1"])
    try store.upsert(statement: statement)
    try store.upsert(l2ProcessingState: MemoryOSL2StatementProcessingState(statementID: statement.id, processingKind: .knowledgeSynthesis, status: .pending, lastAttemptAt: now))
    _ = try facade.enqueueL2ToKnowledgeBackgroundJobs(policy: MemoryOSL2KnowledgeSynthesisTriggerPolicy(minPendingStatementCount: 1, maxStatementsPerBlock: 10), now: now)

    let summaries = try facade.runBackgroundAIQueueOnce(executor: StaticMemoryOSBackgroundExecutor(rawArtifactJSON: try encodedKnowledgeArtifact()), now: now)

    #expect(summaries.count == 1)
    #expect(summaries[0].accepted)
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l3_beliefs;").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l4_entities;").first?.first == "1")
    let states = try store.l2ProcessingStates(processingKind: .knowledgeSynthesis, status: .succeeded, limit: 10)
    #expect(states.count == 1)
    #expect(states[0].processedByArtifactID == summaries[0].artifactID)
}

private final class StaticMemoryOSBackgroundExecutor: MemoryOSBackgroundModelExecutor, @unchecked Sendable {
    let rawArtifactJSON: String

    init(rawArtifactJSON: String) {
        self.rawArtifactJSON = rawArtifactJSON
    }

    func execute(_ request: MemoryOSBackgroundModelRequest) throws -> MemoryOSBackgroundModelResponse {
        MemoryOSBackgroundModelResponse(rawArtifactJSON: rawArtifactJSON, metadata: ["model_id": "mock-memory-worker"])
    }
}

private func encodedGraphArtifact() throws -> String {
    let output = GraphStructuredExtractionOutput(
        entities: [
            GraphStructuredExtractedEntity(localID: "person-1", name: "诗闻", entityKind: .personObject, scope: .personal, confidence: 0.95, evidenceSpanIDs: ["span-1"]),
            GraphStructuredExtractedEntity(localID: "project-1", name: "Connor Memory OS", entityKind: .workObject, scope: .project, confidence: 0.93, evidenceSpanIDs: ["span-1"])
        ],
        statements: [
            GraphStructuredExtractedStatement(explicitID: "stmt-1", subjectLocalID: "person-1", predicate: .relatedTo, objectLocalID: "project-1", statementText: "诗闻正在推进 Connor Memory OS。", confidence: 0.91, evidenceSpanIDs: ["span-1"])
        ],
        evidenceSpans: [GraphStructuredEvidenceSpan(id: "span-1", text: "诗闻正在推进 Connor Memory OS。")]
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return String(data: try encoder.encode(output), encoding: .utf8)!
}

private func encodedKnowledgeArtifact() throws -> String {
    let output = MemoryOSKnowledgeExtractionOutput(
        knowledgeCandidates: [
            MemoryOSKnowledgeCandidate(
                id: "candidate-1",
                title: "供需弹性知识",
                claim: "供需弹性可用于分析价格变化下的需求响应。",
                category: "economics",
                knowledgeType: "theory",
                scope: "general",
                domain: "economics",
                signalAssessment: MemoryOSKnowledgeSignalAssessment(signalQualityAccepted: true, reuseScopeAccepted: true, noveltyAccepted: true, structurabilityAccepted: true),
                confidence: 0.84,
                evidenceStatementIDs: ["stmt-1"],
                relatedEntityIDs: ["concept-elasticity"]
            )
        ],
        conceptEntities: [MemoryOSExtractedConceptEntity(localID: "concept-elasticity", name: "供需弹性", conceptType: "concept", domain: "economics")]
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return String(data: try encoder.encode(output), encoding: .utf8)!
}

private func temporaryAppMemoryOSBackgroundWorkerDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("app-memory-os-background-worker-\(UUID().uuidString).sqlite")
}
