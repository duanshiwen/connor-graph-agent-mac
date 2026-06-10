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
