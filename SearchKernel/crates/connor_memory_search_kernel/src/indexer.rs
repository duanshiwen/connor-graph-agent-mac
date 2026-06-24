use std::path::Path;

use crate::document::MemorySearchDocument;
use crate::error::KernelResult;

pub struct MemorySearchIndexer;

impl MemorySearchIndexer {
    pub fn rebuild_from_documents(_index_dir: &Path, _documents: &[MemorySearchDocument]) -> KernelResult<usize> {
        Ok(_documents.len())
    }
}
