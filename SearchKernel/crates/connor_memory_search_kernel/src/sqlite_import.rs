use std::path::Path;

use rusqlite::Connection;

use crate::document::{MemorySearchDocument, SearchLayer, SearchRecordKind};
use crate::error::{KernelError, KernelResult};

pub fn load_documents_from_sqlite(database_path: &Path, limit_per_layer: Option<usize>) -> KernelResult<Vec<MemorySearchDocument>> {
    let connection = Connection::open(database_path).map_err(|err| KernelError::new(err.to_string()))?;
    let mut documents = Vec::new();
    documents.extend(load_l0(&connection, limit_per_layer)?);
    documents.extend(load_l1(&connection, limit_per_layer)?);
    documents.extend(load_l2(&connection, limit_per_layer)?);
    documents.extend(load_l3(&connection, limit_per_layer)?);
    documents.extend(load_l4_entities(&connection, limit_per_layer)?);
    documents.extend(load_l4_statements(&connection, limit_per_layer)?);
    Ok(documents)
}

fn suffix(limit: Option<usize>) -> String {
    limit.map(|value| format!(" LIMIT {}", value)).unwrap_or_default()
}

fn load_l0(connection: &Connection, limit: Option<usize>) -> KernelResult<Vec<MemorySearchDocument>> {
    let sql = format!("SELECT id, source_type, title, content, occurred_at, ingested_at, metadata_json FROM memory_l0_provenance_objects ORDER BY occurred_at DESC{}", suffix(limit));
    query_documents(connection, &sql, |row| {
        let id: String = row.get(0)?;
        let source_type: String = row.get(1)?;
        let title: String = row.get(2)?;
        let content: String = row.get(3)?;
        let occurred_at: String = row.get(4)?;
        let ingested_at: String = row.get(5)?;
        let metadata_json: String = row.get(6)?;
        Ok(MemorySearchDocument {
            id: format!("L0:{}", id),
            layer: SearchLayer::L0,
            record_id: id,
            record_kind: SearchRecordKind::ProvenanceObject,
            title,
            aliases: vec![],
            summary: content.chars().take(240).collect(),
            body: content,
            keywords: vec![source_type],
            ids: vec![],
            created_at: Some(ingested_at),
            updated_at: Some(occurred_at),
            metadata_json,
        })
    })
}

fn load_l1(connection: &Connection, limit: Option<usize>) -> KernelResult<Vec<MemorySearchDocument>> {
    let sql = format!("SELECT c.id, c.event_type, c.occurred_at, c.metadata_json, o.title, o.content, o.id FROM memory_l1_capture_events c JOIN memory_l0_provenance_objects o ON o.id = c.provenance_object_id ORDER BY c.occurred_at DESC{}", suffix(limit));
    query_documents(connection, &sql, |row| {
        let id: String = row.get(0)?;
        let event_type: String = row.get(1)?;
        let occurred_at: String = row.get(2)?;
        let metadata_json: String = row.get(3)?;
        let title: String = row.get(4)?;
        let content: String = row.get(5)?;
        let provenance_id: String = row.get(6)?;
        Ok(MemorySearchDocument {
            id: format!("L1:{}", id),
            layer: SearchLayer::L1,
            record_id: id,
            record_kind: SearchRecordKind::CaptureEvent,
            title: event_type.clone(),
            aliases: vec![title],
            summary: content.chars().take(240).collect(),
            body: content,
            keywords: vec![event_type],
            ids: vec![provenance_id],
            created_at: Some(occurred_at.clone()),
            updated_at: Some(occurred_at),
            metadata_json,
        })
    })
}

fn load_l2(connection: &Connection, limit: Option<usize>) -> KernelResult<Vec<MemorySearchDocument>> {
    let sql = format!("SELECT id, subject_id, predicate, object_id, text, assertion_kind, committed_at, metadata_json FROM memory_l2_statements ORDER BY committed_at DESC{}", suffix(limit));
    query_documents(connection, &sql, |row| {
        let id: String = row.get(0)?;
        let subject_id: String = row.get(1)?;
        let predicate: String = row.get(2)?;
        let object_id: Option<String> = row.get(3)?;
        let text: String = row.get(4)?;
        let assertion_kind: String = row.get(5)?;
        let committed_at: String = row.get(6)?;
        let metadata_json: String = row.get(7)?;
        let mut ids = vec![subject_id];
        if let Some(object_id) = object_id { ids.push(object_id); }
        Ok(MemorySearchDocument {
            id: format!("L2:{}", id),
            layer: SearchLayer::L2,
            record_id: id,
            record_kind: SearchRecordKind::Statement,
            title: predicate.clone(),
            aliases: vec![],
            summary: text.clone(),
            body: text,
            keywords: vec![predicate, assertion_kind],
            ids,
            created_at: Some(committed_at.clone()),
            updated_at: Some(committed_at),
            metadata_json,
        })
    })
}

