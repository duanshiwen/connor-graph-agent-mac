use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum SearchLayer {
    L0,
    L1,
    L2,
    L3,
    L4,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum SearchRecordKind {
    ProvenanceObject,
    ProvenanceSpan,
    CaptureEvent,
    TimeBlock,
    Statement,
    Belief,
    Entity,
    EntityStatement,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemorySearchDocument {
    pub id: String,
    pub layer: SearchLayer,
    pub record_id: String,
    pub record_kind: SearchRecordKind,
    pub title: String,
    pub aliases: Vec<String>,
    pub summary: String,
    pub body: String,
    pub keywords: Vec<String>,
    pub ids: Vec<String>,
    pub created_at: Option<String>,
    pub updated_at: Option<String>,
    pub metadata_json: String,
}
