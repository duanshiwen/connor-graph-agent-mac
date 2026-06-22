import Foundation
import ConnorGraphCore

public extension SQLiteMemoryOSStore {
    func upsert(l2ProcessingState state: MemoryOSL2StatementProcessingState) throws {
        try execute("""
        INSERT OR REPLACE INTO memory_l2_statement_processing_state
        (statement_id, processing_kind, status, source_artifact_id, processed_by_artifact_id, last_attempt_at, metadata_json)
        VALUES (\(quote(state.statementID)), \(quote(state.processingKind.rawValue)), \(quote(state.status.rawValue)), \(quote(state.sourceArtifactID)), \(quote(state.processedByArtifactID)), \(quote(state.lastAttemptAt.map(iso))), \(quote(json(state.metadata))))
        """)
    }

    func l2ProcessingStates(processingKind: MemoryOSL2ProcessingKind? = nil, status: MemoryOSQueueStatus? = nil, limit: Int = 100) throws -> [MemoryOSL2StatementProcessingState] {
        let kindClause = processingKind.map { " AND processing_kind = \(quote($0.rawValue))" } ?? ""
        let statusClause = status.map { " AND status = \(quote($0.rawValue))" } ?? ""
        return try query(sql: """
        SELECT statement_id, processing_kind, status, source_artifact_id, processed_by_artifact_id, last_attempt_at, metadata_json
        FROM memory_l2_statement_processing_state
        WHERE 1 = 1\(kindClause)\(statusClause)
        ORDER BY last_attempt_at ASC, statement_id ASC
        LIMIT \(limit)
        """).map { row in
            MemoryOSL2StatementProcessingState(
                statementID: row[0],
                processingKind: MemoryOSL2ProcessingKind(rawValue: row[1]) ?? .knowledgeSynthesis,
                status: MemoryOSQueueStatus(rawValue: row[2]) ?? .pending,
                sourceArtifactID: row[3].isEmpty ? nil : row[3],
                processedByArtifactID: row[4].isEmpty ? nil : row[4],
                lastAttemptAt: row[5].isEmpty ? nil : ISO8601DateFormatter().date(from: row[5]),
                metadata: (try? decode([String: String].self, row[6])) ?? [:]
            )
        }
    }
}
