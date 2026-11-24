import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphStore

@Suite("Memory account sync revisions")
struct MemoryOSAccountSyncRevisionTests {
    @Test func tracksRawWritesDeletesAndRollbacksWithoutRetainingPayloads() throws {
        let store = try SQLiteMemoryOSStore(path: ":memory:")
        try store.migrate()
        try store.execute("INSERT INTO memory_l3_beliefs(id, statement, created_at, updated_at) VALUES ('one', 'initial', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z');")
        let baseline = try store.accountSyncSnapshot(storeID: nil, after: nil)
        #expect(baseline.changedIDs["memory_l3"] == ["one"])
        #expect(baseline.liveKeys == ["memory_l3|one"])
        #expect(try store.accountSyncSnapshot(storeID: baseline.storeID, after: baseline.revision).changedIDs.isEmpty)
        try store.execute("BEGIN; UPDATE memory_l3_beliefs SET statement = 'rolled back' WHERE id = 'one'; ROLLBACK;")
        #expect(try store.accountSyncSnapshot(storeID: baseline.storeID, after: baseline.revision).revision == baseline.revision)
        try store.execute("UPDATE memory_l3_beliefs SET statement = 'changed' WHERE id = 'one';")
        let update = try store.accountSyncSnapshot(storeID: baseline.storeID, after: baseline.revision)
        #expect(update.changedIDs["memory_l3"] == ["one"])
        #expect(try store.listAllBeliefs(ids: update.changedIDs["memory_l3"]).first?.statement == "changed")
        try store.execute("DELETE FROM memory_l3_beliefs WHERE id = 'one';")
        let deletion = try store.accountSyncSnapshot(storeID: update.storeID, after: update.revision)
        #expect(deletion.changedIDs["memory_l3"] == ["one"])
        #expect(deletion.liveKeys.isEmpty)
        #expect(try store.listAllBeliefs(ids: []).isEmpty)
        #expect(try store.query(sql: "SELECT COUNT(*) FROM memory_account_sync_revisions;") == [["1"]])
    }

    @Test func migrationTracksExistingRowsAndIsIdempotent() throws {
        let store = try SQLiteMemoryOSStore(path: ":memory:")
        try store.migrate()
        try store.execute("INSERT INTO memory_l3_beliefs(id, statement, created_at, updated_at) VALUES ('old', 'old', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z');")
        let baseline = try store.accountSyncSnapshot(storeID: nil, after: nil)
        try store.migrate()
        let next = try store.accountSyncSnapshot(storeID: baseline.storeID, after: baseline.revision)
        #expect(next.storeID == baseline.storeID)
        #expect(next.changedIDs.isEmpty)
        // A restored/replaced database must receive a full scan, even if its
        // numeric watermark happens to match the previous database.
        #expect(try store.accountSyncSnapshot(storeID: "another-database", after: next.revision).changedIDs["memory_l3"] == ["old"])
    }

    @Test func changesFromAnotherConnectionAreVisible() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("memory.sqlite").path
        let store = try SQLiteMemoryOSStore(path: path)
        try store.migrate()
        let baseline = try store.accountSyncSnapshot(storeID: nil, after: nil)
        let writer = try SQLiteMemoryOSStore(path: path)
        try writer.execute("INSERT INTO memory_l3_beliefs(id, statement, created_at, updated_at) VALUES ('external', 'external', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z');")
        #expect(try store.accountSyncSnapshot(storeID: baseline.storeID, after: baseline.revision).changedIDs["memory_l3"] == ["external"])
    }

    @Test func incrementalReadOnlyDecodesChangedRecordsInLargeStore() throws {
        let store = try SQLiteMemoryOSStore(path: ":memory:")
        try store.migrate()
        try store.execute("""
        WITH RECURSIVE numbers(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM numbers WHERE n < 1000)
        INSERT INTO memory_l3_beliefs(id, statement, created_at, updated_at)
        SELECT 'belief-' || n, 'statement-' || n, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z' FROM numbers;
        """)
        let baseline = try store.accountSyncSnapshot(storeID: nil, after: nil)
        #expect(baseline.changedIDs["memory_l3"]?.count == 1000)
        try store.execute("UPDATE memory_l3_beliefs SET statement = 'changed' WHERE id = 'belief-999';")
        let fullStart = ContinuousClock.now
        let full = try store.listAllBeliefs()
        let fullElapsed = fullStart.duration(to: .now)
        let incrementalStart = ContinuousClock.now
        let snapshot = try store.accountSyncSnapshot(storeID: baseline.storeID, after: baseline.revision)
        let partial = try store.listAllBeliefs(ids: snapshot.changedIDs["memory_l3"] ?? [])
        let incrementalElapsed = incrementalStart.duration(to: .now)
        #expect(full.count == 1000)
        #expect(partial.count == 1)
        #expect(partial.first?.id == "belief-999")
        #expect(partial.first?.statement == "changed")
        print("CONNOR_SYNC_BENCH full_records=1000 changed_records=1 full=\(fullElapsed) incremental=\(incrementalElapsed)")
    }

    @Test func clearingMemoryResetsTrackingAndLeavesStoreUsable() throws {
        let store = try SQLiteMemoryOSStore(path: ":memory:")
        try store.migrate()
        let before = try store.accountSyncSnapshot(storeID: nil, after: nil)
        try store.clearAllMemoryData()
        let after = try store.accountSyncSnapshot(storeID: before.storeID, after: before.revision)
        #expect(after.storeID != before.storeID)
        #expect(after.liveKeys.isEmpty)
        #expect(try store.schemaHealthReport().status == .healthy)
        try store.execute("INSERT INTO memory_l3_beliefs(id, statement, created_at, updated_at) VALUES ('new', 'new', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z');")
        #expect(try store.accountSyncSnapshot(storeID: after.storeID, after: after.revision).changedIDs["memory_l3"] == ["new"])
    }

    @Test func sharedDateFormatterPreservesStoragePrecisionUnderConcurrency() async throws {
        let store = try SQLiteMemoryOSStore(path: ":memory:")
        try store.migrate()
        let date = Date(timeIntervalSince1970: 1_800.875)
        try store.upsert(provenance: MemoryOSProvenanceObject(id: "date", sourceType: .manual, title: "date", content: "date", occurredAt: date))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask { () async throws -> Void in
                    let reference = ISO8601DateFormatter().string(from: date)
                    for _ in 0..<100 {
                        #expect(store.iso(date) == reference)
                        let record = try store.provenanceObject(id: "date")
                        #expect(record?.occurredAt == Date(timeIntervalSince1970: 1_800))
                    }
                }
            }
            try await group.waitForAll()
        }
    }
}
