import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphStore

@Test func conversationSummaryCommitIsAtomicAndRevisionChecked() throws {
    let store = try SQLiteGraphKernelStore(path: ":memory:")
    try store.migrate()
    let payload = ConversationSummaryPayload(currentGoal: "Ship rolling summaries")
    let first = ConversationSummaryState(
        sessionID: "session",
        revision: 1,
        compressionGeneration: 1,
        payload: payload,
        coveredThroughMessageID: "message-2",
        coveredMessageCount: 2,
        coveredPrefixHash: "prefix-1",
        currentSummaryHash: "summary-1",
        sourceTokenEstimate: 1_000,
        summaryTokenEstimate: 100,
        generationModelID: "model",
        generatedAt: Date(timeIntervalSince1970: 10)
    )
    let firstRecord = ConversationCompactionRecord(
        sessionID: "session",
        generation: 1,
        baseRevision: 0,
        newCutoffMessageID: "message-2",
        deltaMessageIDs: ["message-1", "message-2"],
        deltaAttachmentIDs: [],
        newSummaryHash: "summary-1",
        modelID: "model",
        startedAt: Date(timeIntervalSince1970: 1),
        completedAt: Date(timeIntervalSince1970: 2),
        status: .succeeded
    )

    #expect(try store.commitConversationCompaction(state: first, record: firstRecord, expectedRevision: nil))
    #expect(try store.conversationSummaryState(sessionID: "session") == first)

    var staleUpdate = first
    staleUpdate.revision = 2
    staleUpdate.currentSummaryHash = "summary-2"
    let staleRecord = ConversationCompactionRecord(
        sessionID: "session",
        generation: 2,
        baseRevision: 0,
        newCutoffMessageID: "message-4",
        deltaMessageIDs: ["message-3", "message-4"],
        deltaAttachmentIDs: [],
        newSummaryHash: "summary-2",
        modelID: "model",
        startedAt: Date(timeIntervalSince1970: 3),
        completedAt: Date(timeIntervalSince1970: 4),
        status: .succeeded
    )

    #expect(try !store.commitConversationCompaction(state: staleUpdate, record: staleRecord, expectedRevision: 0))
    #expect(try store.conversationCompactionRecords(sessionID: "session").count == 1)
    #expect(try store.conversationSummaryState(sessionID: "session")?.currentSummaryHash == "summary-1")
}
