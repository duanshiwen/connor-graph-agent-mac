use jieba_rs::Jieba;
use once_cell::sync::Lazy;
use std::collections::HashSet;

static JIEBA: Lazy<Jieba> = Lazy::new(Jieba::new);

pub fn normalize_query(input: &str) -> String {
    input.trim().to_string()
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct QueryPlan {
    pub normalized_text: String,
    pub phrases: Vec<String>,
    pub terms: Vec<String>,
}

impl QueryPlan {
    pub fn retrieval_terms(&self) -> Vec<String> {
        deduplicated(self.phrases.iter().chain(self.terms.iter()).cloned())
    }
}

pub fn parse_query(input: &str) -> QueryPlan {
    let normalized_text = normalize_query(input);
    if normalized_text.is_empty() {
        return QueryPlan { normalized_text, phrases: vec![], terms: vec![] };
    }

    let mut terms = Vec::new();
    let mut quoted_phrases = Vec::new();
    let mut current = String::new();
    let mut closing_quote = None;
    let mut had_explicit_separator = false;

    for character in normalized_text.chars() {
        if let Some(expected) = closing_quote {
            if character == expected {
                push_trimmed(&mut quoted_phrases, &mut current);
                closing_quote = None;
            } else {
                current.push(character);
            }
            continue;
        }

        if let Some(expected) = closing_quote_for(character) {
            push_trimmed(&mut terms, &mut current);
            closing_quote = Some(expected);
        } else if character.is_whitespace() || is_explicit_separator(character) {
            had_explicit_separator |= is_explicit_separator(character);
            push_trimmed(&mut terms, &mut current);
        } else {
            current.push(character);
        }
    }

    if closing_quote.is_some() {
        push_trimmed(&mut quoted_phrases, &mut current);
    } else {
        push_trimmed(&mut terms, &mut current);
    }

    let mut phrases = quoted_phrases.clone();
    if !had_explicit_separator {
        phrases.push(normalized_text.clone());
    }
    QueryPlan {
        normalized_text,
        phrases: deduplicated(phrases),
        terms: deduplicated(quoted_phrases.into_iter().chain(terms)),
    }
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
    let plan = parse_query(input);
    let mut terms = Vec::new();
    for value in plan.retrieval_terms() {
        terms.push(value.clone());
        terms.extend(jieba_tokens(&value));
    }
    deduplicated(terms)
}

fn push_trimmed(values: &mut Vec<String>, current: &mut String) {
    let value = current.trim();
    if !value.is_empty() {
        values.push(value.to_string());
    }
    current.clear();
}

fn closing_quote_for(character: char) -> Option<char> {
    match character {
        '"' => Some('"'),
        '\'' => Some('\''),
        '“' => Some('”'),
        '‘' => Some('’'),
        _ => None,
    }
}

fn is_explicit_separator(character: char) -> bool {
    matches!(character, ',' | '，' | ';' | '；' | '、' | '|' | '｜')
}

fn deduplicated(values: impl IntoIterator<Item = String>) -> Vec<String> {
    let mut seen = HashSet::new();
    values
        .into_iter()
        .filter_map(|value| {
            let trimmed = value.trim();
            let key = trimmed.to_lowercase();
            if trimmed.is_empty() || !seen.insert(key) {
                None
            } else {
                Some(trimmed.to_string())
            }
        })
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

    #[test]
    fn query_terms_include_core_country_token() {
        let terms = query_terms("有哪些国家");
        assert!(terms.iter().any(|term| term.contains("国家")));
    }

    #[test]
    fn parses_common_llm_separators_without_indexing_punctuation() {
        for separator in [" ", ",", "，", ";", "；", "、", "|", "｜", "\n", "\t"] {
            let terms = parse_query(&format!("Annie{separator}Friend")).terms;
            assert_eq!(terms, vec!["Annie", "Friend"], "separator={separator:?}");
        }
    }

    #[test]
    fn preserves_quoted_phrases() {
        let plan = parse_query("\"Annie Friend\"；AI 产品经理");
        assert_eq!(plan.phrases, vec!["Annie Friend"]);
        assert_eq!(plan.terms, vec!["Annie Friend", "AI", "产品经理"]);
    }
}
