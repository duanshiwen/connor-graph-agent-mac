import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore
import ConnorGraphAppSupport

@Suite("Memory OS Headless Knowledge Loop Executor Tests")
struct MemoryOSHeadlessKnowledgeLoopExecutorTests {
    @Test func executesToolCallPersistsRunTraceAndReturnsFinalArtifact() throws {
        let store = try SQLiteMemoryOSStore(path: temporaryHeadlessLoopDatabaseURL().path)
        try store.migrate()
        let model = ScriptedLoopModel(script: [
            MemoryOSBackgroundLoopModelResponse(
                assistantText: "I need to search existing memory first.",
                toolCalls: [MemoryOSBackgroundToolCall(id: "tool-1", name: "memory_os_search", argumentsJSON: #"{"query":"stateless batch","layers":["L2","L3","L4"],"limit":5}"#)]
            ),
            MemoryOSBackgroundLoopModelResponse(assistantText: #"{"warnings":[],"metadata":{"ok":"true"}}"#, metadata: ["final": "true"])
        ])
        let executor = MemoryOSHeadlessKnowledgeLoopExecutor(
            model: model,
            toolExecutor: MemoryOSBackgroundToolExecutor(facade: AppMemoryOSFacade(store: store)),
            store: store
        )

        let response = try executor.execute(MemoryOSBackgroundModelRequest(
            jobID: "job-1",
            kind: MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue,
            schemaName: "MemoryOSL1UnifiedProjectionOutput",
            artifactType: "memory_os_l1_unified_projection",
            prompt: "Preset prompt + current L1 batch only",
            metadata: ["background_run_id": "run-1"]
        ))

        #expect(response.rawArtifactJSON.contains("metadata"))
        #expect(response.metadata["background_run_id"] == "run-1")
        #expect(response.metadata["tool_trace_count"] == "1")
        #expect(response.metadata["stateless_batch"] == "true")

        let run = try #require(try store.backgroundRuns(limit: 10).first { $0.id == "run-1" })
        #expect(run.status == .succeeded)
        #expect(run.statelessBatch)
        #expect(run.toolCallCount == 1)

        let messages = try store.backgroundMessages(runID: "run-1")
        #expect(messages.first?.content == "Preset prompt + current L1 batch only")
        #expect(messages.contains { $0.role == .tool && $0.toolName == "memory_os_search" })
        #expect(try store.backgroundToolCalls(runID: "run-1").count == 1)
    }

    @Test func facadeQueueRunnerInjectsQueueMetadataIntoHeadlessRun() throws {
        let store = try SQLiteMemoryOSStore(path: temporaryHeadlessLoopDatabaseURL().path)
        try store.migrate()
        let facade = AppMemoryOSFacade(store: store)
        let now = Date(timeIntervalSince1970: 3_000)
        _ = try facade.ingestChatMessage(messageID: "message-1", sessionID: "session", role: "user", content: "Memory OS needs a headless run.", occurredAt: now)
        let jobs = try facade.enqueueL1UnifiedProjectionBackgroundJobs(policy: MemoryOSL1ProcessingTriggerPolicy(minPendingCount: 1, maxEventsPerBlock: 10), now: now)
        let queueID = try #require(jobs.first?.id)
        let model = CapturingLoopModel()
        let executor = MemoryOSHeadlessKnowledgeLoopExecutor(
            model: model,
            toolExecutor: MemoryOSBackgroundToolExecutor(facade: facade),
            store: store
        )

        _ = try facade.runBackgroundAIQueueOnce(executor: executor, limit: 1, now: now)

        let run = try #require(try store.backgroundRuns(limit: 10).first { $0.queueItemID == queueID })
        #expect(run.id == "memory-run:\(queueID)")
        #expect(run.statelessBatch)
        #expect(run.metadata["queue_item_id"] == queueID)
    }

    @Test func secondRunDoesNotInheritFirstRunMessagesOrToolResults() throws {
        let store = try SQLiteMemoryOSStore(path: temporaryHeadlessLoopDatabaseURL().path)
        try store.migrate()
        let model = CapturingLoopModel()
        let executor = MemoryOSHeadlessKnowledgeLoopExecutor(
            model: model,
            toolExecutor: MemoryOSBackgroundToolExecutor(facade: AppMemoryOSFacade(store: store)),
            store: store
        )

        _ = try executor.execute(MemoryOSBackgroundModelRequest(
            jobID: "job-1",
            kind: MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue,
            schemaName: "MemoryOSL1UnifiedProjectionOutput",
            artifactType: "memory_os_l1_unified_projection",
            prompt: "First batch prompt",
            metadata: ["background_run_id": "run-1"]
        ))
        _ = try executor.execute(MemoryOSBackgroundModelRequest(
            jobID: "job-2",
            kind: MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue,
            schemaName: "MemoryOSL1UnifiedProjectionOutput",
            artifactType: "memory_os_l1_unified_projection",
            prompt: "Second batch prompt",
            metadata: ["background_run_id": "run-2"]
        ))

        let captured = model.capturedInitialMessageContents
        #expect(captured == ["First batch prompt", "Second batch prompt"])
        #expect(captured[1].contains("First batch prompt") == false)
        #expect(try store.backgroundMessages(runID: "run-2").map(\.content) == ["Second batch prompt"])
    }

    @Test func retryReusesSuccessfulWriteToolResultInsteadOfWritingTwice() throws {
        let store = try SQLiteMemoryOSStore(path: temporaryHeadlessLoopDatabaseURL().path)
        try store.migrate()
        let model = RetryWriteLoopModel()
        let executor = MemoryOSHeadlessKnowledgeLoopExecutor(
            model: model,
            toolExecutor: MemoryOSBackgroundToolExecutor(facade: AppMemoryOSFacade(store: store)),
            store: store
        )
        let request = MemoryOSBackgroundModelRequest(
            jobID: "retry-job",
            kind: MemoryOSBackgroundJobKind.l1SynthesizeKnowledge.rawValue,
            schemaName: "MemoryOSL1UnifiedProjectionOutput",
            artifactType: "memory_os_l1_unified_projection",
            prompt: "Write once even if the model connection fails later.",
            metadata: ["background_run_id": "retry-run"]
        )

        #expect(throws: RetryWriteLoopModel.Failure.self) { try executor.execute(request) }
        _ = try executor.execute(request)

        #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_l3_beliefs;").first?.first == "1")
        #expect(try store.backgroundToolCalls(runID: "retry-run").contains { $0.metadata["idempotent_replay"] == "true" })
    }
}

private final class ScriptedLoopModel: MemoryOSBackgroundToolLoopModel, @unchecked Sendable {
    let modelID = "scripted-loop-model"
    private var script: [MemoryOSBackgroundLoopModelResponse]

    init(script: [MemoryOSBackgroundLoopModelResponse]) {
        self.script = script
    }

    func complete(_ request: MemoryOSBackgroundLoopModelRequest) throws -> MemoryOSBackgroundLoopModelResponse {
        guard !script.isEmpty else { return MemoryOSBackgroundLoopModelResponse(assistantText: "{}") }
        return script.removeFirst()
    }
}

private final class CapturingLoopModel: MemoryOSBackgroundToolLoopModel, @unchecked Sendable {
    let modelID = "capturing-loop-model"
    var capturedInitialMessageContents: [String] = []

    func complete(_ request: MemoryOSBackgroundLoopModelRequest) throws -> MemoryOSBackgroundLoopModelResponse {
        capturedInitialMessageContents.append(request.messages.map(\.content).joined(separator: "\n"))
        return MemoryOSBackgroundLoopModelResponse(assistantText: "{}")
    }
}

private final class RetryWriteLoopModel: MemoryOSBackgroundToolLoopModel, @unchecked Sendable {
    enum Failure: Error { case disconnected }

    let modelID = "retry-write-loop-model"
    private var invocation = 0
    private let arguments = #"{"beliefs":[{"statement":"Retries must be idempotent.","domain":"engineering"}]}"#

    func complete(_ request: MemoryOSBackgroundLoopModelRequest) throws -> MemoryOSBackgroundLoopModelResponse {
        invocation += 1
        switch invocation {
        case 1:
            return MemoryOSBackgroundLoopModelResponse(toolCalls: [MemoryOSBackgroundToolCall(id: "write-1", name: "memory_os_l3_update_beliefs", argumentsJSON: arguments)])
        case 2:
            throw Failure.disconnected
        case 3:
            return MemoryOSBackgroundLoopModelResponse(toolCalls: [MemoryOSBackgroundToolCall(id: "write-2", name: "memory_os_l3_update_beliefs", argumentsJSON: arguments)])
        default:
            return MemoryOSBackgroundLoopModelResponse(assistantText: "{}")
        }
    }
}

private func temporaryHeadlessLoopDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}
