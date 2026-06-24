use std::path::Path;

use tantivy::{doc, Index};

use crate::document::MemorySearchDocument;
use crate::error::{KernelError, KernelResult};
use crate::schema::{memory_search_fields, memory_search_schema};
use crate::tokenizer::searchable_text;

pub struct MemorySearchIndexer;

impl MemorySearchIndexer {
    pub fn rebuild_from_documents(index_dir: &Path, documents: &[MemorySearchDocument]) -> KernelResult<usize> {
        std::fs::create_dir_all(index_dir).map_err(|err| KernelError::new(err.to_string()))?;
        let schema = memory_search_schema();
        let index = match Index::open_in_dir(index_dir) {
            Ok(index) => index,
            Err(_) => Index::create_in_dir(index_dir, schema.clone()).map_err(|err| KernelError::new(err.to_string()))?,
        };
        let fields = memory_search_fields(&schema);
        let mut writer = index.writer(50_000_000).map_err(|err| KernelError::new(err.to_string()))?;
        writer.delete_all_documents().map_err(|err| KernelError::new(err.to_string()))?;
        for item in documents {
            let layer = serde_json::to_string(&item.layer)
                .unwrap_or_else(|_| format!("{:?}", item.layer))
                .trim_matches('"')
                .to_string();
            let record_kind = serde_json::to_string(&item.record_kind)
                .unwrap_or_else(|_| format!("{:?}", item.record_kind))
                .trim_matches('"')
                .to_string();
            writer
                .add_document(doc!(
                    fields.id => item.id.clone(),
                    fields.layer => layer,
                    fields.record_id => item.record_id.clone(),
                    fields.record_kind => record_kind,
                    fields.title => searchable_text(&item.title),
                    fields.aliases => searchable_text(&item.aliases.join(" ")),
                    fields.summary => searchable_text(&item.summary),
                    fields.body => searchable_text(&item.body),
                    fields.keywords => searchable_text(&item.keywords.join(" ")),
                    fields.ids => item.ids.join(" "),
                    fields.metadata_json => item.metadata_json.clone(),
                ))
                .map_err(|err| KernelError::new(err.to_string()))?;
        }
        writer.commit().map_err(|err| KernelError::new(err.to_string()))?;
        Ok(documents.len())
    }
}
