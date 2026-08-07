pub mod document;
pub mod error;
pub mod ffi;
pub mod indexer;
pub mod query;
pub mod schema;
pub mod sqlite_import;
pub mod tokenizer;

pub use document::{MemorySearchDocument, SearchLayer, SearchRecordKind};
pub use error::{KernelError, KernelResult};
pub use query::{MemorySearchHit, MemorySearchRequest, MemorySearchResponse};

use std::collections::HashSet;
use std::path::PathBuf;

use rusqlite::Connection;
use tantivy::collector::TopDocs;
use tantivy::query::{BooleanQuery, Occur, Query, QueryParser, TermQuery};
use tantivy::schema::{IndexRecordOption, Value};
use tantivy::{DocAddress, Index, TantivyDocument, Term};

use crate::indexer::MemorySearchIndexer;
use crate::schema::{memory_search_fields, memory_search_schema, FIELD_EXACT_RAW};
use crate::sqlite_import::{load_document_by_id, load_documents_from_sqlite};
use crate::tokenizer::query_terms;

#[derive(Debug)]
pub struct ConnorMemorySearchKernel {
    index_dir: PathBuf,
}

#[derive(Debug, Default, PartialEq, Eq)]
pub struct DrainQueueResult {
    pub upserted: usize,
    pub deleted: usize,
    pub failed: usize,
    pub remaining: usize,
}

impl ConnorMemorySearchKernel {
    pub fn open(index_dir: impl Into<PathBuf>) -> KernelResult<Self> {
        let index_dir = index_dir.into();
        std::fs::create_dir_all(&index_dir).map_err(|err| KernelError::new(err.to_string()))?;
        let schema = memory_search_schema();
        let _index = match Index::open_in_dir(&index_dir) {
            Ok(index) if index.schema().get_field(FIELD_EXACT_RAW).is_ok() => index,
            Ok(_) => {
                std::fs::remove_dir_all(&index_dir).map_err(|err| KernelError::new(err.to_string()))?;
                std::fs::create_dir_all(&index_dir).map_err(|err| KernelError::new(err.to_string()))?;
                Index::create_in_dir(&index_dir, schema).map_err(|err| KernelError::new(err.to_string()))?
            }
            Err(_) => Index::create_in_dir(&index_dir, schema).map_err(|err| KernelError::new(err.to_string()))?,
        };
        Ok(Self { index_dir })
    }

    pub fn index_dir(&self) -> &std::path::Path {
        &self.index_dir
    }

    pub fn rebuild_from_documents(&self, documents: &[MemorySearchDocument]) -> KernelResult<usize> {
        MemorySearchIndexer::rebuild_from_documents(&self.index_dir, documents)
    }

    pub fn rebuild_from_sqlite(&self, database_path: impl AsRef<std::path::Path>, limit_per_layer: Option<usize>) -> KernelResult<usize> {
        let documents = load_documents_from_sqlite(database_path.as_ref(), limit_per_layer)?;
        self.rebuild_from_documents(&documents)
    }

    /// Upserts one record into the index, or removes the stale document when the
    /// source record no longer exists. Returns whether the record was upserted.
    pub fn upsert_record_from_sqlite(
        &self,
        database_path: impl AsRef<std::path::Path>,
        layer: &str,
        record_id: &str,
    ) -> KernelResult<bool> {
        match load_document_by_id(database_path.as_ref(), layer, record_id)? {
            Some(document) => {
                MemorySearchIndexer::upsert_document(&self.index_dir, &document)?;
                Ok(true)
            }
            None => {
                MemorySearchIndexer::delete_document(&self.index_dir, layer, record_id)?;
                Ok(false)
            }
        }
    }

    /// Removes the indexed document for a layer + record id.
    pub fn delete_record(&self, layer: &str, record_id: &str) -> KernelResult<()> {
        MemorySearchIndexer::delete_document(&self.index_dir, layer, record_id).map(|_| ())
    }

