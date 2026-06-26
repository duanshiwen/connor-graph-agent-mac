import Foundation
import NaturalLanguage

public enum NativeSearchQueryTokenKind: String, Codable, Sendable, Equatable, Hashable {
    case word
    case number
    case cjk
    case cjkGram
    case phrase
}

public struct NativeSearchQueryToken: Codable, Sendable, Equatable, Hashable {
    public var value: String
    public var kind: NativeSearchQueryTokenKind
    public var weight: Double
    public var isSoftStopWord: Bool

    public init(value: String, kind: NativeSearchQueryTokenKind = .word, weight: Double = 1, isSoftStopWord: Bool = false) {
        self.value = value
        self.kind = kind
        self.weight = weight
        self.isSoftStopWord = isSoftStopWord
    }
}

public struct NativeSearchNormalizedQuery: Codable, Sendable, Equatable, Hashable {
    public var rawText: String
    public var normalizedText: String
    public var tokens: [NativeSearchQueryToken]
    public var quotedPhrases: [String]

    public init(rawText: String, normalizedText: String, tokens: [NativeSearchQueryToken], quotedPhrases: [String] = []) {
        self.rawText = rawText
        self.normalizedText = normalizedText
        self.tokens = tokens
        self.quotedPhrases = quotedPhrases
    }

    public var strongTokens: [NativeSearchQueryToken] { tokens.filter { !$0.isSoftStopWord } }
    public var softStopTokens: [NativeSearchQueryToken] { tokens.filter(\.isSoftStopWord) }
    public var strongTokenValues: [String] { strongTokens.map(\.value) }
    public var softStopTokenValues: [String] { softStopTokens.map(\.value) }

    public var scoringTokens: [NativeSearchQueryToken] {
        let strong = strongTokens
        return strong.isEmpty ? tokens : strong
    }

    public var displayTokens: [NativeSearchQueryToken] {
        scoringTokens.filter { token in
            !token.isSoftStopWord && token.kind != .cjkGram
        }
    }

    public var displayTokenValues: [String] { displayTokens.map(\.value) }
}

public enum NativeSearchQueryNormalizer {
    private static let filterLexicon = TextFilterLexicon.default

    public static func normalize(_ rawText: String) -> NativeSearchNormalizedQuery {
        let normalizedText = rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedText.isEmpty else {
            return NativeSearchNormalizedQuery(rawText: rawText, normalizedText: normalizedText, tokens: [])
        }

        var tokens: [NativeSearchQueryToken] = []
        let runs = characterRuns(in: normalizedText)
        for run in runs {
            switch run.kind {
            case .cjk:
                tokens.append(contentsOf: tokenizeCJK(run.text))
            case .word, .number, .cjkGram, .phrase:
                let action = filterLexicon.action(for: run.text, context: .searchQuery)
                let isStop = action != .keep
                tokens.append(NativeSearchQueryToken(value: run.text, kind: run.kind, weight: filterLexicon.weightMultiplier(for: run.text, context: .searchQuery), isSoftStopWord: isStop))
            }
        }
        return NativeSearchNormalizedQuery(rawText: rawText, normalizedText: normalizedText, tokens: dedupe(tokens))
    }

    private static func tokenizeCJK(_ text: String) -> [NativeSearchQueryToken] {
        let compact = String(text.filter { !$0.isWhitespace })
        guard !compact.isEmpty else { return [] }

        var tokens: [NativeSearchQueryToken] = []
        tokens.append(NativeSearchQueryToken(value: compact, kind: .phrase, weight: 1.4, isSoftStopWord: false))
        tokens.append(contentsOf: semanticCJKTokens(compact))
        tokens.append(contentsOf: fallbackCJKGrams(compact))
        return tokens
    }

    private static func semanticCJKTokens(_ text: String) -> [NativeSearchQueryToken] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var tokens: [NativeSearchQueryToken] = []
        let fullRange = text.startIndex..<text.endIndex
        tokenizer.enumerateTokens(in: fullRange) { range, _ in
            let value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return true }
            tokens.append(token(value, kind: .cjk))
            return true
        }

        for entry in filterLexicon.entries(containedIn: text, language: .chinese) {
            guard filterLexicon.action(for: entry.term, context: .searchQuery) != .keep else { continue }
            tokens.append(NativeSearchQueryToken(value: entry.term, kind: .cjk, weight: entry.weightMultiplier, isSoftStopWord: true))
        }

        if tokens.isEmpty {
            return [token(text, kind: .cjk)]
        }
        return tokens
    }

    private static func token(_ value: String, kind: NativeSearchQueryTokenKind) -> NativeSearchQueryToken {
        let action = filterLexicon.action(for: value, context: .searchQuery)
        let isStop = action != .keep
        return NativeSearchQueryToken(
            value: value,
            kind: kind,
            weight: filterLexicon.weightMultiplier(for: value, context: .searchQuery),
            isSoftStopWord: isStop
        )
    }

    private static func fallbackCJKGrams(_ text: String) -> [NativeSearchQueryToken] {
        let chars = Array(text).filter { !$0.isWhitespace }
        guard chars.count > 1 else { return [] }
        var tokens: [NativeSearchQueryToken] = []
        if chars.count >= 3 {
            for index in 0...(chars.count - 3) {
                let gram = String(chars[index...index + 2])
                tokens.append(NativeSearchQueryToken(value: gram, kind: .cjkGram, weight: 0.35, isSoftStopWord: false))
            }
        }
        for index in 0..<(chars.count - 1) {
            let gram = String(chars[index...index + 1])
            tokens.append(NativeSearchQueryToken(value: gram, kind: .cjkGram, weight: 0.25, isSoftStopWord: false))
        }
        return tokens
    }

    private static func characterRuns(in text: String) -> [(text: String, kind: NativeSearchQueryTokenKind)] {
        var runs: [(String, NativeSearchQueryTokenKind)] = []
        var current = ""
        var currentKind: NativeSearchQueryTokenKind?

        func flush() {
            guard let kind = currentKind, !current.isEmpty else { return }
            runs.append((current, kind))
            current = ""
            currentKind = nil
        }

        for scalar in text.unicodeScalars {
            let kind: NativeSearchQueryTokenKind?
            if CharacterSet.letters.contains(scalar) {
                kind = isCJK(scalar) ? .cjk : .word
            } else if CharacterSet.decimalDigits.contains(scalar) {
                kind = .word
            } else {
                kind = nil
            }

            guard let kind else {
                flush()
                continue
            }
            if currentKind == kind {
                current.unicodeScalars.append(scalar)
            } else {
                flush()
                currentKind = kind
                current.unicodeScalars.append(scalar)
            }
        }
        flush()
        return runs
    }

    private static func isCJK(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2A6DF, 0x2A700...0x2B73F, 0x2B740...0x2B81F, 0x2B820...0x2CEAF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }

    private static func dedupe(_ tokens: [NativeSearchQueryToken]) -> [NativeSearchQueryToken] {
        var seen: Set<String> = []
        var result: [NativeSearchQueryToken] = []
        for token in tokens {
            let key = "\(token.kind.rawValue):\(token.value):\(token.isSoftStopWord)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(token)
        }
        return result
    }
}
