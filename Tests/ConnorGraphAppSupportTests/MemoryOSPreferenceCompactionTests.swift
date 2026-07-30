import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore
import ConnorGraphAppSupport

@Test func compressedProfileViewUsesPublishedSnapshotPlusRawDelta() throws {
    let (store, facade) = try preferenceTestRuntime()
    let start = Date(timeIntervalSince1970: 100_000)
    try insertPreference(index: 0, at: start, store: store)
    let first = try #require(MemoryOSPreferenceCompactionStore(store: store).preferenceRecords().first)
    let draft = MemoryOSPreferenceCompactionJobDraft(
        records: [first],
        targetWatermark: .init(committedAt: first.committedAt, statementID: first.id)
    )
    let output = MemoryOSPreferenceCompactionOutput(
        items: [.init(key: "communication.conciseness", statement: "The user prefers concise replies.", supportingRecordIDs: [first.id])],
        sourceDispositions: [.init(recordID: first.id, action: .active, itemKey: "communication.conciseness")]
    )
    _ = try facade.publishPreferenceCompaction(draft: draft, rawOutput: encoded(output), modelID: "test-model", now: start.addingTimeInterval(1))
    try insertPreference(index: 1, at: start.addingTimeInterval(2), store: store)

    let compressed = try facade.currentUserProfileHits(view: .compressed)
    let raw = try facade.currentUserProfileHits(view: .raw)

    #expect(compressed.contains { $0.title == "compressed_profile_preferences" && $0.summary.contains("concise replies") })
    #expect(compressed.contains { $0.recordID == "preference-1" })
    #expect(!compressed.contains { $0.recordID == "preference-0" })
    #expect(raw.contains { $0.recordID == "preference-0" })
    #expect(raw.contains { $0.recordID == "preference-1" })
    #expect(!raw.contains { $0.title == "compressed_profile_preferences" })
}

@Test func preferenceCompactionEnqueuesAtTwentyAndBatchesAtMostSixty() throws {
    let (store, facade) = try preferenceTestRuntime()
    let start = Date(timeIntervalSince1970: 200_000)
    for index in 0..<19 { try insertPreference(index: index, at: start.addingTimeInterval(Double(index)), store: store) }
    #expect(try facade.enqueuePreferenceCompactionBackgroundJob(now: start.addingTimeInterval(19)) == nil)

    try insertPreference(index: 19, at: start.addingTimeInterval(19), store: store)
    let queuedItem = try facade.enqueuePreferenceCompactionBackgroundJob(now: start.addingTimeInterval(20))
    let item = try #require(queuedItem)
    let draft = try store.decode(MemoryOSPreferenceCompactionJobDraft.self, item.payloadJSON)
    #expect(draft.records.count == 20)
    #expect(draft.metadata["drain_backlog"] == "false")
}

@Test func preferenceCompactionDrainsSixtyThenQueuesRemainingRecords() throws {
    let (store, facade) = try preferenceTestRuntime()
    let start = Date(timeIntervalSince1970: 300_000)
    for index in 0..<61 { try insertPreference(index: index, at: start.addingTimeInterval(Double(index)), store: store) }
    let queuedFirstItem = try facade.enqueuePreferenceCompactionBackgroundJob(now: start.addingTimeInterval(61))
    let firstItem = try #require(queuedFirstItem)
    let firstDraft = try store.decode(MemoryOSPreferenceCompactionJobDraft.self, firstItem.payloadJSON)
    #expect(firstDraft.records.count == 60)
    #expect(firstDraft.metadata["drain_backlog"] == "true")

    let summaries = try facade.runBackgroundAIQueueOnce(executor: PreferenceCompactionTestExecutor(), limit: 1, now: start.addingTimeInterval(62))
    #expect(summaries.count == 1)
    #expect(summaries[0].accepted)

    let next = try #require(store.runnableQueueItems(kind: MemoryOSBackgroundJobKind.preferenceCompaction.rawValue, limit: 10, now: start.addingTimeInterval(62)).first)
    let nextDraft = try store.decode(MemoryOSPreferenceCompactionJobDraft.self, next.payloadJSON)
    #expect(nextDraft.records.count == 1)
    #expect(nextDraft.baseSnapshotID != nil)
}

