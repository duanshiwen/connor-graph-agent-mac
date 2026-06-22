import Foundation
import ConnorGraphCore

public struct MemoryOSTemporalEntityKernelAdapter: Sendable {
    public var store: SQLiteMemoryOSStore

    public init(store: SQLiteMemoryOSStore) {
        self.store = store
    }

    public func upsertEntity(_ entity: MemoryOSEntity) throws {
        try store.upsert(entity: entity)
    }

    public func entity(id: String) throws -> MemoryOSEntity? {
        try store.entity(id: id)
    }

    public func searchEntities(query: String, limit: Int = 20) throws -> [String] {
        try store.searchEntitiesFTS(query: query, limit: limit)
    }
}

public struct SQLiteMemoryOSLegacyImporter: Sendable {
    public var store: SQLiteMemoryOSStore

    public init(store: SQLiteMemoryOSStore) {
        self.store = store
    }

    public func recordDryRun(id: String = UUID().uuidString, startedAt: Date = Date()) throws -> String {
        try store.execute("""
        INSERT OR REPLACE INTO memory_legacy_import_runs(id, status, dry_run, started_at, metadata_json)
        VALUES (\(store.quote(id)), 'dry_run_completed', 1, \(store.quote(store.iso(startedAt))), '{}')
        """)
        return id
    }
}
