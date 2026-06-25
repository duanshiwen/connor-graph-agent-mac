import Foundation
import Testing
@testable import ConnorGraphSearch

@Suite("Memory OS Search Quality Golden Tests")
struct MemoryOSSearchQualityGoldenTests {
    @Test func l4EntityGoldenQueriesReturnExpectedRecords() throws {
        let kernel = try makeGoldenKernel()
        let cases: [(query: String, expected: String, topN: Int)] = [
            ("中国", "wikidata:Q148", 1),
            ("中华人民共和国", "wikidata:Q148", 1),
            ("中國", "wikidata:Q148", 1),
            ("China", "wikidata:Q148", 1),
            ("PRC", "wikidata:Q148", 1),
            ("Q148", "wikidata:Q148", 1),
            ("法国", "wikidata:Q142", 1),
            ("日本", "wikidata:Q17", 1),
            ("国家", "wikidata:Q7275", 3),
            ("有哪些国家", "wikidata:Q7275", 3),
            ("P31", "wikidata:P31", 1),
            ("P17", "wikidata:P17", 1)
        ]
        for item in cases {
            let response = try kernel.search(.init(query: item.query, layers: [.l4], limit: 10))
            let top = response.hits.prefix(item.topN).map(\.recordID)
            #expect(top.contains(item.expected), "Expected \(item.expected) in top \(item.topN) for query \(item.query), got \(top)")
        }
        let explanationResponse = try kernel.search(.init(query: "中国", layers: [.l4], limit: 1))
        let explanation = try #require(explanationResponse.hits.first)
        #expect(explanation.rankReason.contains("matched_fields="))
        #expect(explanation.rankReason.contains("aliases"))
        #expect(explanation.rankReason.contains("boosts="))
        #expect(explanation.matchedChannel.contains("tantivy"))
    }
}