@Test func preferenceCompactionDailySweepRunsOnlyWithOldUnpublishedRecords() throws {
    let (store, facade) = try preferenceTestRuntime()
    let start = Date(timeIntervalSince1970: 400_000)
    let coordinator = AppMemoryOSPipelineTriggerCoordinator(facade: facade)
    #expect(try coordinator.runDailySweep(now: start).isEmpty)

    try insertPreference(index: 0, at: start, store: store)
    #expect(try coordinator.runDailySweep(now: start.addingTimeInterval(86_399)).isEmpty)
    let items = try coordinator.runDailySweep(now: start.addingTimeInterval(86_400))
    #expect(items.contains { $0.kind == MemoryOSBackgroundJobKind.preferenceCompaction.rawValue })
}

@Test func preferenceCompactionRejectsOutputThatDropsANewSourceRecord() throws {
    let (_, facade) = try preferenceTestRuntime()
    let record = MemoryOSPreferenceCompactionSourceRecord(id: "source-1", statement: "Use concise replies", predicate: "RELATED_TO", confidence: 0.9, committedAt: Date(timeIntervalSince1970: 500_000))
    let draft = MemoryOSPreferenceCompactionJobDraft(records: [record], targetWatermark: .init(committedAt: record.committedAt, statementID: record.id))
    let invalid = MemoryOSPreferenceCompactionOutput(items: [], sourceDispositions: [])

    #expect(throws: MemoryOSPreferenceCompactionValidationError.self) {
        _ = try facade.publishPreferenceCompaction(draft: draft, rawOutput: encoded(invalid), modelID: "test-model")
    }
}

@Test func preferenceCompactionPromptDoesNotIncludePreviousCanonicalProfile() throws {
    let previousMarker = "PREVIOUS_PROFILE_MUST_NOT_REENTER_THE_PROMPT"
    let record = MemoryOSPreferenceCompactionSourceRecord(
        id: "source-new",
        statement: "Use direct replies",
        predicate: "PREFERS",
        confidence: 0.9,
        committedAt: Date(timeIntervalSince1970: 600_000)
    )
    let draft = MemoryOSPreferenceCompactionJobDraft(
        baseSnapshotID: "snapshot-previous",
        previousProfile: .init(
            items: [.init(key: "previous.item", statement: previousMarker, supportingRecordIDs: ["source-old"])],
            sourceDispositions: []
        ),
        previousSourceRecordCount: 1,
        records: [record],
        targetWatermark: .init(committedAt: record.committedAt, statementID: record.id)
    )
    let executor = CapturingPreferenceCompactionExecutor()

    _ = try MemoryOSPreferenceCompactionWorker(executor: executor).run(draft)

    let prompt = try #require(executor.lastRequest?.prompt)
    #expect(prompt.contains(record.statement))
    #expect(!prompt.contains(previousMarker))
    #expect(!prompt.contains("Previous canonical profile"))
}

