use tantivy::schema::{Field, Schema, STORED, STRING, TEXT};

pub const FIELD_ID: &str = "id";
pub const FIELD_LAYER: &str = "layer";
pub const FIELD_RECORD_ID: &str = "record_id";
pub const FIELD_RECORD_KIND: &str = "record_kind";
pub const FIELD_TITLE: &str = "title";
pub const FIELD_ALIASES: &str = "aliases";
pub const FIELD_SUMMARY: &str = "summary";
pub const FIELD_BODY: &str = "body";
pub const FIELD_KEYWORDS: &str = "keywords";
pub const FIELD_IDS: &str = "ids";
pub const FIELD_METADATA_JSON: &str = "metadata_json";
pub const FIELD_EXACT_TERMS: &str = "exact_terms";
pub const FIELD_EXACT_RAW: &str = "exact_raw";

#[derive(Debug, Clone, Copy)]
pub struct MemorySearchFields {
    pub id: Field,
    pub layer: Field,
    pub record_id: Field,
    pub record_kind: Field,
    pub title: Field,
    pub aliases: Field,
    pub summary: Field,
    pub body: Field,
    pub keywords: Field,
    pub ids: Field,
    pub metadata_json: Field,
    pub exact_terms: Field,
    pub exact_raw: Field,
}

pub fn memory_search_schema() -> Schema {
    let mut builder = Schema::builder();
    builder.add_text_field(FIELD_ID, STRING | STORED);
    builder.add_text_field(FIELD_LAYER, STRING | STORED);
    builder.add_text_field(FIELD_RECORD_ID, STRING | STORED);
    builder.add_text_field(FIELD_RECORD_KIND, STRING | STORED);
    builder.add_text_field(FIELD_TITLE, TEXT | STORED);
    builder.add_text_field(FIELD_ALIASES, TEXT | STORED);
    builder.add_text_field(FIELD_SUMMARY, TEXT | STORED);
    builder.add_text_field(FIELD_BODY, TEXT | STORED);
    builder.add_text_field(FIELD_KEYWORDS, TEXT | STORED);
    builder.add_text_field(FIELD_IDS, TEXT | STORED);
    builder.add_text_field(FIELD_METADATA_JSON, STORED);
    builder.add_text_field(FIELD_EXACT_TERMS, TEXT | STORED);
    builder.add_text_field(FIELD_EXACT_RAW, STRING | STORED);
    builder.build()
}

pub fn memory_search_fields(schema: &Schema) -> MemorySearchFields {
    MemorySearchFields {
        id: schema.get_field(FIELD_ID).expect("id field"),
        layer: schema.get_field(FIELD_LAYER).expect("layer field"),
        record_id: schema.get_field(FIELD_RECORD_ID).expect("record_id field"),
        record_kind: schema.get_field(FIELD_RECORD_KIND).expect("record_kind field"),
        title: schema.get_field(FIELD_TITLE).expect("title field"),
        aliases: schema.get_field(FIELD_ALIASES).expect("aliases field"),
        summary: schema.get_field(FIELD_SUMMARY).expect("summary field"),
        body: schema.get_field(FIELD_BODY).expect("body field"),
        keywords: schema.get_field(FIELD_KEYWORDS).expect("keywords field"),
        ids: schema.get_field(FIELD_IDS).expect("ids field"),
        metadata_json: schema.get_field(FIELD_METADATA_JSON).expect("metadata_json field"),
        exact_terms: schema.get_field(FIELD_EXACT_TERMS).expect("exact_terms field"),
        exact_raw: schema.get_field(FIELD_EXACT_RAW).expect("exact_raw field"),
    }
}
