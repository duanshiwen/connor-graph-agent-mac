use std::path::Path;

use tantivy::{Index, TantivyDocument};

use crate::document::MemorySearchDocument;
use crate::error::{KernelError, KernelResult};
use crate::schema::{memory_search_fields, memory_search_schema};
use crate::tokenizer::searchable_text;

pub struct MemorySearchIndexer;

impl MemorySearchIndexer {
    pub fn rebuild_from_documents(index_dir: &Path, documents: &[MemorySearchDocument]) -> KernelResult<usize> {
        if index_dir.exists() {
            std::fs::remove_dir_all(index_dir).map_err(|err| KernelError::new(err.to_string()))?;
        }
        std::fs::create_dir_all(index_dir).map_err(|err| KernelError::new(err.to_string()))?;
        let schema = memory_search_schema();
        let index = Index::create_in_dir(index_dir, schema.clone()).map_err(|err| KernelError::new(err.to_string()))?;
        let fields = memory_search_fields(&schema);
        let mut writer = index.writer(50_000_000).map_err(|err| KernelError::new(err.to_string()))?;
        for item in documents {
            let layer = serde_json::to_string(&item.layer)
                .unwrap_or_else(|_| format!("{:?}", item.layer))
                .trim_matches('"')
                .to_string();
            let record_kind = serde_json::to_string(&item.record_kind)
                .unwrap_or_else(|_| format!("{:?}", item.record_kind))
                .trim_matches('"')
                .to_string();
            let mut document = TantivyDocument::default();
            document.add_text(fields.id, item.id.clone());
            document.add_text(fields.layer, layer);
            document.add_text(fields.record_id, item.record_id.clone());
            document.add_text(fields.record_kind, record_kind);
            document.add_text(fields.title, searchable_text(&item.title));
            document.add_text(fields.aliases, searchable_text(&item.aliases.join(" ")));
            document.add_text(fields.summary, searchable_text(&item.summary));
            document.add_text(fields.body, searchable_text(&item.body));
            document.add_text(fields.keywords, searchable_text(&item.keywords.join(" ")));
            document.add_text(fields.ids, item.ids.join(" "));
            document.add_text(fields.metadata_json, item.metadata_json.clone());
            document.add_text(fields.exact_terms, exact_terms(item).join("\n"));
            for term in exact_terms(item) {
                document.add_text(fields.exact_raw, term.to_lowercase());
            }
            writer.add_document(document).map_err(|err| KernelError::new(err.to_string()))?;
        }
        writer.commit().map_err(|err| KernelError::new(err.to_string()))?;
        Ok(documents.len())
    }
}

fn exact_terms(item: &MemorySearchDocument) -> Vec<String> {
    let mut terms = vec![item.record_id.clone(), item.title.clone()];
    terms.extend(item.aliases.iter().cloned());
    terms.extend(item.ids.iter().cloned());
    terms.sort();
    terms.dedup();
    terms
}
