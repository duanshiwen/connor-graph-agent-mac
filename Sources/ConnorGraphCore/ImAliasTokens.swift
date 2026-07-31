import Foundation

/// Forwarding anonymization tokens: when IM transcripts are forwarded to the AI,
/// participant identities are replaced with the opaque token `@CXxxxxxx`
/// (`@CX` = Connor eXternal participant, followed by 6 uppercase hex digits).
///
/// The generation side (`ImTranscriptAnonymizer`) and the resolution side
/// (projection batch rewriting) share this single definition so that
/// generation == resolution byte-for-byte. Tokens enter L0/L1 verbatim and flow
/// into projection, where they are resolved back to the real L4 person entity.
///
/// Scanning is implemented without regular expressions on purpose: the format is
/// trivial and this keeps the type free of shared mutable regex state under
/// strict concurrency.
public enum ImAliasTokens {
    /// Token prefix shared by every alias token.
    public static let tokenPrefix = "@CX"

    /// Number of hex digits following the prefix.
    public static let hexDigitCount = 6

    /// Total character count of a well-formed token.
    public static var tokenLength: Int { tokenPrefix.count + hexDigitCount }

    /// Whether the string is exactly one token (full match after trimming).
    public static func isToken(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == tokenLength else { return false }
        return firstToken(in: trimmed) == trimmed
    }

    /// First token occurring anywhere in the string (nil when absent).
    public static func firstToken(in value: String) -> String? {
        let characters = Array(value)
        let prefix = Array(tokenPrefix)
        guard characters.count >= tokenLength else { return nil }
        var index = 0
        while index <= characters.count - tokenLength {
            if Array(characters[index..<(index + prefix.count)]) == prefix {
                let digits = characters[(index + prefix.count)..<(index + tokenLength)]
                if digits.allSatisfy(isUppercaseHexDigit) {
                    return String(characters[index..<(index + tokenLength)])
                }
            }
            index += 1
        }
        return nil
    }

    /// All distinct tokens occurring in the string, in order of first appearance.
    public static func tokens(in value: String) -> [String] {
        var found: [String] = []
        var seen = Set<String>()
        var remainder = Substring(value)
        while let token = firstToken(in: String(remainder)) {
            if seen.insert(token).inserted { found.append(token) }
            guard let range = remainder.range(of: token) else { break }
            remainder = remainder[range.upperBound...]
        }
        return found
    }

    private static func isUppercaseHexDigit(_ character: Character) -> Bool {
        ("0"..."9").contains(character) || ("A"..."F").contains(character)
    }
}