private func makeGoldenKernel() throws -> MemoryOSSearchKernel {
    let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let libraryURL = MemoryOSSearchKernel.defaultReleaseLibraryURL(repositoryRoot: repositoryRoot)
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("memory-os-search-golden-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    let db = temp.appendingPathComponent("memory-os.sqlite")
    try makeGoldenSQLiteFixture(at: db)
    let kernel = try MemoryOSSearchKernel(libraryURL: libraryURL, indexDirectory: temp.appendingPathComponent("index", isDirectory: true))
    #expect(try kernel.rebuildFromSQLite(databaseURL: db) >= 9)
    return kernel
}

private func makeGoldenSQLiteFixture(at url: URL) throws {
    let sql = """
    CREATE TABLE memory_l0_provenance_objects (id TEXT PRIMARY KEY, source_type TEXT NOT NULL, source_id TEXT, title TEXT NOT NULL, content TEXT NOT NULL, content_hash TEXT NOT NULL, occurred_at TEXT NOT NULL, ingested_at TEXT NOT NULL, session_id TEXT, work_object_id TEXT, confidentiality TEXT NOT NULL, status TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE TABLE memory_l1_capture_events (id TEXT PRIMARY KEY, provenance_object_id TEXT NOT NULL, event_type TEXT NOT NULL, occurred_at TEXT NOT NULL, token_estimate INTEGER NOT NULL DEFAULT 0, processing_state TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE TABLE memory_l2_statements (id TEXT PRIMARY KEY, subject_id TEXT NOT NULL, predicate TEXT NOT NULL, object_id TEXT, text TEXT NOT NULL, assertion_kind TEXT NOT NULL, confidence REAL NOT NULL, valid_at TEXT NOT NULL, committed_at TEXT NOT NULL, evidence_span_ids_json TEXT NOT NULL DEFAULT '[]', source_artifact_id TEXT, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE TABLE memory_l3_beliefs (id TEXT PRIMARY KEY, topic TEXT NOT NULL, statement TEXT NOT NULL, projection_kind TEXT NOT NULL, confidence REAL NOT NULL, evidence_statement_ids_json TEXT NOT NULL DEFAULT '[]', valid_at TEXT NOT NULL, projected_at TEXT NOT NULL, source_artifact_id TEXT, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE TABLE memory_l4_entities (id TEXT PRIMARY KEY, stable_key TEXT NOT NULL UNIQUE, entity_type TEXT NOT NULL, name TEXT NOT NULL, aliases_json TEXT NOT NULL DEFAULT '[]', summary TEXT NOT NULL DEFAULT '', confidence REAL NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, valid_from TEXT, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE TABLE memory_l4_entity_aliases (id TEXT PRIMARY KEY, entity_id TEXT NOT NULL, alias TEXT NOT NULL, normalized_alias TEXT NOT NULL, created_at TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}');
    CREATE TABLE memory_l4_entity_statements (id TEXT PRIMARY KEY, entity_id TEXT NOT NULL, predicate TEXT NOT NULL, object_entity_id TEXT, text TEXT NOT NULL, assertion_kind TEXT NOT NULL, confidence REAL NOT NULL, valid_at TEXT NOT NULL, committed_at TEXT NOT NULL, evidence_span_ids_json TEXT NOT NULL DEFAULT '[]', source_artifact_id TEXT, metadata_json TEXT NOT NULL DEFAULT '{}');
    INSERT INTO memory_l0_provenance_objects VALUES ('p1','chat',NULL,'标题','中国 法国 日本 国家 P31 P17','h','2026-06-24','2026-06-24',NULL,NULL,'personal','active','{}');
    INSERT INTO memory_l1_capture_events VALUES ('c1','p1','message','2026-06-24',1,'pending','{}');
    INSERT INTO memory_l2_statements VALUES ('s1','subj','mentions',NULL,'中国 法国 日本 都是国家','fact',0.9,'2026-06-24','2026-06-24','[]',NULL,'{}');
    INSERT INTO memory_l3_beliefs VALUES ('b1','国家','国家查询应优先解析类实体','knowledge',0.9,'[]','2026-06-24','2026-06-24',NULL,'{}');
    INSERT INTO memory_l4_entities VALUES ('wikidata:Q148','wikidata:Q148','country','中华人民共和国','["中国","中國","China","PRC","Q148"]','东亚国家',0.9,'2026-06-24','2026-06-24',NULL,'{}');
    INSERT INTO memory_l4_entities VALUES ('wikidata:Q142','wikidata:Q142','country','法國','["法国","France","Q142"]','欧洲国家',0.9,'2026-06-24','2026-06-24',NULL,'{}');
    INSERT INTO memory_l4_entities VALUES ('wikidata:Q17','wikidata:Q17','country','日本','["Japan","Q17"]','东亚国家',0.9,'2026-06-24','2026-06-24',NULL,'{}');
    INSERT INTO memory_l4_entities VALUES ('wikidata:Q7275','wikidata:Q7275','class','国家','["國家","country","有哪些国家"]','共同体',0.9,'2026-06-24','2026-06-24',NULL,'{}');
    INSERT INTO memory_l4_entities VALUES ('wikidata:P31','wikidata:P31','property','隶属于','["instance of","P31"]','实体所属类别',0.9,'2026-06-24','2026-06-24',NULL,'{}');
    INSERT INTO memory_l4_entities VALUES ('wikidata:P17','wikidata:P17','property','国家','["country","P17"]','此项目所在国家',0.9,'2026-06-24','2026-06-24',NULL,'{}');
    INSERT INTO memory_l4_entity_aliases VALUES ('a1','wikidata:Q148','中国','中国','2026-06-24','{}');
    INSERT INTO memory_l4_entity_aliases VALUES ('a2','wikidata:Q148','中國','中國','2026-06-24','{}');
    INSERT INTO memory_l4_entity_aliases VALUES ('a3','wikidata:Q142','法国','法国','2026-06-24','{}');
    INSERT INTO memory_l4_entity_aliases VALUES ('a4','wikidata:Q17','日本','日本','2026-06-24','{}');
    INSERT INTO memory_l4_entity_aliases VALUES ('a5','wikidata:Q7275','国家','国家','2026-06-24','{}');
    INSERT INTO memory_l4_entity_aliases VALUES ('a6','wikidata:P31','P31','p31','2026-06-24','{}');
    INSERT INTO memory_l4_entity_aliases VALUES ('a7','wikidata:P17','P17','p17','2026-06-24','{}');
    INSERT INTO memory_l4_entity_statements VALUES ('st1','wikidata:Q148','P31','wikidata:Q7275','中国 instance of 国家','fact',0.9,'2026-06-24','2026-06-24','[]',NULL,'{}');
    INSERT INTO memory_l4_entity_statements VALUES ('st2','wikidata:Q142','P31','wikidata:Q7275','法国 instance of 国家','fact',0.9,'2026-06-24','2026-06-24','[]',NULL,'{}');
    INSERT INTO memory_l4_entity_statements VALUES ('st3','wikidata:Q17','P31','wikidata:Q7275','日本 instance of 国家','fact',0.9,'2026-06-24','2026-06-24','[]',NULL,'{}');
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
