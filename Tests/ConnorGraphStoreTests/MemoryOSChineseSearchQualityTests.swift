import Testing
import Foundation
@testable import ConnorGraphStore

@Suite("Memory OS Chinese Search Quality Tests")
struct MemoryOSChineseSearchQualityTests {
    @Test func chineseNaturalLanguageCountryQueriesNormalizeToCoreTerm() throws {
        let store = try makeStore()
        try seedCountryGraph(store)
        let service = SQLiteMemoryOSUnifiedRetrievalService(store: store)

        let countryHits = try service.search(MemoryOSRetrievalQuery(text: "国家", layers: [.l4], limit: 10))
        #expect(countryHits.contains { $0.recordID == "wikidata:Q6256" })

        let allCountryHits = try service.search(MemoryOSRetrievalQuery(text: "所有国家", layers: [.l4], limit: 10))
        #expect(!allCountryHits.isEmpty)
        #expect(allCountryHits.contains { $0.recordID == "wikidata:Q6256" || $0.recordID == "wikidata:Q148" })

        let whichCountryHits = try service.search(MemoryOSRetrievalQuery(text: "有哪些国家", layers: [.l4], limit: 10))
        #expect(!whichCountryHits.isEmpty)
        #expect(whichCountryHits.contains { $0.recordID == "wikidata:Q6256" || $0.recordID == "wikidata:Q148" })
    }

    @Test func chineseAliasQueryFindsChinaEntity() throws {
        let store = try makeStore()
        try seedCountryGraph(store)
        let service = SQLiteMemoryOSUnifiedRetrievalService(store: store)

        let simplified = try service.search(MemoryOSRetrievalQuery(text: "中国", layers: [.l4], limit: 5))
        #expect(simplified.contains { $0.recordID == "wikidata:Q148" })

        let traditional = try service.search(MemoryOSRetrievalQuery(text: "中國", layers: [.l4], limit: 5))
        #expect(traditional.contains { $0.recordID == "wikidata:Q148" })
    }

    @Test func l4InstancesReturnsGraphStructuredCountryMembership() throws {
        let store = try makeStore()
        try seedCountryGraph(store)
        let subgraph = try SQLiteMemoryOSGraphRetrievalService(store: store).l4Instances(MemoryOSL4InstanceQuery(classEntityIDs: ["wikidata:Q6256"], predicates: ["P31"], limit: 10))

        #expect(subgraph.nodes.contains { $0.id == "wikidata:Q6256" && $0.metadata["role"] == "class" })
        #expect(subgraph.nodes.contains { $0.id == "wikidata:Q148" && $0.metadata["role"] == "instance" })
        #expect(subgraph.edges.contains { $0.sourceID == "wikidata:Q148" && $0.targetID == "wikidata:Q6256" && $0.predicate == "P31" })
    }

    private func makeStore() throws -> SQLiteMemoryOSStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("memory-os-search-quality-\(UUID().uuidString).sqlite")
        let store = try SQLiteMemoryOSStore(path: url.path)
        try store.migrate()
        return store
    }

    private func seedCountryGraph(_ store: SQLiteMemoryOSStore) throws {
        try store.execute("""
        INSERT OR REPLACE INTO memory_l4_entities
        (id, stable_key, entity_type, name, aliases_json, summary, confidence, created_at, updated_at, valid_from, metadata_json)
        VALUES
        ('wikidata:Q6256', 'wikidata:Q6256', 'class', '地理、地域意义上的国家、地区', '["国家", "country"]', '国家和地区 class', 0.9, '2026-06-24T00:00:00Z', '2026-06-24T00:00:00Z', '2026-06-24T00:00:00Z', '{}'),
        ('wikidata:Q3624078', 'wikidata:Q3624078', 'class', '主權國家', '["主权国家", "sovereign state"]', '主权国家 class', 0.9, '2026-06-24T00:00:00Z', '2026-06-24T00:00:00Z', '2026-06-24T00:00:00Z', '{}'),
        ('wikidata:Q148', 'wikidata:Q148', 'country', '中华人民共和国', '["中国", "中國", "China", "PRC"]', '东亚国家', 0.9, '2026-06-24T00:00:00Z', '2026-06-24T00:00:00Z', '2026-06-24T00:00:00Z', '{}');
        """)
        try store.execute("""
        INSERT OR REPLACE INTO memory_l4_entity_aliases
        (id, entity_id, alias, normalized_alias, created_at, metadata_json)
        VALUES
        ('alias-q6256-country-zh', 'wikidata:Q6256', '国家', '国家', '2026-06-24T00:00:00Z', '{}'),
        ('alias-q148-cn', 'wikidata:Q148', '中国', '中国', '2026-06-24T00:00:00Z', '{}'),
        ('alias-q148-tw', 'wikidata:Q148', '中國', '中國', '2026-06-24T00:00:00Z', '{}'),
        ('alias-q148-en', 'wikidata:Q148', 'China', 'china', '2026-06-24T00:00:00Z', '{}');
        """)
        try store.execute("""
        INSERT OR REPLACE INTO memory_l4_entity_statements
        (id, entity_id, predicate, object_entity_id, text, assertion_kind, confidence, valid_at, committed_at, evidence_span_ids_json, source_artifact_id, metadata_json)
        VALUES
        ('stmt-q148-instance-country', 'wikidata:Q148', 'P31', 'wikidata:Q6256', '中华人民共和国 -- 隶属于 --> 地理、地域意义上的国家、地区', 'fact', 0.9, '2026-06-24T00:00:00Z', '2026-06-24T00:00:00Z', '[]', NULL, '{}');
        """)
        try store.execute("""
        INSERT INTO memory_l4_entities_fts(entity_id, entity_type, name, aliases, summary)
        VALUES
        ('wikidata:Q6256', 'class', '地理、地域意义上的国家、地区', '国家 country', '国家和地区 class'),
        ('wikidata:Q3624078', 'class', '主權國家', '主权国家 sovereign state', '主权国家 class'),
        ('wikidata:Q148', 'country', '中华人民共和国', '中国 中國 China PRC', '东亚国家');
        """)
        try store.execute("""
        INSERT INTO memory_l4_statements_fts(statement_id, predicate, text)
        VALUES ('stmt-q148-instance-country', 'P31', '中华人民共和国 -- 隶属于 --> 地理、地域意义上的国家、地区');
        """)
    }
}
