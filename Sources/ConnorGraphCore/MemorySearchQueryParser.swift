import Foundation

public struct MemorySearchQueryPlan: Codable, Sendable, Equatable, Hashable {
    public var rawText: String
    public var normalizedText: String
    public var phrases: [String]
    public var terms: [String]

    public init(rawText: String, normalizedText: String, phrases: [String], terms: [String]) {
        self.rawText = rawText
        self.normalizedText = normalizedText
        self.phrases = phrases
        self.terms = terms
    }

    public var retrievalTerms: [String] {
        MemorySearchQueryParser.deduplicated(phrases + terms)
    }
}

public enum MemorySearchQueryParser {
    private static let separators: Set<Character> = [",", "，", ";", "；", "、", "|", "｜"]
    private static let openingQuotes: [Character: Character] = [
        "\"": "\"",
        "'": "'",
        "“": "”",
        "‘": "’"
    ]

    public static func parse(_ rawText: String) -> MemorySearchQueryPlan {
        let normalizedText = rawText
            .precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return MemorySearchQueryPlan(rawText: rawText, normalizedText: "", phrases: [], terms: [])
        }

        var terms: [String] = []
        var quotedPhrases: [String] = []
        var current = ""
        var closingQuote: Character?

        func flush(into values: inout [String]) {
            let value = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { values.append(value) }
            current = ""
        }

        for character in normalizedText {
            if let expected = closingQuote {
                if character == expected {
                    flush(into: &quotedPhrases)
                    closingQuote = nil
                } else {
                    current.append(character)
                }
                continue
            }

            if let expected = openingQuotes[character] {
                flush(into: &terms)
                closingQuote = expected
            } else if character.isWhitespace || character.isNewline || separators.contains(character) {
                flush(into: &terms)
            } else {
                current.append(character)
            }
        }

        if closingQuote == nil {
            flush(into: &terms)
        } else {
            flush(into: &quotedPhrases)
        }

        let unquotedWholePhrase = normalizedText.contains(where: separators.contains) ? [] : [normalizedText]
        return MemorySearchQueryPlan(
            rawText: rawText,
            normalizedText: normalizedText,
            phrases: deduplicated(quotedPhrases + unquotedWholePhrase),
            terms: deduplicated(quotedPhrases + terms)
        )
    }

    static func deduplicated(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { value in
            let key = value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            return !key.isEmpty && seen.insert(key).inserted
        }
    }
}
