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

#[derive(Debug)]
pub struct ConnorMemorySearchKernel {
    index_dir: std::path::PathBuf,
}

impl ConnorMemorySearchKernel {
    pub fn open(index_dir: impl Into<std::path::PathBuf>) -> KernelResult<Self> {
        Ok(Self { index_dir: index_dir.into() })
    }

    pub fn index_dir(&self) -> &std::path::Path {
        &self.index_dir
    }

    pub fn search(&self, _request: MemorySearchRequest) -> KernelResult<MemorySearchResponse> {
        Ok(MemorySearchResponse { hits: Vec::new(), backend: "tantivy-embedded".to_string() })
    }
}
