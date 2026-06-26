import Foundation
import ConnorGraphCore

public enum NativeSourceSearchFTSQueryBuilder {
    public static func query(for normalized: NativeSearchNormalizedQuery) -> String {
        var seen: Set<String> = []
        let terms = normalized.scoringTokens
            .map { sanitized($0.value) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
            .prefix(24)
            .map { term -> String in
                if isASCIITerm(term), term.count >= 3 { return "\(term)*" }
                return term
            }
        return terms.joined(separator: " OR ")
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
}
