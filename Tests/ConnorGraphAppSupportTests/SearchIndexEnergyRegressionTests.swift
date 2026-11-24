import Foundation
import SQLite3
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Search index energy regressions")
struct SearchIndexEnergyRegressionTests {
    @Test func legacyFTSLookupMigrationPreservesRowsAndSupportsReplacementAndDeletion() async throws {
        let url = temporaryDatabaseURL()
        var service: SessionSearchIndexService? = try SessionSearchIndexService(databaseURL: url)
        let session = AgentSession(id: "legacy", title: "Legacy", messages: [AgentMessage(id: "m1", role: .user, content: "legacykeyword")])
        try await service?.upsert(session: session)
        service = nil
        // Simulate the pre-optimization on-disk schema without dropping its FTS.
        try sql(url, "DROP TABLE session_search_fts_row_lookup")
        let reopened = try SessionSearchIndexService(databaseURL: url)
        #expect(try await reopened.search(query: "legacykeyword", limit: 10).map(\.id) == ["legacy"])
        var replacement = session
        replacement.messages[0].content = "replacementkeyword"
        try await reopened.upsert(session: replacement)
        #expect(try await reopened.search(query: "legacykeyword", limit: 10).isEmpty)
        #expect(try await reopened.search(query: "replacementkeyword", limit: 10).map(\.id) == ["legacy"])
        try await reopened.remove(sessionID: "legacy")
        #expect(try await reopened.search(query: "replacementkeyword", limit: 10).isEmpty)
        #expect(try scalar(url, "SELECT COUNT(*) FROM session_search_fts_row_lookup") == 0)
    }

    @Test func repairOnlyTouchesAffectedSessionsIncludingEmptyAndDeletedSources() async throws {
        let url = temporaryDatabaseURL()
        let service = try SessionSearchIndexService(databaseURL: url)
        let stable = AgentSession(id: "stable", title: "Stable", messages: [AgentMessage(id: "s", role: .user, content: "stablekeyword")])
        var changed = AgentSession(id: "changed", title: "Changed", messages: [AgentMessage(id: "c", role: .user, content: "oldkeyword")])
        let deleted = AgentSession(id: "deleted", title: "Deleted", messages: [AgentMessage(role: .user, content: "deletedkeyword")])
        _ = try await service.bootstrapIfEmpty(sessions: [stable, changed, deleted])
        let stableRowID = try scalar(url, "SELECT fts_rowid FROM session_search_fts_row_lookup WHERE document_id='stable'")
        changed.messages.append(AgentMessage(id: "c2", role: .assistant, content: "newkeyword"))
        let sourceIDs = ["stable": ["s"], "changed": ["c", "c2"], "empty": []]
        #expect(try await service.sessionsNeedingRepair(sourceSessionMessageIDs: sourceIDs) == ["changed", "empty"])
        let result = try await service.repair(sessions: [changed, AgentSession(id: "empty", title: "Empty")], sourceSessionIDs: Set(sourceIDs.keys))
        #expect(result == SessionSearchIndexSynchronizationResult(upsertedCount: 2, removedCount: 1, unchangedCount: 1))
        #expect(try await service.sessionsNeedingRepair(sourceSessionMessageIDs: sourceIDs).isEmpty)
        #expect(try scalar(url, "SELECT fts_rowid FROM session_search_fts_row_lookup WHERE document_id='stable'") == stableRowID)
        #expect(try await service.search(query: "newkeyword", limit: 10).map(\.id) == ["changed"])
        #expect(try await service.search(query: "deletedkeyword", limit: 10).isEmpty)
        // Removing a message must also invalidate that session's index.
        #expect(try await service.sessionsNeedingRepair(sourceSessionMessageIDs: ["changed": ["c"]]) == ["changed"])
    }

