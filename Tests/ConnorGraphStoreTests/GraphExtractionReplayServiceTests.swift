import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

private func temporaryExtractionReplayDatabaseURL(_ name: String = UUID().uuidString) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("\(name).sqlite")
}

private let replayExtractionJSON = """
{
  "entities": [
    {
      "localID": "shiwen",
      "name": "诗闻",
      "entityKind": "person_object",
      "scope": "personal",
      "canonicalClassID": null,
      "aliases": [],
      "summary": "",
      "confidence": 0.9,
      "evidenceSpanIDs": ["span-1"],
      "metadata": {}
    },
    {
      "localID": "tea",
      "name": "tea",
      "entityKind": "life_object",
      "scope": "personal",
      "canonicalClassID": null,
      "aliases": [],
      "summary": "",
      "confidence": 0.85,
      "evidenceSpanIDs": ["span-1"],
      "metadata": {}
    }
  ],
  "statements": [
    {
      "explicitID": null,
      "subjectLocalID": "shiwen",
      "predicate": "PREFERS",
      "objectLocalID": "tea",
      "statementText": "诗闻 prefers tea",
      "confidence": 0.88,
      "validAt": null,
      "referenceTime": null,
      "evidenceSpanIDs": ["span-1"],
      "metadata": {}
    }
  ],
  "evidenceSpans": [
    { "id": "span-1", "text": "诗闻 prefers tea.", "startOffset": null, "endOffset": null }
  ],
  "warnings": [],
  "confidence": 0.87,
  "metadata": {}
}
"""

@Test func extractionReplayDecodesStoredPayloadAndAppendsReplayTrace() throws {
    let store = try SQLiteGraphKernelStore(path: temporaryExtractionReplayDatabaseURL().path)
    try store.migrate()
    let now = Date(timeIntervalSince1970: 1_000)
    let source = GraphExtractionSource(id: "chat-replay-1", graphID: "default", sourceType: .chat, title: "Preference", content: "诗闻 prefers tea.", occurredAt: now)
    let job = GraphJobV3(
        id: "job-replay-1",
        graphID: "default",
        type: .extraction,
        payload: GraphExtractionJobPayload(source: source).dictionary,
        createdAt: now,
        nextRunAt: now
    )
    try store.upsert(job: job)
    try store.appendExtractionTrace(GraphExtractionTrace(
        id: "trace-original-1",
        jobID: job.id,
        graphID: "default",
        sourceID: source.id,
        sourceType: source.sourceType,
        outcome: .failed,
        errorMessage: "original failed",
        createdAt: now
    ))
    try store.appendExtractionTracePayload(GraphExtractionTracePayload(
        traceID: "trace-original-1",
        normalizedJSON: replayExtractionJSON,
        createdAt: now
    ))

    let result = try GraphExtractionReplayService(store: store).replay(
        traceID: "trace-original-1",
        mode: .decodeStoredRawResponse,
        now: Date(timeIntervalSince1970: 2_000)
    )

    #expect(result.originalTraceID == "trace-original-1")
    #expect(result.draft?.entities.count == 2)
    #expect(result.admissionDecision?.action == .autoCommit)
    let replayTrace = try #require(store.extractionTrace(id: result.replayTraceID))
    #expect(replayTrace.metadata["replayed_from_trace_id"] == "trace-original-1")
    #expect(replayTrace.metadata["dry_run"] == "true")
    #expect(replayTrace.extractedStatementCount == 1)
    let replayPayload = try #require(store.extractionTracePayload(traceID: result.replayTraceID))
    #expect(replayPayload.normalizedJSON?.contains("诗闻 prefers tea") == true)
}
