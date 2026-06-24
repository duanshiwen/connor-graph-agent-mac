pub mod document;
pub mod error;
pub mod ffi;
pub mod indexer;
pub mod query;
pub mod schema;
pub mod tokenizer;

pub use document::{MemorySearchDocument, SearchLayer, SearchRecordKind};
pub use error::{KernelError, KernelResult};
pub use query::{MemorySearchHit, MemorySearchRequest, MemorySearchResponse};

use std::path::PathBuf;

use tantivy::collector::TopDocs;
use tantivy::query::QueryParser;
use tantivy::schema::Value;
use tantivy::{Index, TantivyDocument};

use crate::indexer::MemorySearchIndexer;
use crate::schema::{memory_search_fields, memory_search_schema};
use crate::tokenizer::query_terms;

#[derive(Debug)]
pub struct ConnorMemorySearchKernel {
    index_dir: PathBuf,
    index: Index,
}

impl ConnorMemorySearchKernel {
    pub fn open(index_dir: impl Into<PathBuf>) -> KernelResult<Self> {
        let index_dir = index_dir.into();
        std::fs::create_dir_all(&index_dir).map_err(|err| KernelError::new(err.to_string()))?;
        let schema = memory_search_schema();
        let index = match Index::open_in_dir(&index_dir) {
            Ok(index) => index,
            Err(_) => Index::create_in_dir(&index_dir, schema).map_err(|err| KernelError::new(err.to_string()))?,
        };
        Ok(Self { index_dir, index })
    }

    pub fn index_dir(&self) -> &std::path::Path {
        &self.index_dir
    }

    pub fn rebuild_from_documents(&self, documents: &[MemorySearchDocument]) -> KernelResult<usize> {
        MemorySearchIndexer::rebuild_from_documents(&self.index_dir, documents)
    }

    pub fn search(&self, request: MemorySearchRequest) -> KernelResult<MemorySearchResponse> {
        let schema = self.index.schema();
        let fields = memory_search_fields(&schema);
        let reader = self.index.reader().map_err(|err| KernelError::new(err.to_string()))?;
        let searcher = reader.searcher();
        let query_fields = vec![fields.title, fields.aliases, fields.summary, fields.body, fields.keywords, fields.ids];
        let parser = QueryParser::for_index(&self.index, query_fields);
        let query_text = query_terms(&request.query).join(" OR ");
        let query = parser.parse_query(&query_text).map_err(|err| KernelError::new(err.to_string()))?;
        let limit = request.limit.max(1).min(100);
        let top_docs = searcher.search(&query, &TopDocs::with_limit(limit)).map_err(|err| KernelError::new(err.to_string()))?;
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
            let summary = stored_text(&doc, fields.summary).unwrap_or_default();
            let body = stored_text(&doc, fields.body).unwrap_or_default();
            let snippet = if !summary.is_empty() { summary } else { body.chars().take(240).collect() };
            let metadata_json = stored_text(&doc, fields.metadata_json).unwrap_or_else(|| "{}".to_string());
            let layer_enum = serde_json::from_str(&format!("\"{}\"", layer)).unwrap_or(SearchLayer::L4);
            hits.push(MemorySearchHit {
                layer: layer_enum,
                record_id,
                record_kind,
                title,
                snippet,
                score,
                matched_channel: "tantivy".to_string(),
                rank_reason: format!("BM25 over embedded Tantivy fields for query `{}`", request.query),
                metadata_json,
            });
        }
        Ok(MemorySearchResponse { hits, backend: "tantivy-embedded".to_string() })
    }
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
        assert_eq!(response.hits.first().map(|hit| hit.record_id.as_str()), Some("wikidata:Q148"));
    }
}
