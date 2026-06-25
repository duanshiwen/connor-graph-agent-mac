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

use tantivy::collector::TopDocs;
use tantivy::query::{QueryParser, TermQuery};
use tantivy::schema::{IndexRecordOption, Value};
use tantivy::{DocAddress, Index, TantivyDocument, Term};

use crate::indexer::MemorySearchIndexer;
use crate::schema::{memory_search_fields, memory_search_schema, FIELD_EXACT_RAW};
use crate::sqlite_import::load_documents_from_sqlite;
use crate::tokenizer::query_terms;

#[derive(Debug)]
pub struct ConnorMemorySearchKernel {
    index_dir: PathBuf,
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

    pub fn search(&self, request: MemorySearchRequest) -> KernelResult<MemorySearchResponse> {
        let index = Index::open_in_dir(&self.index_dir).map_err(|err| KernelError::new(err.to_string()))?;
        let schema = index.schema();
        let fields = memory_search_fields(&schema);
        let reader = index.reader().map_err(|err| KernelError::new(err.to_string()))?;
        let searcher = reader.searcher();
        let query_fields = vec![fields.title, fields.aliases, fields.summary, fields.body, fields.keywords, fields.ids, fields.exact_terms];
        let parser = QueryParser::for_index(&index, query_fields);
        let query_text = query_terms(&request.query).join(" OR ");
        let query = parser.parse_query(&query_text).map_err(|err| KernelError::new(err.to_string()))?;
        let limit = request.limit.max(1).min(100);
        let fetch_limit = (limit * 100).max(500).min(5_000);
        let mut top_docs = searcher.search(&query, &TopDocs::with_limit(fetch_limit)).map_err(|err| KernelError::new(err.to_string()))?;
        let exact_term = Term::from_field_text(fields.exact_raw, &request.query.trim().to_lowercase());
        let exact_query = TermQuery::new(exact_term, IndexRecordOption::Basic);
        let exact_docs = searcher.search(&exact_query, &TopDocs::with_limit(100)).map_err(|err| KernelError::new(err.to_string()))?;
        top_docs.extend(exact_docs.into_iter().map(|(_score, address)| (10_000.0, address)));
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
            let metadata_json = stored_text(&doc, fields.metadata_json).unwrap_or_else(|| "{}".to_string());
            let layer_enum = serde_json::from_str(&format!("\"{}\"", layer)).unwrap_or(SearchLayer::L4);
            let boost_explanation = exact_match_boost(&request.query, &record_id, &record_kind, &title, &exact_terms);
            let field_matches = field_match_explanation(
                &request.query,
                &[("record_id", &record_id), ("title", &title), ("aliases", &aliases), ("summary", &summary), ("body", &body), ("keywords", &keywords), ("ids", &ids), ("exact_terms", &exact_terms)],
            );
            let boosted_score = score + boost_explanation.boost;
            let matched_channel = if score >= 10_000.0 { "exact_raw+tantivy" } else { "tantivy" };
            let rank_reason = format!(
                "base_score={:.3}; matched_fields={}; boosts={}; query_terms={}",
                score,
                if field_matches.is_empty() { "none".to_string() } else { field_matches.join(",") },
                if boost_explanation.reasons.is_empty() { "none".to_string() } else { boost_explanation.reasons.join(",") },
                query_terms(&request.query).join(",")
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
                metadata_json,
            });
        }
        hits.sort_by(|left, right| right.score.partial_cmp(&left.score).unwrap_or(std::cmp::Ordering::Equal));
        hits.truncate(limit);
        Ok(MemorySearchResponse { hits, backend: "tantivy-embedded".to_string() })
    }
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

fn field_match_explanation(query: &str, fields: &[(&str, &String)]) -> Vec<String> {
    let mut needles = query_terms(query);
    let raw = query.trim().to_lowercase();
    if !raw.is_empty() && !needles.contains(&raw) { needles.push(raw); }
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
    use tempfile::tempdir;

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
            .search(MemorySearchRequest { query: "中国".to_string(), layers: vec![SearchLayer::L4], limit: 10 })
            .expect("search");
        assert_eq!(response.backend, "tantivy-embedded");
        let first = response.hits.first().expect("first hit");
        assert_eq!(first.record_id.as_str(), "wikidata:Q148");
        assert!(first.rank_reason.contains("matched_fields="));
        assert!(first.rank_reason.contains("aliases"));
        assert!(first.rank_reason.contains("boosts="));
        assert!(first.rank_reason.contains("exact_raw:+1000"));
    }
}
