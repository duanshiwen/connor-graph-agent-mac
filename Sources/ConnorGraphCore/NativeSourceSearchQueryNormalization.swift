import Foundation

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
}

public enum NativeSearchQueryNormalizer {
    private static let englishSoftStopWords: Set<String> = [
        "a", "an", "the",
        "and", "or", "but",
        "of", "to", "in", "on", "for", "with", "by", "at", "from",
        "is", "are", "was", "were", "be", "been", "being",
        "this", "that", "these", "those",
        "about", "into", "as"
    ]

    private static let chineseSoftStopWords: [String] = [
        "关于", "里面", "一下", "一个", "一些", "这个", "那个",
        "的", "了", "是", "在", "和", "与", "或", "我", "你", "他", "她", "它"
    ]

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
                let isStop = englishSoftStopWords.contains(run.text)
                tokens.append(NativeSearchQueryToken(value: run.text, kind: run.kind, weight: isStop ? 0.1 : 1, isSoftStopWord: isStop))
            }
        }
        return NativeSearchNormalizedQuery(rawText: rawText, normalizedText: normalizedText, tokens: dedupe(tokens))
    }

    private static func tokenizeCJK(_ text: String) -> [NativeSearchQueryToken] {
        var remaining = text
        var tokens: [NativeSearchQueryToken] = []
        for stop in chineseSoftStopWords.sorted(by: { $0.count > $1.count }) {
            while let range = remaining.range(of: stop) {
                let before = String(remaining[..<range.lowerBound])
                tokens.append(contentsOf: cjkStrongTokens(before))
                tokens.append(NativeSearchQueryToken(value: stop, kind: .cjk, weight: 0.1, isSoftStopWord: true))
                remaining = String(remaining[range.upperBound...])
            }
        }
        tokens.append(contentsOf: cjkStrongTokens(remaining))
        return tokens
    }

    private static func cjkStrongTokens(_ text: String) -> [NativeSearchQueryToken] {
        let chars = Array(text).filter { !$0.isWhitespace }
        guard !chars.isEmpty else { return [] }
        let value = String(chars)
        if chars.count <= 2 {
            return [NativeSearchQueryToken(value: value, kind: .cjk, weight: 1, isSoftStopWord: false)]
        }
        var tokens = [NativeSearchQueryToken(value: value, kind: .cjk, weight: 1, isSoftStopWord: false)]
        for index in 0..<(chars.count - 1) {
            let gram = String(chars[index...index + 1])
            tokens.append(NativeSearchQueryToken(value: gram, kind: .cjkGram, weight: 0.8, isSoftStopWord: false))
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
