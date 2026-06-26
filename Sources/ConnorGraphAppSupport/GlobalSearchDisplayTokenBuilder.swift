import Foundation
import ConnorGraphCore

public enum GlobalSearchDisplayTokenBuilder {
    public static func tokens(for query: String, limit: Int = 8, lexicon: TextFilterLexicon = .default) -> [String] {
        let normalized = NativeSearchQueryNormalizer.normalize(query)
        let primary = uniqueDisplayTokens(from: normalized.displayTokenValues, query: query, limit: limit, lexicon: lexicon, filterLowValue: true)
        if !primary.isEmpty { return primary }

        let fallbackValues = normalized.scoringTokens
            .filter { $0.kind != .cjkGram }
            .map(\.value)
        let fallback = uniqueDisplayTokens(from: fallbackValues, query: query, limit: limit, lexicon: lexicon, filterLowValue: false)
        if !fallback.isEmpty { return fallback }

        return uniqueDisplayTokens(from: normalized.tokens.map(\.value), query: query, limit: limit, lexicon: lexicon, filterLowValue: false)
    }

    private static func uniqueDisplayTokens(
        from values: [String],
        query: String,
        limit: Int,
        lexicon: TextFilterLexicon,
        filterLowValue: Bool
    ) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            guard !value.isEmpty else { continue }
            guard value.count >= 2 || query.count <= 2 else { continue }
            if filterLowValue {
                let action = lexicon.action(for: value, context: .searchDisplay)
                guard action != .dropForDisplay && action != .dropForQuery else { continue }
            }
            guard seen.insert(value).inserted else { continue }
            result.append(value)
            if result.count >= limit { break }
        }
        return result
    }
}