fn load_l3(connection: &Connection, limit: Option<usize>) -> KernelResult<Vec<MemorySearchDocument>> {
    let sql = format!("SELECT id, statement, domain, related_object_names, created_at, updated_at FROM memory_l3_beliefs ORDER BY updated_at DESC{}", suffix(limit));
    query_documents(connection, &sql, |row| {
        let id: String = row.get(0)?;
        let statement: String = row.get(1)?;
        let domain: String = row.get(2)?;
        let related_object_names: String = row.get(3)?;
        let created_at: String = row.get(4)?;
        let updated_at: String = row.get(5)?;
        let metadata_json = serde_json::json!({
            "domain": domain,
            "related_object_names": related_object_names,
            "created_at": created_at,
            "updated_at": updated_at
        }).to_string();
        Ok(MemorySearchDocument {
            id: format!("L3:{}", id),
            layer: SearchLayer::L3,
            record_id: id,
            record_kind: SearchRecordKind::Belief,
            title: statement.chars().take(80).collect(),
            aliases: vec![],
            summary: statement.clone(),
            body: statement,
            keywords: vec![],
            ids: vec![],
            created_at: Some(created_at),
            updated_at: Some(updated_at),
            metadata_json,
        })
    })
}

fn load_l4_entities(connection: &Connection, limit: Option<usize>) -> KernelResult<Vec<MemorySearchDocument>> {
    let sql = format!("SELECT e.id, e.stable_key, e.entity_type, e.name, e.aliases_json, e.summary, e.created_at, e.updated_at, e.metadata_json, COALESCE(group_concat(a.alias, ' '), '') FROM memory_l4_entities e LEFT JOIN memory_l4_entity_aliases a ON a.entity_id = e.id GROUP BY e.id ORDER BY e.updated_at DESC{}", suffix(limit));
    query_documents(connection, &sql, |row| {
        let id: String = row.get(0)?;
        let stable_key: String = row.get(1)?;
        let entity_type: String = row.get(2)?;
        let name: String = row.get(3)?;
        let aliases_json: String = row.get(4)?;
        let summary: String = row.get(5)?;
        let created_at: String = row.get(6)?;
        let updated_at: String = row.get(7)?;
        let metadata_json: String = row.get(8)?;
        let alias_blob: String = row.get(9)?;
        let mut aliases = serde_json::from_str::<Vec<String>>(&aliases_json).unwrap_or_default();
        aliases.extend(alias_blob.split_whitespace().map(ToOwned::to_owned));
        aliases.sort();
        aliases.dedup();
        Ok(MemorySearchDocument {
            id: format!("L4:{}", id),
            layer: SearchLayer::L4,
            record_id: id.clone(),
            record_kind: SearchRecordKind::Entity,
            title: name,
            aliases,
            summary: summary.clone(),
            body: summary,
            keywords: vec![entity_type],
            ids: vec![id, stable_key],
            created_at: Some(created_at),
            updated_at: Some(updated_at),
            metadata_json,
        })
    })
}

fn load_l4_statements(connection: &Connection, limit: Option<usize>) -> KernelResult<Vec<MemorySearchDocument>> {
    let sql = format!("SELECT id, entity_id, predicate, object_entity_id, text, assertion_kind, committed_at, metadata_json FROM memory_l4_entity_statements ORDER BY committed_at DESC{}", suffix(limit));
    query_documents(connection, &sql, |row| {
        let id: String = row.get(0)?;
        let entity_id: String = row.get(1)?;
        let predicate: String = row.get(2)?;
        let object_entity_id: Option<String> = row.get(3)?;
        let text: String = row.get(4)?;
        let assertion_kind: String = row.get(5)?;
        let committed_at: String = row.get(6)?;
        let metadata_json: String = row.get(7)?;
        let mut ids = vec![entity_id];
        if let Some(object_entity_id) = object_entity_id { ids.push(object_entity_id); }
        Ok(MemorySearchDocument {
            id: format!("L4S:{}", id),
            layer: SearchLayer::L4,
            record_id: id,
            record_kind: SearchRecordKind::EntityStatement,
            title: predicate.clone(),
            aliases: vec![],
            summary: text.clone(),
            body: text,
            keywords: vec![predicate, assertion_kind],
            ids,
            created_at: Some(committed_at.clone()),
            updated_at: Some(committed_at),
            metadata_json,
        })
    })
}

fn query_documents<F>(connection: &Connection, sql: &str, mut map: F) -> KernelResult<Vec<MemorySearchDocument>>
where
    F: FnMut(&rusqlite::Row<'_>) -> rusqlite::Result<MemorySearchDocument>,
{
    let mut statement = connection.prepare(sql).map_err(|err| KernelError::new(format!("prepare failed: {} | {}", err, sql)))?;
    let rows = statement.query_map([], |row| map(row)).map_err(|err| KernelError::new(err.to_string()))?;
    let mut documents = Vec::new();
    for row in rows {
        documents.push(row.map_err(|err| KernelError::new(err.to_string()))?);
    }
    Ok(documents)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn loads_l0_to_l4_documents_from_sqlite() {
        let dir = tempdir().expect("tempdir");
        let db = dir.path().join("memory-os.sqlite");
        let connection = Connection::open(&db).expect("open sqlite");
        connection.execute_batch(r#"
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
            INSERT INTO memory_l4_entity_statements VALUES ('st1','wikidata:Q148','P31','wikidata:Q6256','中国 instance of 国家','fact',0.9,'2026-06-24','2026-06-24','[]',NULL,'{}');
        "#).expect("schema");
        let documents = load_documents_from_sqlite(&db, None).expect("load documents");
        assert_eq!(documents.len(), 6);
        assert!(documents.iter().any(|doc| doc.record_id == "wikidata:Q148" && doc.aliases.contains(&"China".to_string())));
    }
}
