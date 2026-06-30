import Foundation

/// Centralized FTS5 MATCH query sanitizer.
///
/// **ALL FTS5 MATCH values MUST be constructed through this type.**
/// Never pass user/LLM input directly to FTS5 MATCH — special characters
/// (`|`, `*`, `(`, `)`, `+`, `-`, `:`, `^`, `"`, `OR`, `AND`, `NOT`, `NEAR`)
/// would be interpreted as FTS5 operators, causing syntax errors or unexpected behavior.
///
/// Strategy: wrap every term in double quotes so FTS5 treats it as a literal phrase.
public enum FTS5QuerySanitizer {

    /// Sanitize a single search term for FTS5 exact-phrase matching.
    ///
    /// - Strips null bytes
    /// - Escapes embedded double quotes (`"` → `""`)
    /// - Wraps in double quotes (FTS5 literal match)
    ///
    /// Input:  `Xbox Series X|S`
    /// Output: `"Xbox Series X|S"`
    public static func sanitizeTerm(_ term: String) -> String {
        let cleaned = term.replacingOccurrences(of: "\0", with: "")
        let escaped = cleaned.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    /// Sanitize multiple pre-split terms, joined with OR for broad matching.
    /// Each term is individually quoted to prevent operator injection.
    ///
    /// Input:  `["旅行", "杭州"]`
    /// Output: `"旅行" OR "杭州"`
    public static func sanitizeTerms(_ terms: [String]) -> String {
        let sanitized = terms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(sanitizeTerm)
        return sanitized.isEmpty ? "\"\"" : sanitized.joined(separator: " OR ")
    }

    /// Sanitize free-text input: split into terms, then sanitize each.
    /// Splits on semicolons (LLM convention for multiple search concepts),
    /// commas, and whitespace.
    ///
    /// Input:  `"旅行; Xbox Series X|S, 杭州"`
    /// Output: `"旅行" OR "Xbox" OR "Series" OR "X|S" OR "杭州"`
    public static func sanitizeText(_ text: String) -> String {
        let terms = text
            .split(separator: ";")
            .flatMap { $0.split(separator: ",") }
            .flatMap { $0.split { $0.isWhitespace } }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return sanitizeTerms(terms)
    }
}