    @Test func repairDetectsSameMessageIDEditsAndTitleChangesThroughSourceMetadata() async throws {
        let service = try SessionSearchIndexService(databaseURL: temporaryDatabaseURL())
        var session = AgentSession(id: "edit", title: "Before", messages: [AgentMessage(id: "m", role: .user, content: "beforekeyword")], updatedAt: Date(timeIntervalSince1970: 100.123))
        try await service.upsert(session: session)
        var metadata = session
        metadata.messages = []
        metadata.updatedAt = Date(timeIntervalSince1970: 100)
        #expect(try await service.sessionsNeedingRepair(sourceSessionMessageIDs: ["edit": ["m"]], sourceMetadata: [metadata]).isEmpty)
        session.messages[0].content = "afterkeyword"
        session.updatedAt = Date(timeIntervalSince1970: 101)
        #expect(try await service.sessionsNeedingRepair(sourceSessionMessageIDs: ["edit": ["m"]], sourceMetadata: [session]) == ["edit"])
        session.updatedAt = metadata.updatedAt
        session.title = "After"
        #expect(try await service.sessionsNeedingRepair(sourceSessionMessageIDs: ["edit": ["m"]], sourceMetadata: [session]) == ["edit"])
    }

    @Test func nativeSnapshotSyncPreservesUnchangedRowsAndReconcilesAllChanges() async throws {
        let url = temporaryDatabaseURL()
        var backend: SQLiteNativeSourceSearchBackend? = try SQLiteNativeSourceSearchBackend(databaseURL: url)
        let stable = document("stable", body: "stablekeyword")
        let removed = document("removed", body: "removedkeyword")
        let other = NativeSearchDocument(id: "other", sourceKind: .mail, externalID: "other", title: "otherkeyword", summary: "", contentHash: "other")
        try await backend?.upsert([stable, removed, other])
        backend = nil
        try sql(url, "DROP TABLE native_search_fts_row_lookup")
        let reopened = try SQLiteNativeSourceSearchBackend(databaseURL: url)
        let originalRow = try scalar(url, "SELECT fts_rowid FROM native_search_fts_row_lookup WHERE document_id='stable'")
        // A new indexedAt and subsecond dates must not cause retokenization.
        var repeated = stable
        repeated.temporal.indexedAt = Date(timeIntervalSince1970: 999)
        let protocolBackend: any NativeSourceSearchBackend = reopened
        try await protocolBackend.synchronizeSource(kind: .browserHistory, sourceInstanceID: nil, documents: [repeated, document("new", body: "newkeyword")])
        #expect(try scalar(url, "SELECT fts_rowid FROM native_search_fts_row_lookup WHERE document_id='stable'") == originalRow)
        #expect(try await reopened.search(NativeSearchQuery(text: "removedkeyword")).isEmpty)
        #expect(try await reopened.search(NativeSearchQuery(text: "newkeyword")).map(\.id) == ["new"])
        #expect(try await reopened.search(NativeSearchQuery(text: "otherkeyword")).map(\.id) == ["other"])
        var edited = repeated
        edited.body = "editedkeyword"
        // Deliberately retain contentHash: correctness cannot rely on hash alone.
        try await reopened.synchronizeSource(kind: .browserHistory, documents: [edited])
        #expect(try await reopened.search(NativeSearchQuery(text: "stablekeyword")).isEmpty)
        #expect(try await reopened.search(NativeSearchQuery(text: "editedkeyword")).map(\.id) == ["stable"])
        try await reopened.synchronizeSource(kind: .browserHistory, documents: [])
        #expect(try await reopened.search(NativeSearchQuery(text: "editedkeyword")).isEmpty)
        #expect(try await reopened.search(NativeSearchQuery(text: "otherkeyword")).count == 1)
    }

