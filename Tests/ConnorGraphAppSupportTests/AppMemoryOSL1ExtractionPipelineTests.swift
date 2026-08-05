import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore
import ConnorGraphAppSupport

@Test func l1UnifiedProjectionPipelineWritesL2L3L4AndClearsL1() async throws {
    let store = try SQLiteMemoryOSStore(path: temporaryL1ExtractionPipelineDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 10_000)
    _ = try facade.ingestChatMessage(messageID: "e2e-1", sessionID: "session", role: "user", content: "段诗闻正在推进 Connor Memory OS 项目。", occurredAt: now)
    _ = try facade.ingestChatMessage(messageID: "e2e-2", sessionID: "session", role: "user", content: "段福强是段诗闻的弟弟。", occurredAt: now.addingTimeInterval(1))
    let enqueued = try facade.enqueueL1UnifiedProjectionBackgroundJobs(
        policy: MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 2, maxEventsPerBlock: 10),
        now: now
    )
    let job = try #require(enqueued.first)

    let executor = MemoryOSHeadlessKnowledgeLoopExecutor(
        model: L1ExtractionPipelineLoopModel(),
        toolExecutor: MemoryOSBackgroundToolExecutor(facade: facade),
        store: store
    )
    let summaries = try await facade.runBackgroundAIQueueOnce(executor: executor, limit: 1, now: now)

    #expect(summaries.count == 1)
    #expect(summaries[0].accepted)
    #expect(try store.queueItem(id: job.id)?.status == .succeeded)
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_capture_events;").first?.first == "0")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l0_provenance_objects;").first?.first == "2")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l2_nodes;").first?.first == "2")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l2_statements;").first?.first == "2")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l3_beliefs;").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l4_entities;").first?.first == "2")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l4_entity_statements;").first?.first == "1")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_audit_events WHERE event_type = 'memory_os.background_job.completed';").first?.first == "1")
}

@Test func l1RunnerDownscalesDeterministicFailureThenCompletesSmallerBatches() async throws {
    let store = try SQLiteMemoryOSStore(path: temporaryL1ExtractionPipelineDatabaseURL().path)
    try store.migrate()
    let facade = AppMemoryOSFacade(store: store)
    let now = Date(timeIntervalSince1970: 11_000)
    for index in 0..<10 {
        _ = try facade.ingestChatMessage(
            messageID: "downscale-e2e-\(index)",
            sessionID: "session",
            role: "user",
            content: "L1 extraction event \(index) needs projection.",
            occurredAt: now.addingTimeInterval(Double(index))
        )
    }
    _ = try facade.enqueueL1UnifiedProjectionBackgroundJobs(
        policy: MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 2, maxEventsPerBlock: 10),
        now: now
    )

    let firstRun = try await facade.runBackgroundAIQueueOnce(
        executor: MemoryOSHeadlessKnowledgeLoopExecutor(
            model: BudgetExhaustedLoopModel(),
            toolExecutor: MemoryOSBackgroundToolExecutor(facade: facade),
            store: store
        ),
        limit: 1,
        now: now
    )

    #expect(firstRun.count == 1)
    #expect(firstRun[0].issues.first?.code == "background_ai_batch_downscaled")
    let downscaledItems = try store.queueItems(kinds: MemoryOSBackgroundJobKind.executableRawValues)
    #expect(downscaledItems.count == 2)
    #expect(downscaledItems.allSatisfy { $0.status == .pending })
    let drafts = try downscaledItems.map { try store.decode(MemoryOSL1UnifiedProjectionJobDraft.self, $0.payloadJSON) }
    #expect(drafts.map(\.captureEventIDs.count) == [5, 5])
    #expect(drafts.allSatisfy { $0.metadata["downscale_level"] == "1" })
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_capture_events;").first?.first == "10")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_audit_events WHERE event_type = 'memory_os.background_job.downscaled';").first?.first == "1")

    let secondRun = try await facade.runBackgroundAIQueueOnce(
        executor: MemoryOSHeadlessKnowledgeLoopExecutor(
            model: L1ExtractionPipelineLoopModel(),
            toolExecutor: MemoryOSBackgroundToolExecutor(facade: facade),
            store: store
        ),
        limit: 5,
        now: now.addingTimeInterval(60)
    )

    #expect(secondRun.allSatisfy { $0.accepted })
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_capture_events;").first?.first == "0")
    #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l1_processing_queue WHERE status = '\(MemoryOSQueueStatus.succeeded.rawValue)';").first?.first == "2")
}

private final class L1ExtractionPipelineLoopModel: MemoryOSBackgroundToolLoopModel, @unchecked Sendable {
    let modelID = "l1-extraction-pipeline-loop-model"
    private var invocation = 0

    func complete(_ request: MemoryOSBackgroundLoopModelRequest) async throws -> MemoryOSBackgroundLoopModelResponse {
        invocation += 1
        switch invocation {
        case 1:
            return MemoryOSBackgroundLoopModelResponse(toolCalls: [
                MemoryOSBackgroundToolCall(id: "read-context", name: "memory_os_recent_context", argumentsJSON: #"{"query":"段诗闻"}"#),
                MemoryOSBackgroundToolCall(id: "write-l2", name: "memory_os_l2_update_entities", argumentsJSON: #"{"entities":[{"name":"段诗闻","type":"person","statements":[{"text":"段诗闻正在推进 Connor Memory OS 项目。"}]},{"name":"Connor Memory OS","type":"project","statements":[{"text":"Connor Memory OS 项目由段诗闻推进。"}]}]}"#)
            ])
        case 2:
            return MemoryOSBackgroundLoopModelResponse(toolCalls: [
                MemoryOSBackgroundToolCall(id: "write-l3", name: "memory_os_l3_update_beliefs", argumentsJSON: #"{"beliefs":[{"statement":"段诗闻负责推进 Connor Memory OS 项目。","domain":"engineering","related_entity_names":"段诗闻,Connor Memory OS"}]}"#)
            ])
        case 3:
            return MemoryOSBackgroundLoopModelResponse(toolCalls: [
                MemoryOSBackgroundToolCall(id: "write-l4", name: "memory_os_l4_update_entities", argumentsJSON: #"{"entities":[{"name":"段诗闻","type":"person","summary":"Connor Memory OS 项目负责人"},{"name":"段福强","type":"person","summary":"段诗闻的弟弟"}],"relations":[{"subjectName":"段福强","predicate":"FAMILY_OF","objectName":"段诗闻","text":"段福强是段诗闻的弟弟"}]}"#)
            ])
        default:
            return MemoryOSBackgroundLoopModelResponse(assistantText: #"{"warnings":[],"metadata":{"completed":"true"}}"#)
        }
    }
}

private final class BudgetExhaustedLoopModel: MemoryOSBackgroundToolLoopModel, @unchecked Sendable {
    let modelID = "budget-exhausted-loop-model"

    func complete(_ request: MemoryOSBackgroundLoopModelRequest) async throws -> MemoryOSBackgroundLoopModelResponse {
        throw MemoryOSHeadlessKnowledgeLoopError.exceededTokenBudget(2_000_000)
    }
}

private func temporaryL1ExtractionPipelineDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("l1-extraction-pipeline-\(UUID().uuidString).sqlite")
}
