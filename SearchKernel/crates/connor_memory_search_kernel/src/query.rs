use serde::{Deserialize, Serialize};

use crate::document::SearchLayer;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemorySearchRequest {
    pub query: String,
    #[serde(default)]
    pub queries: Vec<String>,
    pub layers: Vec<SearchLayer>,
    pub limit: usize,
}

impl MemorySearchRequest {
    pub fn effective_queries(&self) -> Vec<&str> {
        let queries = self.queries.iter().map(String::as_str).filter(|query| !query.trim().is_empty()).collect::<Vec<_>>();
        if queries.is_empty() { vec![self.query.as_str()] } else { queries }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemorySearchHit {
    pub layer: SearchLayer,
    pub record_id: String,
    pub record_kind: String,
    pub title: String,
    pub snippet: String,
    pub score: f32,
    pub matched_channel: String,
    pub rank_reason: String,
    pub updated_at: Option<String>,
    pub metadata_json: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemorySearchResponse {
    pub hits: Vec<MemorySearchHit>,
    pub backend: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn legacy_request_without_queries_remains_decodable() {
        let request: MemorySearchRequest = serde_json::from_str(
            r#"{"query":"Annie","layers":["L1"],"limit":10}"#,
        )
        .expect("legacy request");

        assert!(request.queries.is_empty());
        assert_eq!(request.effective_queries(), vec!["Annie"]);
    }
}
