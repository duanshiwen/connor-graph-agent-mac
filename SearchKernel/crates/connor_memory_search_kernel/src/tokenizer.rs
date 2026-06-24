use jieba_rs::Jieba;
use once_cell::sync::Lazy;

static JIEBA: Lazy<Jieba> = Lazy::new(Jieba::new);

pub fn normalize_query(input: &str) -> String {
    input.trim().to_string()
}

pub fn jieba_tokens(input: &str) -> Vec<String> {
    JIEBA
        .cut(input, false)
        .into_iter()
        .map(str::trim)
        .filter(|token| !token.is_empty())
        .map(ToOwned::to_owned)
        .collect()
}

pub fn searchable_text(input: &str) -> String {
    let tokens = jieba_tokens(input);
    if tokens.is_empty() {
        return input.to_string();
    }
    format!("{} {}", input, tokens.join(" "))
}

pub fn query_terms(input: &str) -> Vec<String> {
    let normalized = normalize_query(input);
    let mut terms = vec![normalized.clone()];
    terms.extend(jieba_tokens(&normalized));
    terms.sort();
    terms.dedup();
    terms.into_iter().filter(|term| !term.trim().is_empty()).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn jieba_tokenizes_country_query() {
        let tokens = jieba_tokens("有哪些国家");
        assert!(!tokens.is_empty());
    }

    #[test]
    fn query_terms_include_core_country_token() {
        let terms = query_terms("有哪些国家");
        assert!(terms.iter().any(|term| term.contains("国家")));
    }
}
