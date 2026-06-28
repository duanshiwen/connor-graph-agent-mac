import Testing
import Foundation
@testable import ConnorGraphSearch

@Suite("Memory OS Search Kernel FFI Tests")
struct MemoryOSSearchKernelFFITests {
    @Test func swiftCallsRustKernelThroughCABI() throws {
        let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let libraryURL = MemoryOSSearchKernel.defaultReleaseLibraryURL(repositoryRoot: repositoryRoot)
        #expect(FileManager.default.fileExists(atPath: libraryURL.path))

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let db = temp.appendingPathComponent("memory-os.sqlite")
        try makeSQLiteFixture(at: db)
        let kernel = try MemoryOSSearchKernel(libraryURL: libraryURL, indexDirectory: temp.appendingPathComponent("index", isDirectory: true))
        let count = try kernel.rebuildFromSQLite(databaseURL: db)
        #expect(count == 6)

        let response = try kernel.search(.init(query: "中国", layers: [.l4], limit: 5))
        #expect(response.backend == "tantivy-embedded")
        #expect(response.hits.contains { $0.recordID == "wikidata:Q148" })
    }
}

private func makeSQLiteFixture(at url: URL) throws {
    let sql = """
    CREATE TABLE memory_l0_provenance_objects (id TEXT PRIMARY KEY, source_type TEXT NOT NULL, source_id TEXT, title TEXT NOT NULL, content TEXT NOT NULL, content_hash TEXT NOT NULL, occurred_at TEXT NOT NULL, ingested_at TEXT NOT NULL, session_id TEXT, work_object_id TEXT, confidentiality TEXT NOT NULL, status TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE TABLE memory_l1_capture_events (id TEXT PRIMARY KEY, provenance_object_id TEXT NOT NULL, event_type TEXT NOT NULL, occurred_at TEXT NOT NULL, token_estimate INTEGER NOT NULL DEFAULT 0, processing_state TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE TABLE memory_l2_statements (id TEXT PRIMARY KEY, subject_id TEXT NOT NULL, predicate TEXT NOT NULL, object_id TEXT, text TEXT NOT NULL, assertion_kind TEXT NOT NULL, confidence REAL NOT NULL, valid_at TEXT NOT NULL, committed_at TEXT NOT NULL, evidence_span_ids_json TEXT NOT NULL DEFAULT '[]', source_artifact_id TEXT, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE TABLE memory_l3_beliefs (id TEXT PRIMARY KEY, statement TEXT NOT NULL, domain TEXT NOT NULL DEFAULT 'general-knowledge', related_object_names TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
    CREATE TABLE memory_l4_entities (id TEXT PRIMARY KEY, stable_key TEXT NOT NULL UNIQUE, entity_type TEXT NOT NULL, name TEXT NOT NULL, aliases_json TEXT NOT NULL DEFAULT '[]', summary TEXT NOT NULL DEFAULT '', confidence REAL NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, valid_from TEXT, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE TABLE memory_l4_entity_aliases (id TEXT PRIMARY KEY, entity_id TEXT NOT NULL, alias TEXT NOT NULL, normalized_alias TEXT NOT NULL, created_at TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE TABLE memory_l4_entity_statements (id TEXT PRIMARY KEY, entity_id TEXT NOT NULL, predicate TEXT NOT NULL, object_entity_id TEXT, text TEXT NOT NULL, assertion_kind TEXT NOT NULL, confidence REAL NOT NULL, valid_at TEXT NOT NULL, committed_at TEXT NOT NULL, evidence_span_ids_json TEXT NOT NULL DEFAULT '[]', source_artifact_id TEXT, metadata_json TEXT NOT NULL DEFAULT '{}');
    INSERT INTO memory_l0_provenance_objects VALUES ('p1','chat',NULL,'标题','内容','h','2026-06-24','2026-06-24',NULL,NULL,'personal','active','{}');
    INSERT INTO memory_l1_capture_events VALUES ('c1','p1','message','2026-06-24',1,'pending','{}');
    INSERT INTO memory_l2_statements VALUES ('s1','subj','likes',NULL,'用户喜欢图谱','fact',0.9,'2026-06-24','2026-06-24','[]',NULL,'{}');
    INSERT INTO memory_l3_beliefs VALUES ('b1','图谱检索应当 graph-first','knowledge-management','Knowledge graph','2026-06-24','2026-06-24');
    INSERT INTO memory_l4_entities VALUES ('wikidata:Q148','wikidata:Q148','country','中华人民共和国','["中国"]','东亚国家',0.9,'2026-06-24','2026-06-24',NULL,'{}');
    INSERT INTO memory_l4_entity_aliases VALUES ('a1','wikidata:Q148','China','china','2026-06-24','{}');
    INSERT INTO memory_l4_entity_statements VALUES ('st1','wikidata:Q148','INSTANCE_OF','wikidata:Q6256','中国 instance of 国家','fact',0.9,'2026-06-24','2026-06-24','[]',NULL,'{}');
    """
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = [url.path]
    let input = Pipe()
    process.standardInput = input
    try process.run()
    input.fileHandleForWriting.write(Data(sql.utf8))
    try input.fileHandleForWriting.close()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
}
