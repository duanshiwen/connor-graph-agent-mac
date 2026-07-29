import Foundation
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphStore

public extension AppMemoryOSFacade {
    func enqueuePreferenceCompactionBackgroundJob(
        forceIfOlderThan24Hours: Bool = false,
        drainBacklog: Bool = false,
        now: Date = Date()
    ) throws -> MemoryOSQueueItem? {
        guard try !hasActivePreferenceCompactionJob() else { return nil }
        let compactionStore = MemoryOSPreferenceCompactionStore(store: store)
        let snapshot = try compactionStore.publishedSnapshot()
        let watermark = snapshot?.watermark
        let pendingCount = try compactionStore.unpublishedPreferenceCount(after: watermark)
        guard pendingCount > 0 else { return nil }

        let reachedCountThreshold = pendingCount >= 20
        let reachedAgeThreshold: Bool
        if forceIfOlderThan24Hours,
           let oldest = try compactionStore.oldestUnpublishedPreferenceDate(after: watermark) {
            reachedAgeThreshold = now.timeIntervalSince(oldest) >= 24 * 60 * 60
        } else {
            reachedAgeThreshold = false
        }
        guard reachedCountThreshold || reachedAgeThreshold || drainBacklog else { return nil }

        let records = try compactionStore.preferenceRecords(after: watermark, limit: 60)
        guard let last = records.last else { return nil }
        let target = MemoryOSPreferenceWatermark(committedAt: last.committedAt, statementID: last.id)
        let triggerReason: String
        if reachedCountThreshold {
            triggerReason = "pending_count_threshold"
        } else if reachedAgeThreshold {
            triggerReason = "pending_age_threshold"
        } else {
            triggerReason = "drain_backlog"
        }
        let draft = MemoryOSPreferenceCompactionJobDraft(
            baseSnapshotID: snapshot?.id,
            previousProfile: snapshot?.profile ?? .init(items: [], sourceDispositions: []),
            previousSourceRecordCount: snapshot?.sourceRecordCount ?? 0,
            records: records,
            targetWatermark: target,
            createdAt: now,
            metadata: [
                "trigger_reason": triggerReason,
                "pending_count": String(pendingCount),
                "batch_count": String(records.count),
                "drain_backlog": String(drainBacklog || pendingCount > 60),
                "base_snapshot_id": snapshot?.id ?? ""
            ]
        )
        let payload = store.json(draft)
        let item = MemoryOSQueueItem(
            kind: draft.kind,
            priority: 20,
            payloadJSON: payload,
            maxAttempts: .max,
            nextRunAt: now,
            idempotencyKey: "\(draft.kind):\(store.iso(target.committedAt)):\(target.statementID)",
            payloadHash: String(payload.hashValue),
            createdAt: now,
            updatedAt: now
        )
        switch try store.enqueueIfAbsent(item) {
        case .inserted(let inserted): return inserted
        case .existing: return nil
        }
    }

    func publishPreferenceCompaction(
        draft: MemoryOSPreferenceCompactionJobDraft,
        rawOutput: String,
        modelID: String?,
        now: Date = Date()
    ) throws -> MemoryOSPreferenceCompactionSnapshot {
        let validatedOutput = try MemoryOSPreferenceCompactionValidator().decodeAndValidate(rawJSON: rawOutput, draft: draft)
        let previousItemsByKey = Dictionary(uniqueKeysWithValues: draft.previousProfile.items.map { ($0.key, $0) })
        var output = validatedOutput
        output.items = output.items.map { item in
            guard let previous = previousItemsByKey[item.key] else { return item }
            var merged = item
            merged.supportingRecordIDs = Array(Set(previous.supportingRecordIDs + item.supportingRecordIDs)).sorted()
            merged.supersededRecordIDs = Array(Set(previous.supersededRecordIDs + item.supersededRecordIDs)).sorted()
            return merged
        }
        let rendered = MemoryOSPreferenceCompactionRenderer.render(output)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let profileJSON = String(decoding: try encoder.encode(output), as: UTF8.self)
        let snapshot = MemoryOSPreferenceCompactionSnapshot(
            id: "preference-snapshot:\(UUID().uuidString)",
            baseSnapshotID: draft.baseSnapshotID,
            watermark: draft.targetWatermark,
            profile: output,
            renderedText: rendered,
            sourceRecordCount: draft.previousSourceRecordCount + draft.records.count,
            modelID: modelID,
            createdAt: now,
            publishedAt: now,
            metadata: [
                "batch_count": String(draft.records.count),
                "canonical_item_count": String(output.items.count),
                "retired_item_count": String(output.retiredItemKeys.count)
            ]
        )
        let insertSQL = """
        INSERT INTO memory_profile_compaction_snapshots
        (id, status, base_snapshot_id, covered_through_committed_at, covered_through_statement_id,
         structured_profile_json, rendered_text, source_record_count, model_id, created_at, published_at, metadata_json)
        SELECT \(store.quote(snapshot.id)), 'published', \(store.quote(snapshot.baseSnapshotID)),
               \(store.quote(store.iso(snapshot.watermark.committedAt))), \(store.quote(snapshot.watermark.statementID)),
               \(store.quote(profileJSON)), \(store.quote(snapshot.renderedText)), \(snapshot.sourceRecordCount),
               \(store.quote(snapshot.modelID)), \(store.quote(store.iso(snapshot.createdAt))),
               \(store.quote(store.iso(now))), \(store.quote(store.json(snapshot.metadata)))
        """
        if let baseSnapshotID = draft.baseSnapshotID {
            try store.execute("""
            BEGIN IMMEDIATE;
            UPDATE memory_profile_compaction_snapshots
            SET status = 'superseded'
            WHERE id = \(store.quote(baseSnapshotID)) AND status = 'published';
            \(insertSQL) WHERE changes() = 1;
            COMMIT;
            """)
        } else {
            try store.execute("""
            BEGIN IMMEDIATE;
            \(insertSQL) WHERE NOT EXISTS (
                SELECT 1 FROM memory_profile_compaction_snapshots WHERE status = 'published'
            );
            COMMIT;
            """)
        }
        guard try MemoryOSPreferenceCompactionStore(store: store).publishedSnapshot()?.id == snapshot.id else {
            throw SQLiteMemoryOSStoreError.executeFailed("Preference snapshot publication lost an optimistic concurrency race")
        }
        MemoryOSQueryCache.shared.invalidateProfile()
        return snapshot
    }

    private func hasActivePreferenceCompactionJob() throws -> Bool {
        let kind = MemoryOSBackgroundJobKind.preferenceCompaction.rawValue
        return try store.query(sql: """
        SELECT COUNT(*)
        FROM memory_l1_processing_queue
        WHERE kind = \(store.quote(kind))
          AND status IN ('pending', 'leased', 'processing', 'retry_scheduled')
        """).first?.first != "0"
    }
}
