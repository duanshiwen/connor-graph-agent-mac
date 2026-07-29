import Foundation
import ConnorGraphMemory
import ConnorGraphStore

public struct MemoryOSPreferenceCompactionStore: Sendable {
    public var store: SQLiteMemoryOSStore

    public init(store: SQLiteMemoryOSStore) {
        self.store = store
    }

    public func publishedSnapshot() throws -> MemoryOSPreferenceCompactionSnapshot? {
        guard let row = try store.query(sql: """
        SELECT id, base_snapshot_id, covered_through_committed_at, covered_through_statement_id,
               structured_profile_json, rendered_text, source_record_count, model_id,
               created_at, published_at, metadata_json
        FROM memory_profile_compaction_snapshots
        WHERE status = 'published'
        ORDER BY published_at DESC
        LIMIT 1
        """).first else { return nil }
        let decoder = JSONDecoder()
        guard let profileData = row[4].data(using: .utf8),
              let profile = try? decoder.decode(MemoryOSPreferenceCompactionOutput.self, from: profileData)
        else {
            throw SQLiteMemoryOSStoreError.decodeFailed("Invalid published preference compaction profile")
        }
        return MemoryOSPreferenceCompactionSnapshot(
            id: row[0],
            baseSnapshotID: row[1].isEmpty ? nil : row[1],
            watermark: MemoryOSPreferenceWatermark(committedAt: try parseDate(row[2]), statementID: row[3]),
            profile: profile,
            renderedText: row[5],
            sourceRecordCount: Int(row[6]) ?? 0,
            modelID: row[7].isEmpty ? nil : row[7],
            createdAt: try parseDate(row[8]),
            publishedAt: row[9].isEmpty ? nil : try parseDate(row[9]),
            metadata: (try? store.decode([String: String].self, row[10])) ?? [:]
        )
    }

    public func preferenceRecords(after watermark: MemoryOSPreferenceWatermark? = nil, limit: Int? = nil) throws -> [MemoryOSPreferenceCompactionSourceRecord] {
        let watermarkClause: String
        if let watermark {
            watermarkClause = """
              AND (s.committed_at > \(store.quote(store.iso(watermark.committedAt)))
                   OR (s.committed_at = \(store.quote(store.iso(watermark.committedAt))) AND s.id > \(store.quote(watermark.statementID))))
            """
        } else {
            watermarkClause = ""
        }
        let limitClause = limit.map { "LIMIT \(max(1, $0))" } ?? ""
        return try store.query(sql: """
        SELECT s.id, s.text, s.predicate, s.confidence, s.committed_at, s.metadata_json
        FROM memory_l2_statements s
        WHERE json_extract(s.metadata_json, '$.l2_fact_type') = 'profile_preference'
          AND (json_extract(s.metadata_json, '$.person_role') = 'current_user'
               OR json_extract(s.metadata_json, '$.identity_anchor') = 'current_user')
        \(watermarkClause)
        ORDER BY s.committed_at ASC, s.id ASC
        \(limitClause)
        """).map { row in
            MemoryOSPreferenceCompactionSourceRecord(
                id: row[0],
                statement: row[1],
                predicate: row[2],
                confidence: Double(row[3]) ?? 0,
                committedAt: try parseDate(row[4]),
                metadata: (try? store.decode([String: String].self, row[5])) ?? [:]
            )
        }
    }

    public func unpublishedPreferenceCount(after watermark: MemoryOSPreferenceWatermark?) throws -> Int {
        Int(try store.query(sql: """
        SELECT COUNT(*)
        FROM memory_l2_statements s
        WHERE json_extract(s.metadata_json, '$.l2_fact_type') = 'profile_preference'
          AND (json_extract(s.metadata_json, '$.person_role') = 'current_user'
               OR json_extract(s.metadata_json, '$.identity_anchor') = 'current_user')
        \(watermarkPredicate(watermark))
        """).first?.first ?? "0") ?? 0
    }

    public func oldestUnpublishedPreferenceDate(after watermark: MemoryOSPreferenceWatermark?) throws -> Date? {
        guard let value = try store.query(sql: """
        SELECT s.committed_at
        FROM memory_l2_statements s
        WHERE json_extract(s.metadata_json, '$.l2_fact_type') = 'profile_preference'
          AND (json_extract(s.metadata_json, '$.person_role') = 'current_user'
               OR json_extract(s.metadata_json, '$.identity_anchor') = 'current_user')
        \(watermarkPredicate(watermark))
        ORDER BY s.committed_at ASC, s.id ASC
        LIMIT 1
        """).first?.first else { return nil }
        return try parseDate(value)
    }

    private func watermarkPredicate(_ watermark: MemoryOSPreferenceWatermark?) -> String {
        guard let watermark else { return "" }
        return """
          AND (s.committed_at > \(store.quote(store.iso(watermark.committedAt)))
               OR (s.committed_at = \(store.quote(store.iso(watermark.committedAt))) AND s.id > \(store.quote(watermark.statementID))))
        """
    }

    private func parseDate(_ value: String) throws -> Date {
        guard let date = ISO8601DateFormatter().date(from: value) else {
            throw SQLiteMemoryOSStoreError.decodeFailed("Invalid preference compaction date: \(value)")
        }
        return date
    }
}