    /// Consumes up to `limit` pending `memory_search_index_queue` items: existing
    /// records are upserted, missing records are deleted from the index, and the
    /// queue rows are marked processed (or failed on per-item errors). One index
    /// writer session is used for the whole batch.
    pub fn drain_queue(
        &self,
        database_path: impl AsRef<std::path::Path>,
        limit: usize,
    ) -> KernelResult<DrainQueueResult> {
        let database_path = database_path.as_ref();
        if limit == 0 {
            return Ok(DrainQueueResult::default());
        }
        let mut connection = Connection::open(database_path).map_err(|err| KernelError::new(err.to_string()))?;
        let mut pending_statement = connection
            .prepare(
                "SELECT id, layer, record_id FROM memory_search_index_queue \
                 WHERE status = 'pending' ORDER BY created_at, id LIMIT ?1",
            )
            .map_err(|err| KernelError::new(err.to_string()))?;
        let items = pending_statement
            .query_map([limit as i64], |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?, row.get::<_, String>(2)?)))
            .map_err(|err| KernelError::new(err.to_string()))?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|err| KernelError::new(err.to_string()))?;
        drop(pending_statement);
        if items.is_empty() {
            return Ok(DrainQueueResult::default());
        }

        let mut upserts = Vec::new();
        let mut deletes = Vec::new();
        let mut outcomes: Vec<(String, Result<(), String>)> = Vec::with_capacity(items.len());
        for (queue_id, layer, record_id) in items {
            let outcome = match load_document_by_id(database_path, &layer, &record_id) {
                Ok(Some(document)) => {
                    upserts.push(document);
                    Ok(())
                }
                Ok(None) => {
                    deletes.push((layer, record_id));
                    Ok(())
                }
                Err(err) => Err(err.to_string()),
            };
            outcomes.push((queue_id, outcome));
        }

        let upserted = MemorySearchIndexer::upsert_and_delete_documents(&self.index_dir, &upserts, &deletes)?;

        {
            let transaction = connection.transaction().map_err(|err| KernelError::new(err.to_string()))?;
            {
                let mut processed_statement = transaction
                    .prepare(
                        "UPDATE memory_search_index_queue \
                         SET status = 'processed', processed_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), error = NULL \
                         WHERE id = ?1",
                    )
                    .map_err(|err| KernelError::new(err.to_string()))?;
                let mut failed_statement = transaction
                    .prepare(
                        "UPDATE memory_search_index_queue \
                         SET status = 'failed', processed_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), error = ?2 \
                         WHERE id = ?1",
                    )
                    .map_err(|err| KernelError::new(err.to_string()))?;
                for (queue_id, outcome) in &outcomes {
                    match outcome {
                        Ok(()) => {
                            processed_statement.execute([queue_id.as_str()]).map_err(|err| KernelError::new(err.to_string()))?;
                        }
                        Err(message) => {
                            failed_statement
                                .execute(rusqlite::params![queue_id.as_str(), message])
                                .map_err(|err| KernelError::new(err.to_string()))?;
                        }
                    }
                }
            }
            transaction.commit().map_err(|err| KernelError::new(err.to_string()))?;
        }

        let remaining: i64 = connection
            .query_row("SELECT COUNT(*) FROM memory_search_index_queue WHERE status = 'pending'", [], |row| row.get(0))
            .map_err(|err| KernelError::new(err.to_string()))?;
        Ok(DrainQueueResult {
            upserted,
            deleted: deletes.len(),
            failed: outcomes.iter().filter(|(_, outcome)| outcome.is_err()).count(),
            remaining: remaining as usize,
        })
    }

    pub fn search(&self, request: MemorySearchRequest) -> KernelResult<MemorySearchResponse> {
        let index = Index::open_in_dir(&self.index_dir).map_err(|err| KernelError::new(err.to_string()))?;
        let schema = index.schema();
        let fields = memory_search_fields(&schema);
        let reader = index.reader().map_err(|err| KernelError::new(err.to_string()))?;
        let searcher = reader.searcher();
        let query_fields = vec![fields.title, fields.aliases, fields.summary, fields.body, fields.keywords, fields.ids, fields.exact_terms];
        let parser = QueryParser::for_index(&index, query_fields);
        let query_inputs = request.effective_queries();
        let terms = deduplicated_terms(query_inputs.iter().flat_map(|query| query_terms(query)));
        if terms.is_empty() {
            return Ok(MemorySearchResponse { hits: vec![], backend: "tantivy-embedded".to_string() });
        }
        let clauses = terms
            .iter()
            .map(|term| {
                parser
                    .parse_query(&literal_query(term))
                    .map(|query| (Occur::Should, query))
                    .map_err(|err| KernelError::new(err.to_string()))
            })
            .collect::<KernelResult<Vec<(Occur, Box<dyn Query>)>>>()?;
        let query = BooleanQuery::new(clauses);
        let limit = request.limit.max(1).min(100);
        let fetch_limit = (limit * 100).max(500).min(5_000);
        let mut top_docs = searcher.search(&query, &TopDocs::with_limit(fetch_limit)).map_err(|err| KernelError::new(err.to_string()))?;
        for query_input in &query_inputs {
            let exact_term = Term::from_field_text(fields.exact_raw, &query_input.trim().to_lowercase());
            let exact_query = TermQuery::new(exact_term, IndexRecordOption::Basic);
            let exact_docs = searcher.search(&exact_query, &TopDocs::with_limit(100)).map_err(|err| KernelError::new(err.to_string()))?;
            top_docs.extend(exact_docs.into_iter().map(|(_score, address)| (10_000.0, address)));
        }
        dedupe_doc_addresses(&mut top_docs);
        let requested_layers: Vec<String> = request
            .layers
            .iter()
            .filter_map(|layer| serde_json::to_string(layer).ok())
            .map(|layer| layer.trim_matches('"').to_string())
            .collect();
        let mut hits = Vec::new();
        for (score, address) in top_docs {
            let doc: TantivyDocument = searcher.doc(address).map_err(|err| KernelError::new(err.to_string()))?;
            let layer = stored_text(&doc, fields.layer).unwrap_or_default();
            if !requested_layers.is_empty() && !requested_layers.contains(&layer) {
                continue;
            }
            let record_id = stored_text(&doc, fields.record_id).unwrap_or_default();
            let record_kind = stored_text(&doc, fields.record_kind).unwrap_or_default();
            let title = stored_text(&doc, fields.title).unwrap_or_else(|| record_id.clone());
            let aliases = stored_text(&doc, fields.aliases).unwrap_or_default();
            let exact_terms = stored_text(&doc, fields.exact_terms).unwrap_or_default();
            let summary = stored_text(&doc, fields.summary).unwrap_or_default();
            let body = stored_text(&doc, fields.body).unwrap_or_default();
            let keywords = stored_text(&doc, fields.keywords).unwrap_or_default();
            let ids = stored_text(&doc, fields.ids).unwrap_or_default();
            let snippet = if !summary.is_empty() { summary.clone() } else { body.chars().take(240).collect() };
            let updated_at = stored_text(&doc, fields.updated_at).filter(|value| !value.trim().is_empty());
            let metadata_json = stored_text(&doc, fields.metadata_json).unwrap_or_else(|| "{}".to_string());
            let layer_enum = serde_json::from_str(&format!("\"{}\"", layer)).unwrap_or(SearchLayer::L4);
            let boost_explanation = query_inputs
                .iter()
                .map(|query| exact_match_boost(query, &record_id, &record_kind, &title, &exact_terms))
                .max_by(|left, right| left.boost.partial_cmp(&right.boost).unwrap_or(std::cmp::Ordering::Equal))
                .unwrap_or(BoostExplanation { boost: 0.0, reasons: vec![] });
            let field_matches = field_match_explanation(
                &query_inputs,
                &[("record_id", &record_id), ("title", &title), ("aliases", &aliases), ("summary", &summary), ("body", &body), ("keywords", &keywords), ("ids", &ids), ("exact_terms", &exact_terms)],
            );
            let boosted_score = score + boost_explanation.boost;
            let matched_channel = if score >= 10_000.0 { "exact_raw+tantivy" } else { "tantivy" };
            let rank_reason = format!(
                "base_score={:.3}; matched_fields={}; boosts={}; query_terms={}",
                score,
                if field_matches.is_empty() { "none".to_string() } else { field_matches.join(",") },
                if boost_explanation.reasons.is_empty() { "none".to_string() } else { boost_explanation.reasons.join(",") },
                terms.join(",")
            );
            hits.push(MemorySearchHit {
                layer: layer_enum,
                record_id,
                record_kind,
                title,
                snippet,
                score: boosted_score,
                matched_channel: matched_channel.to_string(),
                rank_reason,
                updated_at,
                metadata_json,
            });
        }
        hits.sort_by(|left, right| right.score.partial_cmp(&left.score).unwrap_or(std::cmp::Ordering::Equal));
        hits.truncate(limit);
        Ok(MemorySearchResponse { hits, backend: "tantivy-embedded".to_string() })
    }
}

