import Foundation
import ConnorGraphCore

public enum NativeSourceSearchFTSQueryBuilder {
    public static func query(for normalized: NativeSearchNormalizedQuery) -> String {
        var seen: Set<String> = []
        let sourceTokens = preferredMatchTokens(for: normalized)
        let terms = sourceTokens
            .map { sanitized($0.value) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
            .prefix(16)
            .map { term -> String in
                if isASCIITerm(term), term.count >= 3 { return "\(term)*" }
                return term
            }
        return terms.joined(separator: " OR ")
    }

    private static func preferredMatchTokens(for normalized: NativeSearchNormalizedQuery) -> [NativeSearchQueryToken] {
        let scoringTokens = normalized.scoringTokens
        let containsCJK = scoringTokens.contains { token in
            token.value.unicodeScalars.contains(where: isCJK)
        }
        guard containsCJK else { return scoringTokens }

        let semanticTokens = scoringTokens.filter { token in
            guard token.kind != .cjkGram else { return false }
            if token.kind == .phrase, token.value.count > 6 { return false }
            if token.value.unicodeScalars.contains(where: isCJK), token.value.count < 2 { return false }
            return true
        }
        return semanticTokens.isEmpty ? scoringTokens : semanticTokens
    }

    private static func sanitized(_ value: String) -> String {
        let scalars = value.unicodeScalars.filter { scalar in
            CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
        }
        return String(String.UnicodeScalarView(scalars)).lowercased()
    }

    private static func isASCIITerm(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { $0.value < 128 }
    }

    private static func isCJK(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2A6DF, 0x2A700...0x2B73F, 0x2B740...0x2B81F, 0x2B820...0x2CEAF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }
}
