use std::path::Path;

use tantivy::{Index, TantivyDocument, Term};

use crate::document::{MemorySearchDocument, SearchRecordKind};
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
            writer.add_document(document_from_item(&fields, item)).map_err(|err| KernelError::new(err.to_string()))?;
        }
        writer.commit().map_err(|err| KernelError::new(err.to_string()))?;
        Ok(documents.len())
    }

    /// Opens the existing index, or creates it when the directory is empty.
    /// Refuses to reuse an index whose schema no longer matches (callers must
    /// trigger a full rebuild in that case).
    pub fn open_or_create_index(index_dir: &Path) -> KernelResult<Index> {
        let schema = memory_search_schema();
        if index_dir.exists() {
            if let Ok(index) = Index::open_in_dir(index_dir) {
                if index.schema().get_field(crate::schema::FIELD_EXACT_RAW).is_ok() {
                    return Ok(index);
                }
            }
        }
        std::fs::create_dir_all(index_dir).map_err(|err| KernelError::new(err.to_string()))?;
        Index::create_in_dir(index_dir, schema).map_err(|err| KernelError::new(err.to_string()))
    }

    /// Adds or replaces a single document. Deletes the previous document with
    /// the same id before adding, so repeated upserts never duplicate.
    pub fn upsert_document(index_dir: &Path, item: &MemorySearchDocument) -> KernelResult<usize> {
        let index = Self::open_or_create_index(index_dir)?;
        let fields = memory_search_fields(&index.schema());
        let mut writer = index.writer(50_000_000).map_err(|err| KernelError::new(err.to_string()))?;
        writer.delete_term(Term::from_field_text(fields.id, &item.id));
        writer.add_document(document_from_item(&fields, item)).map_err(|err| KernelError::new(err.to_string()))?;
        writer.commit().map_err(|err| KernelError::new(err.to_string()))?;
        Ok(1)
    }

    /// Removes a document by its indexed id (layer + record id). L4 covers both
    /// entity and entity-statement ids, so both forms are removed.
    pub fn delete_document(index_dir: &Path, layer: &str, record_id: &str) -> KernelResult<usize> {
        let index = Self::open_or_create_index(index_dir)?;
        let fields = memory_search_fields(&index.schema());
        let mut writer: tantivy::IndexWriter<TantivyDocument> =
            index.writer(50_000_000).map_err(|err| KernelError::new(err.to_string()))?;
        for id in document_ids_for(layer, record_id) {
            writer.delete_term(Term::from_field_text(fields.id, &id));
        }
        writer.commit().map_err(|err| KernelError::new(err.to_string()))?;
        Ok(0)
    }

    /// Applies a batch of upserts and deletes in one writer session so the
    /// queue drain commits once instead of once per record.
    pub fn upsert_and_delete_documents(
        index_dir: &Path,
        upserts: &[MemorySearchDocument],
        deletes: &[(String, String)],
    ) -> KernelResult<usize> {
        let index = Self::open_or_create_index(index_dir)?;
        let fields = memory_search_fields(&index.schema());
        let mut writer = index.writer(50_000_000).map_err(|err| KernelError::new(err.to_string()))?;
        for item in upserts {
            writer.delete_term(Term::from_field_text(fields.id, &item.id));
            writer.add_document(document_from_item(&fields, item)).map_err(|err| KernelError::new(err.to_string()))?;
        }
        for (layer, record_id) in deletes {
            for id in document_ids_for(layer, record_id) {
                writer.delete_term(Term::from_field_text(fields.id, &id));
            }
        }
        writer.commit().map_err(|err| KernelError::new(err.to_string()))?;
        Ok(upserts.len())
    }

    /// Counts documents currently stored under a layer by term query.
    pub fn layer_document_count(index_dir: &Path, layer: &str) -> KernelResult<usize> {
        let index = Self::open_or_create_index(index_dir)?;
        let fields = memory_search_fields(&index.schema());
        let reader = index.reader().map_err(|err| KernelError::new(err.to_string()))?;
        let term = Term::from_field_text(fields.layer, layer);
        let searcher = reader.searcher();
        searcher
            .doc_freq(&term)
            .map(|count| count as usize)
            .map_err(|err| KernelError::new(err.to_string()))
    }
}

fn document_from_item(fields: &crate::schema::MemorySearchFields, item: &MemorySearchDocument) -> TantivyDocument {
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
    document.add_text(fields.created_at, item.created_at.clone().unwrap_or_default());
    document.add_text(fields.updated_at, item.updated_at.clone().unwrap_or_default());
    document.add_text(fields.metadata_json, item.metadata_json.clone());
    document.add_text(fields.exact_terms, exact_terms(item).join("\n"));
    for term in exact_terms(item) {
        document.add_text(fields.exact_raw, term.to_lowercase());
    }
    document
}

fn document_ids_for(layer: &str, record_id: &str) -> Vec<String> {
    match layer {
        "L4" => vec![format!("L4:{}", record_id), format!("L4S:{}", record_id)],
        _ => vec![format!("{}:{}", layer, record_id)],
    }
}

fn exact_terms(item: &MemorySearchDocument) -> Vec<String> {
    let mut terms = vec![item.record_id.clone()];
    if item.record_kind != SearchRecordKind::EntityStatement {
        terms.push(item.title.clone());
        terms.extend(item.aliases.iter().cloned());
        terms.extend(item.ids.iter().cloned());
    }
    terms.sort();
    terms.dedup();
    terms
}
