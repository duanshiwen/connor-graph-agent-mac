import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryExtractionTraceDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

@Test func extractionTracePersistsAndLoadsByJobAndSource() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryExtractionTraceDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    let trace = GraphExtractionTrace(
        id: "trace-1",
        jobID: "job-1",
        graphID: "default",
        sourceID: "source-1",
        sourceType: .chat,
        outcome: .held,
        admissionAction: .hold,
        admissionReasons: [.lowStatementConfidence, .missingStatementEvidence],
        extractedEntityCount: 2,
        extractedStatementCount: 1,
        committedEntityCount: 0,
        committedStatementCount: 0,
        anomalyCount: 0,
        errorMessage: "held by policy",
        createdAt: now,
        metadata: ["extractor": "test"]
    )

    try store.appendExtractionTrace(trace)

    let byJob = try store.extractionTraces(jobID: "job-1")
    let bySource = try store.extractionTraces(graphID: "default", sourceID: "source-1")

    #expect(byJob == [trace])
    #expect(bySource == [trace])
}

@Test func extractionTracePayloadPersistsAndLoadsByTraceID() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryExtractionTraceDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 2_000)
    let payload = GraphExtractionTracePayload(
        traceID: "trace-payload-1",
        promptText: "extract this",
        rawResponseJSON: "{\"id\":\"resp-1\"}",
        normalizedJSON: "{\"entities\":[]}",
        decoderErrorKind: "invalid_json",
        decoderErrorMessage: "invalidJSON: test",
        createdAt: now,
        metadata: ["note": "test"]
    )

    try store.appendExtractionTracePayload(payload)

    #expect(try store.extractionTracePayload(traceID: "trace-payload-1") == payload)
    #expect(try store.extractionTracePayload(traceID: "missing") == nil)
}

@Test func memoryChangeLogPersistsAndLoadsRecentEntries() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryExtractionTraceDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 2_500)
    let entry = GraphMemoryChangeLogEntry(
        id: "change-1",
        graphID: "default",
        action: .extractionCommitted,
        traceID: "trace-1",
        jobID: "job-1",
        sourceID: "source-1",
        sourceType: .chat,
        entityIDs: ["entity-1"],
        statementIDs: ["statement-1"],
        summary: "committed test",
        createdAt: now,
        metadata: ["admission_action": "auto_commit"]
    )

    try store.appendMemoryChangeLogEntry(entry)

    #expect(try store.memoryChangeLogEntries(graphID: "default") == [entry])
}

@Test func admissionHoldQueuePersistsLoadsAndUpdatesStatus() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryExtractionTraceDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 3_000)
    let item = GraphAdmissionHoldQueueItem(
        id: "hold-1",
        traceID: "trace-1",
        jobID: "job-1",
        graphID: "default",
        sourceID: "source-1",
        sourceType: .chat,
        reasons: [.lowStatementConfidence, .missingStatementEvidence],
        recommendedActions: [.rerunExtraction, .groundSource, .replayTrace],
        message: "held by policy",
        createdAt: now,
        metadata: ["system_queue": "true"]
    )

    try store.upsertAdmissionHoldQueueItem(item)

    #expect(try store.admissionHoldQueueItem(id: "hold-1") == item)
    #expect(try store.admissionHoldQueueItems(graphID: "default", status: .open).map(\.id) == ["hold-1"])

    let resolvedAt = Date(timeIntervalSince1970: 4_000)
    try store.updateAdmissionHoldQueueItemStatus(id: "hold-1", status: .resolved, resolvedAt: resolvedAt, now: resolvedAt)
    let resolved = try #require(try store.admissionHoldQueueItem(id: "hold-1"))
    #expect(resolved.status == .resolved)
    #expect(resolved.resolvedAt == resolvedAt)
    #expect(try store.admissionHoldQueueItems(graphID: "default", status: .open).isEmpty)
}
