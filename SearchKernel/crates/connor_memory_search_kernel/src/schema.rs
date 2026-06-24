use tantivy::schema::{Schema, STORED, STRING, TEXT};

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
    builder.add_text_field(FIELD_KEYWORDS, TEXT);
    builder.add_text_field(FIELD_IDS, TEXT | STORED);
    builder.add_text_field(FIELD_METADATA_JSON, STORED);
    builder.build()
}