fn literal_query(term: &str) -> String {
    let escaped = term.replace('\\', "\\\\").replace('"', "\\\"");
    format!("\"{escaped}\"")
}

fn deduplicated_terms(values: impl IntoIterator<Item = String>) -> Vec<String> {
    let mut seen = HashSet::new();
    values
        .into_iter()
        .filter(|value| seen.insert(value.to_lowercase()))
        .collect()
}

fn dedupe_doc_addresses(items: &mut Vec<(f32, DocAddress)>) {
    let mut seen = HashSet::new();
    items.retain(|(_, address)| seen.insert(*address));
}

struct BoostExplanation {
    boost: f32,
    reasons: Vec<String>,
}

fn exact_match_boost(query: &str, record_id: &str, record_kind: &str, title: &str, exact_terms: &str) -> BoostExplanation {
    let q = query.trim().to_lowercase();
    if q.is_empty() { return BoostExplanation { boost: 0.0, reasons: vec![] }; }
    let exact = exact_terms.lines().map(|term| term.trim().to_lowercase()).collect::<Vec<_>>();
    let mut boost = 0.0;
    let mut reasons = Vec::new();
    if record_id.to_lowercase() == q {
        boost += 1_200.0;
        reasons.push("record_id_exact:+1200".to_string());
    }
    if exact.iter().any(|term| term == &q) {
        boost += 1_000.0;
        reasons.push("exact_raw:+1000".to_string());
    }
    if title.to_lowercase() == q {
        boost += 1_000.0;
        reasons.push("title_exact:+1000".to_string());
    }
    if exact.iter().any(|term| term == &q) && matches!(record_kind, "entity" | "Entity") {
        boost += 500.0;
        reasons.push("entity_exact:+500".to_string());
    }
    if matches!(record_kind, "entity_statement" | "EntityStatement") {
        boost -= 50.0;
        reasons.push("entity_statement_penalty:-50".to_string());
    }
    if title.to_lowercase().contains(&q) {
        boost += 10.0;
        reasons.push("title_contains:+10".to_string());
    }
    BoostExplanation { boost, reasons }
}

