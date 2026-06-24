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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn jieba_tokenizes_country_query() {
        let tokens = jieba_tokens("有哪些国家");
        assert!(!tokens.is_empty());
    }
}
