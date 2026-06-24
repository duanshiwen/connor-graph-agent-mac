use serde::{Deserialize, Serialize};

use crate::document::SearchLayer;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemorySearchRequest {
    pub query: String,
    pub layers: Vec<SearchLayer>,
    pub limit: usize,
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
    pub metadata_json: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemorySearchResponse {
    pub hits: Vec<MemorySearchHit>,
    pub backend: String,
}