fn field_match_explanation(queries: &[&str], fields: &[(&str, &String)]) -> Vec<String> {
    let needles = deduplicated_terms(
        queries
            .iter()
            .flat_map(|query| query_terms(query))
            .map(|term| term.to_lowercase()),
    );
    let mut matched = Vec::new();
    for (field, value) in fields {
        let haystack = value.to_lowercase();
        if !haystack.is_empty() && needles.iter().any(|needle| !needle.is_empty() && haystack.contains(needle)) {
            matched.push((*field).to_string());
        }
    }
    matched.sort();
    matched.dedup();
    matched
}

fn stored_text(doc: &TantivyDocument, field: tantivy::schema::Field) -> Option<String> {
    doc.get_first(field).and_then(|value| value.as_str()).map(ToOwned::to_owned)
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;
    use tempfile::tempdir;

    fn fixture_database(dir: &std::path::Path) -> std::path::PathBuf {
        let db = dir.join("memory-os.sqlite");
        let connection = Connection::open(&db).expect("open sqlite");
        connection
            .execute_batch(
                r#"
                CREATE TABLE memory_l0_provenance_objects (id TEXT PRIMARY KEY, source_type TEXT NOT NULL, source_id TEXT, title TEXT NOT NULL, content TEXT NOT NULL, content_hash TEXT NOT NULL, occurred_at TEXT NOT NULL, ingested_at TEXT NOT NULL, session_id TEXT, work_object_id TEXT, confidentiality TEXT NOT NULL, status TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}');
                CREATE TABLE memory_l1_capture_events (id TEXT PRIMARY KEY, provenance_object_id TEXT NOT NULL, event_type TEXT NOT NULL, occurred_at TEXT NOT NULL, token_estimate INTEGER NOT NULL DEFAULT 0, processing_state TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}');
                CREATE TABLE memory_l2_statements (id TEXT PRIMARY KEY, subject_id TEXT NOT NULL, predicate TEXT NOT NULL, object_id TEXT, text TEXT NOT NULL, assertion_kind TEXT NOT NULL, confidence REAL NOT NULL, valid_at TEXT NOT NULL, committed_at TEXT NOT NULL, evidence_span_ids_json TEXT NOT NULL DEFAULT '[]', source_artifact_id TEXT, metadata_json TEXT NOT NULL DEFAULT '{}');
                CREATE TABLE memory_l3_beliefs (id TEXT PRIMARY KEY, statement TEXT NOT NULL, domain TEXT NOT NULL DEFAULT 'general-knowledge', related_object_names TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
                CREATE TABLE memory_l4_entities (id TEXT PRIMARY KEY, stable_key TEXT NOT NULL UNIQUE, entity_type TEXT NOT NULL, name TEXT NOT NULL, aliases_json TEXT NOT NULL DEFAULT '[]', summary TEXT NOT NULL DEFAULT '', confidence REAL NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, valid_from TEXT, metadata_json TEXT NOT NULL DEFAULT '{}');
                CREATE TABLE memory_l4_entity_aliases (id TEXT PRIMARY KEY, entity_id TEXT NOT NULL, alias TEXT NOT NULL, normalized_alias TEXT NOT NULL, created_at TEXT NOT NULL, metadata_json TEXT NOT NULL DEFAULT '{}');
                CREATE TABLE memory_l4_entity_statements (id TEXT PRIMARY KEY, entity_id TEXT NOT NULL, predicate TEXT NOT NULL, object_entity_id TEXT, text TEXT NOT NULL, assertion_kind TEXT NOT NULL, confidence REAL NOT NULL, valid_at TEXT NOT NULL, committed_at TEXT NOT NULL, evidence_span_ids_json TEXT NOT NULL DEFAULT '[]', source_artifact_id TEXT, metadata_json TEXT NOT NULL DEFAULT '{}');
                CREATE TABLE memory_search_index_queue (id TEXT PRIMARY KEY, layer TEXT NOT NULL, record_id TEXT NOT NULL, operation TEXT NOT NULL, created_at TEXT NOT NULL, processed_at TEXT, status TEXT NOT NULL, error TEXT);
                INSERT INTO memory_l2_statements VALUES ('s1','subj','likes',NULL,'用户喜欢图谱','fact',0.9,'2026-06-24','2026-06-24','[]',NULL,'{}');
                INSERT INTO memory_search_index_queue VALUES ('q1','L2','s1','upsert','2026-08-01T00:00:00Z',NULL,'pending',NULL);
                INSERT INTO memory_search_index_queue VALUES ('q2','L2','missing','upsert','2026-08-01T00:00:01Z',NULL,'pending',NULL);
                INSERT INTO memory_search_index_queue VALUES ('q3','L1','c1','upsert','2026-08-01T00:00:02Z',NULL,'pending',NULL);
                "#,
            )
            .expect("fixture schema");
        db
    }

    #[test]
    fn drain_queue_upserts_live_and_deletes_stale_records() {
        let dir = tempdir().expect("tempdir");
        let db = fixture_database(dir.path());
        let kernel = ConnorMemorySearchKernel::open(dir.path().join("index")).expect("open");

        let result = kernel.drain_queue(&db, 10).expect("drain");
        assert_eq!(result.upserted, 1);
        assert_eq!(result.deleted, 2);
        assert_eq!(result.failed, 0);
        assert_eq!(result.remaining, 0);

        let response = kernel
            .search(MemorySearchRequest {
                query: "图谱".to_string(),
                queries: vec![],
                layers: vec![SearchLayer::L2],
                limit: 10,
            })
            .expect("search");
        assert_eq!(response.hits.len(), 1);
        assert_eq!(response.hits[0].record_id, "s1");

        let connection = Connection::open(&db).expect("open sqlite");
        let statuses = connection
            .prepare("SELECT status FROM memory_search_index_queue ORDER BY id")
            .expect("prepare")
            .query_map([], |row| row.get::<_, String>(0))
            .expect("query")
            .collect::<Result<Vec<_>, _>>()
            .expect("collect");
        assert_eq!(statuses, vec!["processed", "processed", "processed"]);
    }

    #[test]
    fn upsert_record_is_idempotent_and_delete_removes_document() {
        let dir = tempdir().expect("tempdir");
        let db = fixture_database(dir.path());
        let kernel = ConnorMemorySearchKernel::open(dir.path().join("index")).expect("open");

        assert!(kernel.upsert_record_from_sqlite(&db, "L2", "s1").expect("upsert once"));
        assert!(kernel.upsert_record_from_sqlite(&db, "L2", "s1").expect("upsert twice"));
        assert!(!kernel.upsert_record_from_sqlite(&db, "L1", "c1").expect("missing upsert"));

        let response = kernel
            .search(MemorySearchRequest {
                query: "图谱".to_string(),
                queries: vec![],
                layers: vec![SearchLayer::L2],
                limit: 10,
            })
            .expect("search");
        assert_eq!(response.hits.len(), 1, "repeated upserts must not duplicate documents");

        kernel.delete_record("L2", "s1").expect("delete");
        let response = kernel
            .search(MemorySearchRequest {
                query: "图谱".to_string(),
                queries: vec![],
                layers: vec![SearchLayer::L2],
                limit: 10,
            })
            .expect("search after delete");
        assert!(response.hits.is_empty());
    }

    #[test]
    fn kernel_rebuilds_and_queries_documents() {
        let dir = tempdir().expect("tempdir");
        let kernel = ConnorMemorySearchKernel::open(dir.path()).expect("open");
        let docs = vec![MemorySearchDocument {
            id: "L4:wikidata:Q148".to_string(),
            layer: SearchLayer::L4,
            record_id: "wikidata:Q148".to_string(),
            record_kind: SearchRecordKind::Entity,
            title: "中华人民共和国".to_string(),
            aliases: vec!["中国".to_string(), "China".to_string(), "PRC".to_string()],
            summary: "东亚国家".to_string(),
            body: "中华人民共和国是一个国家".to_string(),
            keywords: vec!["国家".to_string()],
            ids: vec!["Q148".to_string(), "wikidata:Q148".to_string()],
            created_at: None,
            updated_at: None,
            metadata_json: "{}".to_string(),
        }];
        assert_eq!(kernel.rebuild_from_documents(&docs).expect("rebuild"), 1);
        let response = ConnorMemorySearchKernel::open(dir.path())
            .expect("reopen")
            .search(MemorySearchRequest { query: "中国".to_string(), queries: vec![], layers: vec![SearchLayer::L4], limit: 10 })
            .expect("search");
        assert_eq!(response.backend, "tantivy-embedded");
        let first = response.hits.first().expect("first hit");
        assert_eq!(first.record_id.as_str(), "wikidata:Q148");
        assert!(first.rank_reason.contains("matched_fields="));
        assert!(first.rank_reason.contains("aliases"));
        assert!(first.rank_reason.contains("boosts="));
        assert!(first.rank_reason.contains("exact_raw:+1000"));
    }

    #[test]
    fn kernel_broadly_recalls_known_term_across_query_separators() {
        let dir = tempdir().expect("tempdir");
        let kernel = ConnorMemorySearchKernel::open(dir.path()).expect("open");
        let docs = vec![MemorySearchDocument {
            id: "L1:annie-capture".to_string(),
            layer: SearchLayer::L1,
            record_id: "annie-capture".to_string(),
            record_kind: SearchRecordKind::CaptureEvent,
            title: "Invitation note".to_string(),
            aliases: vec![],
            summary: "Annie received the product invitation.".to_string(),
            body: "Annie received the product invitation.".to_string(),
            keywords: vec![],
            ids: vec![],
            created_at: None,
            updated_at: None,
            metadata_json: "{}".to_string(),
        }];
        kernel.rebuild_from_documents(&docs).expect("rebuild");

        for query in [
            "Annie Friend",
            "Annie,Friend",
            "Annie，Friend",
            "Annie;Friend",
            "Annie；Friend",
            "Annie、Friend",
            "Annie|Friend",
            "Annie｜Friend",
            "Annie\nFriend",
            "Annie 朋友 friend",
            "Annie OR Friend",
        ] {
            let response = kernel
                .search(MemorySearchRequest { query: query.to_string(), queries: vec![], layers: vec![SearchLayer::L1], limit: 10 })
                .expect(query);
            assert_eq!(response.hits.first().map(|hit| hit.record_id.as_str()), Some("annie-capture"), "query={query:?}");
            assert!(response.hits[0].rank_reason.contains("matched_fields=body"), "query={query:?}; reason={}", response.hits[0].rank_reason);
        }
    }

    #[test]
    fn structured_queries_preserve_independent_recall_and_exact_boosts() {
        let dir = tempdir().expect("tempdir");
        let kernel = ConnorMemorySearchKernel::open(dir.path()).expect("open");
        let docs = vec![MemorySearchDocument {
            id: "L4:annie".to_string(),
            layer: SearchLayer::L4,
            record_id: "annie".to_string(),
            record_kind: SearchRecordKind::Entity,
            title: "Annie".to_string(),
            aliases: vec![],
            summary: "A known person".to_string(),
            body: "Annie is a known person.".to_string(),
            keywords: vec![],
            ids: vec![],
            created_at: None,
            updated_at: None,
            metadata_json: "{}".to_string(),
        }];
        kernel.rebuild_from_documents(&docs).expect("rebuild");

        let response = kernel
            .search(MemorySearchRequest {
                query: "Annie Friend".to_string(),
                queries: vec!["Annie".to_string(), "Friend".to_string()],
                layers: vec![SearchLayer::L4],
                limit: 10,
            })
            .expect("structured search");

        assert_eq!(response.hits[0].record_id, "annie");
        assert!(response.hits[0].rank_reason.contains("exact_raw:+1000"));
    }
}