    @Test func synchronizationPreservesStoredSubsecondTimeChangesWithTheSameHash() async throws {
        let url = temporaryDatabaseURL()
        let backend = try SQLiteNativeSourceSearchBackend(databaseURL: url)
        var entry = document("time", body: "timekeyword")
        try await backend.upsert([entry])
        #expect(try scalar(url, "SELECT COUNT(*) FROM native_search_docs WHERE primary_time > 100.5") == 0)
        entry.temporal.primaryTime = Date(timeIntervalSince1970: 100.789)
        try await backend.synchronizeSource(kind: .browserHistory, documents: [entry])
        // Check the SQL candidate-filter column directly: JSON dates have always
        // used whole ISO8601 seconds, while this column must retain subseconds.
        #expect(try scalar(url, "SELECT COUNT(*) FROM native_search_docs WHERE primary_time > 100.5") == 1)
        #expect(try await backend.search(NativeSearchQuery(text: "timekeyword")).map(\.id) == ["time"])
    }

    @Test func failedRepairRollsBackFTSLookupAndSourceDocumentsTogether() async throws {
        let url = temporaryDatabaseURL()
        let service = try SessionSearchIndexService(databaseURL: url)
        var original = AgentSession(id: "original", title: "originalkeyword")
        try await service.upsert(session: original)
        try sql(url, "CREATE TRIGGER reject_blocked BEFORE INSERT ON session_search_docs WHEN NEW.session_id='blocked' BEGIN SELECT RAISE(ABORT, 'injected failure'); END")
        do {
            _ = try await service.repair(sessions: [AgentSession(id: "blocked", title: "blockedkeyword")], sourceSessionIDs: ["blocked"])
            Issue.record("Expected injected database failure")
        } catch {}
        #expect(try await service.search(query: "originalkeyword", limit: 10).map(\.id) == ["original"])
        #expect(try scalar(url, "SELECT COUNT(*) FROM session_search_fts_row_lookup") == 1)
        original.title = "updatedkeyword"
        try await service.upsert(session: original)
        #expect(try await service.search(query: "originalkeyword", limit: 10).isEmpty)
        #expect(try await service.search(query: "updatedkeyword", limit: 10).map(\.id) == ["original"])
    }

    @Test func batchedCJKIndexTermsExactlyMatchIndependentNormalization() {
        let runs = ["雅加达豪华酒店", "康纳同学", "雅加达豪华酒店", "的", "研究生命起源", "西雅图不相信眼泪", "𠀀中文", "康纳同学"]
        var seen: Set<String> = []
        let reference = runs.flatMap { NativeSearchQueryNormalizer.normalize($0).tokens.map(\.value) }.filter { seen.insert($0).inserted }
        #expect(NativeSearchQueryNormalizer.indexTermValues(cjkRuns: runs) == reference)
    }

    @Test func cancelledRepairDoesNotChangeSearchCoverage() async throws {
        let service = try SessionSearchIndexService(databaseURL: temporaryDatabaseURL())
        let original = AgentSession(id: "original", title: "originalkeyword")
        try await service.upsert(session: original)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.repair(sessions: [], sourceSessionIDs: [])
        }
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch is CancellationError {}
        #expect(try await service.search(query: "originalkeyword", limit: 10).map(\.id) == ["original"])
    }

    private func document(_ id: String, body: String) -> NativeSearchDocument {
        NativeSearchDocument(id: id, sourceKind: .browserHistory, sourceInstanceID: "session", externalID: id, title: "History", summary: "", body: body,
            temporal: NativeSearchTemporalMetadata(primaryTime: Date(timeIntervalSince1970: 100.123), primaryTimeKind: .updatedAt, indexedAt: Date(timeIntervalSince1970: 200)), contentHash: id)
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("search-energy-\(UUID().uuidString)").appendingPathComponent("search.sqlite")
    }

    private func sql(_ url: URL, _ query: String) throws {
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, query, nil, nil, nil) == SQLITE_OK)
    }

    private func scalar(_ url: URL, _ query: String) throws -> Int64 {
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        return sqlite3_column_int64(statement, 0)
    }
}