@Test func preferenceCompactionRuntimeMergesIndependentBatchWithPublishedProfile() throws {
    let (store, facade) = try preferenceTestRuntime()
    let start = Date(timeIntervalSince1970: 700_000)
    try insertPreference(index: 0, at: start, store: store)
    try insertPreference(index: 1, at: start.addingTimeInterval(1), store: store)
    let records = try MemoryOSPreferenceCompactionStore(store: store).preferenceRecords()
    let first = try #require(records.first)
    let second = try #require(records.last)
    let firstDraft = MemoryOSPreferenceCompactionJobDraft(
        records: [first],
        targetWatermark: .init(committedAt: first.committedAt, statementID: first.id)
    )
    let firstOutput = MemoryOSPreferenceCompactionOutput(
        items: [
            .init(key: "communication.style", statement: "Prefer concise replies.", supportingRecordIDs: [first.id]),
            .init(key: "visual.style", statement: "Prefer bright visuals.", supportingRecordIDs: [first.id])
        ],
        sourceDispositions: [.init(recordID: first.id, action: .active, itemKey: "communication.style")]
    )
    let firstSnapshot = try facade.publishPreferenceCompaction(
        draft: firstDraft,
        rawOutput: encoded(firstOutput),
        modelID: "test-model",
        now: start.addingTimeInterval(2)
    )
    let secondDraft = MemoryOSPreferenceCompactionJobDraft(
        baseSnapshotID: firstSnapshot.id,
        previousProfile: firstSnapshot.profile,
        previousSourceRecordCount: firstSnapshot.sourceRecordCount,
        records: [second],
        targetWatermark: .init(committedAt: second.committedAt, statementID: second.id)
    )
    let secondOutput = MemoryOSPreferenceCompactionOutput(
        items: [.init(key: "communication.style", statement: "Prefer direct, concise replies.", supportingRecordIDs: [second.id])],
        sourceDispositions: [.init(recordID: second.id, action: .merged, itemKey: "communication.style")]
    )

    let merged = try facade.publishPreferenceCompaction(
        draft: secondDraft,
        rawOutput: encoded(secondOutput),
        modelID: "test-model",
        now: start.addingTimeInterval(3)
    )

    #expect(merged.profile.items.map(\.key).sorted() == ["communication.style", "visual.style"])
    let communication = try #require(merged.profile.items.first { $0.key == "communication.style" })
    #expect(communication.statement == "Prefer direct, concise replies.")
    #expect(Set(communication.supportingRecordIDs) == Set([first.id, second.id]))
    #expect(merged.sourceRecordCount == 2)
}

private final class PreferenceCompactionTestExecutor: MemoryOSBackgroundModelExecutor, @unchecked Sendable {
    func execute(_ request: MemoryOSBackgroundModelRequest) throws -> MemoryOSBackgroundModelResponse {
        let sourceIDs = request.sourceRecordIDs
        let output = MemoryOSPreferenceCompactionOutput(
            items: [.init(key: "test.preference", statement: "The user has recorded test preferences.", supportingRecordIDs: sourceIDs)],
            sourceDispositions: sourceIDs.map { .init(recordID: $0, action: .merged, itemKey: "test.preference") }
        )
        return MemoryOSBackgroundModelResponse(rawArtifactJSON: encoded(output), metadata: ["model_id": "test-model"])
    }
}

private final class CapturingPreferenceCompactionExecutor: MemoryOSBackgroundModelExecutor, @unchecked Sendable {
    var lastRequest: MemoryOSBackgroundModelRequest?

    func execute(_ request: MemoryOSBackgroundModelRequest) throws -> MemoryOSBackgroundModelResponse {
        lastRequest = request
        let sourceIDs = request.sourceRecordIDs
        let output = MemoryOSPreferenceCompactionOutput(
            items: [.init(key: "communication.directness", statement: "Use direct replies.", supportingRecordIDs: sourceIDs)],
            sourceDispositions: sourceIDs.map { .init(recordID: $0, action: .active, itemKey: "communication.directness") }
        )
        return MemoryOSBackgroundModelResponse(rawArtifactJSON: encoded(output), metadata: ["model_id": "test-model"])
    }
}

private func preferenceTestRuntime() throws -> (SQLiteMemoryOSStore, AppMemoryOSFacade) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("memory-preference-compaction-\(UUID().uuidString).sqlite")
    let store = try SQLiteMemoryOSStore(path: url.path)
    try store.migrate()
    try store.upsert(node: MemoryOSNode(
        id: "node-current-user",
        stableKey: "current_user_profile",
        nodeType: "person_profile",
        name: "Current User",
        metadata: ["person_role": "current_user"]
    ))
    let facade = AppMemoryOSFacade(store: store)
    _ = try facade.ensureCurrentUserAnchor()
    return (store, facade)
}

private func insertPreference(index: Int, at date: Date, store: SQLiteMemoryOSStore) throws {
    try store.upsert(statement: MemoryOSStatement(
        id: "preference-\(index)",
        subjectID: "node-current-user",
        predicate: "RELATED_TO",
        text: "Preference statement \(index)",
        confidence: 0.9,
        validAt: date,
        committedAt: date,
        metadata: [
            "l2_fact_type": "profile_preference",
            "person_role": "current_user",
            "identity_anchor": "current_user"
        ]
    ))
}

private func encoded<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try! encoder.encode(value), as: UTF8.self)
}
